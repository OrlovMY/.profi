<#
.SYNOPSIS
  Безопасная уборка отработавших git worktree и выводов фоновых задач Claude Code.
  Реализует рецепт knowledge/recipes/git-worktree-branch-hygiene.md (шаги 1.1–1.6) кодом,
  чтобы его не исполняли руками.

.DESCRIPTION
  По умолчанию — ХОЛОСТОЙ ПРОГОН: ничего не удаляет, печатает, что удалил бы и почему.
  Удаляет только с -Apply. Удаляет ПО ОДНОЙ копии и только через `git worktree remove` БЕЗ -f.

  Копия удаляется, только если сошлось ВСЁ:
    1. копия не основной чекаут и не заблокирована (locked);
    2. у копии есть ветка (DETACHED не трогаем — коммиты могут быть только там);
    3. ветка целиком влита в -Main (`git merge-base --is-ancestor`);
    4. `git status --porcelain` пуст (нет незакоммиченного и неотслеживаемого);
    5. внутри НЕТ ни одной точки повторного разбора (junction/symlink) на ЛЮБОЙ глубине —
       именно связь дважды (05.09 и 19.09.2026) опустошила node_modules основного чекаута;
       обход сам в связи не заходит; ноль просмотренных узлов = «ослепли» = отказ;
    6. ни один файл не менялся за последние -ActiveHours часов (копия не в работе).
  Перед самим удалением проверка связей повторяется. После каждой копии сверяется целость
  контрольных каталогов основного чекаута; при расхождении — немедленная остановка.

  ВАЖНО: скрипт НЕ запускать через конвейер (| head, | tail, | Out-String) — конвейер
  подменяет код возврата. Запускать как есть; код возврата 0 = без отказов, 1 = были
  пропуски, 2 = аварийная остановка.

.EXAMPLE
  # 1) Посмотреть (ничего не удаляет):
  pwsh -NoProfile -File P:\OrlovMY\.profi\tools\wt-cleanup.ps1 -Repo P:\OrlovMY\MDMy
  # 2) Удалить то, что признано безопасным, и удалить их влитые ветки:
  pwsh -NoProfile -File P:\OrlovMY\.profi\tools\wt-cleanup.ps1 -Repo P:\OrlovMY\MDMy -Apply -DeleteMergedBranches
  # 3) Выводы фоновых задач своей сессии (по умолчанию холостой прогон):
  pwsh -NoProfile -File P:\OrlovMY\.profi\tools\wt-cleanup.ps1 -Repo P:\OrlovMY\MDMy -TaskOutputs
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$Main,
    [switch]$Apply,
    [string]$ExpectVersion,  # PQ-01: обязателен при -Apply — версия из последнего холостого прогона
    [switch]$Gate,         # PQ-01: проверка-отказ для выката: холостой прогон, код 3, если есть что убрать
    [switch]$DeleteMergedBranches,
    [switch]$MergedBranches,
    [switch]$Orphans,      # незарегистрированные каталоги в <repo>\.claude\worktrees (git о них не знает)
    [int]$ActiveHours = 24,
    [int]$Max = 0,
    [switch]$TaskOutputs,
    [string]$SessionDir,   # каталог, из которого запущена сессия Claude, если он не совпадает с -Repo (напр. родительский)
    [int]$TaskOutputMinMB = 50,
    [int]$TaskOutputAgeHours = 1
)

