# API Specification — Restricted ICA Legal Knowledge & Collaboration Platform

> **Source of truth:** This document is derived from `Docs/Solution-Architecture-Document.md` and `Docs/implementation-plan.md`. All endpoints, roles, enums, integrations, and conventions trace back to those documents. Items inferred from context (rather than explicitly stated) are flagged as `Assumption:`.

---

## 1. API Overview

| Field | Value |
|---|---|
| Application | Restricted ICA Legal Knowledge & Collaboration Platform |
| Purpose | Backend HTTP API supporting legal knowledge repository, expert Q&A, knowledge articles, curated news, social feed, AI-assisted hybrid search & RAG, multi-language content, and moderation workflows for an invite-only ICA community. |
| API style | REST over HTTPS, JSON request/response bodies, OpenAPI 3.1 contract |
| API consumers | (1) Next.js web frontend (primary), (2) future mobile clients, (3) internal admin tools, (4) automated test suites, (5) Celery workers calling back into a small subset of internal endpoints |
| Versioning | URI path: all endpoints live under `/api/v1`. Breaking changes bump to `/api/v2`. |
| Interactive docs | `/docs` (Swagger UI), `/redoc` (ReDoc). |

### Base URL placeholders

| Environment | Base URL |
|---|---|
| Local dev | `http://localhost:8000/api/v1` |
| Dev | `https://api.dev.ica-platform.example.com/api/v1` |
| QA | `https://api.qa.ica-platform.example.com/api/v1` |
| UAT | `https://api.uat.ica-platform.example.com/api/v1` |
| Production | `https://api.ica-platform.example.com/api/v1` |

> `Assumption:` Exact production hostnames are placeholders; the SAD specifies CloudFront → ALB → ECS Fargate but does not fix DNS names.

---

## 2. Authentication & Authorization

### 2.1 Authentication mechanism

- **Protocol:** OAuth2 password-grant style, custom — `POST /auth/login` returns a JWT.
- **Algorithm:** RS256 (asymmetric); public key exposed for verification by downstream services if needed.
- **Access token transport:** `Authorization: Bearer <JWT>` header. Frontend keeps it in memory (Zustand store); never in `localStorage`.
- **Access token lifetime:** 30 minutes.
- **Refresh token transport:** `HttpOnly; Secure; SameSite=Strict` cookie. Path is scoped to `/api/v1/auth/refresh-token`. Lifetime 7 days.
- **Logout:** writes the access token's `jti` to `revoked_tokens` (Postgres) **and** to `redis-cache:revoked:{jti}` with TTL = remaining lifetime. `get_current_user` consults Redis first.
- **Password hashing:** bcrypt, work factor ≥ 12.
- **Password reset:** single-use token (1 hour TTL) delivered via email.
- **Onboarding:** invite-only. Self-registration is disabled. Valid `code` required for `POST /auth/signup`.

### 2.2 Token format (JWT payload claims)

```json
{
  "sub": "<user_id UUID>",
  "user_id": "<UUID>",
  "role": "admin|moderator|member",
  "org_id": "<UUID>",
  "jti": "<UUID>",
  "iat": 1715000000,
  "exp": 1715001800
}
```

### 2.3 Roles (RBAC)

Three roles plus a system actor:

| Role | Code | Notes |
|---|---|---|
| Admin | `admin` | Full platform privileges, invite generation, configuration |
| Moderator | `moderator` | Moderation queue, approve/reject/verify, no platform config |
| Member | `member` | UGC submission, search, AI search, profile management |
| System | `admin` (seeded) | Used as actor by automated jobs (e.g., Docling rejection); email `null` |

### 2.4 RBAC matrix (high-level)

| Capability | Admin | Moderator | Member |
|---|:-:|:-:|:-:|
| Generate invites, manage users/orgs | ✓ | — | — |
| Approve/Reject/Request-Changes/Retract | ✓ | ✓ | — |
| Access flagged queue | ✓ | — | — |
| Verify answers (`PATCH /answers/{id}/verify`) | ✓ | ✓ | — |
| Promote Q&A → knowledge article (Phase 2) | ✓ | ✓ | — |
| Feature/pin news | ✓ | — | — |
| Submit UGC, view approved content | ✓ | ✓ | ✓ |
| Use AI search / RAG | ✓ | ✓ | ✓ |
| GDPR self-export | ✓ | ✓ | ✓ |
| Full audit log | ✓ | — | — |
| Platform configuration | ✓ | — | — |

### 2.5 Tenancy

- **Logical multi-tenancy.** `org_id` is part of the JWT payload.
- **No** `X-Tenant-Id` header — tenant is derived server-side from the JWT.
- Organization membership controls **onboarding and attribution only**, not read access. Approved content is platform-wide (per design constraint DC-2 in SAD).

### 2.6 Common authorization rules

1. All `/api/v1/*` endpoints require a valid Bearer JWT **except** `/auth/verify-invite`, `/auth/signup`, `/auth/login`, `/auth/forgot-password`, `/auth/reset-password`, `/auth/refresh-token`, and `/health/*`.
2. Mutation endpoints additionally check the role on the JWT against the endpoint's permission requirement.
3. Owners of UGC may edit their content **only while it is in `pending` or `revision_required` status** (`Assumption:` derived from moderation workflow description).
4. Soft-delete (`DELETE /users/{id}`) anonymises rather than removes — preserves contribution attribution.

---

## 3. Common API Standards

### 3.1 URL conventions

- Base path `/api/v1`.
- Lower-case kebab-style for compound segments (`/forgot-password`).
- Plural resource collections (`/documents`, `/questions`, `/news`).
- Hierarchical paths for sub-resources (`/questions/{id}/answers`).
- Action endpoints are short verbs after the resource (`/posts/{id}/like`, `/answers/{id}/accept`, `/moderation/approve`).

### 3.2 HTTP method semantics

| Method | Use |
|---|---|
| GET | Idempotent read |
| POST | Create or trigger action |
| PUT | Full replace |
| PATCH | Partial update |
| DELETE | Soft-delete / anonymise |

### 3.3 Request / response format

- `Content-Type: application/json; charset=utf-8` for all bodies except file upload (which goes direct-to-S3 — the API never receives binary payloads).
- All IDs are UUID v4.
- All timestamps are UTC ISO 8601 with `Z` suffix (`2026-05-13T10:30:00Z`).

### 3.4 Pagination

Two styles, by endpoint:

**Offset (default)** — most list endpoints:

```
GET /documents?page=1&page_size=10
```

| Param | Default | Max | Notes |
|---|---|---|---|
| `page` | 1 | — | 1-based |
| `page_size` | 10 | 50 (20 for `/search` and `/ai/ask`) | |

Response envelope:

```json
{ "items": [...], "total": 123, "page": 1, "page_size": 10 }
```

**Cursor (keyset)** — high-volume feeds (`GET /posts`, `GET /moderation/queue`, subqueues):

```
GET /posts?cursor=<opaque>&page_size=20
```

The `cursor` is an opaque base64-URL-encoded `{created_at, id}` pair. Response:

```json
{ "items": [...], "next_cursor": "eyJ0Ijoi...", "page_size": 20 }
```

`next_cursor` is `null` at the end of the feed.

### 3.5 Filtering & sorting

- Multi-value via repeated query params: `?country=KE&country=IN&category=cat1`.
- Date ranges: `date_from`, `date_to` (ISO 8601).
- Default sort is `created_at DESC` for lists; search results are ranked by hybrid RRF (k=60).
- Documents default to `law_status=active`; pass `?status=retracted` to view retracted.

### 3.6 Idempotency

Idempotent endpoints (server returns the same logical outcome on retry):

- `POST /auth/logout`
- `POST /moderation/{approve|reject|request-changes|flag|retract}`
- `PATCH /answers/{id}/accept`
- `POST /posts/{id}/like` (toggles)

> `Assumption:` `Idempotency-Key` header is **not** required by the platform; idempotency is enforced by the server based on entity state. Clients may still send `X-Request-ID` for traceability.

### 3.7 Date/time format

- UTC ISO 8601 with `Z` suffix, e.g., `2026-05-13T10:30:00Z`. Server rejects naïve timestamps.

### 3.8 File upload / download

- **Upload pattern:** direct-to-S3 signed PUT URL. The API never accepts the file bytes.
  1. `POST /documents` with metadata → returns `{document_id, upload_url, file_key, status:"pending_upload"}`.
  2. Client `PUT`s the file directly to `upload_url`.
  3. Client calls `POST /documents/{id}/confirm` to advance status to `pending` (moderation queue).
- **Download:** `GET /documents/{id}/download` returns `{download_url, expires_at}` (15-minute pre-signed URL).
- **Max file size:** 50 MB.
- **Allowed MIME types:** `application/pdf` (docs); `image/jpeg`, `image/png` (avatars).
- **Pre-signed URL TTL:** 900 seconds.

### 3.9 Language

- `?lang=<BCP-47>` on document/question/news GET endpoints triggers translate-on-read (Phase 2). Supported: `en`, `es`, `fr`.

---

## 4. Common Headers

### Request

| Header | Required | Notes |
|---|---|---|
| `Authorization: Bearer <JWT>` | Yes (most endpoints) | Skipped for public auth/health endpoints |
| `Content-Type: application/json` | Yes (write methods) | |
| `Accept: application/json` | Recommended | Default if absent |
| `Accept-Language: en|es|fr` | Optional | Hints translate-on-read; explicit `?lang=` query wins |
| `X-Request-ID` | Optional | Client-supplied correlation ID; if absent, server generates and echoes one back |
| `Cookie: refresh_token=...` | Only on `POST /auth/refresh-token` | HttpOnly cookie |

> **No `X-Tenant-Id` header.** Tenant scope is taken from the JWT's `org_id`.

### Response

| Header | When |
|---|---|
| `X-Request-ID` | Every response (UUID) |
| `X-Notification-Unread-Count` | Every authenticated response (badge piggyback for MVP) |
| `Cache-Control: private, no-store` | Personalised endpoints |
| `Cache-Control: public, max-age=3600` | Reference data (`/countries`, `/categories`, `/tags`) |
| `Cache-Control: public, max-age=300` | `/news?featured=true` |
| `Retry-After: <seconds>` | 429 responses |
| `Content-Language: en|es|fr` | Translate-on-read responses |

---

## 5. Common Response Structure

### 5.1 Success

Single resource:

```json
{ "id": "…", "title": "…", "created_at": "2026-05-13T10:30:00Z", ... }
```

Collections use the pagination envelopes (§3.4).

### 5.2 Error

```json
{
  "detail": "Human-readable description of what went wrong.",
  "error_code": "MACHINE_READABLE_CODE",
  "field_errors": [
    { "field": "email", "message": "must be a valid email" }
  ]
}
```

`field_errors` is present only for 400/422 responses.

### 5.3 Search response

```json
{
  "results": [...],
  "total": 42,
  "page": 1,
  "page_size": 10,
  "query_lang": "en",
  "search_mode": "hybrid",
  "latency_ms": 123,
  "cache_hit": false
}
```

