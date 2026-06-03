# Claude Code Configuration: Prompt Adaptation Analysis
## Current Stack → Target Stack Migration Guide

**Current Techstack:** React + Python/FastAPI + PostgreSQL  
**Target Techstack:** React + Node.js/Fastify + PostgreSQL  
**Source prompt:** `Docs/claude-agent-settings-prompt.txt`

---

## 1. Required Changes for Target Stack

### Retain As-Is

| Section | Reason |
|---|---|
| Prompt preamble (project discovery steps 1–6) | Fully stack-agnostic |
| Ownership rules table | Principle applies to any stack |
| `CLAUDE.md` structure and format rules | Stack-agnostic routing document |
| `architecture-deep-dive` skeleton | All sections apply; only tool names change |
| `frontend-guidelines` skill | React stack is identical |
| `/fix-error`, `/phase-status`, `/update-checklist`, `/session-end` command structures | Logic is stack-agnostic |
| `prefer_lsp.py` hook script | Same logic; only the `lsp_exts` list changes |
| `settings.json` Playwright allow-list | Unchanged |
| `settings.local.json` template | Unchanged |
| Final validation checklist concept | Same checks, different tool names |

### Must Modify

| Section | What Changes |
|---|---|
| Discovery step 7 ("ruff hook path") | Replace with ESLint/Biome path |
| `CLAUDE.md` → Tech Stack | Python/FastAPI → Node.js/Fastify; SQLAlchemy → Prisma or Drizzle; Celery → BullMQ; Ruff/mypy → ESLint + tsc |
| `CLAUDE.md` → Key Rules | Session pattern (`async with get_tenant_session`) → Fastify request lifecycle; remove Pydantic-specific rules |
| `CLAUDE.md` → Code navigation policy | Add `.ts` backend files to LSP list (whole project is now TypeScript) |
| `backend-patterns` skill | Complete rewrite: Fastify plugin model, Prisma/Drizzle, Zod, BullMQ, no Python constructs |
| `/impl-phase` command | New implementation order for Node.js; replace `alembic` with `prisma migrate`; replace `pytest` with `vitest` |
| `/new-endpoint` command | Fastify route plugin pattern with Zod type-provider instead of FastAPI decorator pattern |
| `/migrate` command | `prisma migrate dev` / `drizzle-kit generate` instead of `alembic revision --autogenerate` |
| `/lint-fix` command | ESLint + `tsc --noEmit` instead of Ruff + mypy |
| `/run-tests` command | Vitest/Jest inside Docker instead of pytest |
| `ts-diagnostics` hook | Now covers **both** `frontend/` and `backend/` since backend is also TypeScript |
| `ruff-check.py` hook | Replace with `eslint-check.py` running ESLint on backend `.ts` files |
| `settings.json` PostToolUse hooks | Remove ruff command; replace with ESLint + `tsc --noEmit` for backend |
| `settings.json` allow list | `pytest:*` → `vitest:*`; `alembic:*` → `prisma:*` |
| Ownership table | "transactional outbox spec" still in backend-patterns; "Cache slot assignments" still in architecture |
| Placeholder table | All `[workers_path]` entries → `.ts` files; `[migration_tool]` → `prisma`; `[linter_cmd]` → ESLint |

### Remove (Python/FastAPI-specific, no equivalent)

| Item | Reason |
|---|---|
| `AsyncSession` / `get_tenant_session()` patterns in commands | SQLAlchemy construct; Fastify uses Prisma client or connection pool |
| `select()` / `insert()` raw query checks in `update-checklist` | Prisma eliminates raw queries by default |
| Repository function signatures in Python | Replace with TypeScript equivalents |
| `python-jose JWT` reference | Use `@fastify/jwt` |
| Celery queue topology (`task_acks_late`, `task_reject_on_worker_lost`) | BullMQ handles this differently |
| `docker compose exec api pytest` pattern | Replace with `docker compose exec api npx vitest run` |
| `ruff-check.py` hook file | ESLint replaces Ruff |

---

## 2. Recommended Skill Structure

| Skill | Status | Scope |
|---|---|---|
| `architecture-deep-dive` | Adapt | System design, multi-tenancy, BullMQ queue topology, Redis slots, event-driven flows, scalability |
| `frontend-guidelines` | Retain | All React/TS/TanStack/Zustand/Tailwind work inside `frontend/` |
| `backend-patterns` | Rewrite | Fastify plugin model, Prisma/Drizzle, Zod validation, service/repository layering, BullMQ workers, outbox pattern |
| `database-patterns` | New (recommended) | Prisma schema authoring, migration discipline, multi-tenant schema strategy, query optimization, transaction patterns |
| `api-contract-guidelines` | New (recommended) | Zod + `fastify-type-provider-zod` patterns, request/response typing, OpenAPI generation, versioning |
| `testing-quality-gates` | New (recommended) | Vitest unit patterns, Supertest integration tests, test isolation, fixture strategy, coverage gates |
| `deployment-devops-guidelines` | Optional | Docker Compose, Nginx, env var management, health checks — only generate if CI/CD is non-trivial |

**Why `database-patterns` is separate:** With Prisma, schema authoring, relations, and migrations are a distinct discipline from the service/repository layer and deserve their own canonical home to avoid duplication across backend-patterns and impl-phase.

---

## 3. Recommended Commands

