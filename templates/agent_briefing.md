# Agent briefing template

HR-D обязательно вставляет этот блок в начало промпта **любого coding-агента**. Без него агенты не знают про окружение и наступают на одни и те же грабли. Замените `<placeholder>`-маркеры на конкретику проекта (или вынесите их в отдельный CLAUDE.md и линкуйте).

---

```
========== <PROJECT> AGENT BRIEFING (do not skip) ==========

ENVIRONMENT:
- User's local machine = management device; <list which dev tooling is NOT installed locally — e.g., no Go/Node/SDK/JDK/gradle/docker>. DO NOT attempt local builds — they will fail.
- Compilation/builds happen ONLY on <build_host> (SSH + Docker available). Build commands:
    - Server: `cd <compose_path> && docker compose build <api_container>`
    - Frontend: `cd <compose_path> && docker compose build <web_container>`
    - Mobile/desktop artifact: `<build_command>` with env `<KEYSTORE_PATH>` / `<SIGNING_VARS>`.

GIT WORKFLOW:
- Branch from `master`; commit message in present-tense English with type prefix (feat/fix/chore/docs).
- New branch name: `feat/<thing>` or `fix/<thing>`. NEVER commit directly to master.
- If `isolation:"worktree"` — the worktree is set up for you, but its base is NOT trusted: take it from the main working directory by the absolute path named in your task, then verify it twice — `git fetch "<absolute path to main working dir>" master && git checkout -b <branch> FETCH_HEAD && git rev-parse --short HEAD` (must equal the hash named in your task) and `ls <marker file from task>` (must exist). Hash differs or marker missing → STOP and report. Do NOT branch from `origin/master` inside a worktree. **From a worktree you NEVER deploy:** no `docker compose build/up` on the server, no `cp` into static/staging dirs, no `git push origin`, no cherry-pick «for sync», no `git reset --hard`; SSH to prod — read-only diagnostics only. Deploy = coordinator after merge. (`playbooks/worktree_deploy_safety.md` — written after a worktree agent rebuilt and deployed prod from a stale base.)
- Note: the worktree isolation guard MAY reject compound shell commands involving git — on this exact refusal («command is too complex to verify that it stays inside the worktree»), split into single calls; this is the sandbox, not a git error (`playbooks/worktree_deploy_safety.md`).
- If NOT isolated — beware of parallel agents. STOP if `git status` shows uncommitted from another task.

PROD-AFFECTING DECISIONS:
- ANY action on shared production infra → STOP, report to HR-D as "ESCALATING TO HR-D" with proposal + reversibility cost. Production-affecting is (full list = `playbooks/prod_escalation.md`, «Что считается production-affecting»): (1) any `docker prune`, volume ops, image deletion; (2) migration retry after error, manual DB fix, `ALTER`/`DROP`; (3) restart cascade (≥2 containers); (4) nginx config swap without `nginx -t`/rollback; (5) pushing a client/agent update to >1 device; (6) any command with `-f`/`--force`/`--volumes` (except the build-cache prune named in DEPLOY WORKFLOW); (7) touching credentials, secrets, certs; (8) disabling/relaxing security middleware «temporarily»; (9) changing data in the prod DB. If unsure whether it counts — it counts.
- Read-only diagnostics (`df`, `docker ps`, `psql SELECT`, log tail) — OK without escalation.
- Single-container restart on already-built image — OK.
- Idempotent migration apply in normal conditions — OK.

TEST DEVICE / TEST ACCOUNT:
- <Description of test device or test account used for smoke. Include identifier, baseline version, special quirks.>
- Test-account secrets: reset/creation goes to docs the same turn — `knowledge/standards/test-account-secret-hygiene.md`.

PROJECT SPECIFICS:
- <Domain-specific rules: SDK quirks, OEM workarounds, framework version constraints, schema invariants, etc.>
- Machine-read names (shell vars, JSON schema keys, config ids) — Latin only: `knowledge/standards/machine-read-names-in-latin.md`.
- <Naming conventions for new files/packages.>
- <Versioning rule: bump versionCode/version on each release; changelog entry mandatory.>

OFFICIAL DOCS:
- For any non-trivial library/SDK — use Context7 MCP proactively before writing code. Memory of LLM is secondary; official docs are primary.

DEPLOY WORKFLOW (если задача включает прод-деплой):
- See `playbooks/deploy_workflow.md` in the kit.
- Pre-flight: `df -h /` must be <70%; if higher → `docker builder prune -f --filter "until=72h"` (build cache only; `-f` = no interactive prompt, this is the routine exception in `prod_escalation.md`). Still >70% → STOP, escalate (image/volume prune is production-affecting, see PROD-AFFECTING DECISIONS above).
- Bundle workflow: ALWAYS `git checkout --detach` on remote BEFORE `git fetch ... HEAD:master`. Without it git REFUSES (loudly) — but the build step runs anyway on the old tree. So after fetch ALWAYS check `git log --oneline -3` before build; that check is the gate, not a formality.
- Migration перед build (всегда). Идемпотентные миграции (`IF NOT EXISTS`).
- Build order: server → web → reload nginx → smoke.
- nginx reload only after `nginx -t` passes.
- On ENOSPC: STOP; build-cache prune only; anything that deletes images or volumes → escalate; then retry migration (build cache is idempotent).

RESOURCE TRACKING:
- Если запускал что-то на VPS — в финальный отчёт peak CPU/RAM (`docker stats --no-stream`), disk before/after (`df -h`), время операции, bandwidth для трафиковых операций.
- Если ничего не запускал — write "no VPS resource impact".

VERIFICATION (REQUIRED at end):
- `git status` must be clean.
- `git log --oneline -3` showing your commits.
- Final commit hash in report.
- If task involves prod deploy: paste curl smoke results.
- If client artifact rebuilt: version + checksum.

ROLE PREFIX:
- Start each response in chat with: `<РОЛЬ> [YYYY-MM-DD HH:MM]: <text>`. Multiple roles → `BE-01 + AL-02: ...` or `HR-D → AL-02: ...`. No exceptions, even for one-line replies.

HANDOFF:
- НЕ ТРОГАТЬ: <integration files owned by other roles — router, main, Layout, compose, etc.>
- ПЕРЕДАТЬ <owner>: <new routes/events/exports to merge into integration files>.

IF BLOCKED:
- If Bash forbidden, deploy impossible, or scope unclear — write strictly «ЗАДАЧА НЕ ЗАВЕРШЕНА» + list of patches for manual application. DO NOT report «готово» falsely.

========== END BRIEFING ==========
```