---

## 6. Error Code Design

| HTTP | `error_code` | Scenario |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Pydantic validation failed |
| 400 | `INVALID_INVITE` | Invite code invalid / expired / used |
| 400 | `BAD_REQUEST` | Generic semantic error |
| 401 | `UNAUTHORIZED` | Missing / malformed JWT |
| 401 | `TOKEN_EXPIRED` | Access token expired (client should refresh) |
| 401 | `TOKEN_REVOKED` | JTI present in revoked set |
| 403 | `FORBIDDEN` | Insufficient role |
| 404 | `NOT_FOUND` | Entity missing or not accessible to caller |
| 409 | `CONFLICT` | Duplicate resource (e.g., already accepted answer) |
| 413 | `FILE_TOO_LARGE` | Upload > 50 MB |
| 422 | `UNPROCESSABLE` | Request well-formed but semantically invalid |
| 429 | `RATE_LIMITED` | Returns `Retry-After` |
| 500 | `INTERNAL_ERROR` | Unhandled exception |
| 503 | `SEARCH_UNAVAILABLE` | OpenSearch outage |
| 503 | `AI_UNAVAILABLE` | LLM provider outage; circuit breaker open |

Validation errors carry per-field detail in `field_errors`. Authentication/authorization errors are flat (no `field_errors`). Business rule errors use 409 or 422 with a descriptive `error_code` (e.g., `ALREADY_ACCEPTED`, `INVITE_EXPIRED`, `QUOTA_EXCEEDED`).

---

## 7. Endpoint Specification (by module)

> **Convention:** All endpoints below sit under `/api/v1`. Required role keys: **A** = Admin, **M** = Moderator, **U** = Member. `—` denotes a public (unauthenticated) endpoint.

### 7.1 Authentication & Onboarding

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/auth/verify-invite` | — | Validate invite code (lookup `Invites` table) |
| POST | `/auth/signup` | — | Register a user with a valid invite |
| POST | `/auth/login` | — | Email + password → JWT |
| POST | `/auth/logout` | A,M,U | Revoke current JTI |
| POST | `/auth/forgot-password` | — | Email a reset link |
| POST | `/auth/reset-password` | — | Consume reset token, set new password |
| POST | `/auth/refresh-token` | (cookie) | Issue new access token from refresh cookie |
| GET | `/auth/me` | A,M,U | Current user profile |
| PATCH | `/auth/me` | A,M,U | Update own profile |
| POST | `/auth/me/preferences` | A,M,U | First-login country/category preferences |
| POST | `/auth/me/change-password` | A,M,U | Change password while logged in |

### 7.2 Users

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/users` | A,M | List users (filters: `role`, `org_id`, `status`, `q`) |
| GET | `/users/{id}` | A,M,U | User profile |
| PUT | `/users/{id}` | A | Update user |
| DELETE | `/users/{id}` | A | Anonymise (GDPR soft-delete) |
| PATCH | `/users/{id}/status` | A | Activate/deactivate |
| PATCH | `/users/{id}/role` | A | Change role |
| GET | `/users/{id}/contributions` | A,M,U | Aggregated contributions |
| GET | `/users/me/export` | A,M,U | (Phase 2) GDPR export — triggers Celery job, returns pre-signed URL |

### 7.3 Organizations

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/organizations` | A,M,U | List orgs |
| POST | `/organizations` | A | Create org |
| GET | `/organizations/{id}` | A,M,U | Get org |
| PUT | `/organizations/{id}` | A | Update org |
| DELETE | `/organizations/{id}` | A | Delete org |
| GET | `/organizations/{id}/members` | A,M | List members |

### 7.4 Invites

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/invites` | A | Generate invite |
| GET | `/invites` | A | List invites |
| GET | `/invites/{code}` | A | Invite details |
| DELETE | `/invites/{code}` | A | Revoke invite |

### 7.5 Documents

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/documents` | A,M,U | Submit metadata; receive signed S3 PUT URL |
| POST | `/documents/{id}/confirm` | A,M,U | Confirm direct-to-S3 upload finished |
| GET | `/documents` | A,M,U | List approved docs (filters) |
| GET | `/documents/{id}` | A,M,U | Document detail |
| PUT | `/documents/{id}` | A,M | Update metadata |
| DELETE | `/documents/{id}` | A | Delete |
| GET | `/documents/{id}/download` | A,M,U | Pre-signed download URL (15 min) |
| GET | `/documents/{id}/related` | A,M,U | (Phase 2) k-NN related |
| GET | `/documents/my` | A,M,U | User's uploads |
| GET | `/documents/{id}/status` | A,M,U | Moderation status + history |
| GET | `/documents/{id}/versions` | A,M | List versions |
| GET | `/documents/{id}/versions/{vid}` | A,M | Specific version |

### 7.6 Questions & Answers

**Questions:**

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/questions` | A,M,U | Submit |
| GET | `/questions` | A,M,U | List approved |
| GET | `/questions/{id}` | A,M,U | Detail |
| PUT | `/questions/{id}` | A,M,U | Edit (pre-moderation only) |
| DELETE | `/questions/{id}` | A | Delete |
| GET | `/questions/my` | A,M,U | Submitter's view |
| PATCH | `/questions/{id}/assign` | A,M | Assign to expert |
| GET | `/questions/{id}/status` | A,M,U | Status |
| POST | `/questions/{id}/promote` | A,M | (Phase 2) Promote to knowledge article |
| GET | `/questions/{id}/versions` | A,M | Versions |
| GET | `/questions/{id}/versions/{vid}` | A,M | Version |
| GET | `/questions/{id}/related` | A,M,U | (Phase 2) Related |

**Answers:**

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/questions/{question_id}/answers` | A,M,U | Post answer |
| GET | `/questions/{question_id}/answers` | A,M,U | List answers |
| PUT | `/answers/{id}` | A,M,U | Edit |
| DELETE | `/answers/{id}` | A | Delete |
| PATCH | `/answers/{id}/accept` | A,M,U (question author) | Accept answer |
| PATCH | `/answers/{id}/verify` | A,M | Lawyer-verify |

**Q&A comments (Phase 2):**

| Method | Path | Roles |
|---|---|---|
| GET | `/questions/{question_id}/comments` | A,M,U |
| POST | `/questions/{question_id}/comments` | A,M,U |
| DELETE | `/questions/{question_id}/comments/{comment_id}` | A,M,U (own) / A |

### 7.7 News

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/news` | A,M,U | Submit |
| GET | `/news` | A,M,U | List approved |
| GET | `/news/{id}` | A,M,U | Detail |
| PUT | `/news/{id}` | A,M | Update |
| DELETE | `/news/{id}` | A | Delete |
| GET | `/news/my` | A,M,U | Own submissions |
| GET | `/news/{id}/status` | A,M,U | Status |
| PATCH | `/news/{id}/feature` | A | (Phase 2) Pin/feature |
| GET | `/news/{id}/versions` | A,M | Versions |
| GET | `/news/{id}/versions/{vid}` | A,M | Version |
| GET | `/news/{id}/related` | A,M,U | (Phase 2) Related |

### 7.8 Posts (social feed)

| Method | Path | Roles | Purpose |
|---|---|---|---|
| POST | `/posts` | A,M,U | Create |
| GET | `/posts` | A,M,U | Cursor-paginated feed |
| GET | `/posts/{id}` | A,M,U | Detail |
| PUT | `/posts/{id}` | A,M,U | Edit |
| DELETE | `/posts/{id}` | A | Delete |
| POST | `/posts/{id}/like` | A,M,U | Toggle like |
| GET | `/posts/{id}/comments` | A,M,U | List comments |
| POST | `/posts/{id}/comments` | A,M,U | Add comment |
| DELETE | `/posts/{id}/comments/{cid}` | A,M | Delete comment |
| GET | `/posts/my` | A,M,U | User's posts |
| GET | `/posts/{id}/status` | A,M,U | Status |
| GET | `/posts/{id}/related` | A,M,U | (Phase 2) Related |

### 7.9 Moderation

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/moderation/queue` | A,M | Unified queue (cursor) |
| GET | `/moderation/queue/questions` | A,M | Pending questions |
| GET | `/moderation/queue/documents` | A,M | Pending documents |
| GET | `/moderation/queue/news` | A,M | Pending news |
| GET | `/moderation/queue/posts` | A,M | Pending posts |
| GET | `/moderation/queue/flagged` | A | Flagged (Admin) |
| POST | `/moderation/approve` | A,M | Approve (idempotent) |
| POST | `/moderation/reject` | A,M | Reject (idempotent; remarks required) |
| POST | `/moderation/request-changes` | A,M | Request revisions |
| POST | `/moderation/flag` | A,M | Hold for senior review |
| POST | `/moderation/retract` | A,M | Retract approved doc |
| GET | `/moderation/logs` | A | Full audit log |
| GET | `/moderation/logs/{entity_type}/{id}` | A,M | Per-item log |
| GET | `/moderation/stats` | A,M | Queue counts & throughput |

### 7.10 Notifications

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/notifications` | A,M,U | List |
| GET | `/notifications/unread-count` | A,M,U | Unread count (Redis-backed) |
| GET | `/notifications/stream` | A,M,U | (Phase 3) SSE stream |
| PATCH | `/notifications/{id}/read` | A,M,U | Mark read |
| PATCH | `/notifications/read-all` | A,M,U | Mark all read |
| DELETE | `/notifications/{id}` | A,M,U | Delete |
| GET | `/notifications/preferences` | A,M,U | Preferences |
| PUT | `/notifications/preferences` | A,M,U | Update preferences |

### 7.11 Search & AI

| Method | Path | Roles | Phase | Purpose |
|---|---|---|---|---|
| GET | `/search` | A,M,U | 1 | Hybrid BM25 + k-NN search |
| POST | `/ai/ask` | A,M,U | 2 | RAG Q&A with citations |
| GET | `/ai/suggestions/{question_id}` | A,M | 2 | Source passages for moderator |
| POST | `/ai/summarize/{document_id}` | A,M,U | 2 | Document summary |
| POST | `/ai/summarize/question/{question_id}` | A,M,U | 2 | Q&A thread summary |
| POST | `/ai/translate` | A,M,U | 2 | Translate text |
| GET | `/ai/translate/languages` | A,M,U | 2 | Supported languages |

### 7.12 Dashboard

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/dashboard` | A,M,U | Aggregated home dashboard |

### 7.13 Taxonomy / Reference data

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/countries` | A,M,U | List countries |
| GET | `/categories` | A,M,U | List categories (filter by `content_type`) |
| POST | `/categories` | A | Create |
| PUT | `/categories/{id}` | A | Update |
| DELETE | `/categories/{id}` | A | Delete |
| GET | `/tags` | A,M,U | List tags |
| POST | `/tags` | A | Create |
| PUT | `/tags/{id}` | A | Update |
| DELETE | `/tags/{id}` | A | Delete |