| Command | Changes from Original |
|---|---|
| `/impl-phase` | New order: Prisma model → migration → Zod schema → repository → service → Fastify route plugin → register → BullMQ worker |
| `/new-endpoint` | Fastify route plugin pattern with Zod type-provider; no decorator syntax |
| `/new-component` | New command — React component scaffold (was absent in original, useful for this stack) |
| `/migrate` | `prisma migrate dev --name $ARG` / review generated SQL / `prisma migrate deploy` |
| `/run-tests` | `docker compose exec api npx vitest run` for backend; `docker compose exec frontend npx vitest run` for frontend |
| `/lint-fix` | `eslint src/ --ext .ts --fix` + `tsc --noEmit` for backend; `tsc --noEmit` for frontend |
| `/fix-error` | Same logic; adjust test command to `vitest run --reporter=verbose` |
| `/phase-status` | Unchanged |
| `/update-checklist` | Replace `select()`/`insert()` checks with Prisma raw query checks; verify route registration |
| `/session-end` | Same structure; adjust lint and test commands |

---

## 4. Recommended Hooks

**Important:** Keep all hooks as Python `.py` scripts (not `.sh`) for Windows compatibility, per the existing convention in this repo's CLAUDE.md.

### PreToolUse — `prefer_lsp.py`

Adjust `lsp_exts` to cover both frontend and backend TypeScript:

```python
lsp_exts = (".ts", ".tsx")   # covers frontend/ and backend/src/
```

Remove `.py` from the list entirely — there is no Python in the target stack.

### PostToolUse — `ts-diagnostics.py` (replaces `.sh`)

The hook now runs `tsc --noEmit` for **both** directories:

- If edited file is under `frontend/` → run `tsc` in `frontend/`
- If edited file is under `backend/` → run `tsc` in `backend/`
- Exit 2 on errors so Claude is forced to fix them

This replaces the original `ts-diagnostics.sh` (which only covered frontend) and gains backend coverage for free since the whole stack is now TypeScript.

### PostToolUse — `eslint-check.py` (replaces `ruff-check.py`)

Runs ESLint after any `.ts`/`.tsx` edit in the backend directory:

```python
# exits 0 (advisory) — same behaviour as ruff-check.py
# command: npx eslint <file> --ext .ts -q
```

Advisory only (exit 0), not blocking — mirrors the original ruff hook behaviour.

### PostToolUse — `prisma-validate.py` (optional)

If the project uses Prisma, add a hook that runs `npx prisma validate` after any edit to `prisma/schema.prisma`. Exit 2 on errors.

### Removed Hooks

| Original hook | Reason removed |
|---|---|
| `ruff-check.py` | No Python backend |
| mypy check | No Python backend |

---

## 5. Required Placeholder Replacements

| Placeholder | Target Stack Value | Notes |
|---|---|---|
| `[frontend_dir]` | `frontend/` | Inspect actual root; may be `client/` or `web/` |
| `[backend_dir]` | `backend/` | May be `server/`, `api/`, or `apps/api/` in monorepos |
| `[models_path]` | `prisma/schema.prisma` | Single file for Prisma; `backend/src/db/schema/` for Drizzle |
| `[schemas_path]` | `backend/src/schemas/<domain>.schema.ts` | Zod schemas for request/response |
| `[services_path]` | `backend/src/services/<domain>.service.ts` | |
| `[repositories_path]` | `backend/src/repositories/<domain>.repository.ts` | |
| `[endpoints_path]` | `backend/src/routes/<domain>/index.ts` | Fastify plugin per domain |
| `[workers_path]` | `backend/src/workers/<domain>.worker.ts` | BullMQ worker files |
| `[migration_tool]` | `prisma` | Or `drizzle-kit` if using Drizzle |
| `[autogenerate_cmd]` | `migrate dev --name` | `prisma migrate dev --name $ARG` |
| `[migration_dir]` | `prisma/migrations/` | Or `drizzle/migrations/` |
| `[linter_cmd]` | `cd backend && npx eslint src/ --ext .ts -q` | Or `npx biome check src/` |
| `[linter_autofix_cmd]` | `cd backend && npx eslint src/ --ext .ts --fix -q` | Or `npx biome check --apply src/` |
| `[type_checker_cmd]` | `cd backend && npx tsc --noEmit` | Runs against backend `tsconfig.json` |
| `[test_cmd]` | `docker compose exec api npx vitest run` | Or `jest --runInBand` |
| `[test_dir]` | `backend/src/__tests__/` | Or `backend/tests/` |
| `[frontend_build_cmd]` | `cd frontend && npm run build` | |
| `[tasks_file]` | `Docs/tasks.md` | Inspect `Docs/` folder first |
| `[checklist_file]` | `Docs/tasks.md` | Same file for git add |
| `[workers_path]` (queue) | `backend/src/workers/` | BullMQ queues defined here |

---

## 6. Optimized Final Prompt

```text
# Prompt: Generate Claude Code Configuration for a React + Node.js/Fastify + PostgreSQL Project

You are setting up Claude Code configuration for a software project from scratch.
Before generating anything, READ the project to discover its actual structure:

1. Read `README.md` (or root-level docs) — domain, purpose, users
2. List the root directory to find top-level folders
3. Read `package.json` at the root, and any `package.json` inside backend/server/api
   directories — identify exact packages: Fastify version, ORM (Prisma vs Drizzle vs
   TypeORM), validation library (Zod vs TypeBox), queue (BullMQ vs Bull vs pg-boss),
   test runner (Vitest vs Jest), linter (ESLint vs Biome)
4. Read `package.json` in the frontend directory — confirm exact React, TanStack Query,
   Zustand, and Tailwind versions
5. Identify: frontend dir name, backend dir name, migration tool, cache, object storage,
   i18n library
6. Check if a `Docs/` or `docs/` folder exists and list its contents
7. Find the task checklist file (commonly `Docs/tasks.md` or similar)
8. Confirm the absolute path to the backend `src/` directory (needed for ESLint hook)
9. Confirm the relative path to the frontend directory (needed for ts-diagnostics hook)
10. Check if `prisma/schema.prisma` exists, or identify the ORM schema file location

Then generate every file below. Every detail must come from what you found —
never use placeholder names, never copy content from another project.

---

## Ownership rules (read before generating anything)

Each fact has exactly ONE canonical home. Violations cost tokens every conversation.

| Fact | Canonical file |
|---|---|
| Cache/DB slot assignments | architecture-deep-dive skill |
| BullMQ queue topology and worker retry config | architecture-deep-dive skill |
| Transactional outbox full spec | backend-patterns skill |
| Prisma/Drizzle schema authoring rules | database-patterns skill |
| Cross-cutting principles | CLAUDE.md |
| Frontend conventions | frontend-guidelines skill |
| Zod + Fastify type-provider contract rules | api-contract-guidelines skill |

When a skill needs to reference a fact it does not own, write one sentence:
"See **[owning skill]** for [topic]." — never copy the content.

---

## File 1: `CLAUDE.md` (project root)

Maximum 45 lines. This is a routing document, not a knowledge base.

```markdown
# CLAUDE.md

