# Сценарий: Git workflow

## Правило

Все новые фичи и фиксы разрабатываются в отдельных ветках. Слияние в `master` — только после завершения работы и успешного деплоя.

| Тип | Ветка | Источник |
|-----|-------|----------|
| Новая фича | `feat/<name>` | `master` |
| Фикс бага | `fix/<name>` | `master` |
| Hotfix (критично) | `hotfix/<name>` | `master` |
| Chore / infra | `chore/<name>` | `master` |

## Правила для агентов

1. **Ветка от master** — `git checkout master && git pull && git checkout -b feat/<name>` **перед** началом работы.
2. **Коммиты только в свою ветку.** Прямая запись в `master` запрещена.
3. **Commit messages** — conventional commits:
   - `feat(scope): ...` — новая фича
   - `fix(scope): ...` — фикс
   - `chore(scope): ...` — служебное
   - `docs(scope): ...` — документация
   - `refactor(scope): ...` — рефакторинг без изменения поведения
4. **По завершении** — сообщить PM-01 хэш коммита и готовность к merge.
5. **Merge в master** — делает владелец интеграционного файла или DO-01 при деплое.

## Что запрещено без явного одобрения пользователя

- `git push --force` в master (или публичные ветки).
- `git reset --hard` на публичных ветках.
- `git rebase -i` интерактивный (--no-edit и т.п.) — не поддерживается в AI-workflow.
- `git commit --no-verify` — не пропускать hooks. Если hook падает — чинить причину, а не обходить.
- `git commit --amend` на опубликованных коммитах.
- Удаление веток, которые могут содержать непомёрдженную работу.

## Destructive Git Operations — всегда спрашивать

Перед выполнением:
- force push
- reset --hard
- branch -D (force delete)
- clean -fdx
- checkout -- / restore .

спросить пользователя явно и дождаться «да».

## Деплой через git bundle (стандарт)

Когда нет push-доступа к VPS, используется bundle-flow. **Критично:** на VPS перед `git fetch` в активную ветку обязательно отстёгивать HEAD, иначе fetch падает silently.

```bash
# Локально:
VPS_HEAD=$(ssh root@<remote_host> "cd <repo_path> && git rev-parse master")
git bundle create /tmp/<task>.bundle ${VPS_HEAD}..HEAD HEAD
scp /tmp/<task>.bundle root@<remote_host>:/tmp/

# На VPS — ВСЕГДА detach перед fetch в master:
ssh root@<remote_host> "cd <repo_path> && \
  git checkout --detach && \
  git fetch /tmp/<task>.bundle HEAD:master && \
  git checkout master && \
  git log --oneline -3"
```

**Почему `--detach` обязателен:** git отказывает `fatal: refusing to fetch into branch 'refs/heads/master' checked out at '<path>'`. Без detach fetch не применяется → последующий `git reset --hard master` указывает на старый ref → артефакты пересобираются со старого кода → пользователь видит регресс. В реальной практике это «молча провалилось» несколько раз подряд.

**Всегда** проверять `git log --oneline -3` после fetch — не доверять «fetch finished without errors».

## Деплой через push (если есть post-receive hook)

```bash
git push vps master    # автоматический deploy
```

В этом случае merge в master = деплой. Политика веток становится критичной — никто не пушит в master то, что не готово к продакшну.

## Когда merge в master

Только **после** фразы пользователя «работает» (или эквивалент). Деплой делается с feature branch; master = только подтверждённый код. См. `playbooks/workflow_loop.md` шаг 9.

---

> **Официальная документация.** При любых технических решениях сверяться с актуальными источниками (Context7 MCP / WebFetch / официальные docs). Не опираться на память модели.
