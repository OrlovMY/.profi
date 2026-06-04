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
- If `isolation:"worktree"` — worktree is set up for you; just `git checkout -b <branch>`, work, commit. Don't worry about parent repo.
- If NOT isolated — beware of parallel agents. STOP if `git status` shows uncommitted from another task.

PROD-AFFECTING DECISIONS:
- ANY action on shared production infra (prune, restart cascade, migration retry, force-deploy, image deletion, secret rotation, schema DROP) → STOP, report to HR-D as "ESCALATING TO HR-D" with proposal + reversibility cost.
- Read-only diagnostics (`df`, `docker ps`, `psql SELECT`, log tail) — OK without escalation.
- Single-container restart on already-built image — OK.
- Idempotent migration apply in normal conditions — OK.

TEST DEVICE / TEST ACCOUNT:
- <Description of test device or test account used for smoke. Include identifier, baseline version, special quirks.>

PROJECT SPECIFICS:
- <Domain-specific rules: SDK quirks, OEM workarounds, framework version constraints, schema invariants, etc.>
- <Naming conventions for new files/packages.>
- <Versioning rule: bump versionCode/version on each release; changelog entry mandatory.>

OFFICIAL DOCS:
- For any non-trivial library/SDK — use Context7 MCP proactively before writing code. Memory of LLM is secondary; official docs are primary.

DEPLOY WORKFLOW (если задача включает прод-деплой):
- See `playbooks/deploy_workflow.md` in the kit.
- Pre-flight: `df -h /` must be <70%; if higher → `docker system prune -af --filter "until=72h"` first.
- Bundle workflow: ALWAYS `git checkout --detach` on remote BEFORE `git fetch ... HEAD:master`, иначе fetch silently fails.
- Migration перед build (всегда). Идемпотентные миграции (`IF NOT EXISTS`).
- Build order: server → web → reload nginx → smoke.
- nginx reload only after `nginx -t` passes.
- On ENOSPC: STOP, prune, retry migration (build cache идемпотентен).

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