## Project Summary
[2–4 sentences: what the system does, who uses it, its primary domain]

[Bullet list of core goals — 4–8 items max]

Principles:
[2–4 cross-cutting invariants that apply to every layer — one line each]
[These are the ONLY place these principles appear across all files]

## Tech Stack
Frontend: [exact React version, TanStack Query version, Zustand, Tailwind, Router]
Backend: [Fastify version, ORM name+version, Zod/TypeBox, @fastify/jwt or equivalent]
Data: [PostgreSQL version, Redis version, object storage if any]
Infra: [BullMQ or equivalent, Docker Compose, Nginx if present, observability tools]

## Skill Routing
Use `architecture-deep-dive` for system design, multi-tenancy, BullMQ queue topology,
  Redis slot strategy, scalability decisions, event-driven workflows.
Use `backend-patterns` for Fastify plugin design, service/repository layering,
  Prisma/Drizzle usage, BullMQ workers, outbox pattern, and integration adapters.
Use `database-patterns` for Prisma schema authoring, migrations, transaction patterns,
  multi-tenant schema strategy, and query optimization.
Use `api-contract-guidelines` for Zod schema definitions, Fastify type-provider wiring,
  OpenAPI generation, and API versioning.
Use `frontend-guidelines` for all work inside `[frontend_dir]/`, including React
  components, TanStack Query hooks, Zustand stores, Tailwind styling, and routing.

## Key Rules
[6–10 one-line invariants — no explanations, no detail]
- Fastify plugins are the unit of route registration; never add routes outside a plugin
- All DB access goes through the repository layer; no Prisma client calls in services
- Transactional outbox: domain events write to outbox table in same DB transaction
- [Redis]: db=0 broker · db=1 [use] · db=2 [use] — see architecture skill for full map
- Heavy tasks ([list]) are always async via BullMQ; never block the request cycle
- All protected routes use the `authenticate` preHandler; role checks use `requireRoles()`
- `[DEMO_ENV_VAR]=true` enables MSW mock handlers

## Code navigation policy
Prefer LSP for `.ts` and `.tsx` symbol lookup (frontend and backend); use Grep only as
fallback for config strings, comments, or non-symbol literals.
```

---

## File 2: `.claude/skills/architecture-deep-dive/SKILL.md`

```markdown
---
name: architecture-deep-dive
description: Use for system architecture, module boundaries, multi-tenancy, BullMQ queue
  topology, Redis slot strategy, scalability, async/event-driven workflows, and platform
  evolution.
---

# Architecture Deep Dive

Use this skill when the task involves:
[bullet list — architecture decisions, search/storage design, queue topology, Redis
 strategy, scaling thresholds, event-driven flows, service boundaries]

## Project Architecture Baseline
[1–2 sentences describing the platform and its core domain]

Core capabilities:
[4–6 bullets — what the system primarily does]

Core principle:
See **CLAUDE.md → Principles** for cross-cutting constraints.

## Core Architecture

### Transaction System
Use PostgreSQL as the source of truth for:
[bullet list — users, orgs, core domain entities, audit logs]

### Multi-Tenancy Strategy
[Describe the isolation model: schema-per-tenant, row-level, or separate DB]
[State the connection routing strategy — how does a request get the right schema/pool?]

### Object Storage
Use [MinIO / S3 / Azure Blob] for: [list asset types]

### Cache / Queue
[THIS IS THE CANONICAL LOCATION FOR CACHE SLOT DEFINITIONS]
Use Redis with [N] dedicated DB slots:
- **db=N** — [purpose] ([TTL, eviction policy, key pattern])
- **db=N** — [purpose] ([TTL, eviction policy, key pattern])
Do not mix data across slots.

[THIS IS THE CANONICAL LOCATION FOR BULLMQ QUEUE TOPOLOGY]
BullMQ queues:
- **[queue-name]** — [worker file, concurrency, retry count, backoff strategy]
- **[queue-name]** — [worker file, concurrency, retry count, backoff strategy]
Worker global config: [removeOnComplete, removeOnFail, defaultJobOptions]

### Event / Async Layer
Use the **transactional outbox pattern** — full spec in **backend-patterns skill**.
Use async workers for: [list — emails, OCR, reports, heavy compute, webhooks]

## Architecture Principles
[4–6 named principles with 1–2 sentences each, specific to this project]

## Canonical Workflows
[Primary workflow 1]: [Step] → [Step] → ... (3–6 workflows total, one line each)

## Scalability Thresholds
[At what scale does each component need to evolve — specific numbers if known]

## When giving architecture advice
Always: [4–6 bullets — explain tradeoffs, simplest viable first, domain constraints]

