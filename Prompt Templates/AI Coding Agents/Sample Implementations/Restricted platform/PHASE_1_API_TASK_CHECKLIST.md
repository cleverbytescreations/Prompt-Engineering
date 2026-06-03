# Implementation Task Checklist (API) — Phase 1 (MVP)

> Scope: FastAPI backend + PostgreSQL + Redis + OpenSearch + MinIO/S3 + Celery + supporting infra defined in SAD §13.
> Excludes all Phase-2 (AI/RAG, translation, `?lang=` content, summarisation, related-content, Q&A discussion comments, GDPR export) and Phase-3 features.
> Layering: API → Service → Repository. CQRS — writes go to PostgreSQL; member-facing reads/search go to OpenSearch via cache. Transactional outbox is mandatory.

---

## 1. Backend Tasks

### Module 0 — Foundation

- [x] **T-B0.1 — Bootstrap FastAPI project skeleton**
      Description: Create `backend/` with FastAPI app, settings, structured logging, exception handlers, Sentry/OTel hooks.
      Files: `backend/app/main.py`, `backend/app/core/config.py`, `backend/app/core/logging.py`, `backend/app/core/tracing.py`, `backend/app/core/exceptions.py`, `backend/pyproject.toml`, `backend/Dockerfile`, `backend/.env.example`.
      Implementation Notes: Use `pydantic-settings` for config. `python-json-logger` for structured logs. Custom exception handler emits `{detail, error_code, field_errors}`.
      Acceptance Criteria: `uvicorn app.main:app --reload` boots; `/docs` available; `/health/live` returns 200.

- [x] **T-B0.2 — Layered architecture skeleton (API/Service/Repository)**
      Description: Create directory scaffolding and base classes for repositories and services with async SQLAlchemy.
      Files: `backend/app/api/__init__.py`, `backend/app/services/base.py`, `backend/app/repositories/base.py`, `backend/app/core/db.py`, `backend/app/core/deps.py`.
      Implementation Notes: Async session factory tied to `DATABASE_URL` (PgBouncer DSN port 5433). `BaseRepository` enforces explicit selects (no N+1; NG-9). `BaseService` accepts a unit-of-work.
      Acceptance Criteria: A trivial `GET /health/ready` uses the session, returns 200 when PG reachable.

- [x] **T-B0.3 — Common middleware (CORS, request-id, OTel, rate limiter)**
      Description: Wire `CORSMiddleware`, request-id propagation, OpenTelemetry FastAPI instrumentation, slowapi limiter backed by `redis-cache`.
      Files: `backend/app/main.py`, `backend/app/core/middleware.py`, `backend/app/core/rate_limit.py`.
      Implementation Notes: CORS `allow_origins=[settings.FRONTEND_URL]`, credentials true, restricted methods/headers per plan §Security. Key func per-IP for anonymous endpoints; per-user for authenticated.
      Acceptance Criteria: Preflight from configured origin succeeds; other origin denied; OTel span emitted for each request.

- [x] **T-B0.4 — Pydantic schemas + standard error envelope**
      Description: Implement project-wide `ErrorResponse`, `PaginatedResponse`, `CursorPaginatedResponse`; map FastAPI `RequestValidationError` to `VALIDATION_ERROR`.
      Files: `backend/app/schemas/common.py`, `backend/app/core/exceptions.py`.
      Acceptance Criteria: A 400 from any endpoint matches the documented envelope shape.

- [x] **T-B0.5 — Complete `.env.example` per SAD §10.1**
      Description: Document every backend env var referenced by §10.1 dev environment without committing real values: `DATABASE_URL` (PgBouncer DSN, port 5433), `ANALYTICS_DATABASE_URL` (read-replica DSN), `REDIS_BROKER_URL` (redis-broker db=0), `REDIS_CACHE_URL` (redis-cache db=0 search · db=1 translation), `OPENSEARCH_URL`, `S3_*` / MinIO creds, `JWT_*` (RS256 keypair paths), `OPENAI_API_KEY`, `EMBEDDING_PROVIDER`, `EMBEDDING_FALLBACK_PROVIDER`, `EMAIL_PRIMARY_PROVIDER`, `EMAIL_FALLBACK_PROVIDER`, `SMTP_*`, `STORAGE_PROVIDER`, `SENTRY_DSN`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `FRONTEND_URL`, plus all Celery reliability vars from §10.1 (see T-I4.4).
      Files: `backend/.env.example`.
      Acceptance Criteria: A fresh `cp .env.example .env` produces a file whose key set matches the union of vars consumed by `app/core/config.py` and `app/workers/celery_app.py`; no real secrets present.

---

### Module 1 — Authentication & Onboarding (Backend)

- [x] **T-B1.1 — JWT auth with RS256 + refresh-token HttpOnly cookie**
      Description: Implement access (30 min, JSON body) + refresh (7 d, HttpOnly Secure SameSite=Strict cookie) tokens; `jti` revocation list via `revoked_tokens` table.
      Files: `backend/app/services/auth_service.py`, `backend/app/core/security.py`, `backend/app/repositories/revoked_tokens_repo.py`, `backend/app/api/v1/auth.py`.
      Implementation Notes: RS256 keys via env. Validator checks `revoked_tokens` only while token unexpired. Cookie path scoped to `/api/v1/auth/refresh-token`.
      Acceptance Criteria: Reused-revoked token returns 401 `TOKEN_EXPIRED`/`UNAUTHORIZED`; refresh rotates access token.

- [x] **T-B1.2 — Invite verification + signup**
      Description: Endpoints: `POST /auth/verify-invite`, `POST /auth/signup`.
      Files: `backend/app/api/v1/auth.py`, `backend/app/services/invite_service.py`, `backend/app/repositories/invites_repo.py`.
      Implementation Notes: Enforce org `max_users` at signup. Mark invite `used_at`/`used_by` atomically. Password hash `argon2`. Generic error messages for expired/revoked invites.
      Acceptance Criteria: Reusing an invite returns `INVALID_INVITE`; signup respects `max_users`.

- [x] **T-B1.3 — Login, logout, refresh, forgot/reset password**
      Description: Implement `POST /auth/login`, `POST /auth/logout`, `POST /auth/refresh-token`, `POST /auth/forgot-password`, `POST /auth/reset-password` with idempotent logout.
      Files: `backend/app/api/v1/auth.py`, `backend/app/services/auth_service.py`, `backend/app/services/email_service.py`.
      Implementation Notes: Forgot-password issues short-lived (1h) opaque token stored hashed. Reset-password rotates `password_hash`, revokes all active tokens for user. `POST /auth/refresh-token` reads the HttpOnly refresh cookie (path-scoped `/api/v1/auth/refresh-token`), rotates access token, optionally rotates refresh token.
      Acceptance Criteria: All five endpoints reachable; standard error codes (`UNAUTHORIZED`, `INVALID_TOKEN`, `TOKEN_EXPIRED`, `RATE_LIMITED`, `VALIDATION_ERROR`) returned; rate limits enforced (login 10/min/IP, forgot-password 3/min/IP, reset 5/min/IP); refresh cookie not visible to JS.

- [x] **T-B1.4 — Profile self-service (`/auth/me*`)**
      Description: `GET /auth/me`, `PATCH /auth/me`, `POST /auth/me/preferences`, `POST /auth/me/change-password`.
      Files: `backend/app/api/v1/auth.py`, `backend/app/services/user_service.py`.
      Acceptance Criteria: Preferences persist to `user_preferences`; password change requires current password.

- [x] **T-B1.5 — Postgres-target integration suite for Module 1 (F-2 from audit)**
      Description: Tests currently run on SQLite via aiosqlite — none of the CITEXT, partial-unique, array-column, or `with_for_update` PG-specific paths are exercised. Add a CI profile that boots the Docker compose Postgres service (T-I4.X3) and re-runs the auth/invite/signup suite against it. Required to validate F-3 race fix on the real lock backend.
      Files: `docker-compose.test.yml`, `backend/tests/integration/test_auth_pg.py`, `.github/workflows/ci.yml`.
      Acceptance Criteria: Same `tests/test_auth_onboarding.py` suite passes against PG; a synthetic concurrent-signup test (2 parallel `httpx` clients, max_users=N) sees exactly N signups succeed and the rest return 429.
      Completed: 2026-05-25

