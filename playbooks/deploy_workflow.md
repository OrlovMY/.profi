# Deploy workflow — generic procedure

Generic deploy pipeline для проекта на VPS с Docker. Подставить плейсхолдеры (`<remote_host>`, `<repo_path>`, `<container_xyz>`) под конкретный проект.

## 1. Pre-flight (mandatory)

```bash
ssh root@<remote_host> "df -h /"
```
- Должно быть **< 70% used**. Если выше → `docker system prune -af --filter "until=72h"`, проверить ещё раз. Только потом — миграции и build.

```bash
ssh root@<remote_host> "docker compose ps --format '{{.Name}}\t{{.Status}}'"
```
- Все контейнеры в `healthy`.

```bash
ssh root@<remote_host> "docker system df"
```
- Reclaimable < 2 GB. Иначе prune.

**Правило:** НИКОГДА не запускать `docker compose build` параллельно с миграцией — build cache забивает overlay fs снизу, и Postgres получает `No space left on device` посреди транзакции.

## 2. Bundle workflow (стандарт)

```bash
# 1. Найти VPS HEAD как точку старта bundle
VPS_HEAD=$(ssh root@<remote_host> "cd <repo_path> && git rev-parse master")

# 2. Создать bundle от VPS HEAD до твоего HEAD
git bundle create /tmp/<task>.bundle ${VPS_HEAD}..HEAD HEAD

# 3. Залить
scp /tmp/<task>.bundle root@<remote_host>:/tmp/

# 4. Применить — КРИТИЧНО: detach HEAD перед fetch в активную ветку
ssh root@<remote_host> "cd <repo_path> && \
  git checkout --detach && \
  git fetch /tmp/<task>.bundle HEAD:master && \
  git checkout master && \
  git log --oneline -3"
```

**Почему `git checkout --detach` обязателен** — полное объяснение в `scenarios/git-workflow.md`. Без detach fetch падает silently → deploy идёт со старого кода. Всегда проверять `git log --oneline -3` после fetch.

## 3. Migration перед build (всегда)

Apply миграции **до** `docker compose build`. Build cache (~1–2 GB) может забить overlay → ENOSPC у Postgres.

```bash
ssh root@<remote_host> "docker exec -i <postgres_container> psql -U <db_user> -d <db_name> < <repo_path>/infra/postgres/migrations/NNN_*.sql"
```

- Все миграции должны быть идемпотентными: `CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... IF NOT EXISTS COLUMN`.
- Verify: `\d <new_table>`.

## 4. Build order

```bash
# Только backend:
ssh root@<remote_host> "cd <compose_path> && docker compose build <api_container> && docker compose up -d <api_container>"

# Только frontend:
ssh root@<remote_host> "cd <compose_path> && docker compose build <web_container> && docker compose up -d <web_container>"

# Оба:
ssh root@<remote_host> "cd <compose_path> && docker compose build <api_container> <web_container> && docker compose up -d <api_container> <web_container>"

# Новая npm зависимость → без кэша:
ssh root@<remote_host> "cd <compose_path> && docker compose build --no-cache <web_container>"
```

## 5. nginx reload (после web rebuild или правок nginx.conf)

```bash
ssh root@<remote_host> "docker exec <web_container> nginx -t && docker exec <web_container> nginx -s reload"
```

Если `nginx -t` упал — **НЕ** делать reload; revert config и report. Иначе уронишь web.

## 6. Smoke (mandatory — paste output verbatim)

- `curl -sk https://<public_host>/healthz` → 200 `{"status":"ok"}`.
- Login + extract token, hit затронутые endpoints (200 vs 4xx/5xx).
- Если меняли nginx — `curl -sI https://<public_host>/` для headers.
- Если меняли клиент-артефакт (APK/binary) — verify checksum + version.

## 7. ENOSPC handling

Если посреди deploy `No space left on device`:
1. STOP, не паниковать, не зацикливаться.
2. `docker system prune -af --filter "until=72h"` (или `--volumes` если согласовано Big 7).
3. `df -h` проверить.
4. **Retry миграции** (она в транзакции откатилась). Build идемпотентен — пересоберётся.
5. Если повторился — эскалация Big 7 (нужен апгрейд диска или агрессивный prune).

## 8. Rollback

| Что | Как |
|---|---|
| Backend | `docker compose up -d <api_container>` со старым tag. Если `docker image prune -af` снёс старые tags → `git checkout <prev-good-commit> && docker compose build <api_container> && docker compose up -d <api_container>`. |
| Frontend | `git revert <merge-commit> && docker compose build <web_container> && docker compose up -d <web_container>`. |
| Migration | Только через reverse migration (`NNN_revert_*.sql`); **никогда** `DROP` руками без эскалации Big 7. |

## 9. Post-deploy fix-tracking

Если что-то требует ручного действия пользователя (grant permission, hard-reload браузера, переэнрол агента) — отдельным пунктом в финальном отчёте HR-D пользователю.

## 10. Resource report

В финальном отчёте deploy-агента указать (см. `templates/resource_log.md`):
- Peak CPU/RAM во время операции.
- Disk before/after.
- Время операции (секунды).
- Bandwidth для трафиковых операций (serve бинарей, log upload).

HR-D переносит в `memory/project_resource_tracking.md`.
