# Implementation Task Checklist (API) — Phase 1 GDPR

> Scope: backend, APIs, database, integration, security, logging/audit, testing, and
> documentation work required to bring **all GDPR obligations into Phase 1**, per
> `Docs/GDPR-rule-implementation-plan.md`. UI tasks live in `PHASE_1_GDPR_UI_TASK_CHECKLIST.md`.
>
> Layering: API → Service → Repository. Writes go to PostgreSQL; transactional outbox is
> mandatory for domain events. Error envelope: `{detail, error_code, field_errors}`.
> All routes under `/api/v1/`.
>
> **Task ID scheme:** `T{module}.{section}.{seq}` — module = GDPR functional area (1–5),
> section = heading number below (1 Backend … 8 Documentation). Effort tags: `[S]` ≤1 day,
> `[M]` 2–3 days, `[L]` 4–5 days.
>
> **Traceability to the plan:** Module 1 ⇒ plan T-B16.1 · Module 2 ⇒ T-B16.2 · Module 3 ⇒
> T-B16.3 · Module 4 ⇒ T-B16.4 · supporting tasks ⇒ T-D3.11, T-I4.16, T-S5.11, T-L6.9, T-T7.9, T-DOC8.9.
>
> GDPR modules:
> - **Module 1 — Data Export (Right of Access & Portability)** — Art. 15, 20
> - **Module 2 — Consent Management** — Art. 6, 7, 13–14
> - **Module 3 — Erasure, Restriction & Objection** — Art. 17, 18, 21
> - **Module 4 — Breach Detection & Security Monitoring** — Art. 33–34
> - **Module 5 — GDPR Compliance Documentation** — Art. 5(2), 30, 35

---

## 1. Backend Tasks

### Module 1 — Data Export (Right of Access & Portability)

- [ ] **T1.1.1 [S] — Implement `GdprExportJobRepository`**
      Description: Async SQLAlchemy repository for the `gdpr_export_jobs` table.
      Files / Components to be changed: `backend/app/repositories/gdpr_jobs_repo.py`.
      Implementation Notes: Methods — `create(user_id) -> GdprExportJob`, `get_by_id(job_id)`, `get_latest_for_user(user_id)`, `mark_running(job_id)`, `mark_completed(job_id, s3_key)`, `mark_failed(job_id, error)`. Extend `BaseRepository`; explicit `select()` only (NG-9). `mark_*` methods set `updated_at`/`completed_at`.
      Acceptance Criteria: Unit test creates a job, transitions it `pending → running → completed`, and reads it back with the correct `s3_key`.

- [ ] **T1.1.2 [M] — Implement `GdprExportService`**
      Description: Service that creates export jobs, enforces the once-per-day quota, and resolves job status with a download URL.
      Files / Components to be changed: `backend/app/services/gdpr_export_service.py`.
      Implementation Notes: `request_export(user_id)` — call `get_latest_for_user`; if a row exists with `created_at > now() - 24h` raise `RateLimitError` (`RATE_LIMITED`); else insert row, enqueue `gdpr_export_job` Celery task with `task_id=job.id` (idempotent), write outbox `gdpr_export.requested`, return job. `get_export_status(user_id, job_id)` — fetch; 404 if missing or `job.user_id != user_id`; when `status='completed'` generate a fresh pre-signed GET URL via `StorageService` using `GDPR_EXPORT_URL_TTL`; return `{job_id, status, download_url?, expires_at?}`. Never leak other users' jobs.
      Acceptance Criteria: First `request_export` returns `pending`; a second call within 24 h raises `RATE_LIMITED`; `get_export_status` for a job owned by another user raises `NOT_FOUND`.

