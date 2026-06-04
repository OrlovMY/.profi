# Resource log template

Шаблон для `memory/project_resource_tracking.md`. HR-D пополняет после каждого деплоя/инцидента.

---

# VPS resource consumption tracking

**Цель:** копить наблюдения о том, какие действия грузят ОЗУ/CPU/диск/трафик, чтобы:

1. Найти узкие места — что оптимизировать.
2. Обосновать апгрейд VPS числами.
3. Не повторять concurrent-ошибки.

---

## Обзор VPS (актуально на <YYYY-MM-DD>)

| Ресурс | Лимит | Регулярная утилизация |
|---|---|---|
| CPU | <N> vCPU | <%idle / peak when> |
| RAM | <N> GB | <typical usage> |
| Disk | <N> GB | <% used> |
| Network | <plan> | <peak when> |

---

## Журнал тяжёлых операций

### <YYYY-MM-DD>

| Операция | CPU peak | RAM peak | Disk delta | Traffic | Время | Замечание |
|---|---|---|---|---|---|---|
| `<command>` | <%> | <MB/GB> | <delta> | <MB/GB> | <s> | <risk / lesson / recommendation> |

---

## Backlog оптимизаций (на основе наблюдений)

| Приоритет | Что | Почему | Кому |
|---|---|---|---|
| HIGH | <optimization> | <symptom from log> | <owner> |
| MEDIUM | <optimization> | <symptom> | <owner> |
| LOW | <optimization> | <symptom> | <owner> |

---

## Триггеры апгрейда VPS

Пороговые значения — `playbooks/resource_tracking.md`.

## Триггеры для конкретных операций (отложенных)

- **<DB tuning>** — Trigger: <metric>. Cost: <downtime>. Owner: <role>.

## Retention policies (user-approved)

- **<table_name>**: <N> дней. Cron <time> UTC daily, скрипт `<path>`. Override env `<VAR>`.

---

## Методология HR-D

После каждой задачи спрашивать у возвращающегося агента: «какой пик ресурсов был замечен (если запускал что-то на VPS)?» — включено в `templates/agent_briefing.md` как часть VERIFICATION-блока.
