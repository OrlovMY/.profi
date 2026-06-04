# Worktree Agent Deploy Safety — HARD RULES

**Создано после регрессии**: агент, работавший в git worktree, пересобрал и **сам задеплоил** web-bundle на прод-сервер, базируясь на устаревшей базе `master`. В git'е код был корректный, но бандл, который скачивал пользователь, — старый. Со стороны это выглядело как «всё сломано».

# Что НЕЛЬЗЯ делать в worktree-агенте

| Запрещено | Почему |
|---|---|
| `docker compose build` на прод-сервере | Build из stale worktree base → old bundle |
| `docker compose up -d --force-recreate` | Перетирает рабочий контейнер старым |
| `cp ...` в директорию статики / staging прода | Подкладывает stale артефакты в prod |
| `git push origin <branch>` | `master` не должен меняться агентом |
| Cherry-pick «для синхронизации» | Затягивает старые коммиты, перекрывая свежие |
| `git reset --hard` на `master` | Может удалить локальные правки |

# Что МОЖНО

| Разрешено | Условие |
|---|---|
| `git fetch origin && git rebase origin/master` | **Обязательно** до start work |
| `git commit` в свою feature ветку | Только локально |
| Build / typecheck для проверки **синтаксиса** | Только в worktree, не на prod-сервере |
| SSH на прод для **read-only** диагностики (curl, logs, ls) | Без mutate |
| Применить миграцию при **explicit ask** в брифинге | Когда координатор явно написал «migration apply разрешена» |

# Mandatory pre-flight для worktree-агента

В начале работы:
```bash
# 1. Sync с prod master (source of truth)
git fetch origin
git log origin/master -10            # показать, что уже отгружено в прод
git rebase origin/master              # катимся на свежак

# 2. Verify clean state
git status                            # working tree clean

# 3. Print branch base
git merge-base HEAD origin/master     # должно совпадать с tip origin/master
```

Если merge-base ≠ tip origin/master — **СТОП**. Основной workspace ушёл вперёд, рестартить worktree.

# Mandatory post-flight

Перед финальным отчётом:
```bash
# 1. Verify не сломал ничего на проде
ssh <prod-host> "curl -sk https://<app-host>/healthz"
ssh <prod-host> "docker exec <web-container> ls <static-dir>/assets | grep index-"
# Сравнить hash с тем, что был в начале (если это не deployment task)

# 2. Если bundle hash сменился без явного deploy в брифинге — REPORT regression
```

# В брифинге worktree-агенту ОБЯЗАТЕЛЬНО

```
### Permissions
- Bash/git/npm/go разрешены ВНУТРИ worktree.
- SSH на прод-сервер разрешён ТОЛЬКО для read-only diagnostics.
- ⛔ ЗАПРЕЩЕНО: `docker compose build/up`, `cp` в директорию статики/staging прода,
  `git push origin`, cherry-pick из других веток, `git reset --hard`.
- Deploy = координатор после merge ветки. Если не уверен → "ВОПРОС:" и стоп.
```

# Сигналы что агент нарушил правила

В его финальном отчёте:
- «Развёрнуто на проде»
- «web-контейнер пересобран и перезапущен»
- «Cherry-pick'нул `xxxxxxx` для синхронизации»
- «docker compose build clean → deployed»
- «Bundle обновлён в директории статики»

→ Это **red flag**. Немедленно re-build из текущего prod master ИЛИ rollback на предыдущий bundle.

# Related
- `.profi/playbooks/deploy_workflow.md` — нормальный deploy через координатора
- `.profi/playbooks/phase_a_b_split.md` — phase A агент только пишет, phase B координатор мержит и деплоит
- `.profi/knowledge/recipes/git_merge_strategies.md` — `-X theirs` опасности

# Rollback recipe (если уже случилось)

```bash
# 1. Re-build из current master
ssh <prod-host> "cd <deploy-dir> && docker compose build --no-cache web && docker compose up -d --force-recreate web"

# 2. Verify bundle hash сменился
ssh <prod-host> "docker exec <web-container> ls <static-dir>/assets | grep index-"

# 3. Force browser reload
# В Chrome: localStorage.clear() + hard reload
# Пользователю: «обнови страницу Ctrl+Shift+R»
```