- [ ] **T1.1.3 [M] — Implement export endpoints `GET /users/me/export` & `GET /users/me/export/{job_id}`**
      Description: FastAPI routes for triggering and polling a personal-data export.
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/schemas/gdpr.py`.
      Implementation Notes: `GET /users/me/export` → `202 Accepted` + `ExportJobCreatedResponse {job_id, status}`. `GET /users/me/export/{job_id}` → `200` + `ExportJobStatusResponse {job_id, status, download_url, expires_at}`. Both require `require_roles('admin','moderator','member')` and an active user. Rate limits attached per T1.5.1. Service errors mapped through the standard envelope.
      Acceptance Criteria: Trigger returns `202` with a UUID `job_id`; polling an unknown `job_id` returns `404 NOT_FOUND`; polling a completed job returns a usable `download_url`.

### Module 2 — Consent Management

- [ ] **T2.1.1 [S] — Implement `UserConsentRepository`**
      Description: Append-only repository for the `user_consents` table.
      Files / Components to be changed: `backend/app/repositories/consents_repo.py`.
      Implementation Notes: Methods — `add(user_id, consent_type, granted, policy_version, source_ip, user_agent)` (INSERT only — never UPDATE/DELETE), `get_latest_per_type(user_id)` using `DISTINCT ON (consent_type) ... ORDER BY consent_type, created_at DESC`, `get_active(user_id, consent_type) -> bool`. Relies on index `idx_user_consents` (T2.3.1).
      Acceptance Criteria: Inserting grant then withdraw for the same `consent_type` yields two rows; `get_latest_per_type` returns the withdraw row.

- [ ] **T2.1.2 [M] — Implement `ConsentService`**
      Description: Business logic for capturing, querying, and withdrawing consent.
      Files / Components to be changed: `backend/app/services/consent_service.py`, `backend/app/core/enums.py`.
      Implementation Notes: `ConsentType` enum = `privacy_policy`, `terms_of_service`, `email_digest`. `record_consent(user_id, type, granted, source_ip, user_agent)` — resolve `policy_version` from `platform_config` (`privacy_policy_version` / `terms_version`; `email_digest` uses `'n/a'`), insert row, emit outbox `consent.granted` or `consent.withdrawn`. `get_current_consents(user_id)` returns latest per type. `assert_signup_consents(accept_privacy, accept_terms)` raises `ConsentRequiredError` if either is false. Withdrawing `privacy_policy`/`terms_of_service` is forbidden while the account is active (raise `CONSENT_WITHDRAWAL_FORBIDDEN`) — that path is account deletion (Module 3).
      Acceptance Criteria: Recording an `email_digest` withdrawal emits exactly one `consent.withdrawn` outbox row; attempting to withdraw `privacy_policy` raises `CONSENT_WITHDRAWAL_FORBIDDEN`.

- [ ] **T2.1.3 [M] — Implement consent endpoints `GET /users/me/consents` & `POST /users/me/consents`**
      Description: Routes to view current consents and grant/withdraw a consent type.
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/schemas/gdpr.py`.
      Implementation Notes: `GET` → list of `{consent_type, granted, policy_version, created_at}` (latest per type). `POST` body `ConsentUpdateRequest {consent_type, granted}` — extract `source_ip` (respecting `X-Forwarded-For` behind CloudFront) and `User-Agent` from the request, delegate to `ConsentService.record_consent`. Authenticated, active user only.
      Acceptance Criteria: `POST` toggling `email_digest` off then `GET` shows `granted=false`; posting an unknown `consent_type` returns `422 VALIDATION_ERROR`.

- [ ] **T2.1.4 [M] — Wire consent capture into signup (`POST /auth/signup` amendment)**
      Description: Make signup record privacy-policy and terms acceptance atomically, and reject signup without them.
      Files / Components to be changed: `backend/app/api/v1/auth.py`, `backend/app/services/auth_service.py`, `backend/app/schemas/auth.py`.
      Implementation Notes: Extend `SignupRequest` with `accept_privacy_policy: bool`, `accept_terms: bool`, `accept_email_digest: bool = False`. In `auth_service.signup`, call `ConsentService.assert_signup_consents` before creating the user; within the **same DB transaction** as the `users` INSERT, insert `user_consents` rows for `privacy_policy` (granted), `terms_of_service` (granted), and `email_digest` (the supplied value). Capture `source_ip`/`user_agent`.
      Acceptance Criteria: Signup with `accept_terms=false` returns `422 CONSENT_REQUIRED` and creates no `users` row; a successful signup creates the user plus 3 `user_consents` rows in one transaction.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.1.1 [M] — Extract shared `UserService.anonymise()` and implement `DELETE /users/me`**
      Description: Self-service account deletion (right to erasure) reusing the admin anonymisation path.
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/services/user_service.py`, `backend/app/schemas/gdpr.py`.
      Implementation Notes: Refactor the admin `DELETE /users/{id}` logic (Phase 1 T-B2.1 / T-S5.10) into a single `UserService.anonymise(user_id)` — null `email`, `full_name`, `avatar_url`; set `status='deleted'`; revoke all active sessions via the same mechanism `reset-password` uses (Phase 1 T-B1.3); emit outbox `user.deleted`. `DELETE /users/me` accepts body `{password}`, verifies it with `verify_password` against the current user (wrong → `401 UNAUTHORIZED`), then calls `anonymise`. Idempotent if already `deleted`. Contributions are retained and attributed to "Anonymised".
      Acceptance Criteria: `DELETE /users/me` with a wrong password → `401`; with the correct password → PII columns null, `status='deleted'`, all tokens revoked, one `user.deleted` outbox row; the user's documents/questions still list with placeholder author.

- [ ] **T3.1.2 [M] — Implement processing restriction `POST /users/me/restrict-processing`**
      Description: Self-service toggle for restriction of processing / objection (Art. 18 & 21).
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/services/user_service.py`, `backend/app/schemas/gdpr.py`.
      Implementation Notes: Body `RestrictProcessingRequest {restricted: bool}`. Set `users.processing_restricted`; emit outbox `user.processing_restricted` or `user.processing_unrestricted`. Idempotent (no-op + `200` if already in the requested state). Return `{processing_restricted}`. While `true`, the account is excluded from non-essential processing (digests, broadcasts) — enforced in T2.4.1.
      Acceptance Criteria: Toggling to `true` sets the column and emits one outbox event; a repeat call returns `200` with no new event.

- [ ] **T3.1.3 [S] — Expose `processing_restricted` in `GET /auth/me`**
      Description: Surface the restriction flag so the UI can render the current state.
      Files / Components to be changed: `backend/app/api/v1/auth.py`, `backend/app/schemas/auth.py`, `backend/app/services/user_service.py`.
      Implementation Notes: Add `processing_restricted: bool` to the `/auth/me` response model. No new query — column is already on `users`.
      Acceptance Criteria: `GET /auth/me` returns `processing_restricted` reflecting the latest toggle.

