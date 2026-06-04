# Recipe: уборка git worktrees + старых веток (после серий worktree-агентов)

## Условия применения
Проект, где coding-агенты работают в изолированных git worktree (`isolation: "worktree"`). Со временем `.claude/worktrees/agent-*` + одноимённые ветки накапливаются, если не чистить после merge. Симптом: сотни локальных веток, десятки/сотни зарегистрированных worktree, locked-worktree пинят даже смерженные ветки.

## Суть (по убыванию безопасности)
1. **Worktrees — безопасно** (удаляет рабочую папку, НЕ ветку; коммиты остаются refs):
   ```bash
   git worktree prune -v
   git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //' \
     | grep '/.claude/worktrees/agent-' | while read -r wt; do
       git worktree unlock "$wt" 2>/dev/null
       git worktree remove --force "$wt" 2>/dev/null
     done
   git worktree prune
   ```
   Locked-worktree требуют `unlock` перед `remove --force`. `prune` сам не снимет те, чья папка ещё на диске.
2. **Merged-ветки — безопасно:** `git branch --merged master | grep -vE '^\*|master' | xargs -r git branch -d` (`-d`, не `-D` — откажется на несмерженном).
3. **Unmerged-ветки — ОСТОРОЖНО:** по каждой `git log --oneline master..<branch>` → решить superseded vs уникальное. Superseded (фича реализована иначе/в проде, эксперимент) → `git branch -D`. Уникальное → оставить + сообщить владельцу. **Не удалять вслепую.**

## Антипаттерны
- ❌ Не чистить worktree после merge → накопление (реальный кейс: 320 веток / 140 worktree).
- ❌ `git branch -D` по `--no-merged` массово без проверки `master..branch` → потеря работы.
- ❌ Делать уборку «на лету» без плана/трекера/документации и без явного «да» владельца — деструктив требует одобрения, а сам факт уборки фиксируется как задача (даже housekeeping ведётся по стандарту проекта).
- ❌ Трогать `master`, деплой-ref (`vps-master`), текущую ветку.

## Лучшая практика
Чистить worktree сразу после merge worktree-агента (не копить). Периодический прогон шагов 1-2 как routine; шаг 3 — ревью.

## Источник
MDMy 2026-06-03: накопилось 320 веток / 140 locked-worktree (нарушение «cleanup after merge»). Owner-напоминание: даже уборка ведётся по стандарту (план+трекер+док). Runbook проекта: `docs/maintenance/repo-hygiene.md`.