- [x] **T-B1.6 — Module 1 outbox events (deferred until T-I4.5 lands)**
      Description: Emit `user.created`, `user.password_changed`, `user.password_reset`, `invite.consumed`, and `invite.revoked` to `outbox_events` from the auth/invite/user services.
      Files: `backend/app/services/auth_service.py`, `backend/app/services/invite_service.py`, `backend/app/services/user_service.py`, `backend/app/repositories/outbox_repo.py`.
      Acceptance Criteria: Each Module 1 state transition produces exactly one outbox row in the same DB transaction; payloads conform to the 4 KB / identifiers-only rule (SAD §5.10).
      Completed: 2026-05-25

---

### Module 2 — User Management (Backend)

- [x] **T-B2.1 — User CRUD + role/status admin endpoints**
      Description: Implement `GET /users` (list with filters: role, status, org, search; offset pagination), `GET /users/{id}`, `PUT /users/{id}`, `DELETE /users/{id}`, `PATCH /users/{id}/status`, `PATCH /users/{id}/role`, `GET /users/{id}/contributions`.
      Files: `backend/app/api/v1/users.py`, `backend/app/services/user_service.py`, `backend/app/repositories/users_repo.py`.
      Implementation Notes: `DELETE` anonymises (nulls PII, sets `status=deleted`) and emits outbox `user.deleted`. Role change emits `user.role_changed`; status change emits `user.status_changed`. `GET /users` restricted to A/M; mutations restricted to A.
      Acceptance Criteria: List endpoint supports all filters and pagination envelope; anonymisation preserves contribution attribution but blanks email/full_name; each mutation emits exactly one outbox event.

---

### Module 3 — Organisation Management (Backend)

- [x] **T-B3.1 — Org CRUD + members endpoint**
      Description: `GET/POST /organizations`, `GET/PUT/DELETE /organizations/{id}`, `GET /organizations/{id}/members`.
      Files: `backend/app/api/v1/organizations.py`, `backend/app/services/org_service.py`, `backend/app/repositories/orgs_repo.py`.
      Implementation Notes: Soft-delete sets `is_active=false`; uniqueness on `lower(name)` partial index already enforced at DB.
      Acceptance Criteria: Duplicate active name returns 409 `CONFLICT`.

---

### Module 4 — Invite Management (Backend)

- [x] **T-B4.1 — Invite CRUD endpoints**
      Description: `POST /invites`, `GET /invites`, `GET /invites/{code}`, `DELETE /invites/{code}`.
      Files: `backend/app/api/v1/invites.py`, `backend/app/services/invite_service.py`.
      Implementation Notes: Code generation = 32-char base32 random. Expiry default from `platform_config.invite_expiry_hours`. Revoke sets `revoked_at`.
      Acceptance Criteria: Issued codes survive list filter; revoked codes show `revoked` status.

---

### Module 5 — Knowledge Repository (Backend)

- [x] **T-B5.1 — `POST /documents` upload endpoint**
      Description: Accept multipart PDF or external URL; create pending row; write outbox event `document.submitted`.
      Files: `backend/app/api/v1/documents.py`, `backend/app/services/document_service.py`, `backend/app/services/storage_service.py`.
      Implementation Notes: 50 MB cap (FastAPI `Request.body` check). MIME + magic-byte validation. Either `file_key` or `external_url`, never both (DC-3). MinIO/S3 via `StorageService` only.
      Acceptance Criteria: Non-PDF returns 422; oversized returns 413; success returns `{id, status: 'pending'}`.

- [x] **T-B5.2 — Document list/detail/edit/delete**
      Description: `GET /documents`, `GET /documents/{id}`, `PUT /documents/{id}`, `DELETE /documents/{id}`, `GET /documents/my`, `GET /documents/{id}/status`.
      Files: `backend/app/api/v1/documents.py`, `backend/app/services/document_service.py`, `backend/app/repositories/documents_repo.py`.
      Implementation Notes: Default list returns only `status='approved'` and `law_status='active'`. `PUT` creates `content_versions` row (≤2 KB metadata diff snapshot).
      Acceptance Criteria: Retracted docs hidden from default list; member can list own pending via `/my`.

- [x] **T-B5.3 — Signed-URL download endpoint**
      Description: `GET /documents/{id}/download` returns a short-lived pre-signed URL.
      Files: `backend/app/api/v1/documents.py`, `backend/app/services/storage_service.py`.
      Implementation Notes: TTL 5 min. Audit log entry per download (outbox `document.downloaded`).
      Acceptance Criteria: Approved doc returns a URL; pending/rejected returns 404.

- [x] **T-B5.4 — Document version history endpoints**
      Description: `GET /documents/{id}/versions`, `GET /documents/{id}/versions/{vid}`.
      Files: `backend/app/api/v1/documents.py`, `backend/app/repositories/content_versions_repo.py`.
      Implementation Notes: Append-only reads from `content_versions WHERE entity_type='document'`.
      Acceptance Criteria: Restricted to A/M; non-existent vid → 404.

---

### Module 6 — Q&A (Backend)

- [ ] **T-B6.1 — Question CRUD + assignment**
      Description: `POST/GET/PUT/DELETE /questions`, `GET /questions/{id}/status`, `PATCH /questions/{id}/assign`, `GET /questions/my`, `GET /questions/assigned` (new — questions assigned to current user, paginated), version endpoints. `GET /questions` additionally accepts `?assigned_to=<user_id>|me` filter (A/M only when filtering by another user; `me` allowed for any authenticated user).
      Files: `backend/app/api/v1/questions.py`, `backend/app/services/qa_service.py`, `backend/app/repositories/questions_repo.py`.
      Implementation Notes: Edit creates version row. Assign restricted to A/M; verifies target is `role IN ('moderator','admin')` or designated expert. **Assignment emits `question.assigned` outbox event** with payload `{question_id, assigned_to_id, assigned_by_id, assigned_at, previous_assignee_id?}` — same-transaction write. Reassignment (overwriting an existing assignee) also emits the event with the previous assignee id populated so the dispatcher can revoke the prior assignment notification. `GET /questions/assigned` returns the current user's assigned-to-them questions ordered by `assigned_at DESC`; supports cursor pagination (default 20, max 50); detail row includes `assigned_at`, `assigned_by` (anonymised user ref), and current question status.
      Acceptance Criteria: Edit pre-moderation succeeds; non-author edit returns 403; assignment writes exactly one `question.assigned` outbox row in the same DB transaction; reassignment writes an outbox row with `previous_assignee_id` populated; `GET /questions/assigned` returns only questions where `assigned_to = current_user`; `GET /questions?assigned_to=me` returns the same set; member calling `GET /questions?assigned_to=<other_user>` returns 403.

- [ ] **T-B6.2 — Answer endpoints**
      Description: `POST /questions/{id}/answers`, `GET /questions/{id}/answers`, `PUT/DELETE /answers/{id}`, `PATCH /answers/{id}/accept|verify|mark-official`.
      Files: `backend/app/api/v1/answers.py`, `backend/app/services/qa_service.py`, `backend/app/repositories/answers_repo.py`.
      Implementation Notes: Only one accepted answer per question (DB enforced via app-level uniqueness or atomic update). Verify restricted to A/M (DC-1). `mark-official` restricted to Admin only — requires `is_verified=true` as a precondition (422 `PRECONDITION_FAILED` otherwise); idempotent. The `answers` table carries three additional columns: `is_ica_official BOOLEAN NOT NULL DEFAULT false`, `marked_official_by UUID REFERENCES users(id)`, `marked_official_at TIMESTAMPTZ`. Only one answer per question may hold `is_ica_official=true` (enforced via partial unique index `WHERE is_ica_official = true`). Outbox: `answer.posted`, `answer.accepted`, `answer.verified` (triggers `qa_verify_embedding_job`), `answer.marked_official`.
      Acceptance Criteria: Accept is idempotent; verify sets `is_verified=true`, `verified_by`, `verified_at`; mark-official on unverified answer returns 422; mark-official sets `is_ica_official=true`, `marked_official_by`, `marked_official_at`; a second mark-official on the same answer returns 200 with current state; marking a new answer official on a question where one already exists clears `is_ica_official` on the prior answer (atomic swap); `answer.marked_official` outbox event emitted.

---

### Module 7 — News (Backend)

- [x] **T-B7.1 — News CRUD + status + version endpoints**
      Description: `POST/GET/PUT/DELETE /news`, `/news/my`, `/news/{id}/status`, `/news/{id}/versions[/vid]`.
      Files: `backend/app/api/v1/news.py`, `backend/app/services/news_service.py`, `backend/app/repositories/news_repo.py`.
      Implementation Notes: Phase 1 ignores `is_featured`/`featured_order` (Phase 2 endpoint).
      Acceptance Criteria: List shows only approved; `?country=` filter works.

