# Worktree Agent Deploy Safety — HARD RULES

**Created 2026-05-22 после регрессии**: agent в worktree пересобрал и **сам задеплоил** web-bundle на VPS, базируясь на устаревшем master. В git'е код был корректный, но бандл, скачиваемый юзером, — старый. Owner увидел «всё сломано».

# Что НЕЛЬЗЯ делать в worktree-агенте

| Запрещено | Почему |
|---|---|
| `docker compose build` на VPS | Build из stale worktree base → old bundle |
| `docker compose up -d --force-recreate` | Перетирает рабочий контейнер старым |
| `cp ... /var/www/...` или `cp ... /opt/mdmy/staging/` | Подкладывает stale артефакты в prod |
| `git push origin <branch>` | Master не должен меняться агентом |
| Cherry-pick «для синхронизации» | Затягивает старые коммиты, перекрывая свежие |
| `git reset --hard` на master | Может удалить локальные правки |

# Что МОЖНО

| Разрешено | Условие |
|---|---|
| `git fetch origin && git rebase origin/master` | **Обязательно** до start work |
| `git commit` в свою feature ветку | Только локально |
| Build / typecheck для проверки **синтаксиса** | Только в worktree, не на VPS prod |
| `ssh root@<vps>` для **read-only** диагностики (curl, logs, ls) | Без mutate |
| Применить миграцию через psql при **explicit ask** в брифинге | Когда HR-D написал «migration apply разрешена» |

# Mandatory pre-flight для worktree-агента

В начале работы:
```bash
# 1. Sync с VPS prod master (source of truth)
git fetch origin
git log origin/master -10            # show what owner has shipped
git rebase origin/master              # катимся на свежак

# 2. Verify clean state
git status                            # working tree clean

# 3. Print branch base
git merge-base HEAD origin/master     # должно совпадать с tip origin/master
```

Если merge-base ≠ tip origin/master — **СТОП**. Owner workspace ушёл вперёд, рестартить worktree.

# Mandatory post-flight

Перед финальным отчётом:
```bash
# 1. Verify не сломал ничего на проде
ssh root@vps "curl -sk https://app/healthz"
ssh root@vps "docker exec web ls /usr/share/nginx/html/assets | grep index-"
# Сравнить hash с тем, что был в начале (если не deployment task)

# 2. Если bundle hash сменился без явного deploy в брифинге — REPORT regression
```

# В брифинге HR-D worktree-агенту ОБЯЗАТЕЛЬНО

```
### Permissions
- Bash/git/npm/go разрешены ВНУТРИ worktree.
- ssh root@<vps> разрешён ТОЛЬКО для read-only diagnostics.
- ⛔ ЗАПРЕЩЕНО: `docker compose build/up`, `cp в /var/www|/opt/mdmy`,
  `git push origin`, cherry-pick из других веток, `git reset --hard`.
- Deploy = HR-D после merge ветки. Если не уверен → "ВОПРОС:" и стоп.
```

# Сигналы что агент нарушил правила

В его финальном отчёте:
- «Развёрнуто на проде»
- «mdm-web пересобран и перезапущен»
- «Cherry-pick'нул `xxxxxxx` для синхронизации»
- «docker compose build clean → deployed»
- «Bundle обновлён в /var/www/...»

→ Это **red flag**. Немедленно re-build из текущего VPS master ИЛИ rollback на предыдущий bundle.

# Related
- `.profi/playbooks/deploy_workflow.md` — нормальный deploy через HR-D
- `.profi/playbooks/phase_a_b_split.md` — phase A агент только пишет, phase B HR-D мержит и деплоит
- `.profi/knowledge/recipes/git_merge_strategies.md` — `-X theirs` опасности

# Rollback recipe (если уже случилось)

```bash
# 1. Re-build из current master
ssh root@vps "cd /opt/mdmy && docker compose build --no-cache web && docker compose up -d --force-recreate web"

# 2. Verify bundle hash сменился
ssh root@vps "docker exec web ls /usr/share/nginx/html/assets | grep index-"

# 3. Force browser reload
# В Chrome: localStorage.clear() + hard reload
# Юзер: «обнови страницу Ctrl+Shift+R»
```