### 7.14 Admin Statistics & Configuration

| Method | Path | Roles | Phase | Purpose |
|---|---|---|---|---|
| GET | `/admin/stats` | A | 1 | Platform stats |
| GET | `/admin/ai-usage` | A | 2 | AI usage / cost |
| GET | `/admin/config` | A | 1 | Read platform config |
| PUT | `/admin/config` | A | 1 | Update platform config |

### 7.15 System / Ops

| Method | Path | Roles | Purpose |
|---|---|---|---|
| GET | `/health/live` | — | Liveness (always 200) |
| GET | `/health/ready` | — | Readiness (200/503) |
| GET | `/health` | — | Alias for `/health/ready` |
| GET | `/metrics` | — (internal-only via WAF) | Prometheus text |

---

## 8. Data Schemas (logical view)

Full JSON Schemas live in the OpenAPI YAML (§11). This section summarises shape.

### 8.1 Core entities

- **User** (`id, email, full_name, role, org_id, status, preferred_lang, avatar_url, created_at, updated_at`)
- **Organization** (`id, name, max_users, created_by, created_at`)
- **Invite** (`code, org_id, created_by, expires_at, used_at, used_by, revoked_at`)
- **Document** (`id, title, country, category_id, law_type, language, source_type, file_key, external_url, status, law_status, submitted_by, approved_at, version, created_at`)
- **DocumentChunk** (internal — `id, document_id, chunk_index, chunk_text, token_count, is_embedded`)
- **Question** (`id, title, body, country, category_id, status, submitted_by, assigned_to, version, created_at`)
- **Answer** (`id, question_id, body, posted_by, is_accepted, is_verified, verified_by, created_at, updated_at`)
- **QuestionComment** (`id, question_id, body, author_id, created_at`)
- **NewsArticle** (`id, title, body, country, category_id, status, submitted_by, approved_at, is_featured, featured_order, version, created_at`)
- **Post** (`id, body, submitted_by, status, likes_count, created_at`)
- **Comment** (`id, post_id, body, author_id, created_at`)
- **KnowledgeArticle** (`id, question_id, promoted_by, promoted_at`)
- **Notification** (`id, user_id, event_type, reference_type, reference_id, is_read, created_at`)
- **NotificationPreference** (`user_id, country_code, category_id`)
- **ContentVersion** (`id, entity_type, entity_id, version_number, snapshot, edited_by, edited_at`)
- **ModerationLog** (`id, actor_id, action, entity_type, entity_id, remarks, created_at`)
- **PlatformConfig** (`key, value, value_type, description, updated_by, updated_at`)
- **AiUsageEvent** (`id, event_type, user_id, input_tokens, output_tokens, embedding_calls, model, estimated_cost_usd, created_at`)

### 8.2 Enums

| Enum | Values |
|---|---|
| `UserRole` | `admin`, `moderator`, `member` |
| `UserStatus` | `active`, `inactive`, `deleted` |
| `ContentStatus` | `pending`, `approved`, `rejected`, `revision_required`, `flagged` |
| `LawStatus` | `active`, `retracted`, `superseded` |
| `SourceType` | `uploaded`, `external_url` |
| `ModerationAction` | `approve`, `reject`, `request_changes`, `flag`, `retract` |
| `EntityType` | `document`, `question`, `news`, `post`, `answer`, `user` |
| `SearchMode` | `hybrid`, `keyword`, `semantic` |
| `SearchType` | `documents`, `questions`, `news`, `posts` |
| `Language` | `en`, `es`, `fr` |
| `NotificationEvent` | see §9.3 |
| `AiEventType` | `rag_query`, `content_flag`, `summarize`, `translation`, `embedding` |

### 8.3 Validation rules (selected)

- `email` — RFC 5322 format.
- `password` — min 12 chars; require at least 1 upper, 1 lower, 1 digit. `Assumption:` exact policy.
- `full_name` — 1..255 chars.
- `title` — 1..255 chars.
- `body` (questions/posts/news/answers) — 1..50000 chars. `Assumption:` upper bound.
- `country` — ISO 3166-1 alpha-2.
- `language` / `preferred_lang` — BCP-47, member of supported set.
- `tags[]` — max 10 per item; tag names 1..64 chars, lowercase, hyphen-allowed.
- `page_size` — 1..50 (or 1..20 for `/search`, `/ai/ask`).
- `q` (search) — min 2 chars.
- `remarks` (moderation reject/request-changes/retract) — 1..2000 chars, required.
- File upload — `Content-Length` ≤ 50 MB, MIME in allow-list.

---

## 9. Integration APIs

### 9.1 External systems

| System | Use | Direction |
|---|---|---|
| OpenAI (embeddings + LLM) | RAG, summarisation; fallback to local `all-MiniLM-L6-v2` | Outbound |
| SendGrid (primary) / AWS SES (fallback) | Transactional email | Outbound |
| Docling | PDF text extraction & OCR (isolated `ingestion` worker) | Outbound (sync within worker) |
| Translation provider | Configurable via `TRANSLATION_PROVIDER` env | Outbound |
| AWS S3 / MinIO | Direct-to-S3 signed PUT/GET URLs | Browser ↔ S3 |
| OpenSearch | Hybrid BM25 + k-NN index | Outbound from API & workers |
| LiveKit (Phase 3) | WebRTC sessions; webhooks | Outbound + Inbound webhook |
| External legal data APIs (Phase 3) | Scheduled imports | Outbound |

### 9.2 Webhooks (inbound)

| Path | Source | Phase | Trigger |
|---|---|---|---|
| `POST /webhooks/livekit` | LiveKit | 3 | Room/participant events; enqueues `session_event_job` |

`Assumption:` exact webhook path; SAD says LiveKit webhooks trigger `session_event_job` but does not pin the URL.

### 9.3 Outbox / domain event types

Persisted to `outbox_events` in the same Postgres transaction as the state change, then relayed to downstream Celery handlers:

`document.approved`, `document.rejected`, `document.retracted`, `document.revision_required`, `document.flagged`, `question.approved`, `question.rejected`, `question.assigned`, `question.commented`, `answer.posted`, `answer.accepted`, `answer.verified`, `news.approved`, `news.featured`, `post.approved`, `post.retracted`, `post.commented`, `post.liked`, `user.deactivated`, `user.role_changed`, `moderation.action`, `notify.submitter`, `notify.moderator`, `notify.admin`, `news.broadcast`, `ai_query.completed`, `ai_query.flagged`, `search_index.requested`, `search_cache.invalidate`, `content.versioned`, `outbox.dead_letter`.

### 9.4 In-app notification event types

`document_approved`, `document_rejected`, `document_revision_required`, `document_retracted`, `question_approved`, `question_assigned`, `question_answered`, `question_commented`, `answer_accepted`, `answer_verified`, `news_broadcast`, `content_flagged`, `invite_redeemed`, `user_deactivated`, `password_reset`, `gdpr_export_ready`.

### 9.5 Background jobs (Celery)

| Queue | Tasks (selected) |
|---|---|
| `ingestion` | `document_ingestion_job`, `chunking_job`, `legal_import_job` |
| `embeddings` | `embedding_generation_job`, `qa_embedding_job`, `qa_verify_embedding_job`, `post_embedding_job`, `embedding_backfill_job` |
| `ai` | `ai_answer_job`, `ai_content_flag_job` |
| `default` | `search_index_job`, `search_cache_invalidate_job`, `notification_dispatch_job`, `news_broadcast_job`, `translation_job`, `gdpr_export_job`, `s3_tag_retracted_job`, `session_event_job`, plus periodic cleanup/health jobs |

These jobs do **not** expose public HTTP APIs; they are invoked via the outbox relay. No "/admin/jobs/run" endpoint is exposed by design.

---

## 10. Security Considerations

### 10.1 Input validation

- Pydantic v2 models on every request body, query, path, header.
- Type-strict; unknown fields rejected.
- Length, range, regex, and enum constraints declared on the schema.
- Tag/category IDs validated against reference tables.

### 10.2 Rate limiting (slowapi + Redis)

| Endpoint | Limit |
|---|---|
| `POST /auth/login` | 10 / min / IP |
| `POST /auth/forgot-password` | 3 / min / IP |
| `POST /auth/signup` | 5 / min / IP |
| `POST /auth/verify-invite` | 10 / min / IP |
| `POST /ai/ask` | 20 / min / user (also 20 / hour / user — stricter wins) |
| `POST /ai/summarize/*` | 10 / min / user |
| `POST /invites` | 60 / min / user |
| `PUT /admin/config` | 30 / min / user |
| Any other authenticated request | 300 / min / user |

Exceeded → `429 RATE_LIMITED` with `Retry-After` header.

### 10.3 CORS

```text
allow_origins = [FRONTEND_URL]
allow_credentials = true
allow_methods    = GET, POST, PUT, PATCH, DELETE, OPTIONS
allow_headers    = Authorization, Content-Type, X-Request-ID
```

### 10.4 Audit logging

- All moderation actions write `moderation_logs` (partitioned quarterly).
- Auth events (login, logout, failed login, password reset) and admin config changes are logged at INFO with `actor_id`, `request_id`.
- `X-Request-ID` propagates through all logs and outbox payloads for end-to-end tracing.

### 10.5 Sensitive data masking

- Email and PII (`full_name`, `avatar_url`) are scrubbed from logs.
- JWTs and refresh cookies never appear in logs.
- Passwords never leave the API surface (only hash in DB).

### 10.6 Versioning policy

- URI path versioning; never break a `/v1` contract.
- Deprecation: server emits `Deprecation: true` and `Sunset: <RFC 1123 date>` response headers when a deprecated endpoint is called. `Assumption:` deprecation mechanism wording.

### 10.7 Access control rules summary

- All endpoints default to "authenticated only"; explicit allow-list of public routes.
- Roles checked via FastAPI dependency (`Depends(require_role(...))`).
- Soft-deleted users (`status=deleted`) are rejected at the auth dependency even with a valid JWT.
- Idempotent action endpoints return `200` with the current entity state if the action has already been applied.

### 10.8 Transport

- HTTPS only; HSTS enforced at CloudFront edge.
- ALB and WAF cap request body at 5 MB (uploads bypass — direct-to-S3).
- FastAPI middleware enforces 100 KB default body limit per endpoint (1 MB on bulk endpoints).

---

## 11. OpenAPI 3.1 YAML

> The YAML below is a single, valid OpenAPI 3.1 document. It groups paths by module via tags. Where two entities share a CRUD shape (e.g., Tag, Category), the YAML pattern is identical; only the path differs. The full schema set is declared in `components/schemas`.

