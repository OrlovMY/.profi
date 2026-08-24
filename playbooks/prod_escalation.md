# Production escalation — STOP → Big 7 → user-approve

Любое действие агента, затрагивающее shared production infrastructure, **требует эскалации в Большую 7 через HR-D до выполнения**. Агент не вправе самостоятельно решать «это безопасно».

## Pipeline (мнемоника)

```
STOP  →  Big 7  →  user-approve (если Big 7 решит)  →  execute
```

## Что считается production-affecting (эскалировать)

1. `docker prune` (любой), volume operations, image deletion.
2. Migration retry после ошибки, ручной DB fix, `ALTER`/`DROP`.
3. Restart cascade (≥ 2 контейнеров одновременно).
4. nginx config swap без готового rollback (без `nginx -t`).
5. Push клиентского обновления / агент-update на > 1 device одновременно.
6. Любая команда с `-f` / `--force` / `--volumes`.
7. Touch credentials, secrets, certs.
8. Disabling/relaxing security middleware «временно».
9. Изменения данных в продовой БД.

## Что НЕ требует эскалации (агент может сам)

- Read-only диагностика (`df`, `docker ps`, `psql -c "SELECT ..."`, `tail logs`).
- Apply известной idempotent migration в нормальных условиях.
- Restart **одного** контейнера на already-built image.
- Rollback на known-good версию по явной инструкции HR-D.
- Build-cache prune без image deletion (если согласовано как routine).

## Когда Big 7 требует user-approve

- **Невосстановимое действие** — `DROP`, `--volumes`, удаление данных, force push в master, перезапись keystore.
- **Downtime > 1 мин.**
- **Безопасность / доступы** — secret rotation, отключение MFA, изменение auth-логики на проде.
- **Изменение биллинга / ресурсов** — апгрейд VPS, новый платный сервис.

## Когда Big 7 пропускает user-approve

- Rollback на known-good.
- Idempotent recovery.
- Build-cache prune без image deletion.
- Restart одного контейнера на already-built image.

В этих случаях HR-D отчитывается по факту: «было X, Big 7 одобрила Y без эскалации, потому что Z».

## Состав Big 7 для эскалации

Минимум три голоса: **PM-01 (priority/risk) + DO-01 (technique) + SEC-01 (security)**. Дополнительно по необходимости:
- QA-01 — если есть тест-импакт.
- AR-01 — если затрагивает архитектуру.
- SEC-02 — если security-surface меняется.

## Эскалационная фраза в промптах агентов

> If you encounter a production-affecting decision (see scope), STOP, do not execute, return to HR-D with: (1) what you propose, (2) why, (3) reversibility cost. HR-D созывает Big 7.

## Emergency action

Только в life-or-death deploy (всё уже сломано, downtime растёт) допустимо emergency action. Агент пишет:

> EMERGENCY: <действие>. Post-hoc review by Big 7.

И сразу же — HR-D созывает Big 7 для post-mortem.

## Деструктивный прод-SSH → координатор маршрутизирует в ПЕРСИСТЕНТНЫЙ Big-7 (owner 2026-07-08)

Когда авто-guard (напр. PreToolUse-хук) детектирует **деструктивную/мутирующую операцию по прод-SSH** (DROP/DELETE/TRUNCATE/UPDATE прод-данных, `rm -rf`, `docker down/rm/prune`, reboot/shutdown хоста, force push и т.п.) — решение принимает **НЕ owner через raw permission-промпт, а координатор, направляя запрос в ПЕРСИСТЕНТНЫЙ Big-7-агент** (SendMessage, накопленный контекст сессии) и действуя по его вердикту ДО выполнения.

- Координатор НЕ выполняет такую операцию, пока не получил вердикт персистентного Big-7.
- Big-7 (минимум PM-01 + DO-01 + **SEC-01**; плюс SEC-02, если меняется security-surface — тот же кворум, что в «Состав Big 7 для эскалации» выше и `roles/big7/INDEX.md`) отвечает: **allow** (явно безопасно/обратимо — дроп временной CI-БД, rollback на known-good, build-cache prune), **deny**, или **escalate-to-owner** — но эскалация к owner ТОЛЬКО для необратимого класса из списка «Когда Big-7 требует user-approve» (DROP/DELETE прод-данных, downtime>1мин, секреты/сертификаты, биллинг/ресурсы). Рутинно-безопасное Big-7 пропускает сам, без owner-промпта.
- Агент ядра потерян (компакт, новая сессия) → координатор **заводит его заново и ждёт вердикта** (`scenarios/big7-consultation.md`, «Жизненный цикл постоянных агентов»); решать «за ядро» координатор не вправе — иначе весь раздел сводится к самопроверке того, кого он ограничивает.
- Персистентный (не свежий) Big-7 — чтобы решение опиралось на контекст сессии (что уже делали, какие гейты пройдены), консистентно с [[delegate-search-to-persistent-haiku]]/persistent-big7.
- Guard-хук при этом — детектор/напоминание; фактический решатель = Big-7 через координатора. (Ослабление enforced-гейта самого хука — только с явного owner-go, т.к. это security-downgrade.)

Почему так (owner): не дёргать owner permission-промптами на каждый деструктив; решение — за Big-7 (review-body для прод-affecting), owner подключается лишь на действительно необратимое.

## Почему правило существует

Реальный кейс: DO-01 при ENOSPC сам выполнил `docker builder prune -af && docker image prune -af`, освободил место и продолжил deploy. Действие безопасно по данным, но затронуло rollback (старые images снесены). Решение должно было приниматься PM-01 (приоритет downtime vs быстрый recovery) + DO-01 (техника) + SEC-01 (безопасность). Self-judgment агента = риск.

История правок: `PE-01-разбор-2026-08-24.md`, блок 2 (Б14 — С2 п. 5, в редакции PQ-01 — «Блок 2: разбор Б1–Б16»); 2026-08-24.

История правок: `PE-01-разбор-2026-08-24.md`, блок 3 (В2 — кворум: SEC-01 обязателен, SEC-02 при security-surface; вердикт — `PQ-01-разбор-2026-08-24.md`, «Блок 3: разбор В1–В10»); 2026-08-24.
