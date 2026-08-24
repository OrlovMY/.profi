#!/bin/bash
# lint-svod.sh — механическая проверка свода: ссылки, wiki-ссылки, bash-блоки, инвариант имени БК.
# Отказ = ненулевой код возврата (носитель — pre-commit; заведено ревизией, раздел 13, Б17).
# Аварийный обход — только сознательный: PROFI_LINT_SKIP=i-know-broken-links-ship-anyway
set -u
if [ "${PROFI_LINT_SKIP:-}" = "i-know-broken-links-ship-anyway" ]; then
  echo "lint-svod: SKIPPED by PROFI_LINT_SKIP (цена названа в самой переменной)"; exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 2
export LC_ALL=en_US.UTF-8
fail=0
SCOPE="README.md knowledge scenarios playbooks roles templates"

# Внешние по построению имена (живут в проекте-потребителе, не в .profi) — класс + поимённый список.
ext_ok() {
  case "$1" in
    MEMORY.md|CLAUDE.md|notes.md|filename.md) return 0 ;;
    project_*.md|feedback_*.md|user_*.md) return 0 ;;
    memory/*|docs/*) return 0 ;;
    agent-admin-server-contract.md) return 0 ;;
  esac
  return 1
}

# 1. `path.md`-ссылки: от корня, от файла, по basename в каталогах свода/архива, либо внешние.
while IFS=: read -r src ln ref; do
  ref="${ref#\`}"; ref="${ref%\`}"
  [ -f "$ref" ] && continue
  [ -f "$(dirname "$src")/$ref" ] && continue
  base="${ref##*/}"
  hit=$(find README.md knowledge scenarios playbooks roles templates archive -name "$base" 2>/dev/null | head -1)
  [ -n "$hit" ] && continue
  ext_ok "$ref" && continue
  echo "BROKEN LINK: $src:$ln -> $ref"; fail=1
done < <(grep -rnoE '`[A-Za-zА-Яа-яЁё0-9_./-]+\.md`' --include="*.md" $SCOPE)

# 2. [[wiki-ссылки]] разрешаются в файл свода.
while IFS=: read -r src ln ref; do
  name="${ref#\[\[}"; name="${name%\]\]}"
  hit=$(find knowledge scenarios playbooks roles templates -name "$name.md" 2>/dev/null | head -1)
  [ -n "$hit" ] || { echo "BROKEN WIKILINK: $src:$ln -> $ref"; fail=1; }
done < <(grep -rnoE '\[\[[A-Za-z0-9_-]+\]\]' --include="*.md" $SCOPE)

# 3. ```bash-блоки парсятся (bash -n). Голый <плейсхолдер> в позиции списка ломает парсер — это и ловим.
#    Поимённый список блоков-шаблонов, standalone не парсящихся ПО ПОСТРОЕНИЮ (плейсхолдеры `<...>`
#    в конце строки или перед &&; исполняются только после подстановки — сверено 25.08.2026, раздел 13 Б17):
tpl_ok() {
  case "$1" in
    knowledge__standards__git-branch-discipline.md.1.sh) return 0 ;;   # ритуал merge+удаления: feat/<name> в конце строки
    knowledge__standards__git-dr-mirror-sync.md.1.sh) return 0 ;;      # форма-шаблон: <branch> после <адрес-записи>
    playbooks__worktree_deploy_safety.md.1.sh) return 0 ;;             # ls <файл-маркер из задания> в конце строки
    playbooks__worktree_deploy_safety.md.2.sh) return 0 ;;             # git fetch <ремоут> && … — плейсхолдер перед &&
  esac
  return 1
}
tmpd=$(mktemp -d)
for f in $(grep -rlE '^```bash' --include="*.md" $SCOPE); do
  awk -v d="$tmpd" -v f="$f" '
    /^```bash/ { i++; on=1; g=f; gsub(/\//,"__",g); out=d "/" g "." i ".sh"; next }
    /^```/ { on=0; next }
    on { print > out }' "$f"
done
for s in "$tmpd"/*.sh; do
  [ -e "$s" ] || break
  tpl_ok "$(basename "$s")" && continue
  bash -n "$s" 2>/dev/null || { echo "BASH SYNTAX: $(basename "$s") ($(bash -n "$s" 2>&1 | head -1))"; fail=1; }
done
rm -rf "$tmpd"

# 4. Инвариант имени БК: имя-с-числом — только дом (INDEX) и датированные исторические (поимённый список 12.1).
allowed='^(roles/big7/INDEX\.md|README\.md|knowledge/standards/delegate-background-ops-to-cheap-subagents\.md|knowledge/standards/delegate-search-to-persistent-haiku\.md|knowledge/standards/deploy-provenance-and-build-integrity\.md|knowledge/standards/transient-artifacts-cleanup\.md):'
viol=$(grep -rnoE '\bBig[ _-]?(6|7|9|10)\b|Больш[а-яё]+[ -]?(шестёрк|семёрк|девятк|десятк)[а-яё]*|Больш[а-яё]+ (6|7|9|10)\b' --include="*.md" $SCOPE | grep -vE "$allowed")
[ -n "$viol" ] && { echo "NAME INVARIANT VIOLATION (дом — roles/big7/INDEX.md):"; echo "$viol"; fail=1; }

[ "$fail" -eq 0 ] && echo "lint-svod: OK (links, wikilinks, bash blocks, name invariant)"
exit $fail