### Module 4 — Breach Detection & Security Monitoring

- [ ] **T4.1.1 [M] — Implement `SecurityEventService` + `security.alert` emission**
      Description: Central service that emits structured security-alert signals a breach-response process depends on.
      Files / Components to be changed: `backend/app/services/security_event_service.py`, `backend/app/core/logging.py`, plus call sites in `auth_service.py`, `user_service.py`, `gdpr_export_service.py`.
      Implementation Notes: `emit(event, severity, *, user_id=None, actor_id=None, detail=None)` writes a JSON log line on the `security.alert` channel with `request_id`. Trigger events: repeated failed logins / lockout burst, privileged role change (member → moderator/admin), bulk user deletion, and abnormal export volume. No automated authority notification — the 72-hour decision is a human/DPO process (T5.8.4).
      Acceptance Criteria: A burst of failed logins and a role elevation each produce one `security.alert` JSON log line carrying `request_id` and `severity`.

- [ ] **T4.1.2 [M] — Implement breach register `POST /admin/breach-log` & `GET /admin/breach-log`**
      Description: Append-only register for the DPO to record assessed data-breach incidents.
      Files / Components to be changed: `backend/app/api/v1/admin.py`, `backend/app/services/breach_log_service.py`, `backend/app/repositories/breach_log_repo.py`, `backend/app/schemas/gdpr.py`.
      Implementation Notes: `POST` (Admin only) body `{detected_at, severity, affected_user_count, reported_to_authority_at?, notes}` — INSERT only, sets `created_by`. `GET` (Admin only) lists incidents, offset pagination. No UPDATE/DELETE endpoints — the register is immutable.
      Acceptance Criteria: An Admin can create and list breach-log rows; a Moderator calling either endpoint receives `403 FORBIDDEN`.

---

## 2. API Tasks

### Module 1 — Data Export

- [ ] **T1.2.1 [S] — Pydantic schemas + OpenAPI docs for export endpoints**
      Description: Request/response models and OpenAPI annotations for the export API.
      Files / Components to be changed: `backend/app/schemas/gdpr.py`, `backend/app/api/v1/users.py`.
      Implementation Notes: Schemas `ExportJobCreatedResponse`, `ExportJobStatusResponse` (`status` enum `pending|running|completed|failed`, `download_url`/`expires_at` nullable). Annotate routes with summary, description, and `responses` for `202/401/403/404/429`. Group under an OpenAPI tag `GDPR`.
      Acceptance Criteria: `/docs` shows both export endpoints under the `GDPR` tag with all documented status codes.

- [ ] **T1.2.2 [S] — Export trigger idempotency & validation**
      Description: Prevent duplicate concurrent export jobs and validate the polling path.
      Files / Components to be changed: `backend/app/services/gdpr_export_service.py`, `backend/app/api/v1/users.py`.
      Implementation Notes: If the latest job for the user is still `pending`/`running`, `GET /users/me/export` returns that job (`202`) instead of creating a new one. Validate `{job_id}` is a UUID → `422` otherwise.
      Acceptance Criteria: Two rapid trigger calls return the same `job_id`; a non-UUID `job_id` returns `422 VALIDATION_ERROR`.

### Module 2 — Consent Management

- [ ] **T2.2.1 [S] — Pydantic schemas + OpenAPI docs for consent endpoints & signup**
      Description: Models and OpenAPI annotations for consent and the amended signup contract.
      Files / Components to be changed: `backend/app/schemas/gdpr.py`, `backend/app/schemas/auth.py`, `backend/app/api/v1/users.py`, `backend/app/api/v1/auth.py`.
      Implementation Notes: `ConsentItem`, `ConsentListResponse`, `ConsentUpdateRequest`. Extend `SignupRequest`. Document `200/401/403/422` on consent routes and the new `422 CONSENT_REQUIRED` on signup.
      Acceptance Criteria: `/docs` reflects the consent endpoints and the three new signup fields.

- [ ] **T2.2.2 [S] — Validation, error handling & new error codes**
      Description: Register GDPR-specific error codes and validation rules in the error envelope.
      Files / Components to be changed: `backend/app/core/exceptions.py`, `backend/app/core/enums.py`.
      Implementation Notes: Add error codes `CONSENT_REQUIRED` (422), `CONSENT_WITHDRAWAL_FORBIDDEN` (422), `INVALID_CONSENT_TYPE` (422). Map `ConsentRequiredError` and related exceptions to the envelope. Reuse existing `RATE_LIMITED`, `UNAUTHORIZED`, `NOT_FOUND`, `FORBIDDEN`.
      Acceptance Criteria: Each new error code is returned in its documented scenario with the standard `{detail, error_code, field_errors}` shape.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.2.1 [S] — Pydantic schemas + OpenAPI docs for erasure & restriction**
      Description: Models and OpenAPI annotations for `DELETE /users/me` and `POST /users/me/restrict-processing`.
      Files / Components to be changed: `backend/app/schemas/gdpr.py`, `backend/app/api/v1/users.py`.
      Implementation Notes: `AccountDeletionRequest {password}`, `RestrictProcessingRequest {restricted}`, `RestrictProcessingResponse {processing_restricted}`. Document `200/204/401/403/422`.
      Acceptance Criteria: `/docs` shows both endpoints under the `GDPR` tag with documented codes.