## Output Style
Prefer: module breakdown, component interaction list, sequence steps,
deployment evolution plan, risks/tradeoffs/recommendations
```

---

## File 3: `.claude/skills/backend-patterns/SKILL.md`

```markdown
---
name: backend-patterns
description: Use for Fastify backend design, service/repository layering, Prisma/Drizzle
  usage, BullMQ worker authoring, outbox pattern, integration adapters, and all
  backend implementation work in [backend_dir]/src/.
---

# Backend Patterns

Use this skill when the task involves:
[bullet list — Fastify plugin design, route handlers, service/repo structure,
 database interaction, queue workers, caching, auth middleware, API design]

## Backend Baseline
Preferred stack:
- Fastify [version] with `fastify-type-provider-zod`
- [Prisma version] or [Drizzle version] — ORM / query builder
- Zod [version] — request/response validation and type inference
- @fastify/jwt or equivalent — auth
- BullMQ [version] — background job queue
- [Redis client] — caching and queue broker

## Backend Architecture Rule

Use clean layering:
1. **Route layer** — `[backend_dir]/src/routes/<domain>/index.ts`
   HTTP concerns only: parse request, call service, return response. Fastify plugin
   with `withTypeProvider<ZodTypeProvider>()` — no business logic here.
2. **Service layer** — `[backend_dir]/src/services/<domain>.service.ts`
   Business logic, orchestration, state machine transitions, outbox event creation.
   Receives a `PrismaClient` or transaction client from the caller.
3. **Repository layer** — `[backend_dir]/src/repositories/<domain>.repository.ts`
   All Prisma/Drizzle queries; receives `db` (PrismaClient or tx); returns typed
   domain objects or scalars. No business logic, no HTTP concerns.
4. **Model/schema layer** — `prisma/schema.prisma` (or `[backend_dir]/src/db/schema/`)
   Source of truth for data shape. See **database-patterns skill** for authoring rules.

Route → Service → Repository → DB. Services receive `db` from the route handler or a
higher-level transaction wrapper. No Prisma calls directly in route handlers or services.

## Route (Plugin) Rules
[4–6 rules:
- every route file exports an `async function plugin(fastify: FastifyInstance)` decorated
  with `fastify.withTypeProvider<ZodTypeProvider>()`
- schema object on every route: `{ body: ..., querystring: ..., response: { 2xx: ... } }`
- auth applied via `preHandler: [fastify.authenticate]` — never inline
- role checks via `preHandler: [fastify.authenticate, requireRoles(['admin'])]`
- register all domain route plugins in a central `src/routes/index.ts`
- status codes are explicit — never rely on Fastify defaults for 201/204]

## Service Layer Rules
[5–7 rules:
- one file per domain: `<domain>.service.ts`
- services receive `db: PrismaClient` (or a Prisma transaction) as first param
- services own business logic, validation beyond Zod, state transitions, outbox writes
- services must NOT contain raw SQL or direct Prisma model access — delegate to repo
- a service may pass the same `db` to multiple repos for cross-domain orchestration
- for operations needing atomicity, wrap in `db.$transaction(async (tx) => { ... })`]

## Repository Layer Rules
[6–8 rules:
- one file per domain: `<domain>.repository.ts`
- all functions are `async`, accept `db: PrismaClient | Prisma.TransactionClient` as
  first param, return typed domain objects or null
- no business logic — only query construction, execution, and result mapping
- no `HttpException` or status codes — throw `Error` or return null; service decides
- repositories are stateless — module-level functions, not class instances
- use Prisma's typed selects with `satisfies` for return shape guarantees

Canonical TypeScript signatures:
```typescript
export async function getById(db: PrismaClient, id: string): Promise<Domain | null>
export async function list(db: PrismaClient, filters: DomainFilters): Promise<Domain[]>
export async function create(db: PrismaClient, data: CreateDomainInput): Promise<Domain>
export async function update(db: PrismaClient, id: string, data: UpdateDomainInput): Promise<Domain>
export async function remove(db: PrismaClient, id: string): Promise<void>
```]

## BullMQ Worker Rules
Use BullMQ for: [list — email notifications, OCR, report generation, webhooks, etc.]
Never block the Fastify request cycle with heavy work.

Typical flow:
1. Route handler accepts request and validates input
2. Service persists initial state + writes outbox event (same DB transaction)
3. Outbox poller enqueues BullMQ job
4. Worker processes job; updates state; emits completion event

Worker files: `[backend_dir]/src/workers/<domain>.worker.ts`
See **architecture-deep-dive skill → BullMQ queue topology** for queue names,
concurrency, and retry configuration.

## Redis Rules
[General rules — what Redis is for (sessions, cache, rate-limit counters, pub/sub),
 what it is NOT for (source of truth for domain data)]

### Redis DB Slot Strategy
See **architecture-deep-dive skill → Cache / Queue** for canonical slot assignments.

## Transactional Outbox Pattern
[THIS IS THE CANONICAL LOCATION FOR THE FULL OUTBOX SPEC]
All domain events ([list event types]) must:
1. Write an `[outbox_table]` row in the same PostgreSQL transaction as the state change
2. Never enqueue a BullMQ job directly from the route handler

Outbox polling worker (`[worker_file_path]`, runs every [interval]) reads PENDING events
→ enqueues BullMQ job → sets PUBLISHED / FAILED / DEAD_LETTER after [N] retries.
Guarantees no lost jobs on API crash or worker restart.

## Security Rules
[RBAC, tenant-level access, audit log requirements — specific to this project]

## Performance Rules
[async I/O, Prisma query batching, Redis caching patterns, read replica usage — 4–5 rules]

## Error Handling Rules
[Fastify error handler pattern, structured error shape, async failure modes, BullMQ DLQ]
```

---

## File 4: `.claude/skills/database-patterns/SKILL.md`

```markdown
---
name: database-patterns
description: Use for Prisma schema authoring, migration discipline, multi-tenant schema
  strategy, PostgreSQL transaction patterns, query optimization, and Prisma client usage.
