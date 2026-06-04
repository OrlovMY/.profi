# Workflow scheme — <PROJECT> canonical playbook

Шаблон для `memory/project_workflow_scheme.md`. Одна точка истины «как сейчас всё устроено». Когда правило меняется — править этот файл и `MEMORY.md` если появилась новая ссылка.

---

## Роль HR-D

HR-D = координатор, не разработчик. Полное описание роли — `.profi/roles/hr-d.md`.

---

## Роли agents

В промпте агента HR-D указывает явную роль (или команду). Subagent_type — `general-purpose` или `Explore`; роль — в первой строке промпта.

Текущая команда (заполнить под проект):
- **<RL-NN>** <role description> | владение <files/packages>
- ...

---

## Большая 7 (Big 7)

Состав, кворум, когда созывать — `.profi/roles/big7/INDEX.md`.
Формат консультации — `.profi/scenarios/big7-consultation.md`.

---

## Production-affecting decisions

**STOP → Big 7 → user-approve (если Big 7 решит) → execute.**

См. `.profi/playbooks/prod_escalation.md` для полного списка.

---

## Phase A / Phase B — параллельная работа

См. `.profi/scenarios/parallel-agents.md`.

---

## Agent briefing

Каждый coding-промпт содержит embedded брифинг — см. `.profi/templates/agent_briefing.md` с подмененными плейсхолдерами под этот проект.

---

## Memory management

HR-D пополняет `memory/*.md` после каждой сессии. См. `.profi/playbooks/memory_management.md`.

`MEMORY.md` = индекс, не содержание.

---

## Git workflow

- Все ветки от `master`. NEVER commit to master directly.
- `feat/<name>` для фич, `fix/<name>` для багов.
- Deploy с feature branch; merge в master — только после «работает» от пользователя.
- Bundle deploy: см. `scenarios/git-workflow.md` (обязателен `--detach` перед fetch).

---

## Resource tracking

См. `.profi/playbooks/resource_tracking.md`.

---

## Workflow loop (типовая сессия)

См. `.profi/playbooks/workflow_loop.md` — 9 шагов от user task до memory update.

---

## Текущая команда (актуально на <YYYY-MM-DD>)

См. `project_team_history.md` и `project_<role>_hired.md` для каждой добавленной роли.