- [ ] **T3.2.2 [S] — Idempotency & error handling for erasure/restriction**
      Description: Guarantee safe repeat calls and correct error mapping.
      Files / Components to be changed: `backend/app/services/user_service.py`, `backend/app/core/exceptions.py`.
      Implementation Notes: `DELETE /users/me` on an already-`deleted` account returns success without re-emitting `user.deleted`. `restrict-processing` is idempotent per T3.1.2. Wrong-password maps to `401 UNAUTHORIZED`.
      Acceptance Criteria: Repeating either call leaves state unchanged and emits no duplicate outbox events.

### Module 4 — Breach Detection & Security Monitoring

- [ ] **T4.2.1 [S] — Pydantic schemas, OpenAPI docs & validation for the breach register**
      Description: Models, annotations, and validation for the breach-log endpoints.
      Files / Components to be changed: `backend/app/schemas/gdpr.py`, `backend/app/api/v1/admin.py`.
      Implementation Notes: `BreachLogCreateRequest`, `BreachLogItem`, `BreachLogListResponse`. `severity` enum `low|medium|high|critical`; `affected_user_count >= 0`; `detected_at` not in the future. Document `201/401/403/422`.
      Acceptance Criteria: `/docs` shows the breach-log endpoints; invalid `severity` returns `422`.

---

## 3. Database Tasks

> All schema changes land in a single Alembic revision `backend/alembic/versions/0007_gdpr.py`
> with a working `downgrade()`. Mirror each table in `backend/app/models/`.

### Module 1 — Data Export

- [ ] **T1.3.1 [M] — Migration & model: `gdpr_export_jobs`**
      Description: Table tracking export-job lifecycle for polling.
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py`, `backend/app/models/gdpr_export_job.py`.
      Implementation Notes: Columns — `id UUID PK DEFAULT gen_random_uuid()`, `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`, `status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','failed'))`, `s3_key TEXT`, `expires_at TIMESTAMPTZ`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `completed_at TIMESTAMPTZ`. Index `idx_gdpr_export_jobs_user ON gdpr_export_jobs(user_id, created_at DESC)` to serve the once-per-day quota lookup.
      Acceptance Criteria: `alembic upgrade head` creates the table; the quota query uses the index (`EXPLAIN`); `downgrade` drops it cleanly.

### Module 2 — Consent Management

- [ ] **T2.3.1 [M] — Migration & model: `user_consents`**
      Description: Append-only consent ledger.
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py`, `backend/app/models/user_consent.py`.
      Implementation Notes: Columns — `id UUID PK`, `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`, `consent_type TEXT NOT NULL CHECK (consent_type IN ('privacy_policy','terms_of_service','email_digest'))`, `granted BOOLEAN NOT NULL`, `policy_version TEXT NOT NULL`, `source_ip INET`, `user_agent TEXT`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`. No `updated_at` — append-only. Index `idx_user_consents ON user_consents(user_id, consent_type, created_at DESC)`.
      Acceptance Criteria: Table created; latest-consent `DISTINCT ON` query uses the index; `downgrade` drops it.

- [ ] **T2.3.2 [S] — Seed `platform_config` policy-version keys**
      Description: Versioning anchors for consent records.
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py` (or extend the Phase 1 seed migration).
      Implementation Notes: Insert `platform_config` rows `privacy_policy_version` (`'1.0'`, string) and `terms_version` (`'1.0'`, string) with `ON CONFLICT (key) DO NOTHING`. These are bumped whenever the Privacy Notice / Terms text changes so re-consent can be detected.
      Acceptance Criteria: Fresh migration populates both keys; `ConsentService` reads them without error.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.3.1 [S] — Migration & model: `users.processing_restricted` column**
      Description: Restriction-of-processing flag on the user record.
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py`, `backend/app/models/user.py`.
      Implementation Notes: `ALTER TABLE users ADD COLUMN processing_restricted BOOLEAN NOT NULL DEFAULT false`. Add the field to the SQLAlchemy `User` model.
      Acceptance Criteria: Column created with default `false` for existing rows; `downgrade` drops it.

### Module 4 — Breach Detection & Security Monitoring