---

# Database Patterns

Use this skill when the task involves:
[Prisma schema changes, migration generation, multi-tenant routing, query optimization,
 relation definitions, seed scripts, soft deletes, UUID vs serial IDs]

## ORM Baseline
- [Prisma version] with [database-url format]
- Schema file: `prisma/schema.prisma` (single source of truth for all models)
- Client generated to: `[client output path]`

## Prisma Schema Rules
[4–6 rules:
- all models use UUID primary keys: `id String @id @default(uuid())`
- createdAt / updatedAt on every model: `@default(now())` / `@updatedAt`
- soft deletes use `deletedAt DateTime?` — never hard-delete user-facing records
- relations always define both sides (no implicit back-relations)
- enums in `schema.prisma` only — never magic strings in application code
- run `npx prisma validate` before every migration]

## Migration Rules
[5–7 rules:
- never edit a migration file after it has been applied to any environment
- migration name describes the change: `add_consultant_status_enum` not `update1`
- review generated SQL before applying — Prisma may generate destructive ops silently
- always test `migrate reset` locally after major schema changes
- production uses `prisma migrate deploy` — never `migrate dev` in CI/prod
- if a migration needs manual SQL (e.g. for a complex index), use `prisma migrate diff`
  to generate a shell then edit before applying]

## Multi-Tenancy Rules
[How tenant isolation is implemented at the DB layer — schema switching, RLS, or
 connection routing — one canonical statement here]

## Transaction Patterns
```typescript
// Preferred: Prisma interactive transaction for cross-model atomicity
await db.$transaction(async (tx) => {
  const record = await domainRepo.create(tx, data)
  await outboxRepo.create(tx, { type: 'DOMAIN_CREATED', payload: record.id })
})
```
[When to use `$transaction` vs relying on Prisma's implicit per-query transactions]

## Query Optimization Rules
[Pagination with cursor-based pagination; N+1 prevention with `include`/`select`;
 when to use `$queryRaw` and how to type it safely]
```

---

## File 5: `.claude/skills/api-contract-guidelines/SKILL.md`

```markdown
---
name: api-contract-guidelines
description: Use for Zod schema definitions, Fastify type-provider wiring, request/response
  typing, OpenAPI generation, error response shape, and API versioning conventions.
---

# API Contract Guidelines

## Zod + Fastify Type Provider

Every route must declare a typed schema and use `withTypeProvider<ZodTypeProvider>()`:

```typescript
import { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'

export async function domainRoutes(fastify: FastifyInstance) {
  const f = fastify.withTypeProvider<ZodTypeProvider>()

  f.post('/domains', {
    schema: {
      body: CreateDomainSchema,
      response: { 201: DomainResponseSchema },
    },
  }, async (request, reply) => {
    const result = await domainService.create(db, request.body)
    return reply.status(201).send(result)
  })
}
```

## Zod Schema Rules
[5–7 rules:
- schemas live in `[backend_dir]/src/schemas/<domain>.schema.ts`
- export both the Zod schema AND the inferred type: `export type Domain = z.infer<typeof DomainSchema>`
- request schemas (body/querystring) use `.strict()` to reject unknown fields
- response schemas use `.strip()` — never leak internal fields to clients
- always define error response schema: `{ 400: ErrorSchema, 401: ErrorSchema, 404: ErrorSchema }`
- shared field patterns (UUID, ISO date, pagination) go in `src/schemas/shared.schema.ts`]

## OpenAPI Rules
[If using `@fastify/swagger` — describe tag grouping, server config, auth scheme definition]

## Versioning Rules
[URL prefix strategy: `/api/v1/...`; when to create v2; backward-compat policy]

## Error Response Shape
```typescript
// All error responses conform to:
{ error: string; code: string; details?: unknown }
```
[Fastify `setErrorHandler` must normalize all errors to this shape before sending]
```

---

## File 6: `.claude/skills/frontend-guidelines/SKILL.md`

*(Retain the original template structure — only update package names from project discovery.)*

---

## File 7: `.claude/hooks/prefer_lsp.py`

```python
#!/usr/bin/env python3
import json
import sys

data = json.load(sys.stdin)
tool_input = data.get("tool_input", {}) or {}

candidates = []
for key in ("path", "paths", "glob", "pattern", "query", "include"):
    value = tool_input.get(key)
    if isinstance(value, str):
        candidates.append(value)
    elif isinstance(value, list):
        candidates.extend(str(v) for v in value)

text = " ".join(candidates).lower()

# Both frontend and backend are TypeScript — LSP covers the full project
lsp_exts = (".ts", ".tsx")

if any(ext in text for ext in lsp_exts):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "For TypeScript code navigation, use the LSP tool instead of Grep. "
                "Prefer definitions, references, symbols, hover/type info, diagnostics. "
                "Use Grep only as a fallback when LSP cannot answer."
            )
        }
    }))

sys.exit(0)
```

---

## File 8: `.claude/hooks/ts-diagnostics.py`

*(Python script — not .sh — for Windows compatibility)*

```python
#!/usr/bin/env python3
"""
Runs tsc --noEmit after any Edit/Write on a .ts/.tsx file.
Covers both frontend/ and backend/ since both are TypeScript.
Exits 2 when errors found so Claude is forced to address them.
"""
import json
import os
import subprocess
import sys

data = json.load(sys.stdin)
file_path = (data.get("tool_input") or {}).get("file_path", "")

if not file_path.endswith((".ts", ".tsx")):
    sys.exit(0)

