# Resource tracking — мониторинг ресурсов VPS/инфры

## Зачем

1. Найти узкие места — что оптимизировать в коде/инфре.
2. Обосновать апгрейд ресурсов VPS (CPU/RAM/disk/bandwidth) числами, а не «кажется тормозит».
3. Не повторять ошибки concurrent-операций, которые сжирают ресурсы.

## Правило HR-D

После любого деплоя или инцидента, где зафиксирован heavy resource usage, добавлять запись в `memory/project_resource_tracking.md`. Также включать в финальные отчёты агентов вопрос «какие ресурсы это потребляло» (см. `templates/agent_briefing.md`).

## Что фиксировать

Каждая heavy операция (build, migration, restart, batch import) — отдельная строка в журнале:

| Поле | Источник | Пример |
|------|----------|--------|
| Операция | название | `docker compose build api` |
| Peak CPU % | `docker stats --no-stream`, `top -b -n1` | `60%` |
| Peak RAM | `docker stats`, `free -m` | `1 GB` |
| Disk delta | `df -h` до/после | `+1.3 GB build cache` |
| Final image size | `docker image ls` | `24 MB` |
| Bandwidth | оценка из размера × количество | `50 MB deps cold` |
| Время | `time <cmd>` | `30–90 с` |
| Замечание | риск, регресс, рекомендация | `Cache не чистится автоматически` |

Format таблицы — см. `templates/resource_log.md`.

## Что обязательно собрать в финальном отчёте deploy-агента

```bash
# До операции:
ssh root@<host> "df -h / && free -m && docker system df"

# Во время (запустить параллельно):
ssh root@<host> "docker stats --no-stream"

# После:
ssh root@<host> "df -h / && free -m && docker system df"
```

Дельта — в финальный отчёт.

## Триггеры апгрейда VPS

| Ресурс | Триггер | Действие |
|--------|---------|----------|
| CPU | устойчиво > 70% за > 1 ч в idle | +1 vCPU |
| RAM | < 500 MB available в idle | +2 GB |
| Disk | auto-cleanup > 40 GB used | +20 GB или внешний volume |
| Bandwidth | ISP throttling, deploy > 1 мин на serve | CDN |

## Триггеры оптимизации (не апгрейда)

| Симптом | Возможная оптимизация | Кому |
|---------|------------------------|------|
| Build cache > 5 GB | Cron weekly `docker builder prune -af --filter "until=168h"` | DO-01 |
| Frequent ENOSPC | Pre-deploy prune обязательным шагом | DO-01 |
| Postgres «too many clients» | Connection pool tuning | BE-01 |
| Большие файлы через WS base64 | Presigned URL через MinIO/S3 | BE-01 + AL/FE |
| Логи растут без bound | Retention policy + cron cleanup | BE + DO |
| API JSON большой | nginx `gzip on` | DO-01 |

## Retention policies (обязательны для растущих таблиц)

- `logs` / `events` / `audit` — 30–90 дней.
- `locations` / time-series — 1 год обычно.
- `commands` (терминальные) — > 90 дней архивировать в audit.

User-approve обязателен для DELETE-cron на проде.

## Anti-patterns

- Concurrent `docker compose build` + миграция → ENOSPC.
- `SELECT *` без `LIMIT` на растущей таблице → CPU/RAM spike.
- Push клиент-апдейта на > 100 устройств одновременно → bandwidth bottleneck.
- Build daemon (gradle daemon, npm cache concurrent) → OOM на маленькой VPS. Использовать `--no-daemon`.
- Логи без ротации → диск.