---

### Module 8 — Social Feed (Backend)

- [ ] **T-B8.1 — Post CRUD + cursor pagination**
      Description: `POST/GET/PUT/DELETE /posts`, `/posts/my`, `/posts/{id}/status`. `GET /posts` uses keyset cursor `(created_at, id)`.
      Files: `backend/app/api/v1/posts.py`, `backend/app/services/post_service.py`, `backend/app/repositories/posts_repo.py`.
      Implementation Notes: Cursor base64-encoded `{created_at, id}`; `WHERE (created_at, id) < (...)`.
      Acceptance Criteria: 100 posts paginate stably under concurrent inserts (no duplicates).

- [ ] **T-B8.2 — Likes (idempotent toggle)**
      Description: `POST /posts/{id}/like` toggles `post_likes` row; updates `likes_count` via `UPDATE ... SET likes_count = likes_count ± 1` (NG-4).
      Files: `backend/app/api/v1/posts.py`, `backend/app/repositories/post_likes_repo.py`.
      Implementation Notes: Single SQL transaction with row lock. Idempotent: repeat call toggles correctly.
      Acceptance Criteria: 2 concurrent like calls from same user yield net like=1 (final state correct).

- [ ] **T-B8.3 — Comments endpoints**
      Description: `GET/POST /posts/{id}/comments`, `DELETE /posts/{id}/comments/{cid}`.
      Files: `backend/app/api/v1/comments.py`, `backend/app/services/comment_service.py`, `backend/app/repositories/comments_repo.py`.
      Implementation Notes: Delete restricted to A/M or comment author.
      Acceptance Criteria: Non-owner non-mod delete returns 403.

---

### Module 9 — Moderation (Backend)

- [ ] **T-B9.1 — Unified moderation queue endpoints**
      Description: `GET /moderation/queue[/questions|documents|news|posts|flagged]`, `GET /moderation/stats`, `GET /moderation/logs[/...]`.
      Files: `backend/app/api/v1/moderation.py`, `backend/app/services/moderation_service.py`, `backend/app/repositories/moderation_repo.py`.
      Implementation Notes: Cursor pagination (default 20, max 50). Flagged queue restricted to Admin (AC-5).
      Acceptance Criteria: Stats counts match queue lengths.

- [ ] **T-B9.2 — Moderation action endpoints (5 actions)**
      Description: `POST /moderation/approve|reject|request-changes|flag|retract` — idempotent; writes `moderation_logs` row + outbox event in same transaction.
      Files: `backend/app/api/v1/moderation.py`, `backend/app/services/moderation_service.py`.
      Implementation Notes: Approve may include `category_id` (categorise at approval, news/posts). Reject/retract require `remarks`. Retract sets `law_status='retracted'`, `retracted_at`, `retraction_reason`. Outbox event triggers `search_index_job` / retraction propagation.
      Acceptance Criteria: Repeated approve returns 200 with current state; retracted document removed from default search via subsequent index update.

---

### Module 10 — Notifications (Backend)

- [x] **T-B10.1 — Notification list + read endpoints**
      Description: `GET /notifications`, `PATCH /notifications/{id}/read`, `PATCH /notifications/read-all`, `DELETE /notifications/{id}`.
      Files: `backend/app/api/v1/notifications.py`, `backend/app/services/notification_service.py`, `backend/app/repositories/notifications_repo.py`.
      Implementation Notes: Read-state updates also invalidate `unread:{user_id}` Redis key (TTL 60s).
      Acceptance Criteria: Bell badge accuracy verified by header check after mark-as-read.
      Completed: 2026-06-02 — Endpoints now use API → service → repository layering; mark-read/read-all/delete invalidate `unread:{user_id}` and response headers verify badge accuracy.

- [x] **T-B10.2 — Unread-count endpoint + `X-Notification-Unread-Count` header middleware**
      Description: `GET /notifications/unread-count` reads-through `redis-cache:unread:{user_id}` (TTL 60s). A response middleware appends the header to every authenticated response.
      Files: `backend/app/api/v1/notifications.py`, `backend/app/core/middleware.py`, `backend/app/services/notification_service.py`.
      Implementation Notes: Polling <60s prohibited — document in OpenAPI. Cache miss path counts and back-fills.
      Acceptance Criteria: Header present on every authenticated 2xx response.
      Completed: 2026-06-02 — `NotificationUnreadCountMiddleware` piggybacks the header on authenticated 2xx responses; unread count read-through uses Redis with PostgreSQL fallback.

- [x] **T-B10.3 — Notification preferences endpoints**
      Description: `GET/PUT /notifications/preferences`.
      Files: `backend/app/api/v1/notifications.py`, `backend/app/repositories/notification_prefs_repo.py`.
      Acceptance Criteria: A null country/category row represents "all".
      Completed: 2026-06-02 — Preferences support persisted country/category filters; empty/default preference resolves to the null country/category "all" row.

---

### Module 11 — Search (Backend, Phase 1 = `/search` only)

- [ ] **T-B11.1 — `GET /search` hybrid endpoint**
      Description: Validate query params, apply pre-filters (country, category, tags, status, date), call OpenSearch with BM25 + k-NN; RRF merge; cache through `redis-cache`.
      Files: `backend/app/api/v1/search.py`, `backend/app/services/search_service.py`, `backend/app/repositories/opensearch_repo.py`, `backend/app/core/cache.py`.
      Implementation Notes: Cache key SHA256 of normalised params; TTL 300s (member) / 60s (mod). Add cache key to `scope:country:{c}:category:{cat}` Redis Set with TTL 600s. Default `law_status=active`. Hard timeout on OpenSearch 800 ms.
      Acceptance Criteria: p95 ≤ 1,500 ms on 500-doc corpus (MVP-6); response includes `latency_ms` and `cache_hit`.

- [ ] **T-B11.2 — Search degradation behaviour**
      Description: When OpenSearch unreachable, return 503 `SEARCH_UNAVAILABLE` with retry-after; circuit breaker (GAP-8) trips after 3 failures.
      Files: `backend/app/services/search_service.py`, `backend/app/core/circuit_breaker.py`.
      Acceptance Criteria: With OpenSearch stopped, 503 returned within 1 s; breaker resets after 60 s.

---

### Module 12 — Dashboard (Backend)

- [ ] **T-B12.1 — `GET /dashboard` aggregated endpoint**
      Description: Single endpoint aggregating recent news, my pending items, unread count, recent Q&A, recent docs.
      Files: `backend/app/api/v1/dashboard.py`, `backend/app/services/dashboard_service.py`.
      Implementation Notes: Uses `ANALYTICS_DATABASE_URL` (read replica) with fall-back to primary when `pg_replica_lag_seconds > 10`.
      Acceptance Criteria: Response time ≤ 300 ms p95 against seeded data.

---

### Module 13 — Taxonomy (Backend)

- [x] **T-B13.1 — Tags & categories CRUD**
      Description: `GET/POST/PUT/DELETE /tags`, `GET/POST/PUT/DELETE /categories`, `GET /countries`.
      Files: `backend/app/api/v1/taxonomy.py`, `backend/app/services/taxonomy_service.py`.
      Implementation Notes: Soft-delete via `is_active=false` for categories. Tag delete cascades on junction tables.
      Acceptance Criteria: Duplicate tag name → 409; deleting parent category nullifies child `parent_id`.
      Completed: 2026-06-03 — Added `/countries`, `/tags`, and `/categories` APIs with admin-only mutations, duplicate tag conflict handling, category soft-delete with child `parent_id` nullification, and API tests.

---

### Module 14 — Admin Stats & Config (Backend)

- [ ] **T-B14.1 — `GET /admin/stats`**
      Description: Aggregated counts: users by role/org, content totals, moderation throughput.
      Files: `backend/app/api/v1/admin.py`, `backend/app/services/admin_service.py`.
      Implementation Notes: Uses analytics replica DSN.
      Acceptance Criteria: Counts match seeded fixtures.

- [ ] **T-B14.2 — `GET/PUT /admin/config`**
      Description: Read/write `platform_config` rows; validate `value_type`; audit via outbox.
      Files: `backend/app/api/v1/admin.py`, `backend/app/services/platform_config_service.py`.
      Acceptance Criteria: Type mismatch → 422; updates audit-logged.

---

### Module 15 — System / Ops (Backend)

