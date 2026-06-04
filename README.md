# Команда промптов для работы над проектом

Набор ролей, сценариев и плейбуков для сборки AI-команды (AI-HR подход). Проверено на реальном проекте промышленного масштаба.

## Что нового по сравнению с прошлой версией

- **Большая 7** вместо Большой 6 — добавлен `SEC-02` (white-hat pentester) как постоянный security gate после каждого изменения.
- **`playbooks/`** — концентрированные процедуры: workflow loop, Phase A/B split, prod-эскалация, deploy, resource tracking, memory.
- **`templates/`** — переиспользуемые шаблоны (agent briefing, MEMORY.md index, resource log, workflow scheme) с `<placeholder>`-маркерами.
- **Phase A / Phase B** — паттерн параллельной работы под `isolation:"worktree"`: subagent не имеет SSH, поэтому код и деплой разделены.
- **Production escalation** — формализованная процедура `STOP → Big 7 → user-approve`.
- **Resource tracking** — обязательная фиксация peak CPU/RAM/disk/bandwidth в финальных отчётах агентов.

## Структура

- `roles/` — промпты-роли. Каждый файл = системный промпт для одного агента.
  - `hr-d.md` — координатор. Единственная точка контакта с пользователем.
  - `big7/` — ядро принятия решений: PM/AR/BE/SEC-01/DO/QA + SEC-02. См. `big7/INDEX.md`.
  - `engineers/` — исполнители (backend, frontend, agent, ...).
- `scenarios/` — повторяющиеся рабочие сценарии (handoff, file ownership, git, parallel agents, post-incident memory).
- `playbooks/` — пошаговые процедуры под конкретные ситуации (deploy, prod-эскалация, Phase A/B, resource tracking, memory management).
- `templates/` — заготовки файлов для нового проекта (agent briefing с плейсхолдерами, MEMORY index, resource log, workflow scheme).
- `knowledge/` — универсальная техническая база знаний (кросс-проектная):
  - `standards/` — минимальные планки качества («UI не ниже этого», «APK обязательно имеет X»)
  - `guides/` — критерии выбора и подходы («выбор БД под условия», «стратегия сборки APK»)
  - `recipes/` — конкретные команды и последовательности для типовых задач

## Как использовать для нового проекта

1. **Скопировать `.profi/` в проект** или держать как submodule / отдельный clone рядом.
2. **Заполнить `templates/agent_briefing.md`** — подменить `<placeholder>`-маркеры на конкретику проекта (deploy host, имена контейнеров, test device, keystore и т.д.). Результат класть в `CLAUDE.md` или передавать в промпте каждого coding-агента.
3. **Скопировать `templates/memory_index.md` → `memory/MEMORY.md`** как индекс памяти; пополнять после каждой сессии.
4. **Назначить роли** — выбрать кто из ядра Большой 7 нужен сейчас, и какие инженеры. Промпт роли = содержимое `roles/<role>.md` + project-specific briefing.
5. **HR-D первый** — пользователь общается ТОЛЬКО с HR-D. HR-D делегирует остальным через Agent tool.
6. **Большая 7** — обязательная консультация перед нетривиальной работой: PM-01, AR-01, BE-01, SEC-01, DO-01, QA-01, SEC-02.

## Ключевые принципы

- **No regression** — изменения только улучшают. → `scenarios/no-regression.md`
- **HR-D не пишет код** — только делегирует агентам. → `roles/hr-d.md`
- **File ownership** — каждый интеграционный файл за одним владельцем. → `scenarios/file-ownership.md`
- **Feature branches** — `feat/xxx`, `fix/xxx` от master; merge только после «работает». → `scenarios/git-workflow.md`
- **Production = STOP** — prod-affecting → Big 7 → user-approve. → `playbooks/prod_escalation.md`
- **Phase A/B** — worktree-агенты только код; деплой отдельным агентом. → `scenarios/parallel-agents.md`
- **Верификация** — `git status` clean + hash в каждом отчёте. → `scenarios/task-template.md`
- **Честность** — не готово = «ЗАДАЧА НЕ ЗАВЕРШЕНА». → `scenarios/task-template.md`
- **Role prefix + время** — `РОЛЬ [YYYY-MM-DD HH:MM]: ...` в каждом сообщении. → `scenarios/communication.md`
- **Официальная документация** — Context7 MCP / WebFetch перед кодом; память модели вторична. → все роли
- **Память = индекс + файлы** — `MEMORY.md` только ссылки. → `playbooks/memory_management.md`

## Быстрый старт

См. `playbooks/workflow_loop.md` для типичного потока «user task → HR-D → агенты → Big 7 → deploy → smoke → memory update».
