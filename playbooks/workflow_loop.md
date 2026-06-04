# Workflow loop — типичный поток сессии

Канонический 9-шаговый цикл от задачи пользователя до обновления памяти. HR-D координирует, остальные исполняют.

## 0. Входящая задача — проверка приоритета

Перед принятием новой задачи HR-D проверяет:
- **Есть ли незавершённая текущая задача?** Если да и новая не помечена «срочно» — сначала завершить текущую, потом браться за новую. Сообщить пользователю.
- **Активный план (`memory/project_active_plan.md`) прочитан?** Если нет — прочитать перед ответом.

## 1. User даёт задачу

HR-D:
- Если ambiguous — задаёт **один** короткий уточняющий вопрос в формате «верно понял: X и Y?» и ждёт подтверждения. Не серия вопросов, не длинная аналитика.
- Если понятно — переформулирует в техзадание (одна-две фразы) и переходит к шагу 2.
- **Не приступает к реализации до подтверждения понимания** — особенно если задача затрагивает несколько систем или меняет архитектуру.

## 2. HR-D разбивает на subtasks

- По ролям из матрицы ownership.
- Решает: параллельно или последовательно?
  - Все coding-задачи параллельно → `isolation:"worktree"` для каждой.
  - Если требуется prod-write → разделить на Phase A (worktree, код) и Phase B (один deploy-агент без isolation).
  - Read-only research — безопасно параллельно без worktree.
- Если задача нетривиальна → созыв Большой 7 (шаг 5 поднимается на 2.5).

## 3. HR-D запускает агентов

Каждый промпт coding-агента содержит:
- Embedded briefing (`templates/agent_briefing.md` с подставленными плейсхолдерами).
- Явную роль: `Ты — <РОЛЬ>`.
- Имя ветки `feat/<name>` / `fix/<name>`.
- Список «НЕ ТРОГАТЬ» (чужие интеграционные файлы).
- Handoff-инструкцию (кому передать diff).
- Verification checklist в конце.

Параллельный запуск независимых агентов в одном сообщении — кратно сокращает wall-time.

## 4. Агенты завершают

Каждый агент возвращает:
- Branch name + commit hash.
- Output `git status` (должно быть clean).
- Список новых endpoints / событий / роутов для handoff владельцу интеграции.
- Peak CPU/RAM/disk/bandwidth, если запускал что-то на VPS.

HR-D суммирует статус в чате (commit hashes, ветки, что отдано на интеграцию).

## 5. Big 7 голосует

На любые prod-affecting и архитектурные решения. Формат — см. `roles/big7/INDEX.md`. Если требуется user-approve — HR-D эскалирует владельцу с (1) что предлагается, (2) почему, (3) reversibility cost.

## 6. Phase B deploy

Один агент без `isolation` (имеет Bash+SSH). Последовательно:
- Pre-flight resource check.
- Merge feature branches; resolve conflicts.
- Bundle → scp → fetch на VPS (с `git checkout --detach` обязательно).
- Migration → build → restart → reload.

Детально — `playbooks/deploy_workflow.md`.

## 7. Smoke + verification

- Health endpoint 200.
- Логин админа + ключевые user-flows.
- Если меняли nginx — curl headers.
- Если меняли клиент — version checksum.
- **Paste output verbatim** в чат HR-D.

QA-01 утверждает; если что-то падает — rollback и обратно на шаг 3.

## 8. HR-D обновляет память

Триггеры и шаблоны — `scenarios/post-incident-memory-update.md`.
Таксономия файлов и структура — `playbooks/memory_management.md`.

## 9. HR-D даёт пользователю чеклист

Что проверить в UI / на устройстве / в логах. Короткий список из 2–5 пунктов. Только то, что пользователь должен сделать руками.

## Merge в master

Правило — `scenarios/git-workflow.md` раздел «Когда merge в master».

## Anti-patterns (избегать)

- `docker compose build` параллельно с миграцией → ENOSPC регресс на overlay fs.
- Merge в master до «работает» от пользователя.
- Отчёт «готово» без commit hash и git status.
- Нарушения worktree/deploy — см. `scenarios/parallel-agents.md` и `scenarios/git-workflow.md`.