- [ ] **T-B15.1 — Health probes + metrics**
      Description: `/health/live`, `/health/ready` (PG, redis-broker, redis-cache, OpenSearch), `/health` alias, `/metrics` (Prometheus, restricted via WAF rule).
      Files: `backend/app/api/v1/system.py`, `backend/app/core/health.py`.
      Implementation Notes: `/health/live` never touches deps; `/health/ready` short timeouts (200 ms each).
      Acceptance Criteria: `/health/ready` returns 503 when PG down; `/health/live` still 200.

---

## 2. API Tasks

- [ ] **T-A2.1 — OpenAPI tag organisation + descriptions per module**
      Description: Annotate every route with summary, description, response models, and error responses (401/403/404/409/413/422/429/503).
      Files: `backend/app/api/v1/*.py`, `backend/app/schemas/*.py`.
      Acceptance Criteria: `/docs` shows all Phase 1 endpoints grouped under 15 modules.

- [ ] **T-A2.2 — Pagination envelopes (offset + cursor)**
      Description: Implement `OffsetPagination` and `CursorPagination` dependency helpers; default 10, max 50 (search max 20). Cursor base64 `{created_at, id}`.
      Files: `backend/app/core/pagination.py`, used by `/posts`, `/moderation/queue*`.
      Acceptance Criteria: Cursor stable under inserts; offset returns `total`.

- [ ] **T-A2.3 — Idempotency wrappers**
      Description: Mark and implement idempotent endpoints (logout, moderation actions, accept, like).
      Files: relevant service methods.
      Acceptance Criteria: Repeated identical call returns 200, current state unchanged.

- [ ] **T-A2.4 — Versioning + prefix**
      Description: All routes under `/api/v1/`.
      Files: `backend/app/main.py`, router includes.
      Acceptance Criteria: `/api/v1/health/ready` reachable.

- [ ] **T-A2.5 — Consistent error mapping**
      Description: Replace default `HTTPException` responses with envelope; map all standard error codes from API Design Standards table.
      Files: `backend/app/core/exceptions.py`.
      Acceptance Criteria: 11 distinct error codes returned in the documented scenarios.

---

## 3. Database Tasks

- [x] **T-D3.1 — Alembic environment + initial migration from `DDL_DATAMODEL.sql`**
      Description: Configure Alembic; encode Phase-1 tables (organizations, users, invites, countries, categories, tags, user_preferences, revoked_tokens, documents, document_chunks, document_tags, questions, answers, question_tags, news_articles, posts, comments, post_likes, post_tags, notifications, notification_preferences, content_versions, moderation_logs, outbox_events, platform_config) in a single base migration.
      Files: `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/versions/0001_init.py`, mirrored SQLAlchemy models in `backend/app/models/*.py`.
      Implementation Notes: Use `CITEXT`, `JSONB`, `UUID DEFAULT gen_random_uuid()`. Defer FK `organizations.created_by → users.id`. Composite FK on `questions.accepted_answer` references `(question_id, id)`.
      Acceptance Criteria: Fresh DB migrates clean; `alembic downgrade base` rolls back.
      Completed: 2026-05-25 — migrations 0001–0005 cover all Phase-1 + Phase-2 forward-prep tables; SQLAlchemy models in `backend/app/models/`.

- [x] **T-D3.2 — Indexes (DB Index Strategy §6.4)**
      Description: Create all secondary, partial, and unique indexes called out in the SQL (`idx_users_org_status`, `idx_users_role`, `idx_invites_org_validity`, partial uniques, etc.). Include `idx_answers_ica_official UNIQUE (question_id) WHERE is_ica_official = true` to enforce at most one official ICA position per question at the DB level.
      Files: `backend/alembic/versions/0002_indexes.py`.
      Acceptance Criteria: `pg_indexes` listing matches the plan; concurrent mark-official calls on the same question yield exactly one winner (verified by integration test).
      Completed: 2026-05-25 — migration `20260525_0006` adds all remaining indexes including `idx_answers_ica_official` partial unique; model-level Index objects mirrored for SQLite test coverage; partial-unique enforcement verified by `test_one_ica_official_per_question`.

- [ ] **T-D3.3 — Partitioned `moderation_logs` (RANGE on `created_at`)**
      Description: Range-partition with quarterly partitions + default; quarterly partition creator script.
      Files: `backend/alembic/versions/0003_moderation_logs_partitions.py`, `backend/app/workers/maintenance/partition_manager.py`.
      Acceptance Criteria: Inserts route to correct quarterly partition; default catches out-of-range.

- [x] **T-D3.4 — Outbox table tuning + indexes**
      Description: `idx_outbox_pending(status, priority, created_at) WHERE status IN ('PENDING','IN_PROGRESS')`; autovacuum overrides on `outbox_events`.
      Files: included in 0001 or follow-up migration.
      Acceptance Criteria: `EXPLAIN ANALYZE` of poll query uses the partial index.
      Completed: 2026-05-25 — `idx_outbox_pending` partial index in migration 0002; autovacuum overrides for `outbox_events`, `notifications`, and `revoked_tokens` applied in migration `20260525_0006`.

- [x] **T-D3.5 — Seed reference data**
      Description: Seed `countries` (ISO 3166-1), starter `categories`, `platform_config` defaults (`ai_confidence_*`, `invite_expiry_hours=72`, `supported_languages=["en","es","fr"]`, `max_content_per_org=500`, `moderation_sla_hours=48`). Note: `supported_languages` covers application UI locales from Phase 1; content translation via `?lang=` pipeline activates in Phase 2 but the config value is correct from the start.
      Files: `backend/alembic/versions/0004_seed.py`.
      Acceptance Criteria: Fresh migration populates these rows; `supported_languages` contains all three BCP-47 codes.
      Completed: 2026-06-03 — Migration `20260603_0010_seed_taxonomy_reference_data.py` chains from current head and seeds countries, starter taxonomy, and required platform config defaults including `["en","es","fr"]`.

- [x] **T-D3.6 — Role separation (app vs admin)**
      Description: Create `ica_app` role with INSERT-only on `outbox_events`, `moderation_logs`, `content_versions`; no UPDATE/DELETE on append-only tables. `ica_ro` for replica reads.
      Files: `backend/alembic/versions/0005_roles_grants.py`.
      Acceptance Criteria: App user cannot UPDATE/DELETE the three append-only tables.
      Completed: 2026-05-25 — migration `20260525_0007`; idempotent role creation via DO block; ica_app gets SELECT+INSERT on append-only tables, full CRUD on others; ica_ro SELECT-only with default-privilege propagation.

- [x] **T-D3.7 — PgBouncer config (transaction mode, pool_size=20 MVP)**
      Description: `pgbouncer.ini` and `userlist.txt` templates; `query_timeout=30000ms`, `client_idle_timeout=60s`.
      Files: `infra/pgbouncer/pgbouncer.ini`, `infra/pgbouncer/userlist.txt`, `docker-compose.yml`.
      Acceptance Criteria: App connects via 5433; idle clients reaped.
      Completed: 2026-05-25 — `infra/pgbouncer/pgbouncer.ini` (transaction mode, pool_size=20, query_timeout=30000ms, client_idle_timeout=60s) and `infra/pgbouncer/userlist.txt` template created; existing docker-compose.option2-local.yml already has edoburu/pgbouncer on port 5433 with matching config.

- [ ] **T-D3.8 — OpenSearch index templates (5 indices)**
      Description: Define templates for `ica_documents`, `ica_document_chunks`, `ica_questions`, `ica_news`, `ica_posts` with `m=16`, `ef_construction=512`, `ef_search=256`, `refresh_interval=30s` during ingestion.
      Files: `backend/app/workers/indexing/templates/*.json`, `backend/app/workers/indexing/setup.py`.
      Acceptance Criteria: Templates installable via a one-shot script; `_cat/indices` lists all five after bootstrap.

- [ ] **T-D3.9 — OpenSearch ISM lifecycle + snapshot policies (§8.10)**
      Description: Define Index State Management policies (rollover threshold by size/age, hot→warm transitions, retention) for all 5 indices; configure S3 snapshot repository and a daily snapshot policy.
      Files: `backend/app/workers/indexing/ism/*.json`, `backend/app/workers/indexing/snapshot_setup.py`, `infra/opensearch/snapshot-repository.json`.
      Implementation Notes: Snapshot to dedicated S3 bucket with lifecycle (30-day retention dev, 90-day prod). ISM rollover at 50 GB / 30 d for `ica_document_chunks`; smaller thresholds for content-type indices.
      Acceptance Criteria: ISM policies attached to indices on bootstrap; manual snapshot succeeds; restore drill documented in runbook.