# Determine which tsconfig to use based on file location
FRONTEND_DIR = "./[frontend_dir]"   # relative to project root
BACKEND_DIR = "./[backend_dir]"     # relative to project root

if os.path.normpath(FRONTEND_DIR) in os.path.normpath(file_path):
    check_dir = FRONTEND_DIR
elif os.path.normpath(BACKEND_DIR) in os.path.normpath(file_path):
    check_dir = BACKEND_DIR
else:
    sys.exit(0)

if not os.path.isdir(check_dir):
    sys.exit(0)

result = subprocess.run(
    ["npx", "tsc", "--noEmit", "--pretty", "false"],
    cwd=check_dir,
    capture_output=True,
    text=True,
)

if result.returncode == 0:
    sys.exit(0)

print(f"TypeScript errors detected after editing: {file_path}")
print()
lines = (result.stdout + result.stderr).splitlines()
print("\n".join(lines[:50]))
sys.exit(2)
```

---

## File 9: `.claude/hooks/eslint-check.py`

*(Replaces ruff-check.py — advisory only, exits 0)*

```python
#!/usr/bin/env python3
"""
Runs ESLint after any Edit/Write on a .ts file in the backend directory.
Advisory only (exit 0) — surfaces warnings without blocking Claude.
"""
import json
import os
import subprocess
import sys

data = json.load(sys.stdin)
file_path = (data.get("tool_input") or {}).get("file_path", "")

BACKEND_DIR = "[ABSOLUTE_BACKEND_PATH]"  # absolute path from project discovery

if not file_path.endswith(".ts"):
    sys.exit(0)

if not file_path.startswith(BACKEND_DIR):
    sys.exit(0)

result = subprocess.run(
    ["npx", "eslint", file_path, "--ext", ".ts", "-q"],
    cwd=BACKEND_DIR,
    capture_output=True,
    text=True,
)

if result.returncode != 0:
    lines = (result.stdout + result.stderr).splitlines()
    print("\n".join(lines[:15]))

sys.exit(0)
```

---

## File 10: `.claude/commands/` — Slash Commands

### Placeholder Table

| Placeholder | Replace with |
|---|---|
| `[project_name]` | actual project name |
| `[backend_dir]` | actual backend path (e.g. `backend/`) |
| `[models_path]` | `prisma/schema.prisma` or `[backend_dir]/src/db/schema/` |
| `[schemas_path]` | `[backend_dir]/src/schemas/<domain>.schema.ts` |
| `[services_path]` | `[backend_dir]/src/services/<domain>.service.ts` |
| `[repositories_path]` | `[backend_dir]/src/repositories/<domain>.repository.ts` |
| `[endpoints_path]` | `[backend_dir]/src/routes/<domain>/index.ts` |
| `[workers_path]` | `[backend_dir]/src/workers/<domain>.worker.ts` |
| `[migration_tool]` | `prisma` or `drizzle-kit` |
| `[autogenerate_cmd]` | `migrate dev --name` (Prisma) or `generate` (Drizzle Kit) |
| `[migration_dir]` | `prisma/migrations/` |
| `[linter_cmd]` | `cd [backend_dir] && npx eslint src/ --ext .ts -q` |
| `[linter_autofix_cmd]` | `cd [backend_dir] && npx eslint src/ --ext .ts --fix -q` |
| `[type_checker_cmd]` | `cd [backend_dir] && npx tsc --noEmit` |
| `[test_cmd]` | `docker compose exec api npx vitest run` |
| `[test_dir]` | `[backend_dir]/src/__tests__/` |
| `[tasks_file]` | `Docs/tasks.md` |
| `[checklist_file]` | `Docs/tasks.md` |
| `[frontend_build_cmd]` | `cd [frontend_dir] && npm run build` |

---

### `impl-phase.md`

```markdown
# /impl-phase

Implement the next incomplete phase of [project_name], following the plan exactly.

## Argument
Pass the phase number: `/impl-phase 3`
If no argument given, detect the next incomplete phase from `[tasks_file]`.

## Instructions

### Step 1 — Scope
Read only the relevant phase section from `[tasks_file]`.
Do NOT re-read the full implementation plan — all architecture context is in `CLAUDE.md`.

### Step 2 — Navigate with LSP, not file search
- Use `LSP goto_definition` to find imported types, base classes, shared utilities.
- Use `LSP find_references` before modifying shared types or services.
- Use `LSP hover` to check types and signatures.
- Only use `Read` with `offset`+`limit` for a known file section.

### Step 3 — Implementation order (always follow this sequence)
1. Prisma schema model → `[models_path]` (run `npx prisma validate` after)
2. Migration: generate → review SQL → apply
3. Zod schemas → `[schemas_path]`
4. Repository → `[repositories_path]` (all Prisma queries here; none in service)
5. Service layer → `[services_path]` (calls repository; owns business logic; uses tx where needed)
6. Fastify route plugin → `[endpoints_path]`
7. Register route plugin in `[backend_dir]/src/routes/index.ts` if new domain
8. BullMQ worker → `[workers_path]` (register in worker bootstrap if new queue)

### Step 4 — Quality gates (run after each file)
```bash
[linter_cmd]
[type_checker_cmd]
```

### Step 5 — Test
```bash
[test_cmd]
```

### Step 6 — Update checklist
Mark completed items `[x]` in `[tasks_file]`.
Update phase status line and `## Overall Progress` table.

## Token-saving rules
- Do not re-read files you just wrote.
- Do not read the full implementation plan — use `CLAUDE.md`.
- Batch related edits in one `Edit` call where possible.
- Stop and confirm before any destructive migration operations.
```

---

### `new-endpoint.md`

```markdown
# /new-endpoint

Scaffold a new Fastify API endpoint following the [project_name] pattern.

## Argument
`/new-endpoint <domain> <verb> <resource>`