$ErrorActionPreference = 'Stop'
$script:pending = 0
# PQ-01: из git-хука приходят GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE — они подменили бы репозиторий у всех git -C ниже.
foreach ($v in 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_PREFIX') { Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue }
# PQ-01 21.10.2026: любое необработанное исключение — аварийная остановка (2), а не «пропуски» (1).
trap { Write-Host "АВАРИЙНАЯ ОСТАНОВКА (исключение): $_" -ForegroundColor Red; exit 2 }
# PQ-01: вывод git (UTF-8) читать как UTF-8, иначе кириллические пути искажаются.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
# PQ-01 (инцидент 21.10.2026: MAIL сделал -Apply новой версией после холостого прогона старой):
# версия = первые 12 знаков SHA-256 этого файла; -Apply без совпадающего -ExpectVersion — отказ.
$Version = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
Write-Host "wt-cleanup.ps1 версия $Version" -ForegroundColor Cyan
if ($Apply -and -not $Gate -and ($ExpectVersion.ToLowerInvariant() -ne $Version)) {
    Write-Host "АВАРИЙНАЯ ОСТАНОВКА: скрипт изменился после холостого прогона (или не передан -ExpectVersion) — повтори холостой прогон и передай -ExpectVersion $Version из его вывода" -ForegroundColor Red; exit 2
}
# PQ-01: игнорируемое, которое заведомо воспроизводится. ВСЁ прочее игнорируемое (.env*, ключи,
# локальные БД, config.local*, неизвестное) удаление копии/сироты блокирует.
$ReproDirs = @('node_modules', '.venv', 'venv', '__pycache__', 'bin', 'obj', 'dist', 'build', 'out', 'target', '.cache')
function IsRepro([string]$rel) {
    $segs = @($rel.Replace('\', '/').TrimEnd('/') -split '/' | Where-Object { $_ })
    foreach ($g in $segs) { if ($ReproDirs -contains $g) { return $true } }
    return ($segs.Count -and $segs[-1] -like '*.log')
}
# Игнорируемые git'ом файлы копии, кроме воспроизводимых. $env GIT_* должны быть выставлены вызывающим, если нужно.
function IgnoredNonRepro([string[]]$gitArgs) {
    $r = Invoke-Git ($gitArgs + @('-c', 'core.quotepath=off', 'ls-files', '--others', '--ignored', '--exclude-standard', '--directory'))
    if ($r.Code) { return @{ Err = "ls-files --ignored: $($r.Out -join ' ')" } }
    return @{ List = @($r.Out | Where-Object { $_ -and -not (IsRepro $_) }) }
}
$script:skipped = 0
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Abort($m) { Write-Host "АВАРИЙНАЯ ОСТАНОВКА: $m" -ForegroundColor Red; exit 2 }
function FreeGB($path) { $d = (Get-Item -LiteralPath $path).PSDrive; [math]::Round((Get-PSDrive $d.Name).Free / 1GB, 1) }

function Invoke-Git([string[]]$a) {
    $out = & git.exe @a 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out | ForEach-Object { "$_" }) }
}

# Обход без захода в связи: возвращает число узлов, список связей и самый свежий mtime.
function Scan([string]$root) {
    $nodes = 0; $links = [Collections.Generic.List[string]]::new(); $newest = [datetime]::MinValue
    $st = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $r0 = [IO.DirectoryInfo]::new($root)
    # PQ-01: сама копия может быть связью на чужой каталог — тогда удаление уйдёт в цель.
    if ($r0.Attributes -band [IO.FileAttributes]::ReparsePoint) { $links.Add("САМА КОПИЯ — СВЯЗЬ: $root"); return [pscustomobject]@{ Nodes = 1; Links = $links; Newest = $newest } }
    $st.Push($r0)
    while ($st.Count) {
        $d = $st.Pop()
        try { $items = $d.GetFileSystemInfos() } catch { $links.Add("НЕ ЧИТАЕТСЯ: $($d.FullName)"); continue }
        foreach ($i in $items) {
            $nodes++
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $t = try { (Get-Item -LiteralPath $i.FullName -Force).Target } catch { '?' }
                $links.Add("$($i.FullName) -> $t"); continue
            }
            if ($i.LastWriteTime -gt $newest) { $newest = $i.LastWriteTime }
            if ($i -is [IO.DirectoryInfo]) { $st.Push($i) }
        }
    }
    [pscustomobject]@{ Nodes = $nodes; Links = $links; Newest = $newest }
}