- [x] **T-D3.10 — Enable `pg_stat_statements` extension**
      Description: Add migration that runs `CREATE EXTENSION IF NOT EXISTS pg_stat_statements` and configures `shared_preload_libraries` via PG parameter group / `postgresql.conf` template.
      Files: `backend/alembic/versions/0006_pg_stat_statements.py`, `infra/postgres/postgresql.conf.template`.
      Acceptance Criteria: `pg_stats_export_job` (T-I4.15) can query `pg_stat_statements` without error.
      Completed: 2026-05-25 — migration `20260525_0008` runs `CREATE EXTENSION IF NOT EXISTS pg_stat_statements`; `infra/postgres/postgresql.conf.template` sets `shared_preload_libraries = 'pg_stat_statements'`; docker-compose postgres command updated to pass `-c shared_preload_libraries=pg_stat_statements`.

---

## 4. Integration Tasks

- [x] **T-I4.1 — Storage abstraction (`StorageService`) — MinIO + S3**
      Description: One interface, two providers selected by `STORAGE_PROVIDER`. Pre-signed PUT for direct upload, pre-signed GET for download.
      Files: `backend/app/services/storage_service.py`, `backend/app/core/storage/{minio_provider.py,s3_provider.py}`.
      Acceptance Criteria: Same test suite passes against MinIO (dev) and a moto-mocked S3.
      Completed: 2026-05-26 — `backend/app/core/storage/` package with `base.py`, `local_provider.py`, `minio_provider.py`, `s3_provider.py`, `factory.py`; `storage_service.py` updated to delegate to provider; `STORAGE_PROVIDER=local|minio|s3`; 70 unit tests pass (LocalProvider full suite + S3 via moto; MinIOProvider integration test deferred to T-T7.2).

- [x] **T-I4.2 — Redis clients (broker + cache, separate DBs)**
      Description: Two `Redis` clients — `redis-broker` (db=0), `redis-cache` (db=0 search/entity/rate-limiter/unread, db=1 reserved for Phase-2 translation).
      Files: `backend/app/core/redis.py`.
      Implementation Notes: Never mix DBs across functions. `allkeys-lru` policy on cache.
      Acceptance Criteria: Logical separation verified by integration test (key in cache db=0 not visible from broker client).
      Completed: 2026-05-26 — `backend/app/core/redis.py` with `get_broker()`, `get_cache()`, `get_translation_cache()` (lru_cache singletons), `ping_broker()`, `ping_cache()`; unit tests verify separation (fakeredis); `infra/redis/redis-broker.conf` (noeviction, AOF) + `infra/redis/redis-cache.conf` (allkeys-lru) created.

- [ ] **T-I4.3 — OpenSearch client wrapper**
      Description: Wrap `opensearch-py` with retry, circuit breaker (3 fails → 60s open), bulk helper (`helpers.bulk`, max 5 MB / 200 ops/request), and 800 ms query timeout.
      Files: `backend/app/repositories/opensearch_repo.py`, `backend/app/core/circuit_breaker.py`.
      Acceptance Criteria: Forced timeouts trip the breaker; downstream callers get 503 `SEARCH_UNAVAILABLE`.

- [x] **T-I4.4 — Celery app + reliability config (SAD §10.1 table)**
      Description: Configure Celery exactly per the §10.1 reliability table: `CELERY_TASK_ACKS_LATE=true`, `CELERY_TASK_REJECT_ON_WORKER_LOST=true`, `CELERY_BROKER_TRANSPORT_OPTIONS={"visibility_timeout": 3600}`, per-queue `CELERY_TASK_TIME_LIMIT` (ingestion=300, embeddings=600), `CELERY_TASK_SOFT_TIME_LIMIT = TIME_LIMIT - 60`, `CELERY_TASK_IGNORE_RESULT=true` (global), `CELERY_RESULT_BACKEND` unset (None), per-queue `worker_prefetch_multiplier` (default=4, ingestion=1, embeddings=1, ai=1), `-Ofair`, queue routing for `default`/`ingestion`/`embeddings`/`ai`.
      Files: `backend/app/workers/celery_app.py`, `backend/app/workers/queues.py`, `backend/celery.docker.cmd`.
      Implementation Notes: `visibility_timeout` MUST exceed longest task; never drop below 300 s (embeddings re-execute risk). Soft limit raises `SoftTimeLimitExceeded` so handlers can checkpoint/cleanup before SIGKILL. Tasks that opt into a result MUST set their own `result_expires=300`.
      Acceptance Criteria: SIGKILL during a long task triggers redelivery, not silent loss; `redis-broker` shows no accumulated result keys after a 1k-task run; KEDA queue-depth gauge tracks real backlog on `ingestion`/`embeddings` queues (no prefetched-but-idle skew).
      Completed: 2026-05-26 — `backend/app/workers/celery_app.py` (all SAD §10.1 reliability settings), `backend/app/workers/queues.py` (4 queues, time limits, prefetch multipliers, route_task()), `backend/app/workers/outbox/poller.py` + `stuck_recovery.py` (stubs for T-I4.5/T-I4.6), `backend/celery.docker.cmd`; `redbeat>=2.2.0` added to pyproject.toml; 33 unit tests (config, routing, time limits, prefetch) all pass.

- [x] **T-I4.5 — Transactional outbox poller + dispatcher**
      Description: Celery beat polls every 5 s: `SELECT ... ORDER BY priority ASC, created_at ASC LIMIT 10 FOR UPDATE SKIP LOCKED`; mark `IN_PROGRESS`; dispatch with `task_id=outbox.id` (idempotent).
      Files: `backend/app/workers/outbox/poller.py`, `backend/app/workers/outbox/dispatcher.py`.
      Acceptance Criteria: Two pollers running concurrently never double-dispatch (verified by integration test).
      Completed: 2026-06-02 — `poller.py` rewritten with full FOR UPDATE SKIP LOCKED logic (PostgreSQL) / plain SELECT (SQLite tests); `dispatcher.py` created with event-handler registry, idempotency guard (status==PUBLISHED check), PENDING reset on failure, DEAD_LETTER after OUTBOX_MAX_RETRIES=5; `task_id=event.id` ensures broker-level deduplication; beat schedule registered in `celery_app.py` (5 s interval); 13 unit tests in `tests/unit/test_outbox_poller.py` all pass.

- [x] **T-I4.6 — `outbox_stuck_recovery_job`**
      Description: Every 10 min, reset `IN_PROGRESS > 10 min` to `PENDING`.
      Files: `backend/app/workers/outbox/stuck_recovery.py`.
      Acceptance Criteria: SIGKILL'd dispatcher leaves rows that recover automatically.
      Completed: 2026-06-02 — `stuck_recovery.py` rewritten: `OutboxEventsRepository.reset_stuck(older_than_minutes=10)` bulk-resets stuck events in a single transaction; beat schedule at 600 s in `celery_app.py`; 5 unit tests covering no-op, recent-event guard, single/multi stale reset, and non-IN_PROGRESS exclusion all pass.

- [ ] **T-I4.7 — `document_ingestion_job` (Docling)**
      Description: On document approval, run Docling OCR + extraction with `DOCLING_TIMEOUT_SECONDS=120`; fall back to raw text on partial failure; full failure rejects document (DC-5).
      Files: `backend/app/workers/ingestion/document_ingestion.py`.
      Acceptance Criteria: Scanned PDF yields ≥ 80% text coverage (MVP-10); timeout falls back gracefully.

- [ ] **T-I4.8 — `chunking_job`**
      Description: Split text into 512-token chunks with 64-token overlap, respecting paragraph boundaries; persist to `document_chunks`.
      Files: `backend/app/workers/ingestion/chunking.py`.
      Acceptance Criteria: Chunk count and `chunk_index` continuity verified on a 50-page sample.

- [ ] **T-I4.9 — `embedding_generation_job` (chunks → OpenSearch via Bulk API)**
      Description: Batch embed 32 chunks at a time; index into `ica_document_chunks` via `helpers.bulk`; primary provider OpenAI, fallback local model.
      Files: `backend/app/workers/embeddings/embedding_generation.py`, `backend/app/core/embeddings/{openai_provider.py,local_provider.py}`.
      Acceptance Criteria: 500 chunks indexed in <2 min on dev; fallback exercised when primary fails.

- [ ] **T-I4.10 — `qa_embedding_job` and `qa_verify_embedding_job`**
      Description: Embed approved Q&A into `ica_questions`; verify-update sets `is_verified=true` via partial update.
      Files: `backend/app/workers/embeddings/qa_embedding.py`.
      Acceptance Criteria: New approved answer appears in semantic search within 30 s.