```yaml
openapi: 3.1.0
info:
  title: ICA Restricted Legal Knowledge & Collaboration Platform API
  version: 1.0.0
  description: |
    REST API for the invite-only ICA platform: legal document repository, expert Q&A,
    curated news, social feed, hybrid search, and RAG-assisted answering.
    All endpoints are JSON over HTTPS and live under /api/v1.
  contact:
    name: ICA Platform Engineering
servers:
  - url: http://localhost:8000/api/v1
    description: Local dev
  - url: https://api.dev.ica-platform.example.com/api/v1
    description: Dev
  - url: https://api.qa.ica-platform.example.com/api/v1
    description: QA
  - url: https://api.uat.ica-platform.example.com/api/v1
    description: UAT
  - url: https://api.ica-platform.example.com/api/v1
    description: Production

tags:
  - name: Auth
  - name: Users
  - name: Organizations
  - name: Invites
  - name: Documents
  - name: Questions
  - name: Answers
  - name: News
  - name: Posts
  - name: Moderation
  - name: Notifications
  - name: Search
  - name: AI
  - name: Dashboard
  - name: Taxonomy
  - name: Admin
  - name: System
  - name: Webhooks

security:
  - bearerAuth: []

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    refreshCookie:
      type: apiKey
      in: cookie
      name: refresh_token

  parameters:
    Page:
      name: page
      in: query
      schema: { type: integer, minimum: 1, default: 1 }
    PageSize:
      name: page_size
      in: query
      schema: { type: integer, minimum: 1, maximum: 50, default: 10 }
    Cursor:
      name: cursor
      in: query
      schema: { type: string, nullable: true }
    Lang:
      name: lang
      in: query
      schema: { $ref: '#/components/schemas/Language' }
    RequestId:
      name: X-Request-ID
      in: header
      schema: { type: string, format: uuid }
    AcceptLanguage:
      name: Accept-Language
      in: header
      schema: { type: string, example: en }

  headers:
    XRequestId:
      schema: { type: string, format: uuid }
    XNotificationUnreadCount:
      schema: { type: integer, minimum: 0 }
    RetryAfter:
      schema: { type: integer, minimum: 0 }

  responses:
    Unauthorized:
      description: Missing or invalid credentials
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    Forbidden:
      description: Insufficient permissions
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    ValidationError:
      description: Validation failed
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    Conflict:
      description: Conflict
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    RateLimited:
      description: Rate limit exceeded
      headers:
        Retry-After: { $ref: '#/components/headers/RetryAfter' }
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    NoContent:
      description: Success — no body

  schemas:
    UUID:
      type: string
      format: uuid

    Language:
      type: string
      enum: [en, es, fr]
      default: en

    UserRole:
      type: string
      enum: [admin, moderator, member]

    UserStatus:
      type: string
      enum: [active, inactive, deleted]

    ContentStatus:
      type: string
      enum: [pending, approved, rejected, revision_required, flagged]

    LawStatus:
      type: string
      enum: [active, retracted, superseded]

    SourceType:
      type: string
      enum: [uploaded, external_url]

    ModerationAction:
      type: string
      enum: [approve, reject, request_changes, flag, retract]

    EntityType:
      type: string
      enum: [document, question, news, post, answer, user]

    SearchMode:
      type: string
      enum: [hybrid, keyword, semantic]
      default: hybrid

    SearchType:
      type: string
      enum: [documents, questions, news, posts]

    Error:
      type: object
      required: [detail, error_code]
      properties:
        detail:        { type: string }
        error_code:    { type: string, example: VALIDATION_ERROR }
        field_errors:
          type: array
          items:
            type: object
            required: [field, message]
            properties:
              field:   { type: string }
              message: { type: string }

    PageMeta:
      type: object
      required: [total, page, page_size]
      properties:
        total:     { type: integer, minimum: 0 }
        page:      { type: integer, minimum: 1 }
        page_size: { type: integer, minimum: 1 }

    CursorPage:
      type: object
      required: [items, page_size]
      properties:
        items:       { type: array, items: {} }
        next_cursor: { type: string, nullable: true }
        page_size:   { type: integer }

    User:
      type: object
      required: [id, full_name, role, status, preferred_lang, created_at]
      properties:
        id:             { $ref: '#/components/schemas/UUID' }
        email:          { type: string, format: email, nullable: true }
        full_name:      { type: string }
        role:           { $ref: '#/components/schemas/UserRole' }
        org_id:         { $ref: '#/components/schemas/UUID', nullable: true }
        status:         { $ref: '#/components/schemas/UserStatus' }
        preferred_lang: { $ref: '#/components/schemas/Language' }
        avatar_url:     { type: string, format: uri, nullable: true }
        created_at:     { type: string, format: date-time }
        updated_at:     { type: string, format: date-time }

    UserUpdate:
      type: object
      properties:
        full_name:      { type: string, maxLength: 255 }
        role:           { $ref: '#/components/schemas/UserRole' }
        status:         { $ref: '#/components/schemas/UserStatus' }
        preferred_lang: { $ref: '#/components/schemas/Language' }
        avatar_url:     { type: string, format: uri }

    Organization:
      type: object
      required: [id, name, max_users, created_at]
      properties:
        id:         { $ref: '#/components/schemas/UUID' }
        name:       { type: string }
        max_users:  { type: integer, default: 100 }
        created_by: { $ref: '#/components/schemas/UUID' }
        created_at: { type: string, format: date-time }

    Invite:
      type: object
      required: [code, org_id, expires_at]
      properties:
        code:       { type: string }
        org_id:     { $ref: '#/components/schemas/UUID' }
        created_by: { $ref: '#/components/schemas/UUID' }
        expires_at: { type: string, format: date-time }
        used_at:    { type: string, format: date-time, nullable: true }
        used_by:    { $ref: '#/components/schemas/UUID', nullable: true }
        revoked_at: { type: string, format: date-time, nullable: true }

    LoginRequest:
      type: object
      required: [email, password]
      properties:
        email:    { type: string, format: email }
        password: { type: string, minLength: 12 }

    LoginResponse:
      type: object
      required: [access_token, token_type, expires_in]
      properties:
        access_token: { type: string }
        token_type:   { type: string, enum: [bearer], default: bearer }
        expires_in:   { type: integer, example: 1800 }

    SignupRequest:
      type: object
      required: [code, email, full_name, password]
      properties:
        code:           { type: string }
        email:          { type: string, format: email }
        full_name:      { type: string, minLength: 1, maxLength: 255 }
        password:       { type: string, minLength: 12 }
        preferred_lang: { $ref: '#/components/schemas/Language' }

    VerifyInviteResponse:
      type: object
      required: [valid]
      properties:
        valid:      { type: boolean }
        org_name:   { type: string, nullable: true }
        expires_at: { type: string, format: date-time, nullable: true }

    ForgotPasswordRequest:
      type: object
      required: [email]
      properties:
        email: { type: string, format: email }

    ResetPasswordRequest:
      type: object
      required: [token, new_password]
      properties:
        token:        { type: string }
        new_password: { type: string, minLength: 12 }

    ChangePasswordRequest:
      type: object
      required: [current_password, new_password]
      properties:
        current_password: { type: string }
        new_password:     { type: string, minLength: 12 }

    UserPreferencesRequest:
      type: object
      properties:
        countries:  { type: array, items: { type: string, minLength: 2, maxLength: 2 } }
        categories: { type: array, items: { $ref: '#/components/schemas/UUID' } }

    Country:
      type: object
      required: [code, name]
      properties:
        code:      { type: string, minLength: 2, maxLength: 2 }
        name:      { type: string }
        is_active: { type: boolean, default: true }

    Category:
      type: object
      required: [id, name]
      properties:
        id:           { $ref: '#/components/schemas/UUID' }
        name:         { type: string }
        parent_id:    { $ref: '#/components/schemas/UUID', nullable: true }
        content_type: { type: string, enum: [document, question, news], nullable: true }

    Tag:
      type: object
      required: [id, name]
      properties:
        id:   { $ref: '#/components/schemas/UUID' }
        name: { type: string }

    DocumentCreateRequest:
      type: object
      required: [title, country, category_id, source_type]
      properties:
        title:        { type: string, minLength: 1, maxLength: 255 }
        country:      { type: string, minLength: 2, maxLength: 2 }
        category_id:  { $ref: '#/components/schemas/UUID' }
        law_type:     { type: string }
        language:     { $ref: '#/components/schemas/Language' }
        source_type:  { $ref: '#/components/schemas/SourceType' }
        external_url: { type: string, format: uri, nullable: true }
        filename:     { type: string, nullable: true }
        content_type: { type: string, nullable: true, example: application/pdf }
        size_bytes:   { type: integer, maximum: 52428800, nullable: true }

    DocumentCreateResponse:
      type: object
      required: [document_id, status]
      properties:
        document_id: { $ref: '#/components/schemas/UUID' }
        upload_url:  { type: string, format: uri, nullable: true }
        file_key:    { type: string, nullable: true }
        status:      { type: string, enum: [pending_upload, pending] }

    Document:
      type: object
      required: [id, title, country, category_id, status, law_status, created_at]
      properties:
        id:            { $ref: '#/components/schemas/UUID' }
        title:         { type: string }
        country:       { type: string }
        category_id:   { $ref: '#/components/schemas/UUID' }
        law_type:      { type: string, nullable: true }
        language:      { $ref: '#/components/schemas/Language' }
        source_type:   { $ref: '#/components/schemas/SourceType' }
        file_key:      { type: string, nullable: true }
        external_url:  { type: string, format: uri, nullable: true }
        status:        { $ref: '#/components/schemas/ContentStatus' }
        law_status:    { $ref: '#/components/schemas/LawStatus' }
        submitted_by:  { $ref: '#/components/schemas/UUID' }
        approved_at:   { type: string, format: date-time, nullable: true }
        version:       { type: integer, default: 1 }
        created_at:    { type: string, format: date-time }

    DocumentUpdate:
      type: object
      properties:
        title:       { type: string }
        category_id: { $ref: '#/components/schemas/UUID' }
        law_type:    { type: string }
        language:    { $ref: '#/components/schemas/Language' }

    DownloadUrlResponse:
      type: object
      required: [download_url, expires_at]
      properties:
        download_url: { type: string, format: uri }
        expires_at:   { type: string, format: date-time }

    Question:
      type: object
      required: [id, title, body, country, category_id, status, submitted_by, created_at]
      properties:
        id:            { $ref: '#/components/schemas/UUID' }
        title:         { type: string }
        body:          { type: string }
        country:       { type: string }
        category_id:   { $ref: '#/components/schemas/UUID' }
        tags:          { type: array, items: { type: string } }
        status:        { $ref: '#/components/schemas/ContentStatus' }
        submitted_by:  { $ref: '#/components/schemas/UUID' }
        assigned_to:   { $ref: '#/components/schemas/UUID', nullable: true }
        version:       { type: integer }
        created_at:    { type: string, format: date-time }

    QuestionCreateRequest:
      type: object
      required: [title, body, country, category_id]
      properties:
        title:       { type: string, minLength: 5, maxLength: 255 }
        body:        { type: string, minLength: 1, maxLength: 50000 }
        country:     { type: string, minLength: 2, maxLength: 2 }
        category_id: { $ref: '#/components/schemas/UUID' }
        tags:        { type: array, items: { type: string }, maxItems: 10 }

    QuestionUpdate:
      type: object
      properties:
        title: { type: string }
        body:  { type: string }
        tags:  { type: array, items: { type: string } }

    Answer:
      type: object
      required: [id, question_id, body, posted_by, created_at]
      properties:
        id:          { $ref: '#/components/schemas/UUID' }
        question_id: { $ref: '#/components/schemas/UUID' }
        body:        { type: string }
        posted_by:   { $ref: '#/components/schemas/UUID' }
        is_accepted: { type: boolean, default: false }
        is_verified: { type: boolean, default: false }
        verified_by: { $ref: '#/components/schemas/UUID', nullable: true }
        created_at:  { type: string, format: date-time }
        updated_at:  { type: string, format: date-time }

    AnswerCreateRequest:
      type: object
      required: [body]
      properties:
        body: { type: string, minLength: 1, maxLength: 50000 }

    QuestionComment:
      type: object
      required: [id, question_id, body, author_id, created_at]
      properties:
        id:          { $ref: '#/components/schemas/UUID' }
        question_id: { $ref: '#/components/schemas/UUID' }
        body:        { type: string }
        author_id:   { $ref: '#/components/schemas/UUID' }
        created_at:  { type: string, format: date-time }

    NewsArticle:
      type: object
      required: [id, title, body, country, category_id, status, created_at]
      properties:
        id:             { $ref: '#/components/schemas/UUID' }
        title:          { type: string }
        body:           { type: string }
        country:        { type: string }
        category_id:    { $ref: '#/components/schemas/UUID' }
        status:         { $ref: '#/components/schemas/ContentStatus' }
        submitted_by:   { $ref: '#/components/schemas/UUID' }
        approved_at:    { type: string, format: date-time, nullable: true }
        is_featured:    { type: boolean, default: false }
        featured_order: { type: integer, nullable: true }
        version:        { type: integer }
        created_at:     { type: string, format: date-time }

    NewsCreateRequest:
      type: object
      required: [title, body, country, category_id]
      properties:
        title:       { type: string, maxLength: 255 }
        body:        { type: string, maxLength: 50000 }
        country:     { type: string, minLength: 2, maxLength: 2 }
        category_id: { $ref: '#/components/schemas/UUID' }

    NewsUpdate:
      type: object
      properties:
        title:       { type: string }
        body:        { type: string }
        category_id: { $ref: '#/components/schemas/UUID' }

    NewsFeatureRequest:
      type: object
      required: [is_featured]
      properties:
        is_featured:    { type: boolean }
        featured_order: { type: integer, nullable: true }

    Post:
      type: object
      required: [id, body, submitted_by, status, created_at]
      properties:
        id:           { $ref: '#/components/schemas/UUID' }
        body:         { type: string }
        submitted_by: { $ref: '#/components/schemas/UUID' }
        status:       { $ref: '#/components/schemas/ContentStatus' }
        likes_count:  { type: integer, default: 0 }
        tags:         { type: array, items: { type: string } }
        created_at:   { type: string, format: date-time }

    PostCreateRequest:
      type: object
      required: [body]
      properties:
        body: { type: string, minLength: 1, maxLength: 5000 }
        tags: { type: array, items: { type: string }, maxItems: 10 }

    Comment:
      type: object
      required: [id, body, author_id, created_at]
      properties:
        id:        { $ref: '#/components/schemas/UUID' }
        post_id:   { $ref: '#/components/schemas/UUID' }
        body:      { type: string }
        author_id: { $ref: '#/components/schemas/UUID' }
        created_at: { type: string, format: date-time }

    CommentCreateRequest:
      type: object
      required: [body]
      properties:
        body: { type: string, minLength: 1, maxLength: 5000 }

    LikeToggleResponse:
      type: object
      required: [liked, likes_count]
      properties:
        liked:       { type: boolean }
        likes_count: { type: integer }

    ModerationActionRequest:
      type: object
      required: [entity_type, entity_id]
      properties:
        entity_type: { $ref: '#/components/schemas/EntityType' }
        entity_id:   { $ref: '#/components/schemas/UUID' }
        category_id: { $ref: '#/components/schemas/UUID', nullable: true }
        remarks:     { type: string, maxLength: 2000 }

    ModerationLog:
      type: object
      required: [id, actor_id, action, entity_type, entity_id, created_at]
      properties:
        id:          { $ref: '#/components/schemas/UUID' }
        actor_id:    { $ref: '#/components/schemas/UUID' }
        action:      { $ref: '#/components/schemas/ModerationAction' }
        entity_type: { $ref: '#/components/schemas/EntityType' }
        entity_id:   { $ref: '#/components/schemas/UUID' }
        remarks:     { type: string, nullable: true }
        created_at:  { type: string, format: date-time }

    QueueItem:
      type: object
      required: [entity_type, entity_id, status, submitted_by, created_at]
      properties:
        entity_type:    { $ref: '#/components/schemas/EntityType' }
        entity_id:      { $ref: '#/components/schemas/UUID' }
        title:          { type: string, nullable: true }
        excerpt:        { type: string, nullable: true }
        status:         { $ref: '#/components/schemas/ContentStatus' }
        submitted_by:   { $ref: '#/components/schemas/UUID' }
        country:        { type: string, nullable: true }
        ai_flag_result: { type: object, nullable: true, additionalProperties: true }
        created_at:     { type: string, format: date-time }

    Notification:
      type: object
      required: [id, user_id, event_type, is_read, created_at]
      properties:
        id:             { $ref: '#/components/schemas/UUID' }
        user_id:        { $ref: '#/components/schemas/UUID' }
        event_type:     { type: string }
        reference_type: { type: string, nullable: true }
        reference_id:   { $ref: '#/components/schemas/UUID', nullable: true }
        is_read:        { type: boolean, default: false }
        created_at:     { type: string, format: date-time }

    NotificationPreference:
      type: object
      properties:
        user_id:      { $ref: '#/components/schemas/UUID' }
        country_code: { type: string, nullable: true }
        category_id:  { $ref: '#/components/schemas/UUID', nullable: true }

    NotificationPreferenceUpdate:
      type: object
      required: [preferences]
      properties:
        preferences:
          type: array
          items:
            type: object
            properties:
              country_code: { type: string, nullable: true }
              category_id:  { $ref: '#/components/schemas/UUID', nullable: true }

    UnreadCountResponse:
      type: object
      required: [count]
      properties:
        count: { type: integer, minimum: 0 }

    SearchResultItem:
      type: object
      required: [type, id, title, score]
      properties:
        type:        { $ref: '#/components/schemas/SearchType' }
        id:          { $ref: '#/components/schemas/UUID' }
        title:       { type: string }
        excerpt:     { type: string, nullable: true }
        country:     { type: string, nullable: true }
        category_id: { $ref: '#/components/schemas/UUID', nullable: true }
        tags:        { type: array, items: { type: string } }
        score:       { type: number, format: float }
        law_status:  { $ref: '#/components/schemas/LawStatus' }
        created_at:  { type: string, format: date-time }

    SearchResponse:
      type: object
      required: [results, total, page, page_size, search_mode]
      properties:
        results:     { type: array, items: { $ref: '#/components/schemas/SearchResultItem' } }
        total:       { type: integer }
        page:        { type: integer }
        page_size:   { type: integer }
        query_lang:  { $ref: '#/components/schemas/Language' }
        search_mode: { $ref: '#/components/schemas/SearchMode' }
        latency_ms:  { type: integer }
        cache_hit:   { type: boolean }

    AskRequest:
      type: object
      required: [query]
      properties:
        query:    { type: string, minLength: 3, maxLength: 1000 }
        country:  { type: string, nullable: true }
        category: { $ref: '#/components/schemas/UUID', nullable: true }
        lang:     { $ref: '#/components/schemas/Language' }

    AskResponse:
      type: object
      required: [answer, citations, confidence, status, disclaimer]
      properties:
        answer:     { type: string }
        citations:
          type: array
          items:
            type: object
            properties:
              source_type: { type: string, enum: [document_chunk, question, news, post] }
              source_id:   { $ref: '#/components/schemas/UUID' }
              passage:     { type: string }
              score:       { type: number }
        confidence: { type: number, format: float, minimum: 0, maximum: 1 }
        status:     { type: string, enum: [generated, pending_expert_review] }
        disclaimer: { type: string }
        latency_ms: { type: integer }

    TranslateRequest:
      type: object
      required: [text, target_lang]
      properties:
        text:        { type: string, minLength: 1, maxLength: 5000 }
        source_lang: { $ref: '#/components/schemas/Language' }
        target_lang: { $ref: '#/components/schemas/Language' }

    TranslateResponse:
      type: object
      required: [translated_text]
      properties:
        translated_text: { type: string }
        detected_lang:   { $ref: '#/components/schemas/Language' }

    DashboardResponse:
      type: object
      properties:
        news_summary:           { type: array, items: { $ref: '#/components/schemas/NewsArticle' } }
        pending_questions:      { type: array, items: { $ref: '#/components/schemas/Question' } }
        my_documents:           { type: array, items: { $ref: '#/components/schemas/Document' } }
        unread_count:           { type: integer }
        moderation_queue_depth: { type: integer, nullable: true }

    PlatformConfig:
      type: object
      additionalProperties: true
      properties:
        ai_confidence_high:   { type: number }
        ai_confidence_low:    { type: number }
        invite_expiry_hours:  { type: integer }
        supported_languages:  { type: array, items: { type: string } }
        max_content_per_org:  { type: integer }
        moderation_sla_hours: { type: integer }

    AdminStatsResponse:
      type: object
      additionalProperties: true
      properties:
        users:      { type: object, additionalProperties: true }
        content:    { type: object, additionalProperties: true }
        moderation: { type: object, additionalProperties: true }
        ai:         { type: object, additionalProperties: true }

    HealthResponse:
      type: object
      required: [status]
      properties:
        status:         { type: string, enum: [ok, degraded, down] }
        db:             { type: string }
        redis_broker:   { type: string }
        redis_cache:    { type: string }
        opensearch:     { type: string }

    VersionEntry:
      type: object
      required: [version_number, edited_by, edited_at]
      properties:
        version_number: { type: integer }
        edited_by:      { $ref: '#/components/schemas/UUID' }
        edited_at:      { type: string, format: date-time }
        snapshot:       { type: object, additionalProperties: true }

paths:

  # ============================================================
  # AUTH
  # ============================================================
  /auth/verify-invite:
    post:
      tags: [Auth]
      summary: Validate invite code
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [code]
              properties:
                code: { type: string }
      responses:
        '200':
          description: Invite validity
          content:
            application/json:
              schema: { $ref: '#/components/schemas/VerifyInviteResponse' }
        '400': { $ref: '#/components/responses/ValidationError' }
        '429': { $ref: '#/components/responses/RateLimited' }

  /auth/signup:
    post:
      tags: [Auth]
      summary: Register with invite
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/SignupRequest' }
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema: { $ref: '#/components/schemas/LoginResponse' }
        '400': { $ref: '#/components/responses/ValidationError' }
        '409': { $ref: '#/components/responses/Conflict' }
        '429': { $ref: '#/components/responses/RateLimited' }

  /auth/login:
    post:
      tags: [Auth]
      summary: Email + password login
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/LoginRequest' }
      responses:
        '200':
          description: Token issued
          headers:
            Set-Cookie:
              schema: { type: string }
              description: refresh_token cookie (HttpOnly, Secure, SameSite=Strict)
          content:
            application/json:
              schema: { $ref: '#/components/schemas/LoginResponse' }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '429': { $ref: '#/components/responses/RateLimited' }

  /auth/logout:
    post:
      tags: [Auth]
      summary: Revoke current token (idempotent)
      responses:
        '200':
          description: Revoked
          content:
            application/json:
              schema:
                type: object
                properties:
                  ok: { type: boolean }

  /auth/forgot-password:
    post:
      tags: [Auth]
      summary: Email password reset link
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/ForgotPasswordRequest' }
      responses:
        '204': { $ref: '#/components/responses/NoContent' }
        '429': { $ref: '#/components/responses/RateLimited' }

  /auth/reset-password:
    post:
      tags: [Auth]
      summary: Consume reset token
      security: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/ResetPasswordRequest' }
      responses:
        '204': { $ref: '#/components/responses/NoContent' }
        '400': { $ref: '#/components/responses/ValidationError' }

  /auth/refresh-token:
    post:
      tags: [Auth]
      summary: Refresh access token
      security:
        - refreshCookie: []
      responses:
        '200':
          description: New access token
          content:
            application/json:
              schema: { $ref: '#/components/schemas/LoginResponse' }
        '401': { $ref: '#/components/responses/Unauthorized' }

  /auth/me:
    get:
      tags: [Auth]
      summary: Current user profile
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
    patch:
      tags: [Auth]
      summary: Update own profile
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UserUpdate' }
      responses:
        '200':
          description: Updated
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }

  /auth/me/preferences:
    post:
      tags: [Auth]
      summary: First-login preferences
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UserPreferencesRequest' }
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /auth/me/change-password:
    post:
      tags: [Auth]
      summary: Change own password
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/ChangePasswordRequest' }
      responses:
        '204': { $ref: '#/components/responses/NoContent' }
        '400': { $ref: '#/components/responses/ValidationError' }

  # ============================================================
  # USERS
  # ============================================================
  /users:
    get:
      tags: [Users]
      summary: List users (Admin/Moderator)
      parameters:
        - { name: role,    in: query, schema: { $ref: '#/components/schemas/UserRole' } }
        - { name: org_id,  in: query, schema: { $ref: '#/components/schemas/UUID' } }
        - { name: status,  in: query, schema: { $ref: '#/components/schemas/UserStatus' } }
        - { name: q,       in: query, schema: { type: string } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: Paged users
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items:
                        type: array
                        items: { $ref: '#/components/schemas/User' }

  /users/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Users]
      summary: Get user
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
        '404': { $ref: '#/components/responses/NotFound' }
    put:
      tags: [Users]
      summary: Update user (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UserUpdate' }
      responses:
        '200': { description: Updated, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }
    delete:
      tags: [Users]
      summary: Anonymise user (Admin, GDPR)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /users/{id}/status:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Users]
      summary: Change user status (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [status]
              properties:
                status: { $ref: '#/components/schemas/UserStatus' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }

  /users/{id}/role:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Users]
      summary: Change role (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [role]
              properties:
                role: { $ref: '#/components/schemas/UserRole' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/User' } } } }

  /users/{id}/contributions:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Users]
      summary: Aggregated contributions
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  documents: { type: array, items: { $ref: '#/components/schemas/Document' } }
                  questions: { type: array, items: { $ref: '#/components/schemas/Question' } }
                  answers:   { type: array, items: { $ref: '#/components/schemas/Answer' } }
                  news:      { type: array, items: { $ref: '#/components/schemas/NewsArticle' } }
                  posts:     { type: array, items: { $ref: '#/components/schemas/Post' } }

  /users/me/export:
    get:
      tags: [Users]
      summary: GDPR self-export (Phase 2)
      responses:
        '202':
          description: Job queued; presigned URL ready when complete
          content:
            application/json:
              schema:
                type: object
                properties:
                  download_url: { type: string, format: uri }
                  expires_at:   { type: string, format: date-time }

  # ============================================================
  # ORGANIZATIONS
  # ============================================================
  /organizations:
    get:
      tags: [Organizations]
      summary: List organizations
      parameters:
        - { name: q, in: query, schema: { type: string } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Organization' } }
    post:
      tags: [Organizations]
      summary: Create org (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [name]
              properties:
                name:      { type: string }
                max_users: { type: integer, default: 100 }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Organization' } } } }

  /organizations/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Organizations]
      summary: Get org
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Organization' } } } }
    put:
      tags: [Organizations]
      summary: Update org (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                name:      { type: string }
                max_users: { type: integer }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Organization' } } } }
    delete:
      tags: [Organizations]
      summary: Delete org (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /organizations/{id}/members:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { $ref: '#/components/parameters/Page' }
      - { $ref: '#/components/parameters/PageSize' }
    get:
      tags: [Organizations]
      summary: List members
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/User' } }

  # ============================================================
  # INVITES
  # ============================================================
  /invites:
    get:
      tags: [Invites]
      summary: List invites (Admin)
      parameters:
        - { name: org_id, in: query, schema: { $ref: '#/components/schemas/UUID' } }
        - { name: status, in: query, schema: { type: string, enum: [active, used, revoked, expired] } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Invite' } }
    post:
      tags: [Invites]
      summary: Generate invite (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [org_id]
              properties:
                org_id:           { $ref: '#/components/schemas/UUID' }
                expires_in_hours: { type: integer, default: 72 }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Invite' } } } }

  /invites/{code}:
    parameters:
      - { name: code, in: path, required: true, schema: { type: string } }
    get:
      tags: [Invites]
      summary: Get invite (Admin)
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Invite' } } } }
    delete:
      tags: [Invites]
      summary: Revoke invite (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  # ============================================================
  # DOCUMENTS
  # ============================================================
  /documents:
    get:
      tags: [Documents]
      summary: List approved documents
      parameters:
        - { name: country,    in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: category,   in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: tags,       in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: law_status, in: query, schema: { $ref: '#/components/schemas/LawStatus' } }
        - { name: date_from,  in: query, schema: { type: string, format: date-time } }
        - { name: date_to,    in: query, schema: { type: string, format: date-time } }
        - { $ref: '#/components/parameters/Lang' }
        - { name: q,          in: query, schema: { type: string, minLength: 2 } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Document' } }
    post:
      tags: [Documents]
      summary: Submit document metadata
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/DocumentCreateRequest' }
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema: { $ref: '#/components/schemas/DocumentCreateResponse' }

  /documents/my:
    get:
      tags: [Documents]
      summary: Caller's uploads
      parameters:
        - { name: status, in: query, schema: { $ref: '#/components/schemas/ContentStatus' } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Document' } }

  /documents/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { $ref: '#/components/parameters/Lang' }
    get:
      tags: [Documents]
      summary: Document detail
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Document' } } } }
        '404': { $ref: '#/components/responses/NotFound' }
    put:
      tags: [Documents]
      summary: Update metadata
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/DocumentUpdate' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Document' } } } }
    delete:
      tags: [Documents]
      summary: Delete (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /documents/{id}/confirm:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    post:
      tags: [Documents]
      summary: Confirm upload completed
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Document' } } } }

  /documents/{id}/download:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Documents]
      summary: Pre-signed download URL
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/DownloadUrlResponse' }

  /documents/{id}/status:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Documents]
      summary: Status & history
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:             { $ref: '#/components/schemas/ContentStatus' }
                  law_status:         { $ref: '#/components/schemas/LawStatus' }
                  moderation_history: { type: array, items: { $ref: '#/components/schemas/ModerationLog' } }

  /documents/{id}/related:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Documents]
      summary: (Phase 2) k-NN related
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/SearchResultItem' }

  /documents/{id}/versions:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Documents]
      summary: List versions
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/VersionEntry' }

  /documents/{id}/versions/{vid}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { name: vid, in: path, required: true, schema: { type: integer } }
    get:
      tags: [Documents]
      summary: Version detail
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/VersionEntry' }

  # ============================================================
  # QUESTIONS & ANSWERS
  # ============================================================
  /questions:
    get:
      tags: [Questions]
      summary: List approved questions
      parameters:
        - { name: country,  in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: category, in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: tags,     in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: status,   in: query, schema: { $ref: '#/components/schemas/ContentStatus' } }
        - { $ref: '#/components/parameters/Lang' }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Question' } }
    post:
      tags: [Questions]
      summary: Submit question
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/QuestionCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Question' } } } }

  /questions/my:
    get:
      tags: [Questions]
      summary: Caller's questions
      parameters:
        - { name: status, in: query, schema: { $ref: '#/components/schemas/ContentStatus' } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Question' } }

  /questions/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { $ref: '#/components/parameters/Lang' }
    get:
      tags: [Questions]
      summary: Question detail
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Question' } } } }
    put:
      tags: [Questions]
      summary: Edit (pre-moderation)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/QuestionUpdate' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Question' } } } }
    delete:
      tags: [Questions]
      summary: Delete (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /questions/{id}/assign:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Questions]
      summary: Assign to expert
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [user_id]
              properties:
                user_id: { $ref: '#/components/schemas/UUID' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Question' } } } }

  /questions/{id}/status:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Questions]
      summary: Status
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:       { $ref: '#/components/schemas/ContentStatus' }
                  assigned_to:  { $ref: '#/components/schemas/UUID', nullable: true }
                  answer_count: { type: integer }

  /questions/{id}/promote:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    post:
      tags: [Questions]
      summary: (Phase 2) Promote to knowledge article
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:           { $ref: '#/components/schemas/UUID' }
                  question_id:  { $ref: '#/components/schemas/UUID' }
                  promoted_by:  { $ref: '#/components/schemas/UUID' }
                  promoted_at:  { type: string, format: date-time }

  /questions/{id}/versions:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Questions]
      summary: List versions
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/VersionEntry' }

  /questions/{id}/versions/{vid}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { name: vid, in: path, required: true, schema: { type: integer } }
    get:
      tags: [Questions]
      summary: Version detail
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/VersionEntry' }

  /questions/{id}/related:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Questions]
      summary: (Phase 2) Related
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/SearchResultItem' }

  /questions/{question_id}/answers:
    parameters:
      - { name: question_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Answers]
      summary: List answers
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Answer' }
    post:
      tags: [Answers]
      summary: Post answer
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AnswerCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Answer' } } } }

  /answers/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    put:
      tags: [Answers]
      summary: Edit answer
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AnswerCreateRequest' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Answer' } } } }
    delete:
      tags: [Answers]
      summary: Delete (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /answers/{id}/accept:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Answers]
      summary: Mark accepted (idempotent; question author)
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Answer' } } } }

  /answers/{id}/verify:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Answers]
      summary: Lawyer-verify (Admin/Moderator)
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Answer' } } } }

  /questions/{question_id}/comments:
    parameters:
      - { name: question_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Questions]
      summary: (Phase 2) List Q&A thread comments
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/QuestionComment' }
    post:
      tags: [Questions]
      summary: (Phase 2) Add comment
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CommentCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/QuestionComment' } } } }

  /questions/{question_id}/comments/{comment_id}:
    parameters:
      - { name: question_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { name: comment_id,  in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    delete:
      tags: [Questions]
      summary: (Phase 2) Delete comment
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  # ============================================================
  # NEWS
  # ============================================================
  /news:
    get:
      tags: [News]
      summary: List approved news
      parameters:
        - { name: country,  in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: category, in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: featured, in: query, schema: { type: boolean } }
        - { $ref: '#/components/parameters/Lang' }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/NewsArticle' } }
    post:
      tags: [News]
      summary: Submit news
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/NewsCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/NewsArticle' } } } }

  /news/my:
    get:
      tags: [News]
      summary: Caller's submissions
      parameters:
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/NewsArticle' } }

  /news/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { $ref: '#/components/parameters/Lang' }
    get:
      tags: [News]
      summary: News detail
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/NewsArticle' } } } }
    put:
      tags: [News]
      summary: Update (Mod/Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/NewsUpdate' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/NewsArticle' } } } }
    delete:
      tags: [News]
      summary: Delete (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /news/{id}/status:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [News]
      summary: Status
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status: { $ref: '#/components/schemas/ContentStatus' }

  /news/{id}/feature:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [News]
      summary: (Phase 2) Pin/feature (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/NewsFeatureRequest' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/NewsArticle' } } } }

  /news/{id}/versions:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [News]
      summary: List versions
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/VersionEntry' }

  /news/{id}/versions/{vid}:
    parameters:
      - { name: id,  in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { name: vid, in: path, required: true, schema: { type: integer } }
    get:
      tags: [News]
      summary: Version detail
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/VersionEntry' }

  /news/{id}/related:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [News]
      summary: (Phase 2) Related
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/SearchResultItem' }

  # ============================================================
  # POSTS
  # ============================================================
  /posts:
    get:
      tags: [Posts]
      summary: Cursor-paginated social feed
      parameters:
        - { $ref: '#/components/parameters/Cursor' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/CursorPage' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Post' } }
    post:
      tags: [Posts]
      summary: Create post
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/PostCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Post' } } } }

  /posts/my:
    get:
      tags: [Posts]
      summary: Caller's posts
      parameters:
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Post' } }

  /posts/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Posts]
      summary: Post detail
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Post' } } } }
    put:
      tags: [Posts]
      summary: Edit post
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [body]
              properties:
                body: { type: string, maxLength: 5000 }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Post' } } } }
    delete:
      tags: [Posts]
      summary: Delete (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /posts/{id}/like:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    post:
      tags: [Posts]
      summary: Toggle like (idempotent)
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/LikeToggleResponse' }

  /posts/{id}/comments:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Posts]
      summary: List comments
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Comment' }
    post:
      tags: [Posts]
      summary: Add comment
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CommentCreateRequest' }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Comment' } } } }

  /posts/{id}/comments/{cid}:
    parameters:
      - { name: id,  in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
      - { name: cid, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    delete:
      tags: [Posts]
      summary: Delete comment (Mod/Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /posts/{id}/status:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Posts]
      summary: Status
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status: { $ref: '#/components/schemas/ContentStatus' }

  /posts/{id}/related:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Posts]
      summary: (Phase 2) Related
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/SearchResultItem' }

  # ============================================================
  # MODERATION
  # ============================================================
  /moderation/queue:
    get:
      tags: [Moderation]
      summary: Unified moderation queue (cursor)
      parameters:
        - { $ref: '#/components/parameters/Cursor' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/CursorPage' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/QueueItem' } }

  /moderation/queue/questions:
    get:
      tags: [Moderation]
      summary: Pending questions
      parameters:
        - { $ref: '#/components/parameters/Cursor' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200': { description: OK, content: { application/json: { schema: { allOf: [ { $ref: '#/components/schemas/CursorPage' } ] } } } }

  /moderation/queue/documents:
    get:
      tags: [Moderation]
      summary: Pending documents
      parameters: [ { $ref: '#/components/parameters/Cursor' }, { $ref: '#/components/parameters/PageSize' } ]
      responses:
        '200': { description: OK, content: { application/json: { schema: { allOf: [ { $ref: '#/components/schemas/CursorPage' } ] } } } }

  /moderation/queue/news:
    get:
      tags: [Moderation]
      summary: Pending news
      parameters: [ { $ref: '#/components/parameters/Cursor' }, { $ref: '#/components/parameters/PageSize' } ]
      responses:
        '200': { description: OK, content: { application/json: { schema: { allOf: [ { $ref: '#/components/schemas/CursorPage' } ] } } } }

  /moderation/queue/posts:
    get:
      tags: [Moderation]
      summary: Pending posts
      parameters: [ { $ref: '#/components/parameters/Cursor' }, { $ref: '#/components/parameters/PageSize' } ]
      responses:
        '200': { description: OK, content: { application/json: { schema: { allOf: [ { $ref: '#/components/schemas/CursorPage' } ] } } } }

  /moderation/queue/flagged:
    get:
      tags: [Moderation]
      summary: Flagged items (Admin)
      parameters: [ { $ref: '#/components/parameters/Cursor' }, { $ref: '#/components/parameters/PageSize' } ]
      responses:
        '200': { description: OK, content: { application/json: { schema: { allOf: [ { $ref: '#/components/schemas/CursorPage' } ] } } } }

  /moderation/approve:
    post:
      tags: [Moderation]
      summary: Approve (idempotent)
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/ModerationActionRequest' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  ok:      { type: boolean }
                  entity:  { type: object, additionalProperties: true }

  /moderation/reject:
    post:
      tags: [Moderation]
      summary: Reject (remarks required, idempotent)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              allOf:
                - { $ref: '#/components/schemas/ModerationActionRequest' }
                - type: object
                  required: [remarks]
      responses:
        '200': { description: OK }

  /moderation/request-changes:
    post:
      tags: [Moderation]
      summary: Request revisions (idempotent)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              allOf:
                - { $ref: '#/components/schemas/ModerationActionRequest' }
                - type: object
                  required: [remarks]
      responses:
        '200': { description: OK }

  /moderation/flag:
    post:
      tags: [Moderation]
      summary: Hold for senior review (idempotent)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              allOf:
                - { $ref: '#/components/schemas/ModerationActionRequest' }
                - type: object
                  required: [remarks]
      responses:
        '200': { description: OK }

  /moderation/retract:
    post:
      tags: [Moderation]
      summary: Retract approved item (idempotent)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              allOf:
                - { $ref: '#/components/schemas/ModerationActionRequest' }
                - type: object
                  required: [remarks]
      responses:
        '200': { description: OK }

  /moderation/logs:
    get:
      tags: [Moderation]
      summary: Full audit log (Admin)
      parameters:
        - { name: actor_id,    in: query, schema: { $ref: '#/components/schemas/UUID' } }
        - { name: entity_type, in: query, schema: { $ref: '#/components/schemas/EntityType' } }
        - { name: action,      in: query, schema: { $ref: '#/components/schemas/ModerationAction' } }
        - { name: date_from,   in: query, schema: { type: string, format: date-time } }
        - { name: date_to,     in: query, schema: { type: string, format: date-time } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/ModerationLog' } }

  /moderation/logs/{entity_type}/{id}:
    parameters:
      - { name: entity_type, in: path, required: true, schema: { $ref: '#/components/schemas/EntityType' } }
      - { name: id,          in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [Moderation]
      summary: Logs for one entity
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/ModerationLog' }

  /moderation/stats:
    get:
      tags: [Moderation]
      summary: Queue counts & throughput
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  by_type:    { type: object, additionalProperties: { type: integer } }
                  throughput: { type: object, additionalProperties: true }

  # ============================================================
  # NOTIFICATIONS
  # ============================================================
  /notifications:
    get:
      tags: [Notifications]
      summary: List notifications
      parameters:
        - { name: is_read, in: query, schema: { type: boolean } }
        - { $ref: '#/components/parameters/Page' }
        - { $ref: '#/components/parameters/PageSize' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                allOf:
                  - { $ref: '#/components/schemas/PageMeta' }
                  - type: object
                    properties:
                      items: { type: array, items: { $ref: '#/components/schemas/Notification' } }

  /notifications/unread-count:
    get:
      tags: [Notifications]
      summary: Unread count (Redis-backed)
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/UnreadCountResponse' }

  /notifications/stream:
    get:
      tags: [Notifications]
      summary: (Phase 3) Server-Sent Events stream
      responses:
        '200':
          description: SSE stream (text/event-stream)
          content:
            text/event-stream:
              schema: { type: string }

  /notifications/{id}/read:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    patch:
      tags: [Notifications]
      summary: Mark single read
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Notification' } } } }

  /notifications/read-all:
    patch:
      tags: [Notifications]
      summary: Mark all read
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  updated_count: { type: integer }

  /notifications/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    delete:
      tags: [Notifications]
      summary: Delete notification
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /notifications/preferences:
    get:
      tags: [Notifications]
      summary: Get preferences
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/NotificationPreference' }
    put:
      tags: [Notifications]
      summary: Update preferences
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/NotificationPreferenceUpdate' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/NotificationPreference' }

  # ============================================================
  # SEARCH & AI
  # ============================================================
  /search:
    get:
      tags: [Search]
      summary: Hybrid BM25 + k-NN search
      parameters:
        - { name: q,         in: query, required: true, schema: { type: string, minLength: 2 } }
        - { name: type,      in: query, schema: { $ref: '#/components/schemas/SearchType' } }
        - { name: country,   in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: category,  in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { name: tags,      in: query, schema: { type: array, items: { type: string } }, style: form, explode: true }
        - { $ref: '#/components/parameters/Lang' }
        - { name: date_from, in: query, schema: { type: string, format: date-time } }
        - { name: date_to,   in: query, schema: { type: string, format: date-time } }
        - { name: status,    in: query, schema: { $ref: '#/components/schemas/LawStatus' } }
        - { name: search_mode, in: query, schema: { $ref: '#/components/schemas/SearchMode' } }
        - { name: page,      in: query, schema: { type: integer, default: 1, minimum: 1 } }
        - { name: page_size, in: query, schema: { type: integer, default: 10, minimum: 1, maximum: 20 } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/SearchResponse' }
        '503':
          description: Search backend unavailable
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Error' }

  /ai/ask:
    post:
      tags: [AI]
      summary: (Phase 2) RAG Q&A with citations
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AskRequest' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AskResponse' }
        '429': { $ref: '#/components/responses/RateLimited' }

  /ai/suggestions/{question_id}:
    parameters:
      - { name: question_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    get:
      tags: [AI]
      summary: (Phase 2) AI suggestions for moderator
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  suggestions:
                    type: array
                    items:
                      type: object
                      properties:
                        source_type: { type: string }
                        source_id:   { $ref: '#/components/schemas/UUID' }
                        passage:     { type: string }
                        score:       { type: number }

  /ai/summarize/{document_id}:
    parameters:
      - { name: document_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    post:
      tags: [AI]
      summary: (Phase 2) Summarize a document
      requestBody:
        required: false
        content:
          application/json:
            schema:
              type: object
              properties:
                lang: { $ref: '#/components/schemas/Language' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  summary:      { type: string }
                  length_words: { type: integer }

  /ai/summarize/question/{question_id}:
    parameters:
      - { name: question_id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    post:
      tags: [AI]
      summary: (Phase 2) Summarize a Q&A thread
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  summary: { type: string }

  /ai/translate:
    post:
      tags: [AI]
      summary: (Phase 2) Translate text
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/TranslateRequest' }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/TranslateResponse' }

  /ai/translate/languages:
    get:
      tags: [AI]
      summary: Supported languages
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  languages:
                    type: array
                    items:
                      type: object
                      properties:
                        code: { type: string }
                        name: { type: string }

  # ============================================================
  # DASHBOARD
  # ============================================================
  /dashboard:
    get:
      tags: [Dashboard]
      summary: Aggregated home dashboard
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/DashboardResponse' }

  # ============================================================
  # TAXONOMY
  # ============================================================
  /countries:
    get:
      tags: [Taxonomy]
      summary: List countries
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Country' }

  /categories:
    get:
      tags: [Taxonomy]
      summary: List categories
      parameters:
        - { name: content_type, in: query, schema: { type: string, enum: [document, question, news] } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Category' }
    post:
      tags: [Taxonomy]
      summary: Create category (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [name]
              properties:
                name:         { type: string }
                parent_id:    { $ref: '#/components/schemas/UUID' }
                content_type: { type: string, enum: [document, question, news] }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Category' } } } }

  /categories/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    put:
      tags: [Taxonomy]
      summary: Update category (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                name:         { type: string }
                parent_id:    { $ref: '#/components/schemas/UUID' }
                content_type: { type: string, enum: [document, question, news] }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Category' } } } }
    delete:
      tags: [Taxonomy]
      summary: Delete category (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  /tags:
    get:
      tags: [Taxonomy]
      summary: List tags
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Tag' }
    post:
      tags: [Taxonomy]
      summary: Create tag (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [name]
              properties:
                name: { type: string }
      responses:
        '201': { description: Created, content: { application/json: { schema: { $ref: '#/components/schemas/Tag' } } } }

  /tags/{id}:
    parameters:
      - { name: id, in: path, required: true, schema: { $ref: '#/components/schemas/UUID' } }
    put:
      tags: [Taxonomy]
      summary: Update tag (Admin)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [name]
              properties:
                name: { type: string }
      responses:
        '200': { description: OK, content: { application/json: { schema: { $ref: '#/components/schemas/Tag' } } } }
    delete:
      tags: [Taxonomy]
      summary: Delete tag (Admin)
      responses:
        '204': { $ref: '#/components/responses/NoContent' }

  # ============================================================
  # ADMIN
  # ============================================================
  /admin/stats:
    get:
      tags: [Admin]
      summary: Platform statistics
      parameters:
        - { name: country,   in: query, schema: { type: string } }
        - { name: date_from, in: query, schema: { type: string, format: date-time } }
        - { name: date_to,   in: query, schema: { type: string, format: date-time } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AdminStatsResponse' }

  /admin/ai-usage:
    get:
      tags: [Admin]
      summary: (Phase 2) AI usage & cost
      parameters:
        - { name: date_from, in: query, schema: { type: string, format: date-time } }
        - { name: date_to,   in: query, schema: { type: string, format: date-time } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  tokens:              { type: integer }
                  embedding_calls:     { type: integer }
                  rag_queries:         { type: integer }
                  translations:        { type: integer }
                  estimated_cost_usd:  { type: number }
                  by_model:            { type: object, additionalProperties: true }

  /admin/config:
    get:
      tags: [Admin]
      summary: Read platform configuration
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PlatformConfig' }
    put:
      tags: [Admin]
      summary: Update platform configuration
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/PlatformConfig' }
      responses:
        '200':
          description: Updated
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PlatformConfig' }

  # ============================================================
  # SYSTEM / OPS
  # ============================================================
  /health/live:
    get:
      tags: [System]
      security: []
      summary: Liveness probe
      responses:
        '200':
          description: Alive
          content:
            application/json:
              schema:
                type: object
                properties:
                  status: { type: string, enum: [ok] }

  /health/ready:
    get:
      tags: [System]
      security: []
      summary: Readiness probe (checks dependencies)
      responses:
        '200':
          description: Ready
          content:
            application/json:
              schema: { $ref: '#/components/schemas/HealthResponse' }
        '503':
          description: Not ready
          content:
            application/json:
              schema: { $ref: '#/components/schemas/HealthResponse' }

  /health:
    get:
      tags: [System]
      security: []
      summary: Alias for /health/ready
      responses:
        '200':
          description: Ready
          content:
            application/json:
              schema: { $ref: '#/components/schemas/HealthResponse' }
        '503':
          description: Not ready
          content:
            application/json:
              schema: { $ref: '#/components/schemas/HealthResponse' }

  /metrics:
    get:
      tags: [System]
      security: []
      summary: Prometheus metrics (internal-only)
      responses:
        '200':
          description: Prometheus text format
          content:
            text/plain:
              schema: { type: string }

  # ============================================================
  # WEBHOOKS (Phase 3)
  # ============================================================
  /webhooks/livekit:
    post:
      tags: [Webhooks]
      summary: (Phase 3) LiveKit room/participant events
      security: []
      requestBody:
        required: true
        description: |
          `Assumption:` payload mirrors LiveKit webhook envelope. Verified via
          shared-secret HMAC on `Authorization: Bearer <signed_jwt>`.
        content:
          application/json:
            schema:
              type: object
              additionalProperties: true
      responses:
        '204': { $ref: '#/components/responses/NoContent' }
```

