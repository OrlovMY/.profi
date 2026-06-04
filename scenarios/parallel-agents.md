# Parallel agents — isolation:"worktree" + Phase A/B

## Проблема

Несколько coding-агентов одновременно в одном git working tree → переключают ветки друг под другом, незавершённые rebase, потеря коммитов. Реальный кейс: ~14 переключений ветки за минуту между двумя параллельными агентами; один оставил 4 файла uncommitted после того как другой переключил ветку.

## Решение: `isolation:"worktree"`

```
Agent({ description, subagent_type, prompt, isolation: "worktree" })
```

Каждый агент работает в отдельном git worktree (свой checkout, свой index, свой WORKDIR). Конфликтов в working tree нет. После завершения агент возвращает worktree path и branch name; HR-D мержит вручную.

## Критическое ограничение: worktree блокирует сеть

Subagent в worktree-sandbox **не имеет SSH/scp/curl к внешним хостам**. Поэтому coding и deploy нельзя совмещать в одном worktree-агенте.

## Phase A / Phase B

### Phase A — coding (параллельно, `isolation:"worktree"`)

Несколько агентов работают одновременно, каждый в своём worktree:
- Создаёт ветку от `master`.
- Пишет код, коммитит.
- Возвращает: branch name + commit hash + handoff-список.
- **НЕ выполняет** `ssh`, `scp`, прод-команды.

Промпт каждого worktree-агента **обязан содержать**:
> «Phase A only. Не выполнять SSH/scp/прод-команды. Написать код, закоммитить, вернуть branch + commit hash. Деплой — отдельный агент.»

### Phase B — deploy (последовательно, один агент, БЕЗ isolation)

После завершения всех Phase A агентов — HR-D запускает **один** агент с Bash+SSH доступом:
- Забирает все ветки.
- Мержит в master, разрешает конфликты.
- Bundle → scp на VPS → `git checkout --detach` → `git fetch ... HEAD:master`.
- Применяет миграции → build → restart → reload nginx.
- Smoke-тесты.

Детально — `playbooks/deploy_workflow.md`.

## Маршрутизация HR-D

| Сценарий | Решение |
|---|---|
| 1 агент пишет код | Без isolation OK. |
| 2+ агентов пишут код в разных пакетах | `isolation:"worktree"` для **всех** writers. |
| 2+ агентов, возможно пересечение файлов | `isolation:"worktree"` для **всех** + handoff через HR-D. |
| Read-only / research (Explore) | Безопасно параллельно без worktree. |
| Coding + deploy | Phase A (worktree) → Phase B (один deploy-агент без isolation). |
| Hotfix в одном файле | Один не-изолированный агент end-to-end. |

## Pre-flight checklist HR-D перед параллельным запуском

1. Все ли агенты read-only? → ОК, параллельно без worktree.
2. Если хоть один пишет — `isolation:"worktree"` для **всех** writers.
3. Промпт каждого агента содержит свою ветку и инструкцию создать её от master.
4. Промпт каждого Phase A агента явно запрещает SSH/scp.
5. После завершения всех Phase A — HR-D последовательно мержит и запускает Phase B.

## Конфликты после Phase A

- Если конфликтов нет — `git merge --no-ff feat/...`.
- Если конфликты — резолвит HR-D или owner интеграционных файлов; авторы получают diff на review.
- Никогда не делать `--strategy-option=ours/theirs` без понимания — теряются изменения.

## Когда НЕ использовать параллель

- Задача затрагивает много общих файлов (`router.go`, `main.go`, `Layout.tsx`) — конфликты неизбежны; serialize.
- Архитектурное решение ещё не принято — параллельно делать нечего.
- Маленькая задача (1 файл, ~30 строк) — параллель не даст выигрыша.

## Anti-patterns

- Worktree-агент пытается `ssh root@<host>` — упадёт на sandbox-блокировке. Всегда упоминать «Phase A only» в промпте.
- Два writer-агента **БЕЗ** worktree → branch flapping, потеря коммитов.
- Один deploy-агент **С** worktree → не сможет scp/ssh. Всегда без isolation для Phase B.
- Параллельный `docker compose build` + миграция → ENOSPC. Сериализовать в Phase B.

---

> **Официальная документация.** При настройке CI/CD или инструментов изоляции — сверяться с актуальной документацией (Context7 MCP / WebFetch), не с памятью модели.