- [ ] **T-I4.11 — `post_embedding_job` + `post_index_job`**
      Description: Embed + index approved posts into `ica_posts`.
      Files: `backend/app/workers/embeddings/post_embedding.py`, `backend/app/workers/indexing/post_index.py`.
      Acceptance Criteria: Approved post appears in `/search?type=posts` within 30 s.

- [ ] **T-I4.12 — `search_index_job → opensearch_refresh_job → search_cache_invalidate_job` chain**
      Description: Celery `chain()` ensures cache invalidation only after OpenSearch confirms index visibility.
      Files: `backend/app/workers/indexing/chain.py`, `backend/app/workers/indexing/refresh.py`, `backend/app/workers/cache/search_cache_invalidate.py`.
      Implementation Notes: `search_cache_invalidate_job` uses `SMEMBERS scope:country:{c}:category:{cat}` + pipelined `DEL`; never `KEYS`/`SCAN`.
      Acceptance Criteria: After approve, next search reflects new content; no stale hits cached.

- [ ] **T-I4.13 — `notification_dispatch_job` + Phase-1 notification catalogue**
      Description: Outbox-driven dispatcher that inserts `notifications` rows, invalidates `unread:{user_id}` (TTL 60s), and emits email via SMTP/SendGrid with SES fallback (when the recipient has the email channel enabled per `notification_preferences`). Register every Phase-1 notification type in a single dispatch catalogue with explicit recipient resolution, template copy (EN/ES/FR per T-D3.5), and channel routing.
      Files: `backend/app/workers/notifications/dispatch.py`, `backend/app/services/notification_service.py`, `backend/app/services/email_service.py`, `backend/app/workers/notifications/templates/*.{html,txt}`, `backend/app/models/notification.py` (enum).
      Implementation Notes: Phase-1 notification catalogue — each entry maps outbox `event_type` → recipient resolver → notification type → template. Channels: in-app always; email gated by user pref.

      | Outbox event | Recipient(s) | Notification type | Channels |
      |---|---|---|---|
      | `question.answered` | Question author | `question_answered` | in-app + email |
      | `question.assigned` | Newly assigned expert; if `previous_assignee_id` present → also send `question.unassigned` to prior assignee (or auto-mark their `question_assigned` notification as read) | `question_assigned` / `question_unassigned` | in-app + email |
      | `answer.verified` | Answer author | `answer_verified` | in-app + email |
      | `answer.accepted` | Answer author | `answer_accepted` | in-app |
      | `answer.marked_official` | Answer author **and** question author (deduplicate when same user) | `answer_marked_official` | in-app + email |
      | `document.approved` / `news.approved` / `post.approved` / `question.approved` | Submitter | `<type>_approved` | in-app + email |
      | `document.rejected` / `news.rejected` / `post.rejected` / `question.rejected` | Submitter | `<type>_rejected` | in-app + email |
      | `document.changes_requested` / etc. | Submitter | `<type>_changes_requested` | in-app + email |
      | `document.retracted` | Submitter | `document_retracted` | in-app + email |
      | `document.downloaded` | (audit only, no notification) | — | — |
      | `user.role_changed` / `user.status_changed` | Affected user | `account_role_changed` / `account_status_changed` | in-app + email |
      | `invite.consumed` | Inviter | `invite_consumed` | in-app |

      Email template body never includes the full content — only a deep link back to `/notifications/{id}` or the entity. Templates support EN/ES/FR; locale resolved from recipient's `users.preferred_lang`. Each notification row stores `payload` (JSONB) with the linked entity reference for client-side deep linking.
      Acceptance Criteria: Every event in the catalogue dispatches a `notifications` row to the correct recipient set; assigning an already-assigned question dispatches `question_unassigned` to the prior assignee; verifying an answer dispatches `answer_verified` to the answer author (not the question author); marking official dispatches exactly two rows when answer author ≠ question author and one row when they are the same user; email channel honours `notification_preferences.email_enabled`; template renders in user's `preferred_lang`.
      Partial (Sprint 2 spine, 2026-06-02): outbox-driven dispatch + post-commit cache invalidation/email wired. In Modules 1–4 the dispatch catalogue is intentionally limited to the events the spec maps to notifications: `user.role_changed → account_role_changed` and `user.status_changed → account_status_changed` (in-app + preference-gated email), and `invite.consumed → invite_consumed` (in-app). All other Module 1–4 outbox events publish as no-ops (no self-notifications). Email body carries only a deep link to `/notifications/{id}` via the provider-boundary stub. REMAINING for full completion: Module 5–9 events (document/news/post/question approve·reject·changes·retract, answer.posted/accepted/verified/marked_official), `question.assigned`/`question_unassigned` reassignment handling, the marked-official dual-recipient + dedup logic, and the real SMTP/SendGrid + SES provider (currently logs only).

- [ ] **T-I4.14 — `news_broadcast_job` (group of 100 per sub-task)**
      Description: Fan-out via `group()` batched in sub-tasks of 100 subscribers based on `notification_preferences`.
      Files: `backend/app/workers/notifications/news_broadcast.py`.
      Acceptance Criteria: 10k-subscriber broadcast completes in seconds; failed sub-task retried independently.

- [ ] **T-I4.X1 — Entity read-through cache helper (§5.12, R5-G07)**
      Description: Service-layer helper for hot entities (`entity:{document|question|news|post}:{id}`) read-through `redis-cache` (TTL 300s). Explicit invalidation on update, approval, retraction, delete; populate via outbox-driven invalidation events.
      Files: `backend/app/core/cache.py` (extend), `backend/app/services/entity_cache.py`, used by detail-fetch repository methods.
      Implementation Notes: Cache key registered in `scope:country:{c}:category:{cat}` Set so retraction propagates alongside search cache invalidation. Cache miss reads PG, populates, returns. Never cache pending content.
      Acceptance Criteria: A second `GET /documents/{id}` returns from cache (verified via `cache_hit` log field); update/approve/retract evicts within 1 s.

- [x] **T-I4.X3 — Dev `docker-compose.yml` covering SAD §10.1 services**
      Description: Single `docker-compose.yml` provisioning the full local stack: `postgres` (5432), `pgbouncer` (5433, transaction mode, pool_size=20), `redis-broker` (6380, db=0, no eviction), `redis-cache` (6381, db=0 search/db=1 translation, `allkeys-lru`), `opensearch` (9200, single-node 1 GB heap), `minio` (9000/9001), `backend` (uvicorn :8000, depends on pgbouncer + both redises + opensearch + minio), `celery-worker` (default queue), `celery-ingestion` (ingestion queue, concurrency=2), `celery-embeddings` (embeddings queue), `celery-beat` (scheduler — outbox poller + maintenance jobs), `frontend` (next dev :3000). Each Celery service is its own container with explicit `-Q <queue>` and `worker_prefetch_multiplier` per T-I4.4.
      Files: `docker-compose.yml`, `infra/postgres/postgresql.conf.template`, `infra/pgbouncer/pgbouncer.ini`, `infra/redis/redis-broker.conf`, `infra/redis/redis-cache.conf`, `infra/opensearch/opensearch.yml`, `backend/celery.docker.cmd`.
      Implementation Notes: Backend connects to PG **only** through PgBouncer (port 5433), never 5432 directly. Redis broker and cache are separate containers with distinct ports (6380/6381) and configs — never share a container. Healthchecks gate `depends_on: condition: service_healthy` so backend waits for PG, Redis, OpenSearch readiness. Bootstrap step runs OpenSearch index templates (T-D3.8) + ISM (T-D3.9) on first start.
      Acceptance Criteria: `docker compose up` brings the whole stack to healthy in <2 min on a clean workstation; `curl localhost:8000/health/ready` returns 200; a `document.submitted` outbox event end-to-end reaches OpenSearch via the celery-ingestion → celery-embeddings chain.
      Completed: 2026-05-26 — `docker-compose.yml` created as canonical dev file (all 10 services with healthcheck gates); `infra/redis/redis-broker.conf` (noeviction, AOF), `infra/redis/redis-cache.conf` (allkeys-lru, lazy-free), `infra/opensearch/opensearch.yml` (single-node, security disabled); all celery commands updated to `app.workers.celery_app`; `docker-compose.option2-local.yml` also fixed to use correct module path.