- [ ] **T4.3.1 [S] — Migration & model: `data_breach_log`**
      Description: Append-only breach incident register.
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py`, `backend/app/models/data_breach_log.py`.
      Implementation Notes: Columns — `id UUID PK`, `detected_at TIMESTAMPTZ NOT NULL`, `severity TEXT NOT NULL CHECK (severity IN ('low','medium','high','critical'))`, `affected_user_count INTEGER NOT NULL DEFAULT 0 CHECK (affected_user_count >= 0)`, `reported_to_authority_at TIMESTAMPTZ`, `notes TEXT NOT NULL`, `created_by UUID NOT NULL REFERENCES users(id)`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
      Acceptance Criteria: Table created; `downgrade` drops it.

### Module 5 — Cross-cutting

- [ ] **T5.3.1 [S] — Extend `ica_app` / `ica_ro` role grants for GDPR tables**
      Description: Apply least-privilege grants consistent with the append-only policy (Phase 1 T-D3.6).
      Files / Components to be changed: `backend/alembic/versions/0007_gdpr.py` (or a follow-up `0008_gdpr_grants.py`).
      Implementation Notes: `ica_app` — INSERT-only on `user_consents` and `data_breach_log` (no UPDATE/DELETE); INSERT + UPDATE on `gdpr_export_jobs` (status transitions); UPDATE on the `users.processing_restricted` column. `ica_ro` — SELECT on all four.
      Acceptance Criteria: The app role cannot UPDATE or DELETE `user_consents`/`data_breach_log`; it can transition `gdpr_export_jobs.status`.

---

## 4. Integration Tasks

### Module 1 — Data Export

- [ ] **T1.4.1 [L] — Implement `gdpr_export_job` Celery worker**
      Description: Worker that assembles the user's personal-data archive and publishes it to S3.
      Files / Components to be changed: `backend/app/workers/gdpr/export.py`, `backend/app/workers/queues.py`.
      Implementation Notes: Runs on the `default` queue. Steps — `mark_running`; gather every entity authored by the user: profile fields, `documents`, `questions`, `answers`, `posts`, `comments`, `news_articles`, `notifications`, `user_preferences`, and consent history; serialise as JSONL (one object per line, `entity_type` discriminator); **metadata only — original PDFs are not bundled** (Art. 20 satisfied by metadata + S3 keys); exclude all PII belonging to other users (e.g. other commenters). Upload to `exports/{user_id}/{job_id}.jsonl` via `StorageService`; `mark_completed(s3_key)`; set `expires_at = now() + GDPR_EXPORT_URL_TTL`; emit outbox `gdpr_export.completed`. On any failure `mark_failed` + emit `gdpr_export.failed`. Honour Celery soft-time-limit for cleanup.
      Acceptance Criteria: A seeded user with content in every module receives a JSONL archive containing all their entities and no other user's email/full name; an injected failure sets `status='failed'` and emits `gdpr_export.failed`.

- [ ] **T1.4.2 [S] — `gdpr_export_cleanup_job` maintenance task**
      Description: Beat-scheduled cleanup of expired export archives.
      Files / Components to be changed: `backend/app/workers/maintenance/gdpr_export_cleanup.py`, `backend/app/workers/celery_beat_schedule.py`.
      Implementation Notes: Daily (e.g. 02:45). Delete S3 objects for `gdpr_export_jobs` where `expires_at < now()`; leave the job row for audit but null `s3_key`. Use a `last_run:*` catch-up guard consistent with Phase 1 T-I4.15.
      Acceptance Criteria: An export archive past `expires_at` is removed from S3 on the next run; the job row is retained.

### Module 2 — Consent Management & Module 3 — Restriction

- [ ] **T23.4.1 [S] — Enforce consent + restriction in broadcast/notification workers**
      Description: Make `news_broadcast_job` and `notification_dispatch_job` honour digest consent and processing restriction.
      Files / Components to be changed: `backend/app/workers/notifications/news_broadcast.py`, `backend/app/workers/notifications/dispatch.py`.
      Implementation Notes: When fanning out non-essential notifications (news digests/broadcasts), filter recipients to users with an **active `email_digest` consent** AND `processing_restricted = false`. Essential transactional notifications (e.g. moderation outcome on the user's own content, `gdpr_export.completed`) are still delivered regardless. Resolve consent via `UserConsentRepository.get_active`.
      Acceptance Criteria: A user who withdrew `email_digest` receives no broadcast; a `processing_restricted` user receives no broadcast but still receives a moderation-outcome notification.

### Module 1 + cross-cutting — Outbox / Notifications

- [ ] **T15.4.2 [S] — Register GDPR outbox event types & notification templates**
      Description: Wire the new domain events into the outbox dispatcher and notification catalogue.
      Files / Components to be changed: `backend/app/workers/outbox/dispatcher.py`, `backend/app/services/notification_service.py`, `backend/app/workers/notifications/templates/`.
      Implementation Notes: Register event types `gdpr_export.requested`, `gdpr_export.completed`, `gdpr_export.failed`, `consent.granted`, `consent.withdrawn`, `user.processing_restricted`, `user.processing_unrestricted` in the dispatch table, each with a Pydantic payload validator (identifiers-only, ≤4 KB — SAD §5.10). Add notification types `gdpr_export_completed` (in-app + email, exposes download link) and `gdpr_export_failed` (in-app) with EN template copy.
      Acceptance Criteria: Each event type has a registered consumer; a `gdpr_export.completed` event produces a notification row for the requesting user.

---

## 5. Security Tasks

### Module 1 — Data Export

- [ ] **T1.5.1 [S] — Rate-limit the export endpoints**
      Description: slowapi limits to prevent export abuse.
      Files / Components to be changed: `backend/app/core/rate_limit.py`, `backend/app/api/v1/users.py`.
      Implementation Notes: `GET /users/me/export` — 1/day/user; `GET /users/me/export/{job_id}` — 60/min/user. Per-user key function. Exceeding returns `429 RATE_LIMITED` + `Retry-After`.
      Acceptance Criteria: A second export trigger within 24 h returns `429` with `Retry-After`; the poll endpoint allows 60 calls/min.

- [ ] **T1.5.2 [S] — Pre-signed export URL TTL + env var**
      Description: Bound the lifetime of the export download URL.
      Files / Components to be changed: `backend/app/core/config.py`, `backend/.env.example`, `backend/app/services/gdpr_export_service.py`.
      Implementation Notes: Add `GDPR_EXPORT_URL_TTL` (default `86400` s / 24 h). The pre-signed GET URL is minted on each `get_export_status` read, not stored.
      Acceptance Criteria: `.env.example` documents `GDPR_EXPORT_URL_TTL`; a URL older than the TTL returns S3 `AccessDenied`.

- [ ] **T1.5.3 [M] — Export archive PII-scoping review**
      Description: Verify the export archive contains no third-party personal data.
      Files / Components to be changed: `backend/app/workers/gdpr/export.py` (review + guards).
      Implementation Notes: Audit every query in the export job: comment threads, answers on the user's questions, and moderation remarks must be filtered/redacted so only the requesting user's PII is included. Add explicit projection of columns rather than `SELECT *`.
      Acceptance Criteria: A documented review confirms no other user's `email`/`full_name` appears in a generated archive; covered by the test in T1.7.2.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.5.1 [S] — Password re-authentication for self-service erasure**
      Description: Require a fresh password check before `DELETE /users/me` proceeds.
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/services/user_service.py`.
      Implementation Notes: Verify the supplied password with `verify_password`; rate-limit `DELETE /users/me` (e.g. 5/min/user) to deter brute force. Wrong password → `401 UNAUTHORIZED` and no state change.
      Acceptance Criteria: Three wrong-password attempts all return `401` with the account untouched; a correct password proceeds to anonymisation.

