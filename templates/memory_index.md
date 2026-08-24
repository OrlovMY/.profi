# MEMORY.md — индекс памяти проекта

Skeleton для нового проекта. Скопировать в `memory/MEMORY.md`, пополнять после каждой сессии. Правила — см. `.profi/playbooks/memory_management.md`.

---

## Status (актуальное состояние проекта)

- [Текущий статус (<YYYY-MM-DD>)](project_session_<YYYY-MM-DD>_status.md) — что в master/проде, открытый backlog, blockers, совет следующей сессии
- [Data pipelines status](project_data_pipelines_status.md) — что работает / что в backlog

## ОБЯЗАТЕЛЬНО ДО ПЕРВОГО ДЕЙСТВИЯ (дата раздела: <YYYY-MM-DD>)

Набор — **перечень, а не признак**: правило попадает сюда не по значку в строке, а по цене нарушения — те, чьё нарушение необратимо (потеря устройства, потеря данных, простой боевой системы), и все действующие разрешения со сроком. Артефакт гейта старта — `ГЕЙТ память: N из M`, где M — число строк этого раздела, а не оценка на глаз (`scenarios/session-start.md`, Шаг 1).

- [<правило с необратимой ценой>](feedback_<...>.md) — <какой ущерб предотвращает>
- [<действующее разрешение со сроком до <дата>>](feedback_<...>.md) — <что разрешено, до когда>

**Порядок ведения:** правило, чьё нарушение стоило инцидента, вносится сюда тем же ходом, что и запись о самом инциденте. **Признак соблюдения:** у раздела стоит дата последнего изменения; появился в памяти новый файл с записью об инциденте, а дата раздела старше этой записи — порядок нарушен, набор пересматривается.

## RESUME / активные программы

Первая незакрытая запись — действующая программа работ; её читают первой на старте (`scenarios/session-start.md`, Шаг 2). Новая программа встаёт наверх тем же ходом, которым заводится; закрытая помечается ✅ и уходит вниз (`playbooks/memory_management.md`).

- [<активная программа> (<YYYY-MM-DD>)](project_<...>.md) — <что делаем, где остановились>
- ✅ [<закрытая программа>](project_<...>.md) — закрыта <YYYY-MM-DD>

## Doctrine — правила работы

- [Библиотека `.profi`](<путь к .profi в этом проекте>/README.md) — роли, сценарии, плейбуки, стандарты. **Здесь не дублируются**: правило живёт в `.profi`, в памяти — только проектная частность со ссылкой (`scenarios/session-start.md`, Шаг 1.5).
- [Agent briefing template](<путь к .profi в этом проекте>/templates/agent_briefing.md) — обязательный блок в каждый coding-промпт; плейсхолдеры подменяются под проект
- [Admin tooltips mandatory](feedback_admin_tooltips.md) — каждый пункт UI с hover-tooltip (проектное требование)
- [Changelog required](feedback_changelog_required.md) — каждая user-visible фича = запись (проектное требование)

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

История правок: `PE-01-разбор-2026-08-24.md`, раздел «Совместная редакция и применение», удаление 1 + каркас Г1, строка-ссылка на `agent_briefing.md` (правка PQ-01 при проверке применения); вердикты — `PQ-01-разбор-2026-08-24.md`; 2026-08-24.

История правок: `ревизия-свода-2026-08-24.md`, П8 (раздел «RESUME / активные программы» добавлен в каркас — три места свода его требуют, каркас не содержал); вердикты — `PQ-01-ревизия-2026-08-24.md`; 2026-08-24.