## Endpoint Pattern (do not deviate)

### 1. Zod Schema — `[schemas_path]`
```typescript
import { z } from 'zod'

export const Create<Resource>Schema = z.object({
  // fields
}).strict()

export const <Resource>ResponseSchema = z.object({
  id: z.string().uuid(),
  createdAt: z.string().datetime(),
  // fields
})

export type Create<Resource>Input = z.infer<typeof Create<Resource>Schema>
export type <Resource>Response = z.infer<typeof <Resource>ResponseSchema>
```

### 2. Repository query — `[repositories_path]`
```typescript
export async function get<Resource>(
  db: PrismaClient, id: string
): Promise<<Resource> | null> { ... }

export async function create<Resource>(
  db: PrismaClient, data: Create<Resource>Input
): Promise<<Resource>> { ... }
```

### 3. Service method — `[services_path]`
```typescript
export async function create<Resource>(
  db: PrismaClient, input: Create<Resource>Input
): Promise<<Resource>Response> {
  const result = await <resource>Repo.create<Resource>(db, input)
  // business logic here
  return result
}
```

### 4. Route plugin — `[endpoints_path]`
```typescript
import { ZodTypeProvider } from 'fastify-type-provider-zod'
export async function <resource>Routes(fastify: FastifyInstance) {
  const f = fastify.withTypeProvider<ZodTypeProvider>()
  f.post('/<resources>', {
    preHandler: [fastify.authenticate],
    schema: {
      body: Create<Resource>Schema,
      response: { 201: <Resource>ResponseSchema },
    },
  }, async (request, reply) => {
    const result = await <resource>Service.create<Resource>(db, request.body)
    return reply.status(201).send(result)
  })
}
```

## Instructions
1. Use `LSP goto_definition` on nearest existing route plugin to confirm imports.
2. Add schema, repository query, service method, and route with single `Edit` per file.
3. Register the new plugin in `[backend_dir]/src/routes/index.ts`.
4. Run: `[linter_cmd] && [type_checker_cmd]`
5. Report what was added (4 locations + registration).
```

---

### `migrate.md`

```markdown
# /migrate

Generate and apply a Prisma migration.

## Argument
Pass migration name: `/migrate <name>`

## Instructions

1. Validate schema first:
   ```bash
   cd [backend_dir] && npx prisma validate
   ```

2. Generate migration:
   ```bash
   cd [backend_dir] && npx prisma migrate dev --name "$ARGUMENT" --create-only
   ```

3. **Review the generated SQL file** before applying:
   - Confirm `CREATE TABLE` / `ALTER TABLE` / `DROP COLUMN` matches intent
   - Watch for implicit destructive ops (column renames appear as drop + add)
   - Add manual SQL for complex indexes inside the migration file if needed

4. Apply:
   ```bash
   cd [backend_dir] && npx prisma migrate dev
   ```

5. Verify:
   ```bash
   cd [backend_dir] && npx prisma migrate status
   ```

6. Regenerate Prisma client:
   ```bash
   cd [backend_dir] && npx prisma generate
   ```

7. If migration fails: run `npx prisma migrate reset` locally, fix schema, regenerate.
   Never edit the DB directly — always go through Prisma migrations.
   Never use `migrate dev` in production — use `migrate deploy`.
```

---

### `run-tests.md`

```markdown
# /run-tests

Run the test suite and report results.

## Argument
Optional: `/run-tests unit` | `/run-tests integration` | `/run-tests all`
Default: full suite.

## Instructions

> All tests run **inside Docker** via `docker compose exec api`. Never run vitest
> directly on the host — the host may lack the correct DB/Redis environment.

1. Verify the api container is running:
   ```bash
   docker compose ps api
   ```
   If not `Up`, run `docker compose up -d api` first.

2. Run the full suite:
   ```bash
   docker compose exec api npx vitest run --reporter=verbose 2>&1 | tail -60
   ```

   Scoped variants:
   ```bash
   # Unit tests only
   docker compose exec api npx vitest run src/__tests__/unit/ 2>&1 | tail -60

   # Single file
   docker compose exec api npx vitest run src/__tests__/<file>.test.ts 2>&1 | tail -40
   ```

3. If tests fail:
   - Read only the failing test file and the service/module it targets.
   - Fix the root cause — do not mock away real failures.
   - Re-run the specific failing test before re-running the suite.

4. Report: pass/fail count, any skipped tests and why, next step if red (file:line).
```

---

### `lint-fix.md`

```markdown
# /lint-fix

Run linter and type checker, then fix all issues found.

## Instructions

1. Auto-fix safe issues:
   ```bash
   [linter_autofix_cmd]
   ```

2. Run type checker:
   ```bash
   [type_checker_cmd]
   ```

3. Fix remaining errors manually:
   - Use LSP `hover` to check types before adding annotations
   - Do not suppress with `// eslint-disable` or `// @ts-ignore` unless truly unavoidable

4. Confirm clean:
   ```bash
   [linter_cmd] && echo "OK"
   ```

5. Report: count fixed, any remaining issues with file:line.
```

---

### `fix-error.md`

```markdown
# /fix-error

Efficiently diagnose and fix a specific error without reading unrelated code.

## Argument
Paste the error/traceback after the command: `/fix-error <traceback>`

## Instructions

### Step 1 — Parse the traceback
Extract: exact file and line number, error type and message, any chained cause.

### Step 2 — Read only what's needed
- Use `Read` with `offset` and `limit` to read ±20 lines around the failing line.
- Use `LSP hover` on the failing symbol to check its type/signature.
- Use `LSP goto_definition` if the error is about a missing or mistyped attribute.

### Step 3 — Fix
Apply the minimal change. Do not refactor surrounding code.