- [ ] **T3.5.2 [S] — Full session revocation on erasure**
      Description: Ensure erasure terminates every active session.
      Files / Components to be changed: `backend/app/services/user_service.py`.
      Implementation Notes: `anonymise()` must revoke access and refresh tokens via the same mechanism `reset-password` uses (Phase 1 T-B1.3). After deletion any presented token resolves to a deleted/anonymised user and is rejected by the RBAC dependency (T-S5.5).
      Acceptance Criteria: A token issued before `DELETE /users/me` returns `401` on the next authenticated request.

### Module 2 & 4 — Consent proof / RBAC

- [ ] **T24.5.1 [S] — Consent proof capture & GDPR endpoint RBAC**
      Description: Store proof-of-consent metadata and lock down GDPR endpoint access.
      Files / Components to be changed: `backend/app/api/v1/users.py`, `backend/app/api/v1/admin.py`, `backend/app/services/consent_service.py`.
      Implementation Notes: Persist `source_ip` (INET) and `user_agent` on every `user_consents` row as evidence of consent (Art. 7(1)). Breach-log endpoints gated `require_roles('admin')`; export/consent/restriction endpoints require an authenticated **active** user (deleted/inactive → `401`/`403`).
      Acceptance Criteria: A consent row carries the caller's IP and user agent; a Moderator gets `403` on `POST /admin/breach-log`; a `deleted` user cannot call any GDPR endpoint.

---

## 6. Logging and Audit Tasks

### Module 1 — Data Export

- [ ] **T1.6.1 [S] — Outbox audit events for export lifecycle**
      Description: Emit domain events for every export-job transition.
      Files / Components to be changed: `backend/app/services/gdpr_export_service.py`, `backend/app/workers/gdpr/export.py`.
      Implementation Notes: `gdpr_export.requested` on trigger (same txn as the job INSERT); `gdpr_export.completed` / `gdpr_export.failed` from the worker. Payloads identifiers-only (`job_id`, `user_id`), ≤4 KB.
      Acceptance Criteria: A full export lifecycle produces exactly one `requested` and one terminal (`completed`/`failed`) outbox row.

### Module 2 — Consent Management

- [ ] **T2.6.1 [S] — Outbox audit events for consent changes**
      Description: Emit `consent.granted` / `consent.withdrawn` on every consent transition.
      Files / Components to be changed: `backend/app/services/consent_service.py`.
      Implementation Notes: Event written in the same transaction as the `user_consents` INSERT. Payload — `user_id`, `consent_type`, `granted`, `policy_version`.
      Acceptance Criteria: Each consent change (including signup-time grants) produces exactly one matching outbox row.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.6.1 [S] — Outbox audit events for restriction & erasure**
      Description: Emit audit events for restriction toggles and confirm erasure auditing.
      Files / Components to be changed: `backend/app/services/user_service.py`.
      Implementation Notes: `user.processing_restricted` / `user.processing_unrestricted` on toggle; confirm `user.deleted` fires on self-service erasure exactly as on the admin path. Same-transaction writes.
      Acceptance Criteria: Every restriction toggle and self-service deletion produces exactly one outbox event in the same transaction as the state change.

### Module 4 — Breach Detection & Security Monitoring