---

## HR-D pre-flight

Перед каждым `Agent({prompt: ...})` для coding-задачи — машинально проверить:

- Briefing включён в начало промпта?
- Плейсхолдеры подменены на конкретику проекта?
- Указана ветка и `isolation:"worktree"` если нужно?
- Указан handoff-owner?

Если задача чисто read-only research (Explore) — briefing можно сократить, но если будет писать код или ходить по SSH — обязательно полный.

История правок: `archive/2026-08/PE-01-разбор-2026-08-24.md`, раздел «Совместная редакция и применение», П1, П2, П4, П8; вердикты — `archive/2026-08/PQ-01-разбор-2026-08-24.md`; 2026-08-24.

История правок: `archive/2026-08/PE-01-разбор-2026-08-24.md`, блок 3 (В10 — строка-вход о страже изоляции, в редакции PQ-01 (MAY reject); вердикт — `archive/2026-08/PQ-01-разбор-2026-08-24.md`, «Блок 3: разбор В1–В10»); 2026-08-24.

История правок: `archive/2026-08/ревизия-свода-2026-08-24.md`, раздел 13, Б6 (test-account-secret-hygiene в TEST DEVICE) + Б7 (machine-read-names-in-latin в PROJECT SPECIFICS); вердикты — `archive/2026-08/PQ-01-ревизия-2026-08-24.md`, «Дополнение по разделу 13»; 2026-08-25.