### Step 4 — Verify
```bash
docker compose exec api npx vitest run src/__tests__/<specific_file>.test.ts
```

### Step 5 — Report
One sentence: what was wrong and what was changed. File:line reference.

## Token rules
- Never read a file in full to find a bug — always use line-targeted `Read`.
- Never re-read a file you just edited.
- If the error is in a dependency, find the last frame that IS your code.
```

---

### `phase-status.md`

```markdown
# /phase-status

Show current phase and exact next tasks.

## Instructions

1. Read `[tasks_file]` — focus only on the first phase marked incomplete.
2. List every unchecked `[ ]` item grouped by section.
3. Summarise parallel vs sequential work.
4. Output prioritised work order — **no implementation, just the plan**.

Keep output under 40 lines.
```

---

### `session-end.md`

```markdown
# /session-end

Wrap up: verify work, update checklist, commit.

## Argument
Pass the phase number: `/session-end 3`

## Instructions

### 1. Verify lint is clean
```bash
[linter_cmd] && echo "OK"
```

### 2. Run tests
```bash
[test_cmd] 2>&1 | tail -15
```
Do not commit if tests are red.

### 3. Update checklist
Run `/update-checklist $PHASE` — mark all verified tasks `[x]`.

### 4. Commit
```bash
git status
git add [backend_dir] [migration_dir] [checklist_file]
git commit -m "Phase $PHASE: <summary>"
```

### 5. Session summary (max 10 lines)
```
Phase N — <name>
Files added : <count> (<list>)
Files edited: <count> (<list>)
Tests       : <pass>/<total>
Checklist   : <X> tasks marked complete
Next session: Phase N+1 — <first task>
```
```

---

### `update-checklist.md`

```markdown
# /update-checklist

Verify and mark completed tasks in the checklist.

## Argument
Pass phase number: `/update-checklist 3`

## Instructions

1. Read only the relevant phase section from `[tasks_file]`.

2. For each task, verify completion using LSP:
   - Prisma model: symbol exists in `[models_path]`
   - Zod schemas: type export exists in `[schemas_path]`
   - Repository: functions exist in `[repositories_path]`
   - Services: function exists in `[services_path]` (confirm no direct Prisma calls)
   - API routes: plugin registered in `[backend_dir]/src/routes/index.ts`

3. Mark verified items `[x]`. Leave unverified items `[ ]`.

4. If all items in a phase are `[x]`:
   - Change phase header from `📅` to `✅`
   - Add: `> **Phase N completed:** YYYY-MM-DD`
   - Update `## Overall Progress` table

5. Save all changes in a single `Edit` call.

## Token rule
Read only the phase section — never the full checklist.
```

---

## File 11: `.claude/settings.json`

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(npx vitest*)",
      "Bash(npx prisma*)",
      "Bash(npx eslint*)",
      "Bash(npx tsc*)",
      "Bash(cd [frontend_dir] && npm run build*)",
      "Bash(docker compose:*)",
      "mcp__plugin_playwright_playwright__browser_navigate",
      "mcp__plugin_playwright_playwright__browser_snapshot",
      "mcp__plugin_playwright_playwright__browser_click",
      "mcp__plugin_playwright_playwright__browser_take_screenshot",
      "mcp__plugin_playwright_playwright__browser_wait_for",
      "mcp__plugin_playwright_playwright__browser_type",
      "mcp__plugin_playwright_playwright__browser_fill_form",
      "mcp__plugin_playwright_playwright__browser_network_requests",
      "mcp__plugin_playwright_playwright__browser_console_messages",
      "mcp__plugin_playwright_playwright__browser_resize",
      "Edit(/.claude/skills/**)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(git reset --hard*)",
      "Bash(rm -rf *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Grep",
        "hooks": [
          {
            "type": "command",
            "command": "python .claude/hooks/prefer_lsp.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python .claude/hooks/ts-diagnostics.py"
          },
          {
            "type": "command",
            "command": "python .claude/hooks/eslint-check.py"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '=== Session End ===' && echo 'Run /update-checklist to mark completed tasks.' && echo 'Run: git add -p && git commit' && echo '=================='"
          }
        ]
      }
    ]
  }
}
```

---

## Final Validation Checklist

Run these checks after generating all files:

- [ ] Search `"BullMQ"` queue topology across all files — canonical definition appears in **one file only** (architecture skill)
- [ ] Search `"$transaction"` — full Prisma transaction pattern appears in **one file only** (database-patterns skill)
- [ ] Search `"outbox"` — full outbox spec appears in **one file only** (backend-patterns skill)
- [ ] Search for domain principles — appear only in `CLAUDE.md`
- [ ] Search `"Grep"` in `CLAUDE.md` — must be one sentence, not a paragraph
- [ ] Grep all command files for any placeholder `[...]` still unreplaced
- [ ] Grep all command files for any path that does NOT exist in this project's folder structure
- [ ] `settings.json` ESLint hook path resolves to an actual directory — run `ls` to verify
- [ ] `settings.json` contains no `//` comment lines — validate with a JSON linter
- [ ] `settings.local.json` is listed in `.gitignore`
- [ ] `ts-diagnostics.py` `FRONTEND_DIR` and `BACKEND_DIR` values match the actual folder names
- [ ] No command file contains the name of a previous or unrelated project
- [ ] `CLAUDE.md` is under 45 lines
- [ ] Search `"prisma\."` in `[services_path]` — must return zero results; all Prisma calls must be in repositories
- [ ] Grep `[repositories_path]` — verify at least one repository file exists per domain that has a service
- [ ] `prefer_lsp.py` does NOT list `.py` in `lsp_exts` — there is no Python in this stack
- [ ] `eslint-check.py` `BACKEND_DIR` is the absolute path, not a relative one
```