---

## 12. Examples

### 12.1 Success — `POST /auth/login`

**Request**

```http
POST /api/v1/auth/login
Content-Type: application/json

{ "email": "user@example.com", "password": "S3cure-Passw0rd!" }
```

**Response** `200 OK`

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "bearer",
  "expires_in": 1800
}
```

Headers: `Set-Cookie: refresh_token=...; HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth/refresh-token; Max-Age=604800`, `X-Request-ID: 6e6a...`, `X-Notification-Unread-Count: 3`.

### 12.2 Validation error — `POST /questions`

**Response** `400 Bad Request`

```json
{
  "detail": "Validation failed",
  "error_code": "VALIDATION_ERROR",
  "field_errors": [
    { "field": "title",  "message": "must be at least 5 characters" },
    { "field": "country","message": "must be a valid ISO 3166-1 alpha-2 code" }
  ]
}
```

### 12.3 Rate-limited — `POST /ai/ask`

**Response** `429 Too Many Requests`

Headers: `Retry-After: 30`

```json
{
  "detail": "Rate limit exceeded. Try again in 30 seconds.",
  "error_code": "RATE_LIMITED"
}
```

### 12.4 Search — `GET /search?q=arbitration&type=documents&country=KE`

**Response** `200 OK`

```json
{
  "results": [
    {
      "type": "documents",
      "id": "0a8d…",
      "title": "Arbitration Act 1995 — Kenya",
      "excerpt": "An act to make new provision for arbitration…",
      "country": "KE",
      "category_id": "1f3…",
      "tags": ["arbitration", "civil-procedure"],
      "score": 0.87,
      "law_status": "active",
      "created_at": "2026-04-10T08:12:00Z"
    }
  ],
  "total": 12,
  "page": 1,
  "page_size": 10,
  "query_lang": "en",
  "search_mode": "hybrid",
  "latency_ms": 138,
  "cache_hit": false
}
```

### 12.5 RAG ask — `POST /ai/ask`

**Response** `200 OK`

```json
{
  "answer": "Under section 12 of the Kenyan Arbitration Act…",
  "citations": [
    { "source_type": "document_chunk", "source_id": "d1c…", "passage": "Section 12. The High Court…", "score": 0.92 }
  ],
  "confidence": 0.81,
  "status": "generated",
  "disclaimer": "AI-generated content. Not legal advice. Verify with a qualified lawyer.",
  "latency_ms": 1840
}
```

---

## 13. Frontend Integration Notes

- Always send `X-Request-ID` (UUID) for traceability — server echoes it on every response and propagates into logs / outbox / Celery jobs.
- Read the `X-Notification-Unread-Count` header on every authenticated response and use it to update the badge — avoids polling `/notifications/unread-count` for MVP.
- Use cursor pagination (`next_cursor`) for `/posts` and `/moderation/queue*`. All other lists are offset-paginated.
- File upload always goes through the two-step direct-to-S3 flow (`POST /documents` → `PUT` to S3 → `POST /documents/{id}/confirm`). Never `POST` raw bytes to the API.
- After login, refresh tokens are managed by the browser via the `refresh_token` HttpOnly cookie. Frontend never touches the refresh token directly.
- Set `Accept-Language` header from the next-intl locale; pass explicit `?lang=` only when displaying a single piece of content in a different language than the user's locale.
- On `401 TOKEN_EXPIRED`, attempt `POST /auth/refresh-token` once; on failure redirect to login.
- On `503 SEARCH_UNAVAILABLE` or `AI_UNAVAILABLE`, surface a friendly fallback ("search is temporarily unavailable") — do not retry tight-loop.

---

## 14. Assumptions

The following details are not explicitly stated in the source documents and are inferred:

1. **Production hostnames** for Dev/QA/UAT/Prod are placeholders.
2. **Password complexity policy** (≥ 12 chars, mixed case + digit) — derived from "bcrypt work factor ≥ 12" without an explicit complexity policy.
3. **Body upper bounds** for `question.body`, `answer.body`, `news.body` set to 50 000 chars; `post.body`/`comment.body` to 5 000.
4. **Edit-own-content window** restricted to `pending|revision_required` statuses.
5. **`Idempotency-Key` header** is not used; idempotency is state-based.
6. **LiveKit webhook URL** = `/webhooks/livekit`; SAD names the job but not the path.
7. **`Deprecation`/`Sunset` headers** as the deprecation mechanism — not explicitly specified.
8. Invite status filter values (`active|used|revoked|expired`) on `GET /invites` are derived from the Invite entity fields.
9. The `accept-answer` endpoint enforces "question author only"; the SAD says it is idempotent and accepting must mark previous accepted answer false — author restriction is the natural authorization rule.

All other items trace directly to `Docs/Solution-Architecture-Document.md` or `Docs/implementation-plan.md`.