- [ ] **T4.6.1 [M] — Security-alert log channel + Prometheus alert rules**
      Description: Make `security.alert` events observable and alertable.
      Files / Components to be changed: `backend/app/core/logging.py`, `backend/app/core/metrics.py`, `infra/prometheus/alerts.yml`.
      Implementation Notes: Ensure `security.alert` lines are structured JSON and scraped/forwarded. Add a Prometheus counter `security_alert_total{event,severity}` and an alert rule firing on `critical`/`high` severity bursts and on any new `data_breach_log` row.
      Acceptance Criteria: A simulated privileged-role-change burst increments the counter and fires the alert rule against test metrics.

---

## 7. Testing Tasks

### Module 1 — Data Export

- [ ] **T1.7.1 [M] — Unit tests: export service & repository**
      Description: Cover quota enforcement, ownership checks, and job-state transitions.
      Files / Components to be changed: `backend/tests/unit/test_gdpr_export_service.py`, `backend/tests/unit/test_gdpr_jobs_repo.py`.
      Implementation Notes: `fakeredis` for rate-limit state; mock `StorageService`. Assert second-trigger-within-24 h raises `RATE_LIMITED`; cross-user `get_export_status` raises `NOT_FOUND`.
      Acceptance Criteria: All cases pass; ≥80% coverage on the new service/repository files.

- [ ] **T1.7.2 [M] — Integration test: export end-to-end**
      Description: Request → poll → download against the dockerised PG/Redis/MinIO stack.
      Files / Components to be changed: `backend/tests/integration/test_gdpr_export.py`.
      Implementation Notes: Seed a user with content across all modules plus a second user who comments on the first user's question. Run the `gdpr_export_job` (`CELERY_ALWAYS_EAGER`), download the archive, assert it contains the user's own entities and **no** second-user `email`/`full_name`.
      Acceptance Criteria: Archive completeness and third-party-PII-exclusion both verified.

- [ ] **T1.7.3 [S] — Security test: export abuse & isolation**
      Description: Verify rate limiting and cross-user access controls.
      Files / Components to be changed: `backend/tests/security/test_gdpr_export_security.py`.
      Implementation Notes: Assert second trigger within 24 h → `429`; polling another user's `job_id` → `404`; an expired pre-signed URL is rejected by S3/MinIO.
      Acceptance Criteria: All three checks pass.

### Module 2 — Consent Management

- [ ] **T2.7.1 [M] — Tests: consent capture, withdrawal & signup gating**
      Description: Unit + integration coverage for the consent lifecycle.
      Files / Components to be changed: `backend/tests/integration/test_consent.py`, `backend/tests/unit/test_consent_service.py`.
      Implementation Notes: Signup without `accept_terms` → `422 CONSENT_REQUIRED`, no `users` row; successful signup writes 3 consent rows; withdrawing `email_digest` then `GET /users/me/consents` shows `granted=false`; withdrawing `privacy_policy` → `CONSENT_WITHDRAWAL_FORBIDDEN`.
      Acceptance Criteria: All scenarios pass on the PG profile.

- [ ] **T2.7.2 [S] — Test: digest broadcast respects consent**
      Description: Verify withdrawn-consent users are excluded from broadcasts.
      Files / Components to be changed: `backend/tests/workers/test_news_broadcast_consent.py`.
      Implementation Notes: Two subscribers, one with `email_digest` withdrawn; run `news_broadcast_job`; assert only the consenting user is notified.
      Acceptance Criteria: Broadcast recipient set excludes the withdrawn-consent user.

### Module 3 — Erasure, Restriction & Objection

- [ ] **T3.7.1 [M] — Integration test: self-service erasure**
      Description: Verify anonymisation, session revocation, and contribution retention.
      Files / Components to be changed: `backend/tests/integration/test_self_erasure.py`.
      Implementation Notes: Create a user with content; `DELETE /users/me` with the correct password; assert PII columns null, `status='deleted'`, prior token now `401`, contributions still listed as "Anonymised", one `user.deleted` outbox row.
      Acceptance Criteria: All assertions pass.

- [ ] **T3.7.2 [S] — Test: processing restriction excludes from non-essential processing**
      Description: Verify a restricted user is dropped from broadcasts/digests but still gets essential notifications.
      Files / Components to be changed: `backend/tests/workers/test_processing_restriction.py`.
      Implementation Notes: Set `processing_restricted=true`; run broadcast + a moderation-outcome dispatch; assert no broadcast, but the moderation notification is delivered.
      Acceptance Criteria: Restriction semantics verified for both essential and non-essential paths.

- [ ] **T3.7.3 [S] — Security test: erasure password gate**
      Description: Verify wrong-password rejection and rate limiting on `DELETE /users/me`.
      Files / Components to be changed: `backend/tests/security/test_self_erasure_security.py`.
      Implementation Notes: Wrong password → `401`, account intact; exceed the rate limit → `429`.
      Acceptance Criteria: Both checks pass.

### Module 4 — Breach Detection & Security Monitoring

- [ ] **T4.7.1 [S] — Tests: security alerts & breach register**
      Description: Verify `security.alert` emission and breach-log behaviour.
      Files / Components to be changed: `backend/tests/integration/test_breach_log.py`, `backend/tests/unit/test_security_event_service.py`.
      Implementation Notes: Assert a privileged role change and a failed-login burst emit `security.alert` lines; `POST /admin/breach-log` works for Admin and `403`s for Moderator; the register rejects UPDATE/DELETE attempts (append-only).
      Acceptance Criteria: All cases pass.