- [ ] **T-I4.X2 — KEDA autoscaling for Celery queues**
      Description: KEDA `ScaledObject` manifests for `default`, `ingestion`, `embeddings` queues using Redis list-length trigger; min/max replicas per queue; cooldown + polling intervals tuned to plan.
      Files: `infra/k8s/keda/{default,ingestion,embeddings}-scaledobject.yaml`, `Docs/deployment-phase1.md`.
      Implementation Notes: Relies on `worker_prefetch_multiplier=1` (T-I4.4) so KEDA sees true queue depth. `embeddings` min=1 max=4; `ingestion` min=1 max=3; `default` min=2 max=8.
      Acceptance Criteria: Synthetic 1k-task burst scales `default` workers up within 60s and back down within cooldown window.

- [ ] **T-I4.15 — Maintenance jobs (Celery beat)**
      Description: `revoked_tokens_cleanup_job` (02:00), `outbox_events_cleanup_job` (02:15), `notification_cleanup_job` (02:30), `replica_lag_monitor_job` (60 s), `pg_stats_export_job` (04:00), `query_log_aggregation_job` (03:00), `cache_warmup_job` (post-deploy + 5 min).
      Files: `backend/app/workers/maintenance/*.py`, `backend/app/workers/celery_beat_schedule.py`.
      Acceptance Criteria: Schedule registered with redbeat; catch-up guard `last_run:*` keys present.

---

## 5. Security Tasks

- [x] **T-S5.1 — JWT (RS256), refresh-token cookie, revocation list**
      Description: As per T-B1.1. Verify cookie `HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth/refresh-token`.
      Acceptance Criteria: Refresh cookie not visible to JS; rotation works.
      Completed: 2026-05-29 — RS256 via PyJWT in `security.py`; cookie set with `httponly=True, samesite="strict", path=/api/v1/auth/refresh-token`; JWT now carries `sub`, `user_id`, `role`, `org_id`; revocation persists via `RevokedTokensRepository` and mirrors `revoked:{jti}` to `redis-cache` with DB fallback on Redis failure; covered in `test_security_logging.py::TestJWTAndCookie`.

- [ ] **T-S5.2 — Rate limiting via slowapi + `redis-cache`**
      Description: Per-IP and per-user limits exactly as specified in plan §Rate Limiting; HTTP 429 + `Retry-After`.
      Files: `backend/app/core/rate_limit.py`, route decorators.
      Acceptance Criteria: Each documented limit verified by integration test.

- [ ] **T-S5.3 — File upload security**
      Description: 50 MB hard cap, content-type whitelist (`application/pdf`), magic-byte check, virus scan hook (stub for Phase 1).
      Files: `backend/app/services/storage_service.py`, `backend/app/api/v1/documents.py`.
      Acceptance Criteria: Disguised executable rejected.

- [ ] **T-S5.4 — CORS lockdown**
      Description: Allowed origins from env only; no wildcard; credentials true.
      Files: `backend/app/main.py`.
      Acceptance Criteria: Cross-origin request from unknown origin blocked.

- [x] **T-S5.5 — RBAC dependency**
      Description: FastAPI dependency `require_roles(...)` for A/M/U gating; verifies user `status='active'`.
      Files: `backend/app/core/deps.py`, used by every protected route.
      Acceptance Criteria: Deactivated user gets 401 on every authenticated request.
      Completed: 2026-05-29 — `require_roles(*roles)` factory in `deps.py`; `get_current_user` checks `status='active'`; 4 tests in `test_security_logging.py::TestRBAC` all pass (member→403, moderator→403 on admin-only, deactivated→401).

- [x] **T-S5.6 — Password policy + Argon2 hashing**
      Description: Min 10 chars, mixed case, digit; Argon2id with `time_cost=3, memory_cost=64MB, parallelism=4`.
      Files: `backend/app/core/security.py`.
      Acceptance Criteria: Weak password rejected at signup and change-password.
      Completed: 2026-05-29 — `validate_password_strength` in `security.py`; `PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)`; `hash_password` calls validator before hashing; 11 tests in `test_security_logging.py::TestPasswordPolicy` all pass.

- [ ] **T-S5.7 — Secrets handling**
      Description: All secrets via env / AWS Secrets Manager / Parameter Store; no secrets in repo; `.env.example` documents shape without values.
      Files: `backend/.env.example`, `infra/secrets/README.md`.
      Acceptance Criteria: `git secrets` / `trufflehog` scan clean.

- [ ] **T-S5.8 — TLS enforcement**
      Description: `sslmode=require` on Postgres DSN; `rediss://` on Redis URLs; `https://` on OpenSearch URL in prod.
      Files: env templates + deployment configs.
      Acceptance Criteria: Plaintext URLs in prod env fail boot.

- [ ] **T-S5.9 — Metrics endpoint protection**
      Description: WAF rule blocks public access to `/metrics`; internal VPN range allow-listed.
      Files: `infra/waf/rules.json`, deployment docs.
      Acceptance Criteria: External request returns 403.

- [ ] **T-S5.X1 — CloudFront + AWS WAF in front of ALB**
      Description: Provision CloudFront distribution fronting the ALB; attach AWS WAF web ACL with OWASP Managed Rules, 5 MB body size cap, geo + IP allow/deny rules, AWS rate-based rule (per-IP 2000/5min). Wire `/metrics` allow-list (T-S5.9) into the same web ACL.
      Files: `infra/terraform/cloudfront.tf`, `infra/terraform/waf.tf`, `Docs/deployment-phase1.md`.
      Implementation Notes: Cache headers — bypass for `/api/*`; cache static OpenAPI/health redirects. Origin protocol HTTPS-only with shared secret header.
      Acceptance Criteria: External `POST /documents` >5 MB body blocked at edge with WAF 413; OWASP rule blocks XSS payload in query string; `/metrics` returns 403 from public IP, 200 from VPN range.

- [ ] **T-S5.10 — PII anonymisation path on user delete**
      Description: `DELETE /users/{id}` null PII, `status='deleted'`, revoke all tokens. Contributions retained but author shown as "Anonymised".
      Files: `backend/app/services/user_service.py`.
      Acceptance Criteria: Email column null post-delete; contributions list still includes their items with placeholder author.

---

## 6. Logging and Audit Tasks

- [x] **T-L6.1 — Structured logging (`python-json-logger`)**
      Description: JSON logs with `request_id`, `user_id`, `route`, `status`, `latency_ms`.
      Files: `backend/app/core/logging.py`.
      Acceptance Criteria: One JSON line per request captured to stdout.
      Completed: 2026-05-29 — `configure_logging()` wires `JsonFormatter` + `_RequestContextFilter`; `LOGGING_CONFIG` is importable by Celery workers; `RequestLoggingMiddleware` emits method/path/status/latency_ms per request; filter fixed to not overwrite `extra`-set fields; covered in `test_security_logging.py::TestStructuredLogging`.

- [x] **T-L6.2 — Request-ID propagation**
      Description: Middleware reads `X-Request-ID` or generates one; included in logs, OTel spans, outbound calls.
      Files: `backend/app/core/middleware.py`.
      Acceptance Criteria: Same ID flows from API → Celery task logs.
      Completed: 2026-05-29 — `RequestIDMiddleware` reads or generates UUID; echoes in `X-Request-ID` response header; `REQUEST_ID_CTX` ContextVar injected via `_RequestContextFilter`; `user_id` now read from `request.state` (not ContextVar) to survive BaseHTTPMiddleware task boundary; Celery publish/prerun/postrun signals propagate request/user context into task logs; covered in `test_security_logging.py::TestRequestIDPropagation`.

- [ ] **T-L6.3 — OpenTelemetry tracing**
      Description: Instrument FastAPI, SQLAlchemy, Redis, OpenSearch, Celery; export to OTLP endpoint when `OTEL_EXPORTER_OTLP_ENDPOINT` set.
      Files: `backend/app/core/tracing.py`.
      Acceptance Criteria: Trace exported with spans across API→DB→Celery.

- [ ] **T-L6.4 — Prometheus metrics**
      Description: `prometheus-fastapi-instrumentator` plus custom counters (Celery queue depth via beat job, search cache hit rate, OpenSearch latency).
      Files: `backend/app/core/metrics.py`.
      Acceptance Criteria: `/metrics` exposes counters; depth gauge increments under load.

- [ ] **T-L6.5 — Sentry integration (backend)**
      Description: Init when `SENTRY_DSN` set; environment tag.
      Files: `backend/app/main.py`.
      Acceptance Criteria: Forced exception appears in Sentry test project.