# PQ-01: удаление без Remove-Item -Recurse — снизу вверх, и при ЛЮБОЙ встреченной связи —
# аварийная остановка (закрывает гонку «связь появилась между повторной Scan и удалением»).
function Remove-TreeNoLinks([string]$root) {
    $d = [IO.DirectoryInfo]::new($root)
    if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { Abort "связь появилась перед удалением: $root" }
    foreach ($i in $d.GetFileSystemInfos()) {
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { Abort "связь появилась перед удалением: $($i.FullName)" }
        if ($i -is [IO.DirectoryInfo]) { Remove-TreeNoLinks $i.FullName }
        else { if ($i.Attributes -band [IO.FileAttributes]::ReadOnly) { $i.Attributes = 'Normal' }; $i.Delete() }
    }
    $d.Delete($false)   # не рекурсивно: каталог уже пуст
}

# PQ-01: сирота с .git-файлом, чей gitdir удалён. Каждый НЕигнорируемый файл хэшируется как blob
# и ищется среди объектов, достижимых из ЛЮБОЙ ссылки (rev-list --objects --all). Не найден —
# содержимое есть только здесь (незакоммиченная работа) — оставить. Игнорируемое (node_modules,
# сборки) — транзит, как и при обычном git worktree remove.
function OrphanUnique([string]$dir) {
    $raw = Get-Content -LiteralPath (Join-Path $dir '.git') -Raw
    if ($raw -notmatch 'gitdir:\s*(.+)') { return @{ Err = '.git-файл без строки gitdir' } }
    $g = $Matches[1].Trim(); if (-not [IO.Path]::IsPathRooted($g)) { $g = Join-Path $dir $g }
    if (Test-Path -LiteralPath $g) { return @{ Err = "gitdir существует ($g) — копия живая или чужая, разбор вручную" } }
    if (-not $script:reach) {
        $r = Invoke-Git @('-C', $Repo, 'rev-list', '--objects', '--all'); if ($r.Code) { return @{ Err = 'rev-list --objects --all не выполнился' } }
        $script:reach = [Collections.Generic.HashSet[string]]::new()
        foreach ($l in $r.Out) { if ($l) { [void]$script:reach.Add(($l -split ' ', 2)[0]) } }
    }
    $idx = [IO.Path]::Combine([IO.Path]::GetTempPath(), "wtc-idx-$([guid]::NewGuid())")
    $old = @($env:GIT_DIR, $env:GIT_WORK_TREE, $env:GIT_INDEX_FILE)
    Push-Location -LiteralPath $dir
    try {
        $env:GIT_DIR = $commonDir; $env:GIT_WORK_TREE = $dir; $env:GIT_INDEX_FILE = $idx   # пустой индекс: все файлы — «прочие»
        $ls = Invoke-Git @('-c', 'core.quotepath=off', 'ls-files', '--others', '--exclude-standard')
        if ($ls.Code) { return @{ Err = "ls-files: $($ls.Out -join ' ')" } }
        $files = @($ls.Out | Where-Object { $_ })
        $ig = IgnoredNonRepro @()
        if ($ig.Err) { return @{ Err = $ig.Err } }
        if ($ig.List.Count) { return @{ Ignored = $ig.List } }
        if (-not $files.Count) { return @{ Unique = @() } }
        $h = $files | & git.exe -c core.quotepath=off hash-object --stdin-paths 2>&1
        if ($LASTEXITCODE) { return @{ Err = "hash-object: $h" } }
        $h = @($h | ForEach-Object { "$_" })
        if ($h.Count -ne $files.Count) { return @{ Err = 'hash-object вернул не столько строк, сколько файлов' } }
        $u = @(for ($k = 0; $k -lt $files.Count; $k++) { if (-not $script:reach.Contains($h[$k])) { $files[$k] } })
        return @{ Unique = $u }
    } finally {
        Pop-Location
        $env:GIT_DIR, $env:GIT_WORK_TREE, $env:GIT_INDEX_FILE = $old
        Remove-Item -LiteralPath $idx -Force -ErrorAction SilentlyContinue
    }
}

