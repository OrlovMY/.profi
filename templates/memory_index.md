# MEMORY.md — индекс памяти проекта

Skeleton для нового проекта. Скопировать в `memory/MEMORY.md`, пополнять после каждой сессии. Правила — см. `.profi/playbooks/memory_management.md`.

---

## Status (актуальное состояние проекта)

- [Текущий статус (<YYYY-MM-DD>)](project_session_<YYYY-MM-DD>_status.md) — что в master/проде, открытый backlog, blockers, совет следующей сессии
- [Data pipelines status](project_data_pipelines_status.md) — что работает / что в backlog

## Doctrine — правила работы

- [Workflow scheme](project_workflow_scheme.md) — канонический playbook (HR-D + agents + Big 7 + Phase A/B)
- [Agent briefing template](agent_briefing_template.md) — обязательный блок в каждый coding-промпт
- [Session start — load memory first](feedback_session_start.md) — в начале сессии читать MEMORY.md
- [Response format — role prefix](feedback_response_format.md) — `РОЛЬ [YYYY-MM-DD HH:MM]: ...`
- [Communication chain](feedback_communication_chain.md) — пользователь общается только с HR-D
- [HR-D never codes](feedback_hrd_no_coding.md) — всегда делегирует
- [Big 7 is the gate](feedback_big7_with_sec02.md) — Big 7 включает SEC-02
- [Production escalation](feedback_prod_escalation.md) — STOP → Big 7 → user-approve
- [No parallel agents on same tree](feedback_no_parallel_same_tree.md) — `isolation:"worktree"` или серриализация
- [Finish before new task](feedback_finish_before_new.md) — закончить текущее перед новым
- [Official docs required](feedback_official_docs_required.md) — Context7 / WebFetch до commit
- [Build policy — no local builds](feedback_build_policy.md) — собираем только на CI/VPS
- [UI redesign on growth](feedback_ui_redesign_on_growth.md) — новые поля = редизайн, не append
- [Admin tooltips mandatory](feedback_admin_tooltips.md) — каждый пункт UI с hover-tooltip
- [Changelog required](feedback_changelog_required.md) — каждая user-visible фича = запись
- [Autonomy policy](feedback_autonomy_policy.md) — деструктив только с явного одобрения
- [Investigate autonomously](feedback_autonomous_diagnosis.md) — не спрашивать что проверить
- [Task clarification](feedback_task_clarification.md) — короткое «верно понял?» перед реализацией

## Infrastructure & deploy

- [Deploy procedure](project_deploy_procedure.md) — полный pipeline local → VPS
- [Deploy bundle pitfall](project_deploy_bundle_pitfall.md) — `git checkout --detach` обязателен
- [Deploy lessons](project_deploy_lessons.md) — concurrency hazards, monitoring gaps
- [Server layout](project_server_layout.md) — пути на VPS, имена контейнеров
- [Resource tracking](project_resource_tracking.md) — журнал тяжёлых операций, триггеры апгрейда
- [WebSocket checklist](project_websocket_checklist.md) — router + nginx + hub + client keepalive

## Team

- [Team history](project_team_history.md) — хронология найма, состав команды
- [SEC-02 white-hat](project_sec02_whitehat.md) — внешний pentester, scope и процесс
- [<New role hired> (<date>)](project_<role>_hired.md) — как нанимали, скиллы, ownership

## Reference

- [<Domain> recipe](project_<domain>_recipe.md) — точная последовательность шагов для нетривиальной операции
- [<SDK/OEM> quirks](project_<sdk>_quirks.md) — особенности конкретного SDK/устройства/браузера

## User-specific

- [<Personal tooling>](user_<tooling>.md) — особенности окружения пользователя

## Backlog

- [<Backlog item title>](project_backlog_<topic>.md) — что отложено, почему, кто owner