### Module 5 — Cross-cutting

- [ ] **T5.7.1 [S] — Add GDPR criteria to the MVP acceptance suite**
      Description: Register a GDPR slice in the Phase 1 acceptance gate.
      Files / Components to be changed: `backend/tests/acceptance/test_mvp_gdpr.py`, `Docs/uat-gate-phase1.md`.
      Implementation Notes: One acceptance test per right — access/portability (export), erasure, restriction, consent — plus a privacy-notice-reachable check. Cross-link to T-T7.9.
      Acceptance Criteria: All GDPR acceptance criteria pass on a clean environment and appear in the UAT gate document.

---

## 8. Documentation Tasks

### Module 5 — GDPR Compliance Documentation

- [ ] **T5.8.1 [M] — Privacy Notice content**
      Description: Author the Privacy Notice consumed by the public `/privacy` page.
      Files / Components to be changed: `Docs/gdpr/privacy-notice.md`.
      Implementation Notes: Cover Art. 13–14 — identity of controller/DPO, categories of data, purposes and lawful bases, recipients, retention periods, data-subject rights and how to exercise them, the strictly-necessary refresh-token cookie disclosure, and complaint rights to a supervisory authority. Versioned to match `platform_config.privacy_policy_version`.
      Acceptance Criteria: DPO-reviewed; every Art. 13–14 item present; version string matches the seeded config key.

- [ ] **T5.8.2 [M] — Records of Processing Activities (Art. 30)**
      Description: Document all Phase 1 processing activities.
      Files / Components to be changed: `Docs/gdpr/records-of-processing.md`.
      Implementation Notes: One entry per activity (authentication, content/UGC, moderation, notifications, search indexing, export) — data categories, purposes, lawful bases, recipients/processors, retention, and the international-transfer note (single pinned AWS region in Phase 1; OpenAI deferred to Phase 2).
      Acceptance Criteria: Every processing activity in the Phase 1 system has a record; reviewed by the DPO.

- [ ] **T5.8.3 [S] — Data Retention Policy**
      Description: Consolidate retention rules into a single register.
      Files / Components to be changed: `Docs/gdpr/retention-policy.md`.
      Implementation Notes: Pull together SAD §3.16 / §8.10 — retracted documents 7 yr, rejected uploads 30 d, AI logs 30 d, backups 30 d, export archives 24 h, outbox cleanup, token cleanup — and map each to the enforcing job (Phase 1 T-I4.15, T1.4.2).
      Acceptance Criteria: Each retained data class has a stated period and a named enforcing mechanism.

- [ ] **T5.8.4 [M] — Breach Notification Runbook (Art. 33–34)**
      Description: Operational runbook for data-breach response.
      Files / Components to be changed: `Docs/gdpr/breach-runbook.md`.
      Implementation Notes: Detection (Sentry, `security.alert`, T4.6.1 alerts) → triage/assessment → 72-hour supervisory-authority notification decision → data-subject notification when high risk → recording in `data_breach_log` (T4.1.2). Include roles, contacts, and a decision tree.
      Acceptance Criteria: Runbook references the breach register and every T4.6.1 alert; reviewed by the DPO.

- [ ] **T5.8.5 [L] — Data Protection Impact Assessment (Art. 35)**
      Description: Initial DPIA for the Phase 1 scope.
      Files / Components to be changed: `Docs/gdpr/dpia-phase1.md`.
      Implementation Notes: Describe processing, necessity/proportionality, risks to data subjects and mitigations, and the data-protection-by-design measures (PII isolation, append-only audit, anonymisation). Record the Art. 22 scope note — no automated decision-making in Phase 1 (AI arrives in Phase 2 and will require a DPIA update).
      Acceptance Criteria: DPIA completed and signed off by the DPO before UAT.

- [ ] **T5.8.6 [S] — Update API consumer guide, OpenAPI spec & upstream docs**
      Description: Reflect the GDPR endpoints and the Phase-1 scope change across project docs.
      Files / Components to be changed: `Docs/api-consumer-guide-phase1.md`, `Docs/openapi-phase1.yaml`, `Docs/PHASE_1_API_TASK_CHECKLIST.md`, `Docs/PHASE_2_API_TASK_CHECKLIST.md`, `Docs/requirement-document.md`, `Docs/Solution-Architecture-Document.md`.
      Implementation Notes: Document the export/consent/restriction/breach-log endpoints in the consumer guide and regenerated OpenAPI. Remove "GDPR export" from the Phase 1 API checklist exclusion (line 4); delete the now-superseded Phase 2 GDPR tasks (`T-B16.1`, `T-D3.9`, `T-I4.8`, `T-S5.3`, `T-S5.4`, `T-L6.6`, `T-T7.10`); revise requirement `A-6` and the SAD "(Phase 2)" labels so data portability is Phase 1. **Upstream-doc edits are a sign-off decision — confirm with the project owner before applying.**
      Acceptance Criteria: Consumer guide and OpenAPI cover all GDPR endpoints; checklist/requirement/SAD edits are applied after owner confirmation.