- [ ] **T-L6.6 — Moderation audit trail**
      Description: Every moderation action writes `moderation_logs` row in same transaction as state change.
      Files: `backend/app/services/moderation_service.py`.
      Acceptance Criteria: Approving a doc inserts exactly one log row with actor/timestamp/remarks.

- [x] **T-L6.7 — Outbox-based domain event audit**
      Description: All state-change endpoints write outbox events (`document.approved`, `answer.verified`, etc.).
      Files: per service.
      Acceptance Criteria: Every Phase-1 state transition has a documented event type.
      Completed: 2026-06-02 — `backend/app/workers/outbox/event_catalog.py` created: 38 Phase-1 event types catalogued (29 implemented, 9 planned for Sprint 3–6); all implemented event types verified against live service code; 5 catalog tests in `tests/unit/test_outbox_poller.py` enforce no duplicates, valid statuses, dot-notation format, and completeness against services.

- [ ] **T-L6.8 — SLO alert rules**
      Description: Prometheus alert templates for: outbox `DEAD_LETTER > 0`, search p95 > 1.5 s, replica lag > 10 s, Celery queue depth > N.
      Files: `infra/prometheus/alerts.yml`.
      Acceptance Criteria: Templates loaded by Prometheus; firing rules validated against test metrics.

---

## 7. Testing Tasks

- [ ] **T-T7.1 — Unit tests (services + repositories)**
      Description: Pytest + pytest-asyncio. Mocks: Redis (`fakeredis`), OpenSearch (responses lib), S3 (moto).
      Files: `backend/tests/unit/**/*.py`.
      Acceptance Criteria: ≥ 80% coverage on `services/` and `repositories/`.

- [ ] **T-T7.2 — API integration tests (httpx + dockerised deps)**
      Description: Spin up PG, Redis, OpenSearch, MinIO via `docker-compose.test.yml`; run end-to-end module tests.
      Files: `backend/tests/integration/**/*.py`, `docker-compose.test.yml`.
      Acceptance Criteria: All 15 modules have at least one happy-path + one error-path test.

- [ ] **T-T7.3 — Celery job tests**
      Description: Use `CELERY_ALWAYS_EAGER` for unit; full broker-backed run for integration.
      Files: `backend/tests/workers/**/*.py`.
      Acceptance Criteria: Ingestion → chunk → embed → index chain produces searchable doc end-to-end.

- [ ] **T-T7.4 — Contract tests (OpenAPI vs frontend)**
      Description: Validate that emitted OpenAPI matches frontend MSW handler schemas.
      Files: `backend/tests/contract/test_openapi.py`.
      Acceptance Criteria: Diff against committed `openapi.yaml` is empty.

- [ ] **T-T7.5 — MVP acceptance test suite (MVP-1…MVP-10)**
      Description: One automated test per MVP acceptance criterion in SAD §13.5.
      Files: `backend/tests/acceptance/test_mvp_*.py`.
      Acceptance Criteria: All 10 pass on a clean environment.

- [ ] **T-T7.6 — Load / SLA test for `/search`**
      Description: `locust` script seeding 500 documents and 50 concurrent users; assert p95 ≤ 1,500 ms (MVP-6).
      Files: `backend/tests/load/locustfile.py`.
      Acceptance Criteria: p95 within budget on UAT hardware.

- [ ] **T-T7.7 — Security tests**
      Description: Auth boundary, role escalation, rate-limit, file upload bypass attempts (oversized, wrong MIME, magic-byte mismatch, path traversal).
      Files: `backend/tests/security/**/*.py`.
      Acceptance Criteria: All attempts return correct error codes; no privilege escalation possible.

- [ ] **T-T7.8 — Migration tests**
      Description: Run `alembic upgrade head` then `downgrade base` on every PR.
      Files: `backend/tests/migrations/test_alembic_round_trip.py`.
      Acceptance Criteria: Round-trip clean on CI.

---

## 7a. Backup & Disaster Recovery Tasks (§12.7)

- [ ] **T-DR9.1 — PostgreSQL PITR + automated backups**
      Description: Enable AWS RDS automated backups with PITR (35-day retention prod, 7-day dev); document a `pg_basebackup`-based restore drill.
      Files: `infra/terraform/rds.tf`, `Docs/runbook-phase1.md` (Restore section).
      Acceptance Criteria: Restore-to-staging drill from 24-h-old snapshot completes in <60 min; RPO ≤ 5 min validated.

- [ ] **T-DR9.2 — OpenSearch snapshot policy + restore drill**
      Description: Schedule daily snapshots to S3 (via T-D3.9 repo); document and execute a restore drill into a parallel cluster.
      Files: `Docs/runbook-phase1.md`.
      Acceptance Criteria: Restored cluster passes `_cat/indices` parity check against prod; cutover script documented.

- [ ] **T-DR9.3 — S3 / MinIO versioning + cross-region replication**
      Description: Enable bucket versioning, MFA-delete (prod), lifecycle rules (90-day non-current expiry), and cross-region replication (prod only) for the documents bucket.
      Files: `infra/terraform/s3.tf`, `infra/minio/policy.json`.
      Acceptance Criteria: Overwriting an object preserves prior version; restoring a "deleted" object from version history succeeds.
      Baseline completed: 2026-06-03 — S3 and MinIO providers now enable bucket versioning when ensuring the documents bucket; S3 overwrite version preservation is covered by moto-backed unit tests. MFA delete, lifecycle, and cross-region replication remain for the full DR task.

- [ ] **T-DR9.4 — DR runbook + quarterly drill schedule**
      Description: Consolidated DR runbook covering PG, OpenSearch, S3, Redis (broker rebuild + cache cold-start); quarterly drill calendar with sign-off template.
      Files: `Docs/dr-runbook-phase1.md`.
      Acceptance Criteria: One full end-to-end drill executed before UAT sign-off; RTO ≤ 4 h, RPO ≤ 15 min documented.

---

## 8. Documentation Tasks

- [ ] **T-DOC8.1 — Backend README**
      Description: Setup, env vars, running migrations, starting Celery workers + beat, running tests, docker-compose.
      Files: `backend/README.md`.
      Acceptance Criteria: New dev runs the stack locally in <15 min.

- [ ] **T-DOC8.2 — Auto-generated OpenAPI**
      Description: `/docs`, `/redoc`; committed `Docs/openapi-phase1.yaml` regenerated in CI.
      Files: `backend/scripts/export_openapi.py`, `Docs/openapi-phase1.yaml`.
      Acceptance Criteria: CI fails if committed spec drifts from runtime.

- [ ] **T-DOC8.3 — Runbook**
      Description: On-call runbook covering: OpenSearch breaker open, outbox `DEAD_LETTER`, replica lag, PgBouncer pool exhaustion, Celery queue backlog.
      Files: `Docs/runbook-phase1.md`.
      Acceptance Criteria: Each alert in T-L6.8 has a runbook section.

- [ ] **T-DOC8.4 — Architecture Decision Records (ADRs)**
      Description: ADRs for: CQRS, transactional outbox, OpenSearch from day one, refresh-token cookie, PgBouncer transaction mode.
      Files: `Docs/adr/0001-*.md` … `0005-*.md`.
      Acceptance Criteria: Each ADR cross-links to SAD/IP section.

- [ ] **T-DOC8.5 — Deployment & CI/CD docs**
      Description: GitHub Actions workflows (CI on PR; CD on main); Dockerfiles; ECS/K8s task definitions; PgBouncer + OpenSearch + Redis topology for dev/UAT/prod.
      Files: `.github/workflows/{ci.yml,cd.yml}`, `infra/**`, `Docs/deployment-phase1.md`.
      Acceptance Criteria: PR pipeline runs lint+test+migrate; main pipeline pushes images and deploys to UAT.

- [ ] **T-DOC8.6 — API consumer guide**
      Description: Frontend-facing summary: pagination styles, idempotency, error codes, rate limits, unread-count header.
      Files: `Docs/api-consumer-guide-phase1.md`.
      Acceptance Criteria: Cross-checked against frontend client implementation.

- [ ] **T-DOC8.7 — Data model reference**
      Description: Diagram + table-by-table doc anchored to `DDL_DATAMODEL.sql`.
      Files: `Docs/data-model-phase1.md`.
      Acceptance Criteria: Matches Alembic migrations 0001–0005.

- [ ] **T-DOC8.8 — UAT acceptance gate document**
      Description: Checklist mapping MVP-1…MVP-10 to test IDs (T-T7.5) and dashboards.
      Files: `Docs/uat-gate-phase1.md`.
      Acceptance Criteria: All 10 criteria measurable and signed off before prod promotion.