# --- репозиторий --------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Repo -PathType Container)) { Abort "нет каталога $Repo" }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$top = Invoke-Git @('-C', $Repo, 'rev-parse', '--show-toplevel'); if ($top.Code) { Abort "не git-репозиторий: $Repo" }
$gd = Invoke-Git @('-C', $Repo, 'rev-parse', '--absolute-git-dir')
$cd = Invoke-Git @('-C', $Repo, 'rev-parse', '--path-format=absolute', '--git-common-dir')
if (($gd.Out -join '') -ne ($cd.Out -join '')) { Abort "-Repo должен указывать на ОСНОВНОЙ чекаут, а не на worktree" }
$mainPath = [IO.Path]::GetFullPath(($top.Out -join '').Replace('/', '\'))
$commonDir = ($cd.Out -join '')
if ($Gate) { $Apply = $false }

if (-not $Main) {
    foreach ($cand in 'main', 'master') {
        if ((Invoke-Git @('-C', $Repo, 'rev-parse', '--verify', '--quiet', "refs/heads/$cand")).Code -eq 0) { $Main = $cand; break }
    }
    if (-not $Main) { Abort "не нашёл ветку main/master — укажи -Main" }
}
Say "Репозиторий: $mainPath   основная ветка: $Main   режим: $(if($Apply){'УДАЛЕНИЕ'}else{'холостой прогон'})" Cyan
Say "Свободно на диске до: $(FreeGB $mainPath) ГБ"

# --- контроль целости основного чекаута ----------------------------------------
$sentinels = Get-ChildItem -LiteralPath $mainPath -Directory -Force -Recurse -Depth 3 -Filter node_modules -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.claude\\worktrees\\' -and $_.FullName -notmatch '\\node_modules\\.+node_modules' }
$baseline = @{}
foreach ($s in $sentinels) { $baseline[$s.FullName] = @(Get-ChildItem -LiteralPath $s.FullName -Force -ErrorAction SilentlyContinue).Count }
$baseline['<корень>'] = @(Get-ChildItem -LiteralPath $mainPath -Force).Count
function CheckIntegrity {
    foreach ($k in @($baseline.Keys)) {
        $p = if ($k -eq '<корень>') { $mainPath } else { $k }
        $now = @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue).Count
        if ($now -lt $baseline[$k]) { Abort "в основном чекауте убыло содержимое: $p ($($baseline[$k]) -> $now)" }
    }
}

# --- перечень копий (путь + ветка + блокировка), без основного ----------------
$wl = Invoke-Git @('-C', $Repo, 'worktree', 'list', '--porcelain'); if ($wl.Code) { Abort "git worktree list: $($wl.Out)" }
$wts = @(); $cur = $null
foreach ($l in $wl.Out + '') {
    if ($l -like 'worktree *') { $cur = [ordered]@{ Path = [IO.Path]::GetFullPath($l.Substring(9).Replace('/', '\')); Branch = $null; Detached = $false; Locked = $false; Prunable = $false } }
    elseif ($l -like 'branch *') { $cur.Branch = $l.Substring(7) -replace '^refs/heads/', '' }
    elseif ($l -eq 'detached') { $cur.Detached = $true }
    elseif ($l -like 'locked*') { $cur.Locked = $true }
    elseif ($l -like 'prunable*') { $cur.Prunable = $true }
    elseif ($l -eq '' -and $cur) { $wts += [pscustomobject]$cur; $cur = $null }
}
$wts = @($wts | Where-Object { $_.Path -ne $mainPath })
Say "Связанных копий: $($wts.Count)"

$ok = @(); $report = @()
foreach ($w in $wts) {
    $why = $null
    if ($w.Prunable -or -not (Test-Path -LiteralPath $w.Path)) { $report += [pscustomobject]@{ Копия = $w.Path; Итог = 'нет каталога — уйдёт по prune' }; continue }
    if ($w.Locked) { $why = 'заблокирована (locked)' }
    elseif ($w.Detached) { $why = 'DETACHED: без ветки — разобрать вручную (log, при неслитых — branch save/<имя>)' }
    else {
        $anc = Invoke-Git @('-C', $Repo, 'merge-base', '--is-ancestor', $w.Branch, $Main)
        if ($anc.Code -eq 1) { $why = "ветка $($w.Branch) не влита в $Main" }
        elseif ($anc.Code -ne 0) { $why = "не удалось проверить слитость: $($anc.Out -join ' ')" }
        else {
            $stt = Invoke-Git @('-C', $w.Path, 'status', '--porcelain')
            if ($stt.Code) { $why = "git status не выполнился: $($stt.Out -join ' ')" }
            elseif ($stt.Out | Where-Object { $_ }) { $why = 'есть незакоммиченное/неотслеживаемое' }
            elseif (($igw = IgnoredNonRepro @('-C', $w.Path)).Err) { $why = $igw.Err }
            elseif ($igw.List.Count) { $why = "игнорируемые невоспроизводимые файлы ($($igw.List.Count)): $(($igw.List | Select-Object -First 8) -join ', ') — .env/ключи/БД/конфиги; git worktree remove удалил бы их молча, разобрать вручную" }
            else {
                $sc = Scan $w.Path
                if ($sc.Nodes -eq 0) { $why = 'просмотрено 0 узлов — проверка ослепла' }
                elseif ($sc.Links.Count) { $why = "СВЯЗИ внутри: $($sc.Links -join '; ')" }
                elseif ($sc.Newest -gt (Get-Date).AddHours(-$ActiveHours)) { $why = "менялась $($sc.Newest.ToString('dd.MM HH:mm')) — возможно, в работе" }
            }
        }
    }
    if ($why) { $script:skipped++; $report += [pscustomobject]@{ Копия = $w.Path; Итог = "ОСТАВЛЕНА: $why" } }
    else { $ok += $w; $report += [pscustomobject]@{ Копия = $w.Path; Итог = "к удалению (ветка $($w.Branch))" } }
}
foreach ($x in $report) { Say ("  {0}
      {1}" -f $x.Копия, $x.Итог) }
$script:pending += $ok.Count
Say "Безопасно к удалению: $($ok.Count)   оставлено: $script:skipped" Cyan

if ($Apply) {
    $n = 0
    foreach ($w in $ok) {
        if ($Max -gt 0 -and $n -ge $Max) { Say "Достигнут лимит -Max $Max" Yellow; break }
        $sc = Scan $w.Path   # повтор проверки связей непосредственно перед удалением
        if ($sc.Nodes -eq 0 -or $sc.Links.Count) { $script:skipped++; Say "ПРОПУСК (связь/слепота при повторной проверке): $($w.Path)" Yellow; continue }
        $r = Invoke-Git @('-C', $Repo, 'worktree', 'remove', $w.Path)   # БЕЗ -f
        if ($r.Code) { $script:skipped++; Say "git отказался удалять $($w.Path): $($r.Out -join ' ')" Yellow; continue }
        $n++; Say "удалена: $($w.Path)" Green
        CheckIntegrity
        if ($DeleteMergedBranches) {
            $b = Invoke-Git @('-C', $Repo, 'branch', '-d', $w.Branch)   # -d (не -D): git сам откажет неслитой
            if ($b.Code) { Say "  ветку $($w.Branch) не удалил: $($b.Out -join ' ')" Yellow } else { Say "  ветка $($w.Branch) удалена" }
        }
    }
    $p = Invoke-Git @('-C', $Repo, 'worktree', 'prune'); if ($p.Code) { Say "prune: $($p.Out)" Yellow }
    CheckIntegrity
    Say "Удалено копий: $n" Cyan
}

# --- осиротевшие каталоги в .claude\worktrees --------------------------------
# Каталог, которого нет в `git worktree list`: git его не удалит, а Remove-Item по связи ушёл бы
# в цель. Поэтому те же проверки: сам не связь, внутри ни одной связи, нет своего .git-каталога
# (могут быть уникальные коммиты), не менялся -ActiveHours; повтор проверки перед удалением.
if ($Orphans) {
    $wtRoot = Join-Path $mainPath '.claude\worktrees'
    # PQ-01: если .claude или .claude\worktrees — связь, «сироты» лежат в ЧУЖОМ каталоге.
    foreach ($q in (Join-Path $mainPath '.claude'), $wtRoot) {
        if ((Test-Path -LiteralPath $q) -and ((Get-Item -LiteralPath $q -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { Abort "$q — связь; поиск сирот отменён" }
    }
    $reg = @{}
    foreach ($l in (Invoke-Git @('-C', $Repo, 'worktree', 'list', '--porcelain')).Out) {
        if ($l -like 'worktree *') { $reg[[IO.Path]::GetFullPath($l.Substring(9).Replace('/', '\')).TrimEnd('\').ToLowerInvariant()] = 1 }
    }
    $orph = @(if (Test-Path -LiteralPath $wtRoot) {
        Get-ChildItem -LiteralPath $wtRoot -Directory -Force | Where-Object { -not $reg.ContainsKey($_.FullName.TrimEnd('\').ToLowerInvariant()) }
    })
    Say "Незарегистрированных каталогов в $wtRoot : $($orph.Count)" Cyan
    foreach ($o in $orph) {
        $why = $null; $kind = 'сирота'
        $sc = Scan $o.FullName
        if ($sc.Links.Count) { $why = "СВЯЗИ: $($sc.Links -join '; ')" }   # в т.ч. «сам — связь» и «не читается»
        elseif ($sc.Nodes -eq 0) { $kind = 'пустой каталог' }               # PQ-01: пуст, прочитан, не связь — терять нечего
        elseif ($sc.Newest -gt (Get-Date).AddHours(-$ActiveHours)) { $why = "менялся $($sc.Newest.ToString('dd.MM HH:mm')) — возможно, в работе" }
        elseif (Test-Path -LiteralPath (Join-Path $o.FullName '.git') -PathType Container) { $why = 'внутри собственный .git-репозиторий — могут быть уникальные коммиты, разобрать вручную' }
        elseif (Test-Path -LiteralPath (Join-Path $o.FullName '.git') -PathType Leaf) {
            $u = OrphanUnique $o.FullName
            if ($u.Err) { $why = ".git-файл: $($u.Err)" }
            elseif ($u.Ignored.Count) { $why = ".git-файл: игнорируемые невоспроизводимые файлы ($($u.Ignored.Count)): $(($u.Ignored | Select-Object -First 8) -join ', ') — .env/ключи/БД/конфиги, разобрать вручную" }
            elseif ($u.Unique.Count) { $why = ".git-файл, gitdir удалён; файлов, которых нет ни в одном коммите: $($u.Unique.Count) (напр. $(($u.Unique | Select-Object -First 5) -join ', ')) — разобрать вручную" }
            else { $kind = 'сирота с .git-файлом: всё неигнорируемое есть в коммитах, игнорируемое воспроизводимо' }
        }
        else {
            # PQ-01: без .git это всё — неотслеживаемое; удаляем, только если ВСЁ внутри воспроизводимо.
            $base = $o.FullName.TrimEnd('\') + '\'
            $bad = @(Get-ChildItem -LiteralPath $o.FullName -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($base.Length) } | Where-Object { -not (IsRepro $_) })
            if ($bad.Count) { $why = "без .git; невоспроизводимые файлы ($($bad.Count)): $(($bad | Select-Object -First 8) -join ', ') — разобрать вручную" }
        }
        if ($why) { $script:skipped++; Say "  $($o.FullName)`n      ОСТАВЛЕН: $why" Yellow; continue }
        $script:pending++
        if (-not $Apply) { Say "  $($o.FullName)`n      к удалению ($kind)"; continue }
        $sc = Scan $o.FullName   # повтор непосредственно перед удалением
        if ($sc.Links.Count) { $script:skipped++; Say "  ПРОПУСК при повторной проверке: $($o.FullName)" Yellow; continue }
        Remove-TreeNoLinks $o.FullName
        Say "  удалён: $($o.FullName)" Green
        CheckIntegrity
    }
}

# --- слитые ветки без копий ---------------------------------------------------
if ($MergedBranches) {
    $busy = @{}
    foreach ($l in (Invoke-Git @('-C', $Repo, 'worktree', 'list', '--porcelain')).Out) { if ($l -like 'branch *') { $busy[($l.Substring(7) -replace '^refs/heads/', '')] = 1 } }
    $all = (Invoke-Git @('-C', $Repo, 'for-each-ref', '--format=%(refname:short)', 'refs/heads/')).Out | Where-Object { $_ }
    $protected = '^(main|master|develop|dev|release/.*|prod.*|stable.*)$'
    $cand = @(foreach ($b in $all) {
        if ($b -eq $Main -or $b -match $protected -or $busy.ContainsKey($b)) { continue }
        if ((Invoke-Git @('-C', $Repo, 'merge-base', '--is-ancestor', $b, $Main)).Code -eq 0) { $b }
    })
    $script:pending += $cand.Count
    Say "Слитых в $Main веток без копий: $($cand.Count)" Cyan
    foreach ($b in $cand) {
        if ($Apply) {
            $d = Invoke-Git @('-C', $Repo, 'branch', '-d', $b)   # -d: git сам откажет неслитой
            if ($d.Code) { $script:skipped++; Say "  не удалена $b : $($d.Out -join ' ')" Yellow } else { Say "  удалена ветка $b" Green }
        } else { Say "  к удалению: $b" }
    }
}

# --- выводы фоновых задач своей сессии ----------------------------------------
if ($TaskOutputs) {
    $base = if ($SessionDir) { [IO.Path]::GetFullPath($SessionDir) } else { $mainPath }
    $proj = ($base -replace '[^A-Za-z0-9]', '-')   # PQ-01: как Claude Code — любой знак кроме латиницы и цифр -> '-'
    $tdir = Join-Path $env:LOCALAPPDATA "Temp\claude\$proj"
    # сессии, запущенные внутри worktree, пишут в «<проект>--claude-worktrees-<имя>»
    $tdirs = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Temp\claude') -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $proj -or $_.Name -like "$proj--claude-worktrees-*" } | ForEach-Object FullName)
    if (-not $tdirs) { Say "Каталога выводов задач нет: $tdir — если сессия запущена из другого каталога (например, родительского), укажи его в -SessionDir" Yellow }
    else {
        $cut = (Get-Date).AddHours(-$TaskOutputAgeHours)
        $big = @(Get-ChildItem -LiteralPath $tdirs -Recurse -File -Force -Filter *.output -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge $TaskOutputMinMB * 1MB -and $_.LastWriteTime -lt $cut })
        $script:pending += $big.Count
        Say "Выводы задач в $tdir больше $TaskOutputMinMB МБ и старше $TaskOutputAgeHours ч: $($big.Count), $([math]::Round((($big | Measure-Object Length -Sum).Sum)/1GB,2)) ГБ"
        foreach ($f in $big) {
            Say ("  {0:N2} ГБ  {1:dd.MM HH:mm}  {2}" -f ($f.Length / 1GB), $f.LastWriteTime, $f.FullName)
            if ($Apply) {
                try { Remove-Item -LiteralPath $f.FullName -Force; Say "    удалён" Green }
                catch { $script:skipped++; Say "    НЕ удалён (занят или нет прав): $($_.Exception.Message)" Yellow }
            }
        }
    }
}

Say "Свободно на диске после: $(FreeGB $mainPath) ГБ"
if ($Gate -and $script:pending) { Write-Host "ОТКАЗ (-Gate): не убрано $($script:pending) — запусти wt-cleanup.ps1 с -Apply" -ForegroundColor Red; exit 3 }
if ($script:skipped) { exit 1 } else { exit 0 }

