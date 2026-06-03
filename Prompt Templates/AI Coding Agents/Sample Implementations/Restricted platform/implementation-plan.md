# ICA Restricted Social Platform — Implementation Plan

## Overview

A restricted, invite-only knowledge collaboration platform for ICA (International Cooperative Alliance) members focused on cooperative law and policy. This plan covers the full MVP build across frontend (Next.js), backend (FastAPI), and infrastructure.

---

## Tech Stack Summary

| Layer                       | Technology                                  |
|-----------------------------|---------------------------------------------|
| Frontend Framework          | Next.js 16 (App Router), TypeScript         |
| UI Component Library        | MUI (Material UI) v5, Tailwind CSS          |
| Frontend State — Server     | React Query (TanStack Query v5)             |
| Frontend State — Client     | Zustand (auth token, role switcher)         |
| Frontend Mocking            | MSW (Mock Service Worker); activated via `NEXT_PUBLIC_DEMO_MODE=true` |
| Backend Framework           | FastAPI (Python 3.12+), SQLAlchemy 2.0 (async), Alembic |
| Data Validation             | Pydantic v2 + `pydantic-settings` (`.env`-based config) |
| Database                    | PostgreSQL 15+ (RDS Multi-AZ in prod); `pg_stat_statements` enabled |
| Connection Pooler           | **PgBouncer** (transaction mode, `pool_size=50`) — deployed in all environments; SQLAlchemy uses `pool_size=5, max_overflow=0`; Celery workers use `NullPool` |
| Cache — Broker              | **`redis-broker`** — Celery broker (db=0); AWS ElastiCache Multi-AZ with automatic failover (RTO <60s) |
| Cache — Application         | **`redis-cache`** — search cache (db=0) + translation cache (db=1) + entity cache + rate limiter + unread counters; `allkeys-lru` eviction; self-healing single instance |
| Object Storage              | MinIO (dev) → AWS S3 (prod); abstracted via `StorageService` + `STORAGE_PROVIDER` env var; **direct-to-S3 signed PUT URL** uploads (API never receives file bytes); S3 lifecycle rules for retracted/rejected/orphaned files |
| Search                      | OpenSearch 2.x — hybrid BM25 + k-NN; **Bulk API mandated** (`helpers.bulk()`); ISM policy with rollover aliases; snapshot-based DR (RTO ≤1h) |
| Embedding — Dev             | `sentence-transformers/all-MiniLM-L6-v2` (384 dims, CPU) |
| Embedding — Prod            | OpenAI `text-embedding-3-small`; switched via `EMBEDDING_PROVIDER` env var; **`EMBEDDING_FALLBACK_PROVIDER=local`** for circuit-breaker fallback |
| LLM (RAG)                   | OpenAI GPT-4o-mini (Phase 2 only); configured via `OPENAI_LLM_MODEL` env var; low-confidence path falls back to expert review |
| RAG Orchestration           | LangGraph (Phase 2) — multi-node workflow inside `ai_answer_job` Celery worker |
| Document Parsing            | Docling (`python-docling`) — PDF extraction, OCR, table structure; 120s timeout; isolated on `ingestion` queue |
| Language Detection          | `langdetect` — detects non-English queries before translation pipeline (<5ms) |
| Async Workers               | Celery 5; **4 queues**: `default` · `ingestion` (Docling) · `embeddings` · `ai`; beat scheduler via `redbeat`; `task_acks_late=True`, `task_ignore_result=True`, per-queue `worker_prefetch_multiplier` |
| Email                       | SMTP / SendGrid (primary) + SES (`EMAIL_FALLBACK_PROVIDER`) for circuit-breaker fallback |
| Translation                 | Configurable via `TRANSLATION_PROVIDER`; cached 7 days in `redis-cache` db=1; circuit breaker caches `_UNAVAILABLE` for 1h on outage |
| Rate Limiting               | `slowapi` (FastAPI-compatible) backed by `redis-cache` — shared counter across all replicas |
| Edge / WAF                  | CloudFront in front of ALB with API cache behaviours (reference data 1h, featured news 5min); **AWS WAF** with OWASP Managed Rules + Known Bad Inputs; 5MB request body cap |
| Container Runtime           | Docker + Docker Compose (dev); AWS ECS / EKS (prod); KEDA autoscaling on Redis queue depth |
| Live Sessions (Phase 3)     | LiveKit — WebRTC audio/video expert Q&A rooms |

---

## Phase Plan

| Phase | Scope                                         | Priority |
|-------|-----------------------------------------------|----------|
| 1     | Core MVP: Auth, Q&A, Repository, News, Moderation, Admin | Must-Have |
| 2     | AI Layer: RAG pipeline, semantic search, AI-assisted answers; Multi-language support (EN/ES/FR); AI cost & usage dashboard; AI answer suggestions; document & Q&A summarisation; related content (k-NN per item); promote Q&A to knowledge article; news curation & pinning | High |
| 3     | Scale: Advanced analytics & recommendations, knowledge graph (entity extraction, law-to-law relationship mapping, topic graph), LiveKit live sessions, native mobile app, external legal API integrations | Future |

### Component Inclusion Matrix

| Component | Phase 1 (MVP) | Phase 2 | Phase 3 |
|---|:---:|:---:|:---:|
| Next.js Web UI (App Router, MUI, Tailwind) | ✓ | | |
| Installable PWA — web app manifest, service worker (app shell + offline page), responsive layouts ≥360px (see T15.2, T15.9–T15.11) | ✓ | | |
| FastAPI Backend API | ✓ | | |
| PostgreSQL (all tables) | ✓ | | |
| `redis-broker` (Celery broker, Multi-AZ HA) | ✓ | | |
| `redis-cache` (search cache + entity cache + rate limiter + unread counters) | ✓ | | |
| PgBouncer (transaction-mode connection pooler) | ✓ | | |
| CloudFront + AWS WAF in front of ALB | ✓ | | |
| OpenSearch BM25 keyword search | ✓ | | |
| OpenSearch k-NN semantic search | ✓ | | |
| MinIO → S3 file storage | ✓ | | |
| JWT Auth + invite-only onboarding | ✓ | | |
| User / Org / Role management | ✓ | | |
| Legal document repository + moderation | ✓ | | |
| Docling ingestion pipeline + chunking + embedding | ✓ | | |
| Q&A forum + expert assignment | ✓ | | |
| News publishing + broadcast notifications | ✓ | | |
| Social feed + likes + comments | ✓ | | |
| Unified moderation queue (all 5 actions) | ✓ | | |
| Audit trail + content versioning | ✓ | | |
| Admin dashboard (users, content, moderation stats) | ✓ | | |
| Taxonomy management (categories, tags, countries) | ✓ | | |
| Member self-service (profile, history, status) | ✓ | | |
| `redis-cache` db=1 translation cache (TTL 7d, `allkeys-lru`) | | ✓ | |
| Multi-language query translation (EN / ES / FR) | | ✓ | |
| AI RAG assistant (`/ai/ask`, LangGraph) | | ✓ | |
| AI content pre-screening (`ai_content_flag_job`) | | ✓ | |
| AI document / Q&A summarisation | | ✓ | |
| AI answer suggestions for moderators | | ✓ | |
| Related content (k-NN per item) | | ✓ | |
| Q&A promote to knowledge article | | ✓ | |
| Q&A discussion threads (question comments) | | ✓ | |
| News curation / pinning | | ✓ | |
| AI usage / cost dashboard | | ✓ | |
| LiveKit live expert sessions | | | ✓ |
| Knowledge graph (Neo4j / Neptune) | | | ✓ |
| Native mobile app | | | ✓ |
| External legal API integrations | | | ✓ |

---

## Architecture

```
React (Next.js PWA)
        ↓
CloudFront + AWS WAF (OWASP Managed Rules, 5MB body cap, geo + IP rules)
        ↓
ALB → FastAPI Gateway (slowapi rate limiter on redis-cache)
        ↓
PgBouncer (transaction mode, pool_size=50)
        ↓
Modular Service Layer
   ├── SearchService   → redis-cache (search + entity cache) → OpenSearch (hybrid BM25 + k-NN, timeout=800ms)
   ├── AIService       → redis-cache db=1 (translation cache, TTL 7d) → LangGraph RAG → LLM (with fallback)
   └── ContentService  → PostgreSQL (primary writes) + S3 (direct-upload signed PUT) + outbox_events
                         └─ DashboardService → PostgreSQL read replica (lag SLA 10s, falls back to primary)
```

Background pipeline:
```
Upload (approved)
  → document_ingestion_job  (ingestion queue): Docling OCR → extract text
  → chunking_job             (ingestion queue): split into 512-token chunks (64-token overlap)
  → embedding_generation_job (embeddings queue): batch embed chunks via OpenSearch Bulk API
  → Celery chain():
       search_index_job → opensearch_refresh_job → search_cache_invalidate_job
       (ensures cache cleared only AFTER OpenSearch confirms index visibility)

Outbox dispatch (every 5s, prioritised)
  → SELECT ... ORDER BY priority ASC, created_at ASC LIMIT 10 FOR UPDATE SKIP LOCKED
  → Mark IN_PROGRESS → Celery apply_async(task_id=outbox.id)  (idempotent)
  → outbox_stuck_recovery_job (every 10 min) resets IN_PROGRESS > 10 min back to PENDING

Non-English Search Query
  → langdetect → redis-cache db=1 (TTL 7d)
      MISS → query_translation_cache_job → cache → OpenSearch hybrid search
      HIT  → OpenSearch hybrid search (≤ 1 500ms total)
```

---

## Project Structure

```
/
├── frontend/                     # Next.js 16 application (App Router) — active
│   ├── app/
│   │   ├── (auth)/               # Login, signup, forgot/reset password
│   │   ├── (app)/                # All authenticated pages
│   │   │   ├── dashboard/
│   │   │   ├── repository/[id|upload|my]
│   │   │   ├── questions/[id|ask|my]
│   │   │   ├── news/[id|create|my]
│   │   │   ├── feed/
│   │   │   ├── post/[create|my]
│   │   │   ├── search/
│   │   │   ├── notifications/
│   │   │   ├── profile/[id|edit]
│   │   │   ├── auth/setup
│   │   │   ├── moderation/[questions|documents|news|posts]
│   │   │   └── admin/[users|orgs|invites|taxonomy|analytics]
│   │   ├── globals.css
│   │   ├── layout.tsx            # Root layout — wraps <Providers>
│   │   └── page.tsx              # Redirects to /dashboard
│   ├── components/
│   │   ├── Providers.tsx         # MUI ThemeProvider + QueryClientProvider
│   │   ├── layout/               # AppLayout, Sidebar, Header, RoleSwitcher
│   │   ├── shared/               # Reusable: StatusBadge, FilterBar, Pagination, etc.
│   │   ├── auth/
│   │   ├── dashboard/
│   │   ├── repository/
│   │   ├── questions/
│   │   ├── news/
│   │   ├── feed/
│   │   ├── moderation/
│   │   ├── admin/
│   │   ├── search/
│   │   ├── notifications/
│   │   └── profile/
│   ├── hooks/                    # React Query hooks per module
│   ├── lib/
│   │   ├── api/                  # Typed fetch client + per-module API functions
│   │   ├── theme.ts              # MUI theme (ICA brand colours)
│   │   └── utils/
│   ├── mocks/
│   │   ├── handlers/             # MSW request handlers per module
│   │   └── data/                 # Demo fixture data (users, docs, questions, etc.)
│   ├── store/                    # Zustand: auth state, role switcher
│   ├── types/                    # Shared TypeScript entity types
│   ├── public/
│   │   ├── sample-docs/          # Sample PDFs for demo
│   │   └── avatars/              # Demo user avatars
│   ├── empty-module.js           # Canvas stub for react-pdf under Turbopack
│   ├── .env.local.example        # Environment variable template
│   ├── .prettierrc
│   ├── eslint.config.mjs
│   ├── next.config.ts
│   └── tsconfig.json             # Path alias: @/* → ./
├── backend/                      # FastAPI application — Phase 1 (MVP)
│   ├── app/
│   │   ├── api/                  # Route handlers
│   │   ├── services/             # Business logic
│   │   ├── repositories/         # DB access layer
│   │   ├── models/               # SQLAlchemy models
│   │   ├── schemas/              # Pydantic schemas
│   │   ├── workers/              # Celery jobs
│   │   └── core/                 # Config, security, deps
│   └── alembic/                  # DB migrations
├── Docs/                         # Project documentation
│   ├── implementation-plan.md    # Full-stack MVP plan and API contracts
│   ├── tasks.md                  # Full-stack task list
│   ├── ui-implementation-plan.md # UI demo build plan
│   └── ui-tasks.md               # UI demo task checklist
├── CLAUDE.md
├── AGENTS.md
├── README.md
└── docker-compose.yml            # (planned)
```

---

## API Endpoints Reference

All endpoints are prefixed with `/api/v1`. Protected endpoints require `Authorization: Bearer <token>`.

Role abbreviations: **A** = Admin, **M** = Moderator, **U** = Member

---

### Module 1 — Authentication & Onboarding

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/auth/verify-invite`            | Validate invite code               | No     | —     |
| POST   | `/auth/signup`                   | Register with valid invite code    | No     | —     |
| POST   | `/auth/login`                    | Email + password login             | No     | —     |
| POST   | `/auth/logout`                   | Invalidate token / session         | Yes    | A,M,U |
| POST   | `/auth/forgot-password`          | Send password reset email          | No     | —     |
| POST   | `/auth/reset-password`           | Reset password with token          | No     | —     |
| POST   | `/auth/refresh-token`            | Refresh JWT access token           | Yes    | A,M,U |
| GET    | `/auth/me`                       | Get current authenticated user     | Yes    | A,M,U |
| PATCH  | `/auth/me`                       | Update own profile                 | Yes    | A,M,U |
| POST   | `/auth/me/preferences`           | Save interest preferences (setup)  | Yes    | A,M,U |
| POST   | `/auth/me/change-password`       | Change password (authenticated)    | Yes    | A,M,U |

---

### Module 2 — User Management

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| GET    | `/users`                         | List all users (with filters)      | Yes    | A,M   |
| GET    | `/users/{id}`                    | Get user profile                   | Yes    | A,M,U |
| PUT    | `/users/{id}`                    | Update user profile                | Yes    | A     |
| DELETE | `/users/{id}`                    | Delete / deactivate user           | Yes    | A     |
| PATCH  | `/users/{id}/status`             | Activate or deactivate user        | Yes    | A     |
| PATCH  | `/users/{id}/role`               | Assign/change user role            | Yes    | A     |
| GET    | `/users/{id}/contributions`      | User's questions, docs, posts      | Yes    | A,M,U |

---

### Module 3 — Organization Management

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| GET    | `/organizations`                 | List all organizations             | Yes    | A,M,U |
| POST   | `/organizations`                 | Create new organization            | Yes    | A     |
| GET    | `/organizations/{id}`            | Get organization details           | Yes    | A,M,U |
| PUT    | `/organizations/{id}`            | Update organization                | Yes    | A     |
| DELETE | `/organizations/{id}`            | Delete organization                | Yes    | A     |
| GET    | `/organizations/{id}/members`    | List members of organization       | Yes    | A,M   |

---

### Module 4 — Invite Management

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/invites`                       | Generate new invite code           | Yes    | A     |
| GET    | `/invites`                       | List all invites                   | Yes    | A     |
| GET    | `/invites/{code}`                | Get invite details / status        | Yes    | A     |
| DELETE | `/invites/{code}`                | Revoke invite code                 | Yes    | A     |

---

### Module 5 — Knowledge Repository (Documents)

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/documents`                     | Upload document (PDF file or external URL) | Yes    | A,M,U |
| GET    | `/documents`                     | List approved documents (filters); accepts `?lang=` for translated titles/summaries **(Phase 2: translation)** | Yes    | A,M,U |
| GET    | `/documents/{id}`                | Get document detail + metadata; accepts `?lang=` for translated content **(Phase 2: translation)** | Yes    | A,M,U |
| PUT    | `/documents/{id}`                | Update document metadata           | Yes    | A,M   |
| DELETE | `/documents/{id}`                | Delete document                    | Yes    | A     |
| GET    | `/documents/{id}/download`       | Download document file             | Yes    | A,M,U |
| GET    | `/documents/{id}/related`        | AI-powered related documents **(Phase 2)** | Yes    | A,M,U |
| GET    | `/documents/my`                  | Current user's uploaded documents  | Yes    | A,M,U |
| GET    | `/documents/{id}/status`         | Get upload/moderation status       | Yes    | A,M,U |
| GET    | `/documents/{id}/versions`       | List all versions of a document    | Yes    | A,M   |
| GET    | `/documents/{id}/versions/{vid}` | Get a specific document version    | Yes    | A,M   |

---

### Module 6 — Question & Answer

#### Questions

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/questions`                     | Submit a new question              | Yes    | A,M,U |
| GET    | `/questions`                     | List approved questions; accepts `?lang=` for translated titles/bodies **(Phase 2: translation)** | Yes    | A,M,U |
| GET    | `/questions/{id}`                | Get question detail; accepts `?lang=` for translated content **(Phase 2: translation)** | Yes    | A,M,U |
| PUT    | `/questions/{id}`                | Edit question (pre-moderation)     | Yes    | A,M,U |
| DELETE | `/questions/{id}`                | Delete question                    | Yes    | A     |
| GET    | `/questions/my`                  | Current user's questions           | Yes    | A,M,U |
| PATCH  | `/questions/{id}/assign`         | Assign question to a legal expert  | Yes    | A,M   |
| GET    | `/questions/{id}/status`         | Get moderation/answer status       | Yes    | A,M,U |
| POST   | `/questions/{id}/promote`        | Promote approved Q&A pair to knowledge article **(Phase 2)** | Yes    | A,M   |
| GET    | `/questions/{id}/versions`       | List version history of a question | Yes    | A,M   |
| GET    | `/questions/{id}/versions/{vid}` | Get a specific question version    | Yes    | A,M   |

#### Answers

| Method | Endpoint                                   | Description                        | Auth   | Roles |
|--------|--------------------------------------------|------------------------------------|--------|-------|
| POST   | `/questions/{question_id}/answers`         | Post an answer                     | Yes    | A,M,U |
| GET    | `/questions/{question_id}/answers`         | List answers for a question        | Yes    | A,M,U |
| PUT    | `/answers/{id}`                            | Edit an answer                     | Yes    | A,M,U |
| DELETE | `/answers/{id}`                            | Delete an answer                   | Yes    | A     |
| PATCH  | `/answers/{id}/accept`                     | Mark answer as accepted            | Yes    | A,M,U |
| PATCH  | `/answers/{id}/verify`                     | Mark answer as expert-verified by credentialled lawyer (sets `is_verified=true`, `verified_by`, `verified_at`) | Yes | A,M |
| PATCH  | `/answers/{id}/mark-official`              | Designate answer as the **official ICA position** (sets `is_ica_official=true`, `marked_official_by`, `marked_official_at`). Requires `is_verified=true` on the answer. Idempotent. Emits `answer.marked_official` outbox event. | Yes | A |

#### Q&A Discussion Comments **(Phase 2)**

Side-channel discussion on approved questions. No moderation required — the platform is invite-only and all participants are vetted members. The question author receives an in-app notification (`question_commented` event) when a new comment is posted. Comments are not indexed in OpenSearch.

| Method | Endpoint                                        | Description                        | Auth   | Roles |
|--------|-------------------------------------------------|------------------------------------|--------|-------|
| GET    | `/questions/{question_id}/comments`             | List comments on a question        | Yes    | A,M,U |
| POST   | `/questions/{question_id}/comments`             | Add a comment to a question        | Yes    | A,M,U |
| DELETE | `/questions/{question_id}/comments/{comment_id}`| Delete a comment (own or Admin)    | Yes    | A,M,U |

---

### Module 7 — News & Updates

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/news`                          | Submit news article                | Yes    | A,M,U |
| GET    | `/news`                          | List approved news; accepts `?lang=` for translated titles/bodies **(Phase 2: translation)** | Yes    | A,M,U |
| GET    | `/news/{id}`                     | Get news article detail; accepts `?lang=` for translated content **(Phase 2: translation)** | Yes    | A,M,U |
| PUT    | `/news/{id}`                     | Update news article                | Yes    | A,M   |
| DELETE | `/news/{id}`                     | Delete news article                | Yes    | A     |
| GET    | `/news/my`                       | Current user's submitted news      | Yes    | A,M,U |
| GET    | `/news/{id}/status`              | Get moderation status of news item | Yes    | A,M,U |
| PATCH  | `/news/{id}/feature`             | Feature/pin an approved news article for prominent display **(Phase 2)** | Yes | A |
| GET    | `/news/{id}/versions`            | List version history of a news article | Yes | A,M |
| GET    | `/news/{id}/versions/{vid}`      | Get a specific news article version | Yes | A,M |

---

### Module 8 — Social Feed / Posts

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| POST   | `/posts`                         | Create a post                      | Yes    | A,M,U |
| GET    | `/posts`                         | List social feed posts             | Yes    | A,M,U |
| GET    | `/posts/{id}`                    | Get post detail                    | Yes    | A,M,U |
| PUT    | `/posts/{id}`                    | Edit post                          | Yes    | A,M,U |
| DELETE | `/posts/{id}`                    | Delete post                        | Yes    | A     |
| POST   | `/posts/{id}/like`               | Like/unlike a post                 | Yes    | A,M,U |
| GET    | `/posts/{id}/comments`           | Get comments on a post             | Yes    | A,M,U |
| POST   | `/posts/{id}/comments`           | Add a comment to a post            | Yes    | A,M,U |
| DELETE | `/posts/{id}/comments/{cid}`     | Delete a comment                   | Yes    | A,M   |
| GET    | `/posts/my`                      | Current user's posts               | Yes    | A,M,U |
| GET    | `/posts/{id}/status`             | Get moderation status of post      | Yes    | A,M,U |

---

### Module 9 — Moderation

| Method | Endpoint                              | Description                             | Auth   | Roles |
|--------|---------------------------------------|-----------------------------------------|--------|-------|
| GET    | `/moderation/queue`                   | Full moderation queue (all types)       | Yes    | A,M   |
| GET    | `/moderation/queue/questions`         | Pending questions queue                 | Yes    | A,M   |
| GET    | `/moderation/queue/documents`         | Pending documents queue                 | Yes    | A,M   |
| GET    | `/moderation/queue/news`              | Pending news queue                      | Yes    | A,M   |
| GET    | `/moderation/queue/posts`             | Pending posts queue                     | Yes    | A,M   |
| GET    | `/moderation/queue/flagged`           | Flagged content queue (held for senior review — Admin only per AC-5) | Yes | A  |
| POST   | `/moderation/approve`                 | Approve a submission; body may include `category_id` to categorize at review time | Yes | A,M |
| POST   | `/moderation/reject`                  | Reject a submission with remarks        | Yes    | A,M   |
| POST   | `/moderation/request-changes`         | Return for revision with feedback       | Yes    | A,M   |
| POST   | `/moderation/flag`                    | Flag content for senior review (holds it without rejecting) | Yes | A,M |
| POST   | `/moderation/retract`                 | Retract an already-approved document (`law_status=retracted`) | Yes | A,M |
| GET    | `/moderation/logs`                    | Full moderation audit log               | Yes    | A     |
| GET    | `/moderation/logs/{entity_type}/{id}` | Moderation history for a specific item  | Yes    | A,M   |
| GET    | `/moderation/stats`                   | Moderation queue counts by type         | Yes    | A,M   |

---

### Module 10 — Notifications

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| GET    | `/notifications`                 | List user's notifications          | Yes    | A,M,U |
| GET    | `/notifications/unread-count`    | Get unread notification count (read-through from `redis-cache` key `unread:{user_id}`, TTL 60s). **Polling at intervals < 60s is prohibited** — clients should rely on the `X-Notification-Unread-Count` response header piggybacked on every authenticated response, or subscribe to `GET /notifications/stream` (SSE, Phase 3). | Yes    | A,M,U |
| GET    | `/notifications/stream`          | Server-Sent Events stream: pushes badge count and notification events on a long-lived HTTP connection (ALB idle timeout tuned to 300s). **(Phase 3)** | Yes | A,M,U |
| PATCH  | `/notifications/{id}/read`       | Mark notification as read          | Yes    | A,M,U |
| PATCH  | `/notifications/read-all`        | Mark all notifications as read     | Yes    | A,M,U |
| DELETE | `/notifications/{id}`            | Delete a notification              | Yes    | A,M,U |
| GET    | `/notifications/preferences`     | Get news subscription preferences (country/category filters for broadcasts) | Yes | A,M,U |
| PUT    | `/notifications/preferences`     | Update news subscription preferences | Yes  | A,M,U |

---

### Module 11 — Search & AI

| Method | Endpoint                         | Description                             | Auth   | Roles | Phase |
|--------|----------------------------------|-----------------------------------------|--------|-------|-------|
| GET    | `/search`                        | Global hybrid search — see query params below | Yes | A,M,U | 1 |
| POST   | `/ai/ask`                        | AI-powered semantic Q&A (RAG)           | Yes    | A,M,U | **2** |
| GET    | `/ai/suggestions/{question_id}`  | AI answer suggestion for a question (REQ-061) | Yes | A,M | **2** |
| POST   | `/ai/summarize/{document_id}`    | AI summary of a document (REQ-067)      | Yes    | A,M,U | **2** |
| POST   | `/ai/summarize/question/{question_id}` | AI summary of a Q&A answer thread (REQ-068) | Yes | A,M,U | **2** |
| GET    | `/questions/{id}/related`        | Semantically related questions (REQ-069) | Yes   | A,M,U | **2** |
| GET    | `/news/{id}/related`             | Semantically related news articles (REQ-069) | Yes | A,M,U | **2** |
| GET    | `/posts/{id}/related`            | Semantically related posts (REQ-069)   | Yes    | A,M,U | **2** |
| POST   | `/ai/translate`                  | Translate text to a specified language  | Yes    | A,M,U | **2** |
| GET    | `/ai/translate/languages`        | List supported translation languages    | Yes    | A,M,U | **2** |

#### `GET /search` — Query Parameter Contract

| Parameter     | Type     | Required | Description |
|---------------|----------|----------|-------------|
| `q`           | string   | Yes      | Search query text (min 2 chars) |
| `type`        | enum     | No       | `documents` \| `questions` \| `news` \| `posts` — omit for global |
| `country`     | string[] | No       | ISO 3166-1 alpha-2 codes, multi-value (e.g. `country=KE&country=IN`) |
| `category`    | string[] | No       | Category IDs, multi-value |
| `lang`        | string   | No       | BCP 47 language code of the query (e.g. `fr`, `ar`). If omitted, assumes English. Triggers translation pipeline. **(Phase 2)** |
| `date_from`   | date     | No       | ISO 8601 filter: content published after this date |
| `date_to`     | date     | No       | ISO 8601 filter: content published before this date |
| `status`      | enum     | No       | `active` \| `retracted` \| `superseded` — defaults to `active` only |
| `page`        | int      | No       | 1-based page number, default `1` |
| `page_size`   | int      | No       | Results per page for search, default `10`, max `20`. General list endpoints (`/documents`, `/questions`, `/news`, `/posts`) support max `50` — see API Design Standards |
| `search_mode` | enum     | No       | `hybrid` (default) \| `keyword` \| `semantic` |

Response envelope:
```json
{
  "results": [...],
  "total": 342,
  "page": 1,
  "page_size": 10,
  "query_lang": "fr",
  "search_mode": "hybrid",
  "latency_ms": 284,
  "cache_hit": false
}
```

---

### Module 12 — Dashboard (Aggregated)

| Method | Endpoint                         | Description                             | Auth   | Roles |
|--------|----------------------------------|-----------------------------------------|--------|-------|
| GET    | `/dashboard`                     | Aggregated: news, questions, docs, notif count | Yes | A,M,U |

---

### Module 13 — Taxonomy / Reference Data

| Method | Endpoint                         | Description                        | Auth   | Roles |
|--------|----------------------------------|------------------------------------|--------|-------|
| GET    | `/tags`                          | List available tags                | Yes    | A,M,U |
| POST   | `/tags`                          | Create new tag                     | Yes    | A     |
| PUT    | `/tags/{id}`                     | Update tag                         | Yes    | A     |
| DELETE | `/tags/{id}`                     | Delete tag                         | Yes    | A     |
| GET    | `/countries`                     | List supported countries           | Yes    | A,M,U |
| GET    | `/categories`                    | List document/question categories  | Yes    | A,M,U |
| POST   | `/categories`                    | Create new category                | Yes    | A     |
| PUT    | `/categories/{id}`               | Update category                    | Yes    | A     |
| DELETE | `/categories/{id}`               | Delete category                    | Yes    | A     |

---

### Module 14 — Admin Statistics & Configuration

| Method | Endpoint                         | Description                             | Auth   | Roles | Phase |
|--------|----------------------------------|-----------------------------------------|--------|-------|-------|
| GET    | `/admin/stats`                   | Platform-wide counts: users (total, by org, by role), content (docs, questions, news, posts), moderation throughput, AI query volume | Yes | A | 1 |
| GET    | `/admin/ai-usage`                | AI usage & cost breakdown: token counts, embedding calls, translation API calls, RAG queries, estimated cost by time range | Yes | A | **2** |
| GET    | `/admin/config`                  | Get current platform configuration (AI confidence thresholds, moderation SLA targets, max content per org, invite expiry, supported languages) | Yes | A | 1 |
| PUT    | `/admin/config`                  | Update platform configuration           | Yes    | A     | 1 |
| GET    | `/users/me/export`               | GDPR data portability export — triggers a Celery job that packages all of the authenticated user's contributions (documents, questions, answers, news, posts) into a JSONL archive and returns a pre-signed S3 download URL | Yes | A,M,U | **2** |

---

### Module 15 — System / Ops

| Method | Endpoint    | Description                                                                                                                                                                                                                                                    | Auth | Roles |
|--------|-------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------|-------|
| GET    | `/health/live`  | **Liveness probe** — returns 200 if the process is running. Never checks external dependencies. Used by Kubernetes `livenessProbe`. Prevents cascading restarts when OpenSearch is temporarily slow. | No | — |
| GET    | `/health/ready` | **Readiness probe** — checks `db`, `redis-broker`, `redis-cache`, `opensearch`. Returns 503 if any dependency unreachable — pod is removed from the ALB target group but NOT restarted. Used by Kubernetes `readinessProbe` and load-balancer health probes. | No | — |
| GET    | `/health`   | Backwards-compatible alias — redirects to `/health/ready`. | No   | —     |
| GET    | `/metrics`  | Prometheus metrics (instrumented by `prometheus-fastapi-instrumentator`). Exposes HTTP latency, Celery queue depth, OpenSearch query latency, cache hit rates, AI usage counters. **Restricted to internal network / VPN via AWS WAF rule** — public access returns HTTP 403 at the edge. | No   | —     |

---

## Frontend Page → API Mapping

| Route                        | Key APIs Used                                              |
|------------------------------|------------------------------------------------------------|
| `/auth/login`                | POST /auth/login                                           |
| `/auth/signup`               | POST /auth/verify-invite, POST /auth/signup                |
| `/auth/forgot-password`      | POST /auth/forgot-password, POST /auth/reset-password      |
| `/auth/setup`                | POST /auth/me/preferences                                  |
| `/dashboard`                 | GET /dashboard, GET /notifications/unread-count            |
| `/repository`                | GET /documents, GET /countries, GET /categories, GET /tags |
| `/repository/[id]`           | GET /documents/{id}, GET /documents/{id}/related           |
| `/repository/upload`         | POST /documents                                            |
| `/questions`                 | GET /questions, GET /countries, GET /categories            |
| `/questions/ask`             | POST /questions, GET /tags                                 |
| `/questions/[id]`            | GET /questions/{id}, GET /questions/{id}/answers, POST /questions/{id}/answers, PATCH /answers/{id}/accept, PATCH /answers/{id}/verify, GET /questions/{id}/comments (Phase 2), POST /questions/{id}/comments (Phase 2), DELETE /questions/{id}/comments/{cid} (Phase 2), GET /ai/suggestions/{id} (Phase 2), POST /questions/{id}/promote (Phase 2) |
| `/questions/my`              | GET /questions/my                                          |
| `/news`                      | GET /news                                                  |
| `/news/[id]`                 | GET /news/{id}, PATCH /news/{id}/feature (Phase 2, Admin only)  |
| `/news/create`               | POST /news                                                 |
| `/news/my`                   | GET /news/my                                               |
| `/feed`                      | GET /posts                                                 |
| `/post/create`               | POST /posts                                                |
| `/post/my`                   | GET /posts/my                                              |
| `/notifications`             | GET /notifications, PATCH /notifications/read-all          |
| `/search`                    | GET /search, POST /ai/ask                                  |
| `/moderation`                | GET /moderation/queue, GET /moderation/stats               |
| `/moderation/questions`      | GET /moderation/queue/questions, POST /moderation/approve, POST /moderation/reject |
| `/moderation/documents`      | GET /moderation/queue/documents, POST /moderation/approve, POST /moderation/reject |
| `/moderation/news`           | GET /moderation/queue/news, POST /moderation/approve, POST /moderation/reject |
| `/moderation/posts`          | GET /moderation/queue/posts, POST /moderation/approve, POST /moderation/reject |
| `/admin/users`               | GET /users, PATCH /users/{id}/status, PATCH /users/{id}/role |
| `/admin/orgs`                | GET /organizations, POST /organizations, PUT /organizations/{id} |
| `/admin/invites`             | POST /invites, GET /invites, DELETE /invites/{code}        |
| `/admin/analytics`           | GET /admin/stats, GET /moderation/stats, GET /admin/ai-usage (Phase 2) |
| `/admin/taxonomy`            | GET /categories, POST /categories, PUT /categories/{id}, DELETE /categories/{id}, GET /tags, POST /tags, PUT /tags/{id}, DELETE /tags/{id} |
| `/admin/config`              | GET /admin/config, PUT /admin/config                       |
| `/profile/[id]`              | GET /users/{id}, GET /users/{id}/contributions             |
| `/profile/edit`              | PATCH /auth/me                                             |
| `/profile/export`            | GET /users/me/export **(Phase 2)**                         |

---

## Background Jobs (Celery Workers)

**Four** Celery queues are used. Workers subscribe to one or more queues; long-running queues (`ingestion`, `embeddings`, `ai`) run on dedicated workers with `worker_prefetch_multiplier=1` so KEDA sees true queue depth and scales correctly.

| Queue | Workers | Concurrency / pod | `worker_prefetch_multiplier` | Purpose |
|---|---|---|---|---|
| `default` | 2+ shared workers | 8 | 4 | Short I/O jobs: notifications, cache invalidation, search indexing, translation lookups |
| `ingestion` | 1+ dedicated workers | 2 | 1 | **Docling extraction + chunking (up to 120s/task)** — isolated to prevent starving fast I/O jobs |
| `embeddings` | 1+ dedicated workers | 4 | 1 | CPU/GPU-bound: all embedding generation; uses OpenSearch Bulk API |
| `ai` | 1+ dedicated workers | 4 | 1 | LLM-bound: RAG, content flag, AI summarisation (Phase 2) |

### Celery Reliability Configuration (mandatory)

| Setting | Value | Reason |
|---|---|---|
| `CELERY_TASK_ACKS_LATE` | `True` | Task acknowledged only after completion — prevents silent loss on worker kill |
| `CELERY_TASK_REJECT_ON_WORKER_LOST` | `True` | Explicit rejection (not silent drop) if worker process is SIGKILLed mid-task |
| `CELERY_BROKER_TRANSPORT_OPTIONS` | `{"visibility_timeout": 3600}` | Must exceed the longest task duration (embedding batch ~300s); do not set below 300s |
| `CELERY_TASK_TIME_LIMIT` | 300 (ingestion), 600 (embeddings) | Hard kill; must be < `visibility_timeout` to avoid broker re-delivery during execution |
| `CELERY_TASK_SOFT_TIME_LIMIT` | `TIME_LIMIT - 60s` | Raises `SoftTimeLimitExceeded` for graceful cleanup before SIGKILL |
| `CELERY_TASK_IGNORE_RESULT` | `True` (global) | Results not stored — broker memory bounded to actual queue depth (<50MB at sustained load); opt-in per-task with `@app.task(ignore_result=False, result_expires=300)` |
| `CELERY_RESULT_BACKEND` | `None` | No result backend configured |
| `-Ofair` worker flag | enabled | Combined with `prefetch_multiplier=1`, KEDA sees true queue depth |

| Job Name                      | Queue        | Trigger                               | Phase | Description |
|-------------------------------|--------------|---------------------------------------|-------|-------------|
| `document_ingestion_job`      | `ingestion`  | On document approved                  | 1     | Docling extraction from PDF (text, OCR, tables); timeout 120s; isolated on dedicated queue; falls back to raw text on failure (DC-5: rejects on full failure) |
| `chunking_job`                | `ingestion`  | After ingestion completes             | 1     | Split extracted text into 512-token chunks with 64-token overlap; respects paragraph boundaries |
| `embedding_generation_job`    | `embeddings` | After chunking                        | 1     | Batch-embed doc chunks (32 at a time) via **OpenSearch Bulk API (`helpers.bulk()`, max 5MB / 200 ops per request)**; circuit breaker falls back to local model via `EMBEDDING_FALLBACK_PROVIDER` |
| `qa_embedding_job`            | `embeddings` | On Q&A pair accepted                  | 1     | Embed question + answer_summary → index into `ica_questions` via Bulk API; translates non-English text to English before embedding |
| `qa_verify_embedding_job`     | `embeddings` | On Q&A pair marked verified           | 1     | Partial update `ica_questions` setting `is_verified=true`; no re-embedding needed |
| `post_embedding_job`          | `embeddings` | On post approved                      | 1     | Embed post body → index into `ica_posts` k-NN field via Bulk API |
| `post_index_job`              | `default`    | On post approved                      | 1     | **(NG-2)** Index approved post into `ica_posts` (`body`, `country`, `tags`, `author_id`, `content_vector`). Posts are never indexed before approval. Retraction triggers partial update removing the post. |
| `opensearch_refresh_job`      | `default`    | Inside Celery `chain()` after indexing | 1    | **(R4-G02)** Issues synchronous `POST /<index>/_refresh`; confirms HTTP 200 before yielding to `search_cache_invalidate_job`. Prevents stale results being re-cached after approval. |
| `ai_answer_job`               | `ai`         | On `POST /ai/ask`                     | 2     | LangGraph workflow: Intent Classifier → Doc + Q&A Retrievers → RRF Merger → Confidence Scorer → LLM Generation or Expert-Review Flag → Audit Logger. Accepts `mode=answer` (default) or `mode=suggestions` (abbreviated RAG for `GET /ai/suggestions/{question_id}` — no LLM call, returns ranked source passages only) |
| `ai_content_flag_job`         | `ai`         | On content submission                 | 2     | AI pre-screen for inappropriate/off-topic content; result stored on submission record and surfaced in moderation queue |
| `translation_job`             | `default`    | On AI query or `?lang=` content fetch | 2     | Translate input to English for processing; translate output back to member's preferred language. Circuit breaker: 3 retries → cache `_UNAVAILABLE` for 1h |
| `notification_dispatch_job`   | `default`    | On content status change              | 1     | Create in-app notification rows for the content contributor; also invalidates `unread:{user_id}` key in `redis-cache`. `channel=email` variant calls SMTP/SendGrid with SES fallback |
| `news_broadcast_job`          | `default`    | On news article approved              | 1     | **(NG-3)** Fan-out via Celery `group()` batched in sub-tasks of 100 subscribers each. A 10,000-subscriber broadcast spawns 100 parallel sub-tasks completing in seconds rather than minutes. |
| `search_index_job`            | `default`    | On content approval                   | 1     | Index content into OpenSearch by type via **Bulk API**: docs → `ica_documents` + `ica_document_chunks`; Q&A → `ica_questions`; news → `ica_news`; posts → `ica_posts`. Dispatched as part of Celery `chain()` with `opensearch_refresh_job → search_cache_invalidate_job`. |
| `search_cache_invalidate_job` | `default`    | On content approval or retraction     | 1     | **(R4-G01)** Reads `SMEMBERS scope:country:{c}:category:{cat}` (Redis Set secondary index) and `DEL`s all keys in a single pipeline; never uses `KEYS` or `SCAN`. Also deletes matching `entity:{type}:{id}` keys. |
| `query_translation_cache_job` | `default`    | On non-English `/search` or `/ai/ask` | 2     | Translate query → English; cache result in `redis-cache` db=1 (**TTL 7 days**, key: `trans:{lang}:{sha256(query)}`); `allkeys-lru` eviction |
| `legal_import_job`            | `ingestion`  | Periodic (configurable schedule)      | 3     | Pull documents from external legal API sources; feed into Docling → chunk → embed → index pipeline; sourced with `is_official=true` |
| `revoked_tokens_cleanup_job`  | `default`    | Nightly (Celery beat, 02:00 UTC)      | 1     | Delete rows from `revoked_tokens` WHERE `expires_at < now()`. Uses the `(expires_at)` index (R4-G06). Catch-up guard via `last_run:revoked_tokens_cleanup_job` Redis key. |
| `outbox_events_cleanup_job`   | `default`    | Nightly (Celery beat, 02:15 UTC)      | 1     | **(GAP-4)** Hard-deletes `outbox_events` rows WHERE `status IN ('PUBLISHED','DEAD_LETTER') AND published_at < now() - INTERVAL '7 days'`. Also prunes AI audit rows (`event_type LIKE 'ai_query.%'`) after 30 days. `DEAD_LETTER` rows fire Prometheus alert `outbox_dead_letter_total > 0` before deletion. |
| `notification_cleanup_job`    | `default`    | Nightly (Celery beat, 02:30 UTC)      | 1     | **(M-5)** Delete `notifications` rows WHERE `is_read=true AND created_at < now() - INTERVAL '90 days'`. Required index: `(user_id, is_read, created_at DESC)`. |
| `outbox_stuck_recovery_job`   | `default`    | Every 10 minutes (Celery beat)        | 1     | **(R4-G05)** Resets `outbox_events` stuck in `IN_PROGRESS > 10 min` back to `PENDING`. Safe to run concurrently with main poller (`FOR UPDATE SKIP LOCKED`). Handles SIGKILL during graceful-shutdown overruns. |
| `replica_lag_monitor_job`     | `default`    | Every 60 seconds (Celery beat)        | 1     | **(R5-G08)** Reads `pg_last_xact_replay_timestamp()` and caches lag (seconds) in `redis-cache` key `pg_replica_lag_seconds`. Routing decisions read the cached value — no per-request lag overhead. |
| `cache_warmup_job`            | `default`    | 5 minutes after deployment marker     | 1     | **(R5-G10)** Pre-loads top-50 search queries, top-20 non-English translations, top-20 hot entities into `redis-cache`. Rate-limited to 1 query/100ms (avoid self-DoS). Search SLA suspended for ~5 minutes post-deploy. |
| `query_log_aggregation_job`   | `default`    | Nightly (Celery beat, 03:00 UTC)      | 1     | **(R5-G10)** Reads `/search` access logs and writes top queries to `cache_warmup_queries` table for the next deploy. |
| `pg_stats_export_job`         | `default`    | Daily (04:00 UTC)                     | 1     | **(R5-G11)** Exports top-20 slowest query templates from `pg_stat_statements` to CloudWatch. Quarterly review documented in operational runbook. |
| `embedding_backfill_job`      | `embeddings` | Manual trigger during model migration | 2     | **(R5-G12)** Rate-limited beat job that re-embeds existing chunks under the new model when `EMBEDDING_DUAL_WRITE=true`. Part of the 6-step migration playbook (add v2 field → dual-write → backfill → verify → cut-over → cleanup). |
| `gdpr_export_job`             | `default`    | On `GET /users/me/export`             | 2     | Package all of the requesting user's contributions (documents, questions, answers, news, posts) into a JSONL archive; upload to S3; return pre-signed URL. Excludes PII from other users. |

> **SAD alignment note:** The following jobs are defined in this plan but are not explicitly listed in the SAD's worker/job descriptions. They are required for correct operation and should not be removed:
> - `post_embedding_job` — embeds approved posts into `ica_posts`; the SAD's ingestion pipeline diagrams cover documents and Q&A only but the index design requires this job.
> - `revoked_tokens_cleanup_job` — referenced in SAD §7.1 as a "nightly Celery cleanup" but never named.
> - `outbox_events_cleanup_job` — referenced in SAD §9.9 as a "nightly Celery job" but never named.
> - `query_translation_cache_job` — the translation pipeline in SAD §9.8 is described procedurally; this is the concrete Celery task that backs it.

---

## Key Design Decisions

1. **CQRS — writes to PostgreSQL, reads/search to OpenSearch**: All content writes land in PostgreSQL as the system of record. On approval, a Celery job indexes the content into OpenSearch (text fields for BM25 + k-NN vector field for semantic). The API never runs FTS queries against PostgreSQL for member-facing search.
2. **Moderation-first**: All user-generated content (questions, documents, news, posts) enters a pending state and must be approved before appearing publicly. Three outcomes: Approve, Reject, Request Changes (revision without full rejection).
3. **AI is assistive**: AI answers and suggestions are surfaced to moderators/members but require human review before being marked authoritative.
4. **Invite-only onboarding**: No self-registration. Admins generate invite codes tied to an organization, subject to per-organisation `max_users` limits enforced at invite generation and signup.
5. **Async processing**: Heavy operations (OCR, embedding, translation) run via Celery workers, never blocking API responses.
6. **Multi-language via English pivot**: All AI processing happens in English. Non-English input is translated to English before RAG retrieval; the output is translated back to the user's preferred language. User language preference is stored on the profile.
7. **Q&A as knowledge base**: Approved question+answer pairs are embedded into the vector DB alongside document chunks, making the Q&A corpus searchable via RAG — not just static documents.
8. **Content versioning**: Every edit to a document, question, or news article before or after approval creates a new `content_versions` row (entity_type, entity_id, version_number, snapshot JSON, edited_by, edited_at). The current approved state remains in the main table; versions are append-only and never deleted. `GET /documents/{id}/versions` exposes this history to Admins and Moderators.
9. **Organisation-level content scoping**: All content (documents, questions, news, posts) is platform-wide by default — members of any organisation can read approved content. Organisation membership controls onboarding (invite quota, max_users) and is recorded on contributions for attribution, but does not gate read access. If a future requirement for org-siloed content emerges, an `org_visibility` field (`public` | `org_only`) can be added to content tables without breaking the current model.
10. **Data privacy and PII**: User PII (email, name) is stored only in the `users` table. Content bodies are not treated as PII. `DELETE /users/{id}` anonymises the record (nulls PII fields, sets `status=deleted`) rather than hard-deleting, to preserve audit trail integrity. Contribution records are retained but attributed to an anonymised placeholder. AI audit logs in `outbox_events` never store raw user queries longer than 30 days (TTL enforced by a nightly Celery cleanup job). GDPR right-to-erasure requests are fulfilled via the anonymisation path above.

---

## Search Performance Architecture

### Performance SLA Target

All member-facing search responses (`GET /search`, `POST /ai/ask`) must complete within **≤ 3 seconds** end-to-end at the 95th percentile under expected load. The budget is allocated per stage:

| Stage | Budget | Notes |
|---|---|---|
| Query translation (non-English) | ≤ 500ms | Served from Redis cache after first call |
| OpenSearch hybrid retrieval (BM25 + k-NN) | ≤ 800ms | Pre-filtered by country/category; k=20 candidates |
| LLM reranking / RAG generation | ≤ 1 000ms | Only for `/ai/ask`; skipped for `/search` |
| FastAPI serialisation + network | ≤ 200ms | |
| **Total (`/search`)** | **≤ 1 500ms** | Leaves 2× headroom against 3s SLA |
| **Total (`/ai/ask`)** | **≤ 2 500ms** | RAG path; translation cache assumed warm |

---

### 8. Search Stack — OpenSearch Hybrid (BM25 + k-NN)

**Problem**: PostgreSQL full-text search does not scale to large multi-country document corpora and has no vector similarity capability. FAISS is in-memory, single-node, and unsuitable for production-scale persistent search.

**Decision**: Use **OpenSearch** as the unified search backend for both keyword and semantic search from the start (not as a future migration). OpenSearch's k-NN plugin provides approximate nearest-neighbour search over dense vectors in the same index as BM25 text fields, enabling hybrid scoring in a single query.

**Index design** — one index per content type, plus a dedicated chunk index for per-passage RAG retrieval:

```
opensearch_index: ica_documents                      ← document-level search (GET /search)
  - id (keyword)
  - title (text, analyzed)
  - content_chunks (text[], analyzed)                ← full BM25 text corpus
  - doc_vector (knn_vector, dims=384)                ← document-level centroid; used for /search related-docs
  - country (keyword)                                ← pre-filter field
  - category (keyword)                               ← pre-filter field
  - tags (keyword[])                                 ← pre-filter field
  - law_status (keyword)                             ← active | retracted | superseded
  - language (keyword)                               ← original content language
  - approved_at (date)
  - contributor_org (keyword)

opensearch_index: ica_document_chunks                ← chunk-level retrieval (POST /ai/ask RAG)
  - chunk_id (keyword)
  - doc_id (keyword)                                 ← joins back to ica_documents
  - chunk_text (text, analyzed)
  - chunk_vector (knn_vector, dims=384)              ← per-chunk embedding — precise passage retrieval
  - chunk_index (integer)                            ← position within document
  - country (keyword)                                ← inherited from parent doc; enables pre-filtering
  - category (keyword)                               ← inherited from parent doc
  - tags (keyword[])                                 ← inherited from parent doc
  - law_status (keyword)                             ← inherited; filters out retracted docs at chunk level

opensearch_index: ica_questions
  - id (keyword)
  - title (text, analyzed)
  - body (text, analyzed)
  - answer_summary (text, analyzed)
  - country (keyword)
  - category (keyword)
  - tags (keyword[])
  - is_verified (boolean)                            ← true only when a credentialled lawyer has validated the answer
  - answer_status (keyword)                          ← pending | approved | verified
  - approved_at (date)
  - content_vector (knn_vector, dims=384)            ← embedding of question + answer_summary concatenated

opensearch_index: ica_news
  - id (keyword)
  - title (text, analyzed)
  - body (text, analyzed)
  - country (keyword)
  - category (keyword)
  - published_at (date)
  - content_vector (knn_vector, dims=384)

opensearch_index: ica_posts
  - id (keyword)
  - body (text, analyzed)
  - country (keyword)
  - tags (keyword[])
  - author_id (keyword)
  - approved_at (date)
  - content_vector (knn_vector, dims=384)            ← lower retrieval weight in RAG; community context only
```

**Hybrid query pattern for `GET /search`** (reciprocal rank fusion against `ica_documents`):
```python
# Pseudocode — executed by SearchService
bm25_hits  = opensearch.search("ica_documents", query={"match": {"content_chunks": q}}, filter=pre_filters, size=20)
knn_hits   = opensearch.search("ica_documents", query={"knn": {"doc_vector": {"vector": embed(q), "k": 20}}}, filter=pre_filters)
results    = reciprocal_rank_fusion(bm25_hits, knn_hits, k=60)[:page_size]
```

**Chunk retrieval pattern for `POST /ai/ask`** (k-NN against `ica_document_chunks`):
```python
# Executed inside LangGraph Doc Retriever Node — returns passages, not whole documents
chunk_hits = opensearch.search("ica_document_chunks", query={"knn": {"chunk_vector": {"vector": embed(q), "k": 20}}}, filter=pre_filters)
# pre_filters carry country/category/tags/law_status=active from original request
```

**Scale trigger**: OpenSearch replaces FAISS. There is no FAISS phase in production — OpenSearch is used from day one in Docker Compose (single-node, 1 shard), scaling to a 3-node cluster when document chunk count exceeds **500k** (see Scale-Out Thresholds in Key Design Decision #14 for the full tier breakdown).

---

### 9. Country / Category Pre-Filtering at the Index Level

**Problem**: Scanning the full corpus for every search query is the primary source of latency at scale. Members always search within a legal jurisdiction context.

**Decision**: All OpenSearch queries apply a **`filter` clause** (not `query`, so it does not affect scoring) on `country` and/or `category` before BM25 and k-NN scoring. OpenSearch evaluates filters using the bitset cache, making them effectively free at retrieval time.

**Implementation**:
```python
pre_filters = {"bool": {"filter": []}}
if country_codes:
    pre_filters["bool"]["filter"].append({"terms": {"country": country_codes}})
if category_ids:
    pre_filters["bool"]["filter"].append({"terms": {"category": category_ids}})
if status:
    pre_filters["bool"]["filter"].append({"term": {"law_status": status}})
else:
    pre_filters["bool"]["filter"].append({"term": {"law_status": "active"}})  # default
```

This means a query scoped to `country=KE` only scores documents from Kenya — reducing the effective corpus size by 1–2 orders of magnitude and keeping k-NN retrieval fast regardless of total index size.

---

### 10. Redis Search Result Cache

**Problem**: Repeated queries (common legal terms, popular jurisdictions) re-execute the full retrieval pipeline on every request. This wastes compute and adds unnecessary latency.

**Decision**: Cache the serialised JSON response of `GET /search` in Redis, keyed on a deterministic hash of all query parameters. Cache is invalidated when new content is approved or retracted in the matching scope.

**Cache key scheme** (stored on `redis-cache` db=0):
```
search:{sha256(q + type + sorted(country) + sorted(category) + status + page + page_size + search_mode)}
TTL: 300 seconds (5 minutes) for member queries
TTL: 60 seconds for moderation-context queries
```

**Cache invalidation (R4-G01, R4-G02)**: On each search write, `SearchService` additionally adds the cache key to a Redis Set per content scope:
```
SADD scope:country:{country_code}:category:{category_id}  search:{sha256}
EXPIRE scope:country:{country_code}:category:{category_id} 600
```
Scope sets are given TTL 600s (2× the cache TTL). On approval/retraction, `search_cache_invalidate_job` runs as the **last step of a Celery `chain()`** — `search_index_job → opensearch_refresh_job → search_cache_invalidate_job` — and performs:
1. `SMEMBERS scope:country:{c}:category:{cat}` — O(keys in that scope only)
2. `DEL` all returned keys in a single Redis pipeline (search keys + matching `entity:{type}:{id}` keys)
3. `DEL scope:country:{c}:category:{cat}`

No `KEYS`, no `SCAN`, no O(total keyspace) operation. The cache is never cleared until `opensearch_refresh_job` confirms HTTP 200 from `POST /<index>/_refresh`, eliminating the stale-result-reseeding race condition.

**FastAPI middleware**: A `SearchCacheMiddleware` checks Redis before invoking `SearchService`. On a cache hit, it sets `cache_hit: true` in the response envelope and returns immediately — target latency ≤ 50ms for cached responses.

---

### 11. Multi-Language Query Translation with Cache

**Problem**: A non-English query (e.g. French, Arabic) must be translated to English before RAG retrieval. A live LLM translation call on every request would add 500–2000ms, blowing the latency budget.

**Decision**: Translate non-English queries once and cache the English translation in `redis-cache` db=1 with a **7-day TTL** (`allkeys-lru` eviction). Resolved the prior contradiction between "indefinite" and "24h" (GAP-9). A circuit breaker (3 retries → cache `_UNAVAILABLE` for 1h) protects against translation-provider outages (GAP-8).

**Flow**:
```
Member submits query in French
  → SearchService detects lang != "en" (from ?lang= param or langdetect)
  → Check redis-cache db=1: trans:{lang}:{sha256(raw_query)}
      HIT  → use cached English query (~1ms)
      MISS → call translation_job synchronously (< 500ms), cache result for 7 days, proceed
  → Run hybrid search with English query
  → Return results with translated snippets (async, best-effort)
```

**Detected vs declared language**: If `?lang=` is not supplied, the backend runs `langdetect` (< 5ms) on the query string to decide whether translation is needed before the cache lookup.

---

### 12. LangGraph RAG Orchestration for `/ai/ask`

**Problem**: A plain RAG pipeline treats all three indexed sources (documents, verified Q&A pairs, user posts) uniformly and has no mechanism to route low-confidence answers to human review, self-correct on thin retrieval, or produce a traceable audit trail — all critical requirements for a legal platform.

**Decision**: Replace the custom retrieval-and-generation logic inside `ai_answer_job` with a **LangGraph workflow**. LangGraph slots in as the orchestration layer within the existing Celery worker; OpenSearch, Redis, and the Celery task contract remain unchanged.

**Node architecture**:
```
User Query (English, post-translation)
        ↓
[Intent Classifier Node]
  Classify: factual / procedural / jurisdictional / out-of-scope
        ↓                              ↓
[Doc Retriever Node]        [Verified Q&A Retriever Node]
  k-NN on ica_document_chunks   k-NN on ica_questions
  filter: law_status=active     filter: is_verified=true
  filter: country/category/tags filter: country/category/tags
  → returns ranked passages     → returns ranked Q&A pairs
        ↓                              ↓
            [Post Retriever Node]
              k-NN on ica_posts
              filter: country/tags
              invoked only when doc + Q&A hits < 3
                    ↓
        [Source Merger & Ranker Node]
          Priority: documents > verified Q&A > posts
          Merge by weighted reciprocal rank fusion:
            doc chunks weight=1.0, verified Q&A weight=0.8, posts weight=0.3
          Apply deduplication (same doc_id, keep highest-scoring chunk)
                    ↓
        [Confidence Scorer Node]
          Score based on: retrieval density, source authority, query-result overlap
                    ↓
         high confidence          low confidence
                ↓                       ↓
  [LLM Generation Node]     [Flag for Expert Review Node]
    Generate answer with        Write to moderation queue
    inline citations            Return "pending expert review" status
    (doc_id, chunk_id, q_id)
                ↓
  [Audit Logger Node]
    Record: query, sources used (doc_ids, chunk_ids, q_ids),
    confidence score, reasoning path → append to outbox_events
```

**Source priority rules**:
| Source | RRF Weight | Condition |
|---|---|---|
| Document chunks (`ica_document_chunks`, `law_status=active`) | 1.0 (primary) | Always retrieved first; pre-filtered by country/category/tags |
| Verified Q&A pairs (`ica_questions`, `is_verified=true`) | 0.8 | Retrieved in parallel with docs; supplements factual grounding |
| Community posts (`ica_posts`) | 0.3 | Retrieved only when doc + Q&A combined hits < 3 |

**Confidence thresholds**:
```python
HIGH_CONFIDENCE  = 0.75   # → LLM generation with citations
LOW_CONFIDENCE   = 0.50   # → flag to moderation queue, no answer surfaced
BELOW_THRESHOLD  = < 0.50 # → return "insufficient information" response
```

**Self-correction loop**: If the Source Merger returns fewer than 3 relevant hits, the graph loops back to Intent Classifier with a reformulated query (query expansion via LLM) — maximum 1 retry before falling back to the low-confidence path.

**Audit trail**: Every node execution appends a structured log entry to `outbox_events` in the same PostgreSQL transaction as the job result write. Fields: `query_hash`, `sources_retrieved` (ids + index), `confidence_score`, `reasoning_path`, `llm_model`, `timestamp`. This provides the legal compliance audit trail.

**Latency impact**: LangGraph graph initialization adds ~50–100ms per invocation. The existing `/ai/ask` budget of ≤ 2500ms absorbs this within the LLM generation allocation (≤ 1000ms), provided the retry loop is exercised at most once.

**What does NOT change**: OpenSearch indexes, Redis caching, Celery task contract (`ai_answer_job`), the translation pipeline, and all endpoint definitions in Module 11 remain unchanged. LangGraph is an internal implementation detail of the worker.

---

### 13. Document Retraction Status

**Problem**: The use-case (Section 6) asks whether retracted laws appear in search. Members searching for applicable law must not unknowingly act on retracted legislation.

**Decision**: Documents have a `law_status` field with three states:

| Status | Meaning | Search behaviour |
|---|---|---|
| `active` | Currently in force | Returned by default |
| `retracted` | Withdrawn by the issuing authority | Excluded from default search; visible only with `?status=retracted` |
| `superseded` | Replaced by a newer law | Excluded from default search; linked document points to replacement |

**Moderation action**: A new moderation action **Retract** (alongside Approve / Reject / Request Changes) is available to Moderators and Admins for already-approved documents. Triggering it:
1. Sets `law_status = retracted` in PostgreSQL
2. Updates the OpenSearch document field in-place (partial update, no re-index)
3. Fires `search_cache_invalidate_job` for the affected country/category scope
4. Sends a notification to the original contributor

**API**: Retraction is handled through the unified moderation endpoint `POST /moderation/retract` (see Module 9). No separate document-level status endpoint exists — all moderation actions, including retraction, go through the moderation service layer to ensure the audit trail is written consistently.

---

### 14. Embedding Model and Chunk Strategy

**Problem**: Embedding quality and chunk size directly determine semantic search recall. Chunks too large lose precision; too small lose context.

**Decision**:

| Parameter | Value | Rationale |
|---|---|---|
| Embedding model | `all-MiniLM-L6-v2` (384 dims, 80ms/chunk on CPU) | Fast, fits Docker Compose; swap to `text-embedding-3-small` for production |
| Chunk size | 512 tokens | Balances legal clause granularity with contextual coherence |
| Chunk overlap | 64 tokens | Prevents clause truncation at boundaries |
| Chunks per doc | max 200 | Documents beyond 200 chunks are split into multiple index entries |
| Index unit | Chunk (not document) | k-NN retrieves the most relevant passage, not the whole document |
| Stored in OpenSearch | Chunk text + vector + parent `document_id` | Allows result grouping by parent document in the API response |

Embedding generation runs in `embedding_generation_job` (Celery), after chunking. The job batches chunks in groups of 32 to maximise GPU/CPU throughput.

---

### 14. Scale-Out Thresholds and Migration Path

| Threshold | Action |
|---|---|
| < 50k document chunks | Single-node OpenSearch, 1 primary shard per index, Docker Compose |
| 50k – 500k chunks | Increase OpenSearch heap to 4GB; add 1 replica shard per index; tune `ef_search` for k-NN |
| > 500k chunks | Expand to 3-node OpenSearch cluster; split indices by region (`ica_documents_africa`, etc.) |
| > 5M chunks | Migrate to managed OpenSearch Service (AWS) or Elastic Cloud; introduce dedicated coordinator nodes; activate ISM Cold → Ultra Warm transition |
| `redis-cache` memory > 2GB | Already running with `allkeys-lru`; increase ElastiCache node size or shard the cache namespace (broker is always separate from MVP onward) |

---

## Data Model — Table Schemas

Supplements the SQLAlchemy models in `backend/app/models/`. These schemas are the definitive reference for Alembic migrations.

### Entity Summary

| Entity | Storage | Key Notes |
|---|---|---|
| `organizations` | PostgreSQL | Org identity and `max_users` quota |
| `users` | PostgreSQL | PII isolated here only (`email`, `full_name`); anonymised on deletion |
| `invites` | PostgreSQL | Single-use, org-scoped, never hard-deleted |
| `countries` | PostgreSQL | ISO 3166-1 codes; managed by Admin |
| `categories` | PostgreSQL | Hierarchical; scoped to content type |
| `tags` | PostgreSQL | Flat tag list; applied to documents, questions, posts |
| `document_tags`, `question_tags`, `post_tags` | PostgreSQL | Tag junction tables |
| `user_preferences` | PostgreSQL | Onboarding interests (country/category) + digest opt-in |
| `revoked_tokens` | PostgreSQL | JWT logout invalidation table; pruned nightly |
| `documents` | PostgreSQL | Includes `source_type` (`uploaded` \| `external_url`) per DC-3; `summary`, `replacement_document_id`, `retracted_at/_reason`, `approved_by` |
| `document_chunks` | PostgreSQL (metadata) + OpenSearch (`ica_document_chunks`, vectors) | Vectors stored in OpenSearch only; PostgreSQL holds inventory |
| `questions` | PostgreSQL | |
| `answers` | PostgreSQL | `is_verified` set by Moderator/Admin per DC-1 |
| `news_articles` | PostgreSQL | Includes `is_featured`, `featured_order` for pinning (Phase 2) |
| `posts` | PostgreSQL | |
| `post_likes` | PostgreSQL | Per-user like tracking for idempotent toggle |
| `comments` | PostgreSQL | |
| `knowledge_articles` | PostgreSQL | Phase 2; promoted Q&A pairs |
| `question_comments` | PostgreSQL | Phase 2; discussion thread on approved questions; no moderation; not indexed in OpenSearch |
| `notifications` | PostgreSQL | |
| `notification_preferences` | PostgreSQL | Country/category broadcast subscription filters |
| `content_versions` | PostgreSQL | Append-only; covers documents, questions, news, posts |
| `moderation_logs` | PostgreSQL | Append-only; no DELETE/UPDATE at application level |
| `outbox_events` | PostgreSQL | Transactional outbox; AI audit rows pruned at 30-day TTL |
| `platform_config` | PostgreSQL | Key-value config store |
| `ai_usage_events` | PostgreSQL | Phase 2; one row per AI operation for cost tracking |

### Core Application Tables

```sql
CREATE TABLE organizations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    max_users   INTEGER NOT NULL DEFAULT 100 CHECK (max_users > 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_by  UUID,                                        -- FK added after users table
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_organizations_name_active
    ON organizations (lower(name)) WHERE is_active = TRUE;

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           CITEXT UNIQUE,                           -- nullable post-anonymisation
    password_hash   TEXT,                                    -- required by Module 1 (/auth/login)
    full_name       TEXT,                                    -- nullable post-anonymisation
    role            TEXT NOT NULL CHECK (role IN ('admin','moderator','member')),
    org_id          UUID NOT NULL REFERENCES organizations(id),
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','inactive','deleted')),
    preferred_lang  TEXT NOT NULL DEFAULT 'en',              -- BCP-47
    avatar_url      TEXT,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_org_status ON users(org_id, status);
CREATE INDEX idx_users_role       ON users(role) WHERE status = 'active';

-- Defer organizations.created_by FK until users exists.
ALTER TABLE organizations
    ADD CONSTRAINT fk_organizations_created_by
    FOREIGN KEY (created_by) REFERENCES users(id);

CREATE TABLE invites (
    code          TEXT PRIMARY KEY,
    org_id        UUID NOT NULL REFERENCES organizations(id),
    invited_email CITEXT,
    invited_role  TEXT CHECK (invited_role IN ('admin','moderator','member')),
    created_by    UUID NOT NULL REFERENCES users(id),
    expires_at    TIMESTAMPTZ NOT NULL,
    used_at       TIMESTAMPTZ,
    used_by       UUID REFERENCES users(id),
    revoked_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    -- never hard-deleted; preserved for audit
);
CREATE INDEX idx_invites_org_validity ON invites(org_id, expires_at, used_at);

CREATE TABLE countries (
    code        CHAR(2) PRIMARY KEY,                         -- ISO 3166-1 alpha-2
    name        TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    parent_id     UUID REFERENCES categories(id) ON DELETE SET NULL,
    content_type  TEXT CHECK (content_type IN ('document','question','news','post')),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (content_type, name, parent_id)
);
CREATE INDEX idx_categories_parent       ON categories(parent_id);
CREATE INDEX idx_categories_content_type ON categories(content_type) WHERE content_type IS NOT NULL;

CREATE TABLE tags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User interest preferences set in onboarding (POST /auth/me/preferences).
CREATE TABLE user_preferences (
    user_id                  UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    interest_country_codes   CHAR(2)[] NOT NULL DEFAULT '{}',
    interest_category_ids    UUID[]    NOT NULL DEFAULT '{}',
    receive_digest_email     BOOLEAN   NOT NULL DEFAULT TRUE,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Authentication Tables (GAP-01)

```sql
-- JWT logout invalidation.
-- The jti (JWT ID) claim from a revoked token is stored here.
-- JWT validator checks this table on every request while the access token has not yet expired.
-- Nightly Celery job deletes rows WHERE expires_at < now() to keep the table small.
CREATE TABLE revoked_tokens (
    token_jti   TEXT PRIMARY KEY,             -- JWT 'jti' claim (UUID)
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_type  TEXT NOT NULL CHECK (token_type IN ('access','refresh')),
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_revoked_tokens_expires ON revoked_tokens(expires_at);
```

### Content Tables

```sql
CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    summary         TEXT,                                    -- 200-word AI summary (POST /ai/summarize/{document_id})
    country         CHAR(2) NOT NULL REFERENCES countries(code),
    category_id     UUID REFERENCES categories(id),
    law_type        TEXT,
    language        TEXT NOT NULL DEFAULT 'en',              -- BCP-47
    -- DC-3: either uploaded file (file_key) or external_url, never both.
    source_type     TEXT NOT NULL DEFAULT 'uploaded'
                    CHECK (source_type IN ('uploaded','external_url')),
    file_key        TEXT,                                    -- S3/MinIO object key
    external_url    TEXT,
    -- Moderation lifecycle
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    -- Law validity lifecycle (separate from moderation status)
    law_status      TEXT NOT NULL DEFAULT 'active'
                    CHECK (law_status IN ('active','retracted','superseded')),
    replacement_document_id UUID REFERENCES documents(id),
    retracted_at    TIMESTAMPTZ,
    retraction_reason TEXT,
    submitted_by    UUID NOT NULL REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    approved_by     UUID REFERENCES users(id),
    version         INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (source_type = 'uploaded'     AND file_key     IS NOT NULL AND external_url IS NULL) OR
        (source_type = 'external_url' AND external_url IS NOT NULL AND file_key     IS NULL)
    )
);

-- PostgreSQL-side metadata for document chunks (H-2).
-- Vectors are stored in OpenSearch (ica_document_chunks index, chunk_vector field).
-- This table is the authoritative inventory; OpenSearch is a derived search index.
-- ON DELETE CASCADE: chunks are removed if the parent document is deleted.
CREATE TABLE document_chunks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index     INTEGER NOT NULL CHECK (chunk_index >= 0),  -- 0-based position within document
    chunk_text      TEXT NOT NULL,                              -- extracted text (~512 tokens)
    token_count     INTEGER NOT NULL CHECK (token_count >= 0),
    page_number     INTEGER CHECK (page_number > 0),            -- for RAG citation rendering
    section_title   TEXT,                                       -- for RAG citation rendering
    is_embedded     BOOLEAN NOT NULL DEFAULT FALSE,             -- set by embedding_generation_job
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (document_id, chunk_index)
);
CREATE INDEX idx_document_chunks_doc     ON document_chunks(document_id);
CREATE INDEX idx_document_chunks_pending ON document_chunks(is_embedded) WHERE is_embedded = FALSE;

CREATE TABLE document_tags (
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    tag_id      UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (document_id, tag_id)
);
CREATE INDEX idx_document_tags_tag ON document_tags(tag_id);

CREATE TABLE questions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title               TEXT NOT NULL,
    body                TEXT NOT NULL,
    country             CHAR(2) NOT NULL REFERENCES countries(code),
    category_id         UUID REFERENCES categories(id),
    status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','rejected','revision_required','flagged','answered','closed')),
    submitted_by        UUID NOT NULL REFERENCES users(id),
    assigned_to         UUID REFERENCES users(id),               -- expert assigned to answer
    accepted_answer_id  UUID,                                    -- FK added after answers exists
    version             INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at           TIMESTAMPTZ
);

CREATE TABLE answers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id     UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    body            TEXT NOT NULL,
    posted_by       UUID NOT NULL REFERENCES users(id),
    is_accepted     BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    verified_by     UUID REFERENCES users(id),
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Composite key for accepted_answer FK guarantees answer belongs to question.
CREATE UNIQUE INDEX ux_answers_question_id_id ON answers (question_id, id);
ALTER TABLE questions
    ADD CONSTRAINT fk_questions_accepted_answer
    FOREIGN KEY (id, accepted_answer_id) REFERENCES answers(question_id, id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE question_tags (
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    tag_id      UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (question_id, tag_id)
);
CREATE INDEX idx_question_tags_tag ON question_tags(tag_id);

-- GAP-04: is_featured and featured_order columns required for PATCH /news/{id}/feature
CREATE TABLE news_articles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    summary         TEXT,
    source_url      TEXT,
    country         CHAR(2) NOT NULL REFERENCES countries(code),
    category_id     UUID REFERENCES categories(id),
    language        TEXT NOT NULL DEFAULT 'en',
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    is_featured     BOOLEAN NOT NULL DEFAULT FALSE,
    featured_order  INTEGER,                                 -- lower = higher position; null = not featured
    submitted_by    UUID NOT NULL REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    approved_by     UUID REFERENCES users(id),
    published_at    TIMESTAMPTZ,
    version         INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE posts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    body            TEXT NOT NULL,
    category_id     UUID REFERENCES categories(id),
    submitted_by    UUID NOT NULL REFERENCES users(id),
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    -- Denormalised counter; source of truth remains post_likes (see SAD §6.1).
    likes_count     INTEGER NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE comments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id             UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    parent_comment_id   UUID REFERENCES comments(id) ON DELETE CASCADE,
    body                TEXT NOT NULL,
    author_id           UUID NOT NULL REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comments_post ON comments(post_id, created_at);

-- Per-user like tracking required for like/unlike toggle (H-3).
-- POST /posts/{id}/like checks this table before insert to implement idempotent toggle.
-- likes_count on posts table is a denormalised counter updated on insert/delete here.
CREATE TABLE post_likes (
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE post_tags (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);
CREATE INDEX idx_post_tags_tag ON post_tags(tag_id);

-- Phase 2: knowledge articles promoted from Q&A pairs
CREATE TABLE knowledge_articles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL UNIQUE REFERENCES questions(id),
    promoted_by UUID NOT NULL REFERENCES users(id),
    promoted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Phase 2: side-channel discussion thread on approved questions.
-- No moderation required — all participants are vetted invite-only members.
-- Not indexed in OpenSearch; purely relational, queried by question_id only.
-- Posting a comment fires a 'question_commented' notification to the question author.
CREATE TABLE question_comments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    author_id   UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_question_comments_question ON question_comments(question_id, created_at);
```

### Audit and Event Tables (GAP-03)

```sql
-- Transactional outbox for domain events.
-- Written atomically with state changes in the same PG transaction.
-- Polled by Celery beat every 5 seconds; never queried directly by API handlers.
-- AI query events (event_type LIKE 'ai_query.%') pruned at 30-day TTL by nightly cleanup job.
-- Outbox state machine: PENDING → IN_PROGRESS → PUBLISHED, or → FAILED → DEAD_LETTER (NG-11)
-- payload max size 4KB enforced via Pydantic OutboxPayload root validator (R4-G11).
-- Priority taxonomy (R5-G01): 0=critical (retraction/flag), 5=default, 10=low (broadcasts).
CREATE TABLE outbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      TEXT NOT NULL,            -- e.g. 'document.approved', 'ai_query.completed'
    entity_type     TEXT,                     -- 'document'|'question'|'news'|'post'|null
    entity_id       UUID,
    payload         JSONB NOT NULL DEFAULT '{}'
                    CHECK (octet_length(payload::text) <= 4096),  -- 4KB hard cap (R4-G11)
    priority        SMALLINT NOT NULL DEFAULT 5,                  -- 0=critical, 5=default, 10=low (R5-G01)
    status          TEXT NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','IN_PROGRESS','PUBLISHED','FAILED','DEAD_LETTER')),
    retry_count     INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    last_error      TEXT,                                  -- populated on FAILED / DEAD_LETTER
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),  -- used by outbox_stuck_recovery_job
    published_at    TIMESTAMPTZ
)
WITH (
    autovacuum_vacuum_scale_factor = 0.05,   -- (R5-G06) high-write table override
    autovacuum_vacuum_cost_delay   = 10      -- ms
);
-- Priority-ordered poll index: ORDER BY priority ASC, created_at ASC LIMIT 10 FOR UPDATE SKIP LOCKED
CREATE INDEX idx_outbox_pending ON outbox_events(status, priority, created_at) WHERE status IN ('PENDING','IN_PROGRESS');
-- GRANT INSERT ON outbox_events TO ica_app;
-- No UPDATE or DELETE permissions granted to the application role.

-- Append-only content version history. Never deleted.
-- (NG-7) snapshot stores metadata DIFF ONLY (title, country, category, status; ≤2KB).
-- NEVER store full document body or chunk_text here — that stays in S3.
-- A CHECK constraint caps snapshot size at 2KB to prevent accidental body storage.
CREATE TABLE content_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type     TEXT NOT NULL CHECK (entity_type IN ('document','question','news','post')),
    entity_id       UUID NOT NULL,
    version_number  INTEGER NOT NULL,
    snapshot        JSONB NOT NULL
                    CHECK (octet_length(snapshot::text) <= 2048),  -- ≤2KB metadata diff only
    edited_by       UUID NOT NULL REFERENCES users(id),
    edited_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_type, entity_id, version_number)
);
-- No UPDATE or DELETE permissions granted to the application role.
-- Partitioning (NG-13): range-partition by edited_at quarterly when row count > 1M.

-- Immutable moderation audit log.
-- (NG-13) Range-partitioned by created_at (quarterly) when row count exceeds 1M.
-- Older partitions archived to S3 + Parquet via pg_dump after compliance retention period.
-- PK must include partition key (PostgreSQL requirement for PARTITION BY RANGE).
CREATE TABLE moderation_logs (
    id          UUID NOT NULL DEFAULT gen_random_uuid(),
    actor_id    UUID NOT NULL REFERENCES users(id),
    action      TEXT NOT NULL
                CHECK (action IN ('approve','reject','request_changes','flag','retract',
                                  'submit','assign','comment','escalate','supersede')),
    entity_type TEXT NOT NULL,
    entity_id   UUID NOT NULL,
    remarks     TEXT,                                       -- required for reject and retract
    metadata    JSONB NOT NULL DEFAULT '{}'::JSONB,         -- e.g. reassignment target, escalation reason
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Default partition catches out-of-range rows; quarterly partitions added by Alembic.
CREATE TABLE moderation_logs_default PARTITION OF moderation_logs DEFAULT;
CREATE TABLE moderation_logs_2026_q2 PARTITION OF moderation_logs
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
-- No UPDATE or DELETE permissions granted to the application role.

-- Aggregated AI usage events for GET /admin/ai-usage (M-5).
-- One row per AI operation. Populated by ai_answer_job, ai_content_flag_job,
-- translation_job, and embedding_generation_job.
CREATE TABLE ai_usage_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type          TEXT NOT NULL
                        CHECK (event_type IN ('rag_query','content_flag','summarize','translation','embedding')),
    user_id             UUID REFERENCES users(id),
    input_tokens        INTEGER NOT NULL DEFAULT 0,
    output_tokens       INTEGER NOT NULL DEFAULT 0,
    embedding_calls     INTEGER NOT NULL DEFAULT 0,
    model               TEXT,                   -- LLM or embedding model used (e.g. 'gpt-4o-mini')
    estimated_cost_usd  NUMERIC(10,6),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_usage_events_created ON ai_usage_events(created_at);
CREATE INDEX idx_ai_usage_events_type    ON ai_usage_events(event_type, created_at);
```

### Notification Tables (GAP-05)

```sql
CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,                           -- e.g. 'question_answered','news_published'
    reference_type  TEXT,                                    -- 'document'|'question'|'news'|'post'|...
    reference_id    UUID,
    title           TEXT,
    body            TEXT,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read, created_at DESC);

-- Controls which news broadcasts a member receives, and per-channel delivery.
-- Used by news_broadcast_job to build the subscriber fan-out list.
-- A NULL country or category means "any". COALESCE in PK so that the
-- (user_id, NULL, NULL) "subscribe to all" row is uniquely representable.
CREATE TABLE notification_preferences (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    country_code    CHAR(2) REFERENCES countries(code),      -- null = all countries
    category_id     UUID REFERENCES categories(id),          -- null = all categories
    email_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    in_app_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, COALESCE(country_code, '--'), COALESCE(category_id::text, '--'))
);
```

### Admin Configuration Table (GAP-02)

```sql
-- Platform configuration key-value store.
-- Sensitive values (API keys) are stored as env var reference names, not raw values.
CREATE TABLE platform_config (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    value_type  TEXT NOT NULL CHECK (value_type IN ('string','integer','float','boolean','json')),
    description TEXT,
    updated_by  UUID REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed data (applied via Alembic migration):
-- ('ai_confidence_high',  '0.75',          'float',   'RAG high-confidence threshold for LLM generation')
-- ('ai_confidence_low',   '0.50',          'float',   'RAG low-confidence threshold; below this routes to expert review')
-- ('invite_expiry_hours', '72',            'integer', 'Default invite code validity in hours')
-- ('supported_languages', '["en","es","fr"]', 'json', 'Active BCP-47 language codes for translation')
-- ('max_content_per_org', '500',           'integer', 'Max approved content items per organisation')
-- ('moderation_sla_hours','48',            'integer', 'Target review SLA in hours (display only; not system-enforced)')
```

---

## Environment Variables Reference

All configuration is provided via environment variables. No hardcoded values in source. Use `.env` locally; inject via AWS Secrets Manager or Parameter Store in production.

### Backend (`backend/.env`)

| Variable | Example | Description |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://ica:password@pgbouncer:5433/ica?sslmode=require` | **Routes through PgBouncer port 5433** (transaction mode, pool_size=50). `sslmode=require` mandatory in prod (NG-18). |
| `ANALYTICS_DATABASE_URL` | `postgresql+asyncpg://ica_ro:password@pgbouncer:5433/ica?sslmode=require` | **(M-2)** Read replica DSN used by `DashboardService` and other analytics queries. Auto-falls back to `DATABASE_URL` when `pg_replica_lag_seconds > 10` (R5-G08). |
| `REDIS_BROKER_URL` | `rediss://redis-broker:6380/0` | **(GAP-1)** Celery broker — dedicated `redis-broker` instance (ElastiCache Multi-AZ HA). TLS via `rediss://` (NG-18). |
| `REDIS_CACHE_URL` | `rediss://redis-cache:6380/0` | **(GAP-1)** Application cache — `redis-cache` instance (`allkeys-lru`). db=0 = search cache + entity cache + rate limiter + unread counters; db=1 = translation cache. Single instance — self-healing. |
| `OPENSEARCH_URL` | `https://opensearch:9200` | OpenSearch node URL — HTTPS with cert validation in prod (NG-18) |
| `SECRET_KEY` | *(RS256 private key, PEM, base64-encoded)* | JWT signing key |
| `PUBLIC_KEY` | *(RS256 public key, PEM, base64-encoded)* | JWT validation key |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `30` | JWT access token lifetime |
| `REFRESH_TOKEN_EXPIRE_DAYS` | `7` | JWT refresh token lifetime |
| `STORAGE_PROVIDER` | `minio` \| `s3` | **GAP-09** Switches `StorageService` implementation. All file operations go through `StorageService`; never call MinIO/S3 SDK directly in business logic. Changing this is a config-only change — no code changes required. |
| `MINIO_ENDPOINT` | `http://minio:9000` | MinIO API endpoint (`STORAGE_PROVIDER=minio`) |
| `MINIO_ACCESS_KEY` | `minioadmin` | |
| `MINIO_SECRET_KEY` | `minioadmin` | |
| `MINIO_BUCKET` | `ica-documents` | |
| `AWS_S3_BUCKET` | `ica-documents-prod` | S3 bucket (`STORAGE_PROVIDER=s3`) |
| `AWS_REGION` | `us-east-1` | |
| `EMBEDDING_PROVIDER` | `local` \| `openai` | **GAP-09** Primary embedding model. `local` = `all-MiniLM-L6-v2` (CPU, dev); `openai` = `text-embedding-3-small` (prod). |
| `EMBEDDING_FALLBACK_PROVIDER` | `local` | **(GAP-8)** Fallback provider when primary fails (3 retries → DEAD_LETTER). For prod, falls back to local model. |
| `EMBEDDING_DUAL_WRITE` | `false` | **(R5-G12)** When `true`, new content embeds both `chunk_vector` (current) and `chunk_vector_v2` (new model). Enabled during embedding model migration. |
| `EMBEDDING_MODEL_VERSION` | `v1` | **(R5-G12)** Reversible query-time switch (`v1` → `v2`) during cut-over phase. |
| `TRANSLATION_PROVIDER` | `openai` \| `aws-translate` | **(GAP-8)** Translation backend. Circuit breaker: 3 retries → cache `_UNAVAILABLE` for 1h. |
| `EMAIL_FALLBACK_PROVIDER` | `ses` | **(GAP-8)** Secondary email provider when SendGrid fails. |
| `OPENAI_API_KEY` | `sk-...` | Required when `EMBEDDING_PROVIDER=openai` or LLM generation is active |
| `OPENAI_LLM_MODEL` | `gpt-4o-mini` | LLM model used by `ai_answer_job` for answer generation |
| `SMTP_HOST` | `smtp.sendgrid.net` | |
| `SMTP_PORT` | `587` | |
| `SMTP_USERNAME` | `apikey` | |
| `SMTP_PASSWORD` | `SG....` | SendGrid API key as SMTP password |
| `SMTP_FROM_EMAIL` | `noreply@ica-platform.org` | |
| `DOCLING_TIMEOUT_SECONDS` | `120` | Max processing time per document; falls back to raw text extraction on timeout |
| `FRONTEND_URL` | `http://localhost:3000` | Allowed CORS origin — must match the deployed frontend URL exactly |
| `ENVIRONMENT` | `development` \| `staging` \| `production` | Used by Sentry and logging |
| `LOG_LEVEL` | `INFO` | Structured log level |
| `SENTRY_DSN` | *(optional)* | Sentry backend DSN |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | *(optional)* | OpenTelemetry collector endpoint |

### Frontend (`frontend/.env.local`)

| Variable | Example | Description |
|---|---|---|
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000/api/v1` | Backend API base URL (public — embedded in browser bundle) |
| `NEXT_PUBLIC_DEMO_MODE` | `false` | `true` activates MSW mock layer. Must be `false` in all deployed environments. |
| `NEXT_PUBLIC_SENTRY_DSN` | *(optional)* | Sentry frontend DSN |

---

## API Design Standards

Applies to all endpoints under `/api/v1`. Both backend and frontend teams must adhere to these conventions to ensure consistency across all modules.

### Standard Error Response Format (GAP-11)

A custom FastAPI exception handler provides a consistent error envelope. The default `HTTPException` response format is replaced with:

```json
{
  "detail": "Human-readable error message",
  "error_code": "MACHINE_READABLE_CODE",
  "field_errors": [
    { "field": "email", "message": "Invalid email format" }
  ]
}
```

`field_errors` is omitted when there are no field-level validation failures (401, 403, 404, etc.).

| HTTP Status | `error_code` | Scenario |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Pydantic schema validation failure |
| 400 | `INVALID_INVITE` | Invite code invalid, expired, or already used |
| 401 | `UNAUTHORIZED` | Missing or malformed JWT |
| 401 | `TOKEN_EXPIRED` | JWT access token has expired |
| 403 | `FORBIDDEN` | Authenticated but insufficient role |
| 404 | `NOT_FOUND` | Entity does not exist or is not accessible to this role |
| 409 | `CONFLICT` | Duplicate resource |
| 413 | `FILE_TOO_LARGE` | Upload exceeds 50 MB limit |
| 422 | `UNPROCESSABLE` | Semantically invalid request |
| 429 | `RATE_LIMITED` | Request rate limit exceeded |
| 503 | `SEARCH_UNAVAILABLE` | OpenSearch unavailable; graceful degradation |

### Pagination Standards (GAP-12, NG-5)

Two pagination styles are supported. Cursor-based (keyset) pagination is **mandatory** for high-volume feeds where offset pagination degrades and stability under concurrent inserts is required.

| Endpoint Group | Pagination Style | Default `page_size` | Max `page_size` |
|---|---|---|---|
| `GET /search` | Offset | 10 | **20** (scoring cost per result justifies lower cap) |
| `GET /posts` (social feed) | **Cursor (keyset)** | 10 | 50 |
| `GET /moderation/queue` and `/moderation/queue/{type}` | **Cursor (keyset)** | 20 | 50 |
| All other list endpoints (`/documents`, `/questions`, `/news`, `/users`, etc.) | Offset | 10 | **50** |

**Cursor-based pagination (NG-5).** The cursor encodes `{created_at, id}` of the last seen item, base64-URL-encoded.

Query pattern (descending feed):
```sql
WHERE (created_at, id) < (cursor_created_at, cursor_id)
ORDER BY created_at DESC, id DESC
LIMIT n;
```

This is O(1) at any position (no scan to skip rows) and stable under concurrent inserts — duplicates or skipped items cannot occur. Clients pass `cursor` as a query param; the response envelope includes `next_cursor` (or `null` at end of feed).

**Response envelopes:**

Offset:
```json
{ "items": [...], "total": 342, "page": 1, "page_size": 10 }
```

Cursor:
```json
{ "items": [...], "next_cursor": "MjAyNi0wNS0xN1QxMDoz...", "page_size": 10 }
```

> **Note:** The SAD §11.11 states "default 10, max 50" uniformly for offset endpoints. This plan intentionally caps search results at 20 because each hybrid BM25 + k-NN result incurs embedding and scoring cost. The 20-cap applies only to `GET /search` and `POST /ai/ask`.

### Idempotency (GAP-13)

The following endpoints are idempotent — a repeated identical call returns the same logical outcome without raising an error. The service layer checks current state before writing and wraps the check-and-write in a database transaction.

| Endpoint | Idempotent Behaviour |
|---|---|
| `POST /auth/logout` | If token already revoked, return 200 (not 401) |
| `POST /moderation/approve` | If already `approved`, return 200 with current state |
| `POST /moderation/reject` | If already `rejected`, return 200 with current state |
| `POST /moderation/request-changes` | If already `revision_required`, return 200 |
| `POST /moderation/flag` | If already `flagged`, return 200 |
| `POST /moderation/retract` | If `law_status` already `retracted`, return 200 |
| `PATCH /answers/{id}/accept` | If already accepted, return 200 |
| `POST /posts/{id}/like` | Toggles like/unlike; 200 either way |

### Other Standards

| Standard | Rule |
|---|---|
| Versioning | All endpoints under `/api/v1/`; breaking changes bump to `/api/v2/` without removing `/api/v1/` |
| HTTP semantics | POST = create; PUT = full replace; PATCH = partial update; DELETE = soft-delete or anonymise |
| Timestamps | UTC ISO 8601 with timezone: `2026-05-13T10:30:00Z` |
| IDs | UUID v4 for all entity IDs; never expose sequential integers |
| OpenAPI docs | Auto-served at `/docs` (Swagger UI) and `/redoc`; no authentication required in development |

---

## Security Configuration

### CORS (GAP-14)

Configure `CORSMiddleware` in `backend/app/main.py`. Never use wildcard origins in production.

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.FRONTEND_URL],
    allow_credentials=True,               # required for HttpOnly cookie refresh token
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)
```

- Development: `FRONTEND_URL=http://localhost:3000`
- Production: `FRONTEND_URL=https://ica-platform.org` (set via Secrets Manager)

### Rate Limiting (GAP-15, GAP-3)

Use `slowapi` (FastAPI-compatible) backed by **`redis-cache`** (not the broker) — a shared counter visible to all API replicas. Unauthenticated endpoints are limited per IP; authenticated endpoints are limited per JWT subject (`user_id`). All limits return HTTP 429 with `Retry-After` header and `error_code: RATE_LIMITED`.

Install: `pip install slowapi`

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, storage_uri=settings.REDIS_CACHE_URL)
app.state.limiter = limiter
```

| Endpoint | Limit | Key |
|---|---|---|
| `POST /auth/login` | 10 / minute | per IP |
| `POST /auth/forgot-password` | 3 / minute | per IP |
| `POST /auth/signup` | 5 / minute | per IP |
| `POST /auth/verify-invite` | 10 / minute | per IP |
| `POST /ai/ask` | 20 / minute | per user |
| `POST /ai/summarize/*` | 10 / minute | per user |
| `POST /invites` (Admin) | 60 / minute | per user |
| `PUT /admin/config` | 30 / minute | per user |
| All other authenticated endpoints | 300 / minute | per user |

On limit exceeded: HTTP 429 with `Retry-After` header and `error_code: RATE_LIMITED`.

### Refresh Token Storage

The refresh token is stored in an **HttpOnly, Secure, SameSite=Strict cookie** — inaccessible to JavaScript, preventing XSS theft. The access token is returned in the JSON body and held in Zustand (in-memory, not localStorage).

```
POST /auth/login response:
  Body:   { "access_token": "...", "token_type": "bearer", "expires_in": 1800 }
  Cookie: refresh_token=...; HttpOnly; Secure; SameSite=Strict;
          Path=/api/v1/auth/refresh-token; Max-Age=604800
```

`POST /auth/refresh-token` reads the cookie automatically; no client-side token handling needed for refresh.

### File Upload Security (M-6, NG-14, NG-15)

**(NG-14) Direct-to-S3 signed PUT URL pattern.** The FastAPI container never receives file bytes — uploads go directly from the client to S3. This eliminates the 4× replicas × 10 × 50MB ≈ 2GB RAM upload memory pressure under burst conditions.

**Two-step upload flow:**

1. **`POST /documents/upload-url`** — client sends `{filename, content_type, size_bytes, title, country, category_id}`. API validates metadata, generates a pre-signed S3 PUT URL with constraints (max-size, content-type, expiry 15 min), and returns `{upload_url, file_key, document_id}` (document row created with `status=pending_upload`).
2. **Client `PUT`s file directly to S3.** S3 enforces content-type and size constraints from the signed URL.
3. **`POST /documents/{id}/confirm`** — client confirms upload. API verifies the S3 object exists, transitions document to `status=pending` (moderation), and dispatches `document_ingestion_job` via the outbox.

Avatar uploads follow the same pattern.

| Control | Value | Enforcement |
|---|---|---|
| Maximum file size | **50 MB** hard cap | Signed URL `content-length-range` constraint; S3 rejects oversized PUT with HTTP 400 |
| MIME type validation | `application/pdf` (documents); `image/jpeg`, `image/png` (avatars) | Signed URL `Content-Type` constraint; server-side post-upload re-validation via `python-magic` before ingestion |
| Pre-signed URL TTL | **15 minutes** (900s) for upload; **15 minutes** for download | `StorageService.generate_presigned_url(expiry=900)`; configurable via `PRESIGNED_URL_EXPIRY_SECONDS` |
| Storage access | Private bucket only — no public S3/MinIO access | All downloads routed through `GET /documents/{id}/download` → pre-signed URL |
| File execution | Docling runs in an isolated `ingestion`-queue Celery worker | Worker process has no shell access to the parsed file path |

**(NG-15) S3 Lifecycle Rules** — three mandatory rules configured on the documents bucket:

| Rule | Trigger | Action |
|---|---|---|
| Retracted documents | `law_status=retracted` → Celery `s3_tag_retracted_job` tags S3 object | Transition to Glacier after 90 days; permanent delete after 7 years (legal retention period) |
| Rejected uploads | `status=rejected` and no resubmission after 30 days | Immediate S3 deletion — no retention obligation |
| Orphaned uploads | Files in `uploads/` prefix with no matching DB row after 48h | S3 lifecycle rule auto-deletes — handles aborted uploads |

Add to backend `.env`:

| Variable | Example | Description |
|---|---|---|
| `PRESIGNED_URL_EXPIRY_SECONDS` | `900` | Pre-signed S3 PUT/GET URL lifetime (default 15 min) |
| `MAX_FILE_SIZE_BYTES` | `52428800` | Upload size cap enforced via signed-URL `content-length-range` (default 50 MB) |

---

## Docker Compose Services (GAP-10)

Complete service definitions for local development. All services use named volumes for data persistence between restarts.

```yaml
version: "3.9"

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ica
      POSTGRES_PASSWORD: password
      POSTGRES_DB: ica
    ports: ["5432:5432"]
    volumes: [postgres_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ica"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgbouncer:                            # (GAP-7) Transaction-mode connection pooler — deployed in ALL environments
    image: edoburu/pgbouncer:1.21
    environment:
      DATABASE_URL: postgres://ica:password@postgres:5432/ica
      POOL_MODE: transaction
      MAX_CLIENT_CONN: 1000
      DEFAULT_POOL_SIZE: 50            # (R4-G03) increased from 20 to handle KEDA max scale
      QUERY_TIMEOUT: 30                # seconds — prevents hung task holding a slot
      CLIENT_IDLE_TIMEOUT: 60          # seconds — releases idle worker connections
      AUTH_TYPE: scram-sha-256
    ports: ["5433:5432"]
    depends_on:
      postgres: { condition: service_healthy }

  redis-broker:                         # (GAP-1) Celery broker only — db=0 exclusively
    image: redis:7-alpine
    ports: ["6379:6379"]
    volumes: [redis_broker_data:/data]
    command: redis-server --appendonly yes --maxmemory 512mb
    # Production: ElastiCache Multi-AZ with automatic failover (RTO <60s)

  redis-cache:                          # (GAP-1) Application cache — allkeys-lru, self-healing
    image: redis:7-alpine
    ports: ["6381:6379"]
    volumes: [redis_cache_data:/data]
    command: redis-server --appendonly no --maxmemory 1gb --maxmemory-policy allkeys-lru
    # db=0: search cache + entity cache + rate limiter + unread counters
    # db=1: translation cache (TTL 7d)

  opensearch:
    image: opensearchproject/opensearch:2.13.0
    environment:
      discovery.type: single-node
      OPENSEARCH_JAVA_OPTS: "-Xms1g -Xmx1g"
      DISABLE_SECURITY_PLUGIN: "true"   # dev only — enable security plugin in staging/prod
    ports: ["9200:9200"]
    volumes: [opensearch_data:/usr/share/opensearch/data]
    ulimits:
      memlock: { soft: -1, hard: -1 }

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports: ["9000:9000", "9001:9001"]
    volumes: [minio_data:/data]

  backend:
    build: ./backend
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    env_file: [./backend/.env]
    ports: ["8000:8000"]
    volumes: [./backend:/app]
    depends_on:
      pgbouncer: { condition: service_started }
      redis-broker: { condition: service_started }
      redis-cache: { condition: service_started }
      opensearch: { condition: service_started }
      minio: { condition: service_started }

  celery-default:                       # Short I/O jobs — prefetch=4
    build: ./backend
    command: >
      celery -A app.workers.celery_app worker
      --loglevel=info -Q default -c 8 -Ofair
      --prefetch-multiplier=4
    env_file: [./backend/.env]
    volumes: [./backend:/app]
    depends_on: [pgbouncer, redis-broker, redis-cache, opensearch, minio]

  celery-ingestion:                     # (GAP-5) Docling isolated — long-running, prefetch=1
    build: ./backend
    command: >
      celery -A app.workers.celery_app worker
      --loglevel=info -Q ingestion -c 2 -Ofair
      --prefetch-multiplier=1
    env_file: [./backend/.env]
    volumes: [./backend:/app]
    depends_on: [pgbouncer, redis-broker, opensearch, minio]

  celery-embeddings:                    # CPU-bound — prefetch=1 so KEDA sees true depth
    build: ./backend
    command: >
      celery -A app.workers.celery_app worker
      --loglevel=info -Q embeddings -c 4 -Ofair
      --prefetch-multiplier=1
    env_file: [./backend/.env]
    volumes: [./backend:/app]
    depends_on: [pgbouncer, redis-broker, opensearch]

  celery-ai:                            # Phase 2 — LLM-bound, prefetch=1
    build: ./backend
    command: >
      celery -A app.workers.celery_app worker
      --loglevel=info -Q ai -c 4 -Ofair
      --prefetch-multiplier=1
    env_file: [./backend/.env]
    volumes: [./backend:/app]
    depends_on: [pgbouncer, redis-broker, opensearch]

  celery-beat:                          # (GAP-2) Redbeat — Redis-backed schedule survives restart
    build: ./backend
    command: >
      celery -A app.workers.celery_app beat
      --loglevel=info
      --scheduler redbeat.RedBeatScheduler
    env_file: [./backend/.env]
    volumes: [./backend:/app]
    depends_on: [pgbouncer, redis-broker]
    # Single replica only — Redbeat stores schedule in redis-broker so restart gap is <30s
    # All cleanup jobs implement a last_run:{job_name} catch-up guard (R4-G12).

  frontend:
    build: ./frontend
    command: npm run dev
    env_file: [./frontend/.env.local]
    ports: ["3000:3000"]
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
    depends_on: [backend]

  flower:                               # Celery job monitoring UI — dev/staging only
    image: mher/flower:2.0
    command: celery flower --broker=redis://redis-broker:6379/0
    ports: ["5555:5555"]
    depends_on: [redis-broker]

volumes:
  postgres_data:
  redis_broker_data:
  redis_cache_data:
  opensearch_data:
  minio_data:
```

**Notes:**
- **Four** Celery worker services: `celery-default`, `celery-ingestion`, `celery-embeddings`, `celery-ai`. In production each becomes a separate ECS service or K8s Deployment, scaled independently by KEDA on its queue depth.
- All application traffic routes through PgBouncer port `5433`; direct PostgreSQL port `5432` is network-restricted in production.
- `celery-beat` uses `redbeat` (Redis-backed scheduler) to survive restarts without duplicate job execution. `pip install celery[redbeat]`.
- `DISABLE_SECURITY_PLUGIN: "true"` is development-only. Enable the OpenSearch security plugin in staging and production with TLS and basic auth.
- Do not expose Flower publicly in production — restrict to VPN or internal network.

---

## UAT / Staging Environment (M-2)

Staging mirrors production topology at reduced scale. Deploy via Docker Compose on a single VM (e.g., a single EC2 `t3.medium`) or a lightweight container platform such as Railway or Fly.io.

| Service | UAT Specification |
|---|---|
| PostgreSQL | Single instance, 4 GB RAM (`db.t3.medium` on RDS or equivalent) |
| PgBouncer | Single instance, `pool_size=20` (UAT scale); transaction mode |
| OpenSearch | Single-node, 2 GB heap (`OPENSEARCH_JAVA_OPTS: "-Xms2g -Xmx2g"`) |
| `redis-broker` | Single instance — Celery broker only (db=0); no Multi-AZ at UAT scale |
| `redis-cache` | Single instance — application cache (db=0) + translation cache (db=1, Phase 2); `allkeys-lru` |
| MinIO / S3 | Single MinIO instance, or a dedicated `ica-uat` prefix on the S3 bucket via `STORAGE_PROVIDER=s3` |
| FastAPI backend | 2 Uvicorn workers (`uvicorn --workers 2`) |
| Celery workers | 4 workers: `default` (c=4), `ingestion` (c=1), `embeddings` (c=2), `ai` (Phase 2 only) |
| Celery beat | Single instance with `redbeat` scheduler |
| Frontend | Next.js production build served via PM2, Vercel Preview, or nginx |
| Flower | Accessible on port 5555; restrict to VPN or IP allowlist |

**Key differences from production:**
- `DISABLE_SECURITY_PLUGIN: "true"` retained on OpenSearch (TLS not required for UAT)
- `ENVIRONMENT=staging` — controls Sentry context and log verbosity
- `NEXT_PUBLIC_DEMO_MODE=false` (same as production; MSW is disabled in all non-dev environments)
- No CloudFront / CDN; direct load balancer access is sufficient for UAT
- Database seeded with anonymised fixture data — **never copy production PII to UAT**

**UAT acceptance gate:** All 10 MVP acceptance criteria (MVP-1 through MVP-10, defined in the SAD Section 13.5) must pass in this environment before production promotion.

---

## CI/CD Pipeline (GAP-10)

GitHub Actions-based pipeline. Two workflows: `ci.yml` (all pull requests) and `cd.yml` (merges to `main`).

### CI Workflow — runs on every pull request

```
Step 1 — Code Quality (parallel jobs)
  ├── Backend:  ruff check backend/  +  mypy backend/app
  └── Frontend: eslint frontend/  +  tsc --noEmit

Step 2 — Tests (parallel jobs)
  ├── Backend unit tests:
  │     pytest backend/tests/unit -x --tb=short
  ├── Backend integration tests:
  │     docker-compose -f docker-compose.test.yml up -d   (postgres + redis + opensearch)
  │     alembic upgrade head
  │     pytest backend/tests/integration -x --tb=short
  │     docker-compose -f docker-compose.test.yml down
  └── Frontend tests:
        jest --ci --coverage

Step 3 — Build verification (parallel jobs)
  ├── Build backend Docker image (no push)
  └── Next.js build: next build (smoke-checks for type errors and missing pages)
```

### CD Workflow — runs on merge to `main`

```
Step 1 — Build and push images
  ├── docker build -t $ECR_REGISTRY/ica-backend:$GITHUB_SHA ./backend
  ├── docker push $ECR_REGISTRY/ica-backend:$GITHUB_SHA
  ├── docker build -t $ECR_REGISTRY/ica-frontend:$GITHUB_SHA ./frontend
  └── docker push $ECR_REGISTRY/ica-frontend:$GITHUB_SHA

Step 2 — Database migration (pre-deploy, BLOCKING; expand-contract pattern, NG-8)
  └── aws ecs run-task --overrides '{"containerOverrides":[{"command":["alembic","upgrade","head"]}]}'
      Waits for task completion. Pipeline ABORTS if migration fails.
      Old containers continue running — no downtime on migration failure.
      • All schema migrations use the expand-contract pattern:
          1. EXPAND   — ALTER TABLE ADD COLUMN nullable (non-locking)
          2. BACKFILL — Celery batch job fills new column for existing rows
          3. CONSTRAIN — ALTER TABLE ALTER COLUMN SET NOT NULL (fast)
          4. CONTRACT — remove old column in a later release
      • CREATE INDEX CONCURRENTLY mandatory for all production indices.
      • downgrade() function required on every Alembic file.

Step 3 — Deploy services (rolling update)
  ├── aws ecs update-service --service ica-backend --force-new-deployment
  ├── aws ecs update-service --service ica-celery-worker --force-new-deployment
  ├── aws ecs update-service --service ica-celery-beat --force-new-deployment
  └── Smoke test: GET $API_URL/api/v1/health → expect HTTP 200

Step 4 — Deploy frontend
  ├── aws s3 sync ./frontend/out s3://$STATIC_BUCKET --delete
  └── aws cloudfront create-invalidation --distribution-id $CF_ID --paths "/*"

Step 5 — Notify
  └── Slack message: success/failure with commit SHA, diff link, deployment duration

Step 6 — Cache warm-up (R5-G10, BACKGROUND)
  └── Trigger Celery 'cache_warmup_job' 5 minutes after deployment marker.
      Pre-loads top-50 search queries (from cache_warmup_queries table),
      top-20 non-English translations, top-20 hot entities into redis-cache.
      Rate-limited to 1 query/100ms to avoid self-DoS against OpenSearch.
      Search latency SLA is suspended for ~5 minutes post-deploy.
```

**Key rules:**
- Docker image tags use the full Git commit SHA (`$GITHUB_SHA`), never `latest`.
- `NEXT_PUBLIC_DEMO_MODE=false` is enforced in all CI/CD environment secrets — never committed to source.
- Rollback procedure: re-run the CD workflow targeting the previous commit SHA. For database rollbacks, run `alembic downgrade -1` manually after verifying the downgrade migration is safe.
- The `main` branch is protected: direct push is blocked; all merges require a passing CI run.

---

## Observability (GAP-16)

All observability components should be instrumented from day one, even in development. Observability is not optional — it is the only way to debug production issues and validate SLA compliance.

### Structured Logging

```python
# backend/app/core/logging.py
import structlog

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
```

Every log entry includes: `timestamp`, `level`, `logger`, `request_id` (from `X-Request-ID` header or UUID generated per request), `user_id` (from JWT when available), `trace_id` (from OpenTelemetry span context).

Log shipping: stdout in development (Docker Compose captures); AWS CloudWatch Logs via `awslogs` log driver in production. Never log PII (email, full name, document content).

### Metrics — Prometheus

```python
# backend/app/main.py
from prometheus_fastapi_instrumentator import Instrumentator
Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```

Install: `pip install prometheus-fastapi-instrumentator`

Key metrics exposed at `GET /metrics`:

| Metric | Type | Labels | Description |
|---|---|---|---|
| `http_request_duration_seconds` | Histogram | method, path, status_code | API request latency; use for SLA monitoring |
| `celery_task_duration_seconds` | Histogram | task_name, queue, status | Worker job execution time; identify slow jobs |
| `opensearch_query_duration_seconds` | Histogram | index, query_type | Search latency per index and query mode |
| `redis_cache_hits_total` | Counter | cache_type (search/translation) | Cache hit rate; indicates search performance health |
| `ai_queries_total` | Counter | outcome (generated/flagged/insufficient) | RAG pipeline outcome distribution |
| `moderation_queue_depth` | Gauge | content_type | Pending items per content type; trigger alerts if > threshold |
| `celery_queue_length` | Gauge | queue | Redis queue depth per Celery queue; used by KEDA for autoscaling |

**Grafana dashboards** (store as JSON in `grafana/dashboards/`):
- **API Performance**: p50/p95/p99 latency by endpoint; error rate; request volume
- **Worker Health**: queue depth per queue; job throughput; failure rate; DLQ count
- **Search**: cache hit rate; OpenSearch latency; BM25 vs k-NN distribution; slow query log
- **AI Usage**: RAG query volume; confidence score distribution; token consumption trend
- **Moderation**: queue depth trends; throughput per moderator; overdue item count (> 48h)

### Distributed Tracing — OpenTelemetry

```python
# backend/app/core/tracing.py
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor

tracer_provider = TracerProvider()
FastAPIInstrumentor.instrument_app(app, tracer_provider=tracer_provider)
SQLAlchemyInstrumentor().instrument()
RedisInstrumentor().instrument()
```

Install: `pip install opentelemetry-sdk opentelemetry-instrumentation-fastapi opentelemetry-instrumentation-sqlalchemy opentelemetry-instrumentation-redis opentelemetry-exporter-otlp`

Trace IDs are propagated to Celery tasks via task headers so a single user request can be traced from API → outbox → Celery worker → OpenSearch:

```python
from opentelemetry import trace, propagate
# In task dispatch:
carrier = {}
propagate.inject(carrier)
task.apply_async(headers={"traceparent": carrier.get("traceparent")})
```

Compatible trace receivers: Jaeger (dev), AWS X-Ray (prod), or any OTLP-compatible backend.

### Error Tracking — Sentry

```python
# backend/app/main.py
import sentry_sdk
if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENVIRONMENT,
        traces_sample_rate=0.1,
        send_default_pii=False,      # never send email, name, or query content to Sentry
    )
```

Frontend (`frontend/instrumentation.ts`):
```typescript
import * as Sentry from "@sentry/nextjs";
if (process.env.NEXT_PUBLIC_SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
    environment: process.env.NODE_ENV,
    tracesSampleRate: 0.1,
  });
}
```

Sentry is optional (disabled when `SENTRY_DSN` is unset) so development works without it. In production, all uncaught exceptions and slow transactions are captured with full stack traces and release version tagging.

---

## Production Deployment Architecture

### AWS Production Topology

All production services run on AWS managed infrastructure. The frontend is served via CloudFront; the backend API runs on ECS/EKS with an Application Load Balancer; Celery workers auto-scale via KEDA on Redis queue depth.

```
                    ┌──────────────────────────────────────────────────┐
                    │          CloudFront CDN  +  AWS WAF              │
                    │  • Next.js static assets (S3)                    │
                    │  • API cache: /categories /countries /tags (1h), │
                    │      /news?featured=true (5min)                  │
                    │  • OWASP Managed Rules + Known Bad Inputs        │
                    │  • 5MB body cap; geo & IP rules; /metrics block  │
                    └─────────────────┬────────────────────────────────┘
                                      │ HTTPS (TLS 1.2+, ACM cert)
                    ┌─────────────────▼────────────────────────────────┐
                    │     Application Load Balancer (ALB)              │
                    │     Body cap 5MB; idle timeout 300s (for SSE)    │
                    └─────────────────┬────────────────────────────────┘
                                      │
                    ┌─────────────────▼────────────────────────────────┐
                    │         AWS EKS Cluster                           │
                    │  FastAPI containers   (min 2, max 10; HPA)        │
                    │  PgBouncer            (transaction mode, pool=50) │
                    │  Celery — default     (KEDA: queue>50; min1 max8) │
                    │  Celery — ingestion   (KEDA: queue>5;  min1 max4) │
                    │  Celery — embeddings  (KEDA: queue>20; min1 max6) │
                    │  Celery — ai          (KEDA: queue>10; min0 max4) │
                    │  Celery beat          (single replica + Redbeat)  │
                    └──┬───────────────┬───────────────┬───────────────┘
                       │ via PgBouncer │               │
           ┌───────────▼──┐  ┌─────────▼──────────┐  ┌▼─────────────────────┐
           │  AWS RDS      │  │ ElastiCache         │  │AWS OpenSearch Svc    │
           │  PostgreSQL   │  │ • redis-broker      │  │3-node cluster (>500k │
           │  Multi-AZ +   │  │   (Multi-AZ HA)     │  │chunks); ISM policy + │
           │  read replica │  │ • redis-cache       │  │rollover aliases;     │
           │  pg_stat_stmts│  │   (allkeys-lru)     │  │snapshot DR (RTO ≤1h) │
           └───────────────┘  └────────────────────┘  └─────────────────────┘
                       │
           ┌───────────▼──┐  ┌─────────────────────┐  ┌──────────────────────┐
           │  AWS S3      │  │ SendGrid (primary) │  │  OpenAI API           │
           │ (direct PUT  │  │ AWS SES (fallback) │  │ + local fallback model│
           │  signed URL, │  │                    │  │ (circuit-breaker per  │
           │  lifecycle   │  │                    │  │  §12.9)               │
           │  rules)      │  │                    │  │                       │
           └──────────────┘  └────────────────────┘  └──────────────────────┘
```

**Secrets management:** All credentials and API keys are stored in AWS Secrets Manager or Parameter Store — never in source control or Docker images. ECS task definitions reference secret ARNs via `secrets` injection.

### Kubernetes-Ready Workload Table

The architecture is Kubernetes-ready without code changes. Use this table when migrating from ECS to EKS.

| Workload | K8s Resource | Scaling Mechanism & Thresholds (NG-16) | CPU req / limit | Mem req / limit | `terminationGracePeriodSeconds` |
|---|---|---|---|---|---|
| FastAPI API | `Deployment` + `HorizontalPodAutoscaler` | CPU target=70% **and** requests/min/pod > 500; min=2, max=10; scale-down stabilisation=300s | 250m / 1000m | 256Mi / 512Mi | 30 |
| PgBouncer | `Deployment` (HA pair) | Static — 2 replicas behind ClusterIP Service | 100m / 500m | 64Mi / 128Mi | 30 |
| Celery `default` | `Deployment` + `KEDA ScaledObject` | `redis-broker` queue length > **50 messages**; min=1, max=8; cooldown=60s | 250m / 500m | 256Mi / 512Mi | 180 |
| Celery `ingestion` | `Deployment` + `KEDA ScaledObject` | `redis-broker` queue length > **5 messages** (each Docling job ~120s); min=1, max=4; concurrency=2 per pod; `podAntiAffinity` preferred | 500m / 2000m | 512Mi / 2Gi | **180** (must exceed Docling 120s) |
| Celery `embeddings` | `Deployment` + `KEDA ScaledObject` | `redis-broker` queue length > **20 messages**; min=1, max=6; concurrency=4 per pod; `podAntiAffinity` preferred | 1000m / 4000m | 512Mi / 1Gi | 180 |
| Celery `ai` | `Deployment` + `KEDA ScaledObject` | `redis-broker` queue length > **10 messages**; min=**0** (scale-to-zero), max=4 | 500m / 2000m | 512Mi / 1Gi | 180 |
| Celery beat | `Deployment`, replica=1 + `PodDisruptionBudget` | No autoscaling — Redbeat-backed schedule in `redis-broker` survives restart (<30s gap) | 100m / 200m | 128Mi / 256Mi | 30 |
| PostgreSQL | AWS RDS Multi-AZ (preferred) — primary + read replica | Managed Multi-AZ failover; `pg_stat_statements` enabled; per-table autovacuum overrides | — | — | — |
| OpenSearch | AWS OpenSearch Service — 3-node at >500k chunks | ISM policy + rollover aliases; daily snapshots; RTO ≤1h via snapshot restore | — | — | — |
| `redis-broker` | AWS ElastiCache Multi-AZ | Managed automatic failover (RTO <60s) | — | — | — |
| `redis-cache` | AWS ElastiCache single-node | Self-healing; `allkeys-lru`; loss is recoverable | — | — | — |
| MinIO | Not used in production — replace with AWS S3 via `STORAGE_PROVIDER=s3` | S3 scales infinitely; lifecycle rules per NG-15 | — | — | — |
| Next.js frontend | Vercel or S3 + CloudFront | CDN-native; no pod scaling needed | — | — | — |

**Why `terminationGracePeriodSeconds: 180` for workers (R4-G05):** Docling tasks run up to 120s. KEDA scale-down sends SIGTERM; the worker must finish the in-flight task before SIGKILL. 180s = 120s + buffer. FastAPI pods use 30s (connection drain only).

**`podAntiAffinity` (preferred):** Added to `ingestion` and `embeddings` Deployments to spread CPU/memory-heavy workers across nodes — prevents OOMKill from co-located Docling (2Gi) and embedding (1Gi) pods.

### Production Environment Checklist

| Item | Requirement |
|---|---|
| OpenSearch security plugin | Enabled with TLS and basic auth (disabled in dev/UAT only); HTTPS with cert validation (NG-18) |
| `redis-broker` | ElastiCache Multi-AZ, AOF enabled; `rediss://` TLS (NG-18); separate from `redis-cache` (GAP-1) |
| `redis-cache` | ElastiCache single-node, `allkeys-lru`, no AOF; `rediss://` TLS |
| PgBouncer | Deployed as Service in front of RDS; `pool_size=50`; direct PG port 5432 network-restricted (GAP-7) |
| PostgreSQL TLS | `sslmode=require` in all `DATABASE_URL` strings (NG-18); ACM-managed certs |
| `pg_stat_statements` | Enabled via RDS parameter group: `shared_preload_libraries=pg_stat_statements`, `pg_stat_statements.max=10000`, `pg_stat_statements.track=top` (R5-G11) |
| Autovacuum overrides | Per-table on `outbox_events`, `notifications`, `revoked_tokens`, `posts` (R5-G06) |
| AWS WAF | Attached to CloudFront with OWASP Managed Rules + Known Bad Inputs + 5MB body cap (NG-12) |
| CloudFront API caching | Cache behaviours for `/api/v1/categories`, `/countries`, `/tags` (TTL 1h) and `/news?featured=true` (TTL 5min); auth-required paths pass-through (GAP-6) |
| S3 bucket policy | Private; no public access; versioning enabled; cross-region replication for documents bucket; **three lifecycle rules** for retracted/rejected/orphaned files (NG-15) |
| S3 upload pattern | Direct-to-S3 signed PUT URL — API never receives file bytes (NG-14) |
| CORS | `FRONTEND_URL` set to exact production domain — no wildcard |
| `NEXT_PUBLIC_DEMO_MODE` | `false` — enforced in CI/CD secrets, never committed |
| JWT signing keys | RS256 key pair generated per environment; stored in Secrets Manager |
| Revoked-token cache | JWT logout writes both `revoked_tokens` table AND `redis-cache` key `revoked:{jti}` with TTL = remaining token lifetime (NG-1) |
| Flower | Not deployed in production — use Grafana + Celery metrics instead |
| `DISABLE_SECURITY_PLUGIN` | Removed entirely from production OpenSearch config |
| Database migration | **Expand-contract pattern mandated** (NG-8): expand → backfill → constrain → contract; `CREATE INDEX CONCURRENTLY` required; `downgrade()` required on all Alembic migrations |
| OpenSearch indexing | OpenSearch Bulk API mandated (`helpers.bulk()`, max 5MB / 200 ops); `refresh_interval=30s` during bulk ingestion, `1s` steady state (M-6) |
| OpenSearch ISM | Policy applied: Hot → Warm (90d/30GB) → Cold (1y) → Delete (retracted >7y); rollover aliases on `ica_news` and `ica_posts` (R5-G04) |
| Index alias strategy | All regional indices behind shared aliases (`ica_documents_all`, etc.); SearchService queries aliases only (R4-G08) |
| K8s pod resources | All workloads have CPU/memory requests + limits; `terminationGracePeriodSeconds: 180` on workers (R4-G04, R4-G05) |
| Outbox stuck recovery | `outbox_stuck_recovery_job` (every 10 min) resets `IN_PROGRESS > 10 min` back to `PENDING` (R4-G05) |
| Celery reliability | `task_acks_late=True`, `reject_on_worker_lost=True`, `visibility_timeout=3600`, `task_ignore_result=True`, per-queue `prefetch_multiplier` (R4-G10, R5-G02, R5-G03) |
| Health probes | `/health/live` + `/health/ready` split (NG-17) |
| Log shipping | `awslogs` driver on all ECS tasks → CloudWatch Logs |
| SLO alerts | All §12.6 alerts wired to PagerDuty (P0) / Slack (P1+): outbox depth, DLQ, search latency, OpenSearch cluster/disk/JVM, PG replica lag, PG dead-tuple ratio, slow-query p95 (R4-G09, R5-G06, R5-G08, R5-G11) |

---

## Design Decisions and Clarifications

The following decisions resolve open questions identified during architecture review. These are binding for implementation — update this section if any decision changes.

---

### DC-1: Who can set `is_verified=true` on an answer?

**Decision:** Any **Moderator** (role = `moderator`) or **Admin** can call `PATCH /answers/{id}/verify`. No separate sub-role or credentialled-lawyer designation is required at the platform level — moderator role is the trust boundary for answer verification.

**Implementation impact:**
- `PATCH /answers/{id}/verify` is already role-gated to `A, M` in Module 6.
- `answers.verified_by` records the actor UUID for audit purposes.
- `is_verified=true` raises the RAG retrieval weight for the Q&A pair in LangGraph (weight 0.8 vs unverified).
- No schema changes required.

---

### DC-2: Content visibility — platform-wide or organisation-scoped?

**Decision:** All approved content (documents, questions, news, posts) is **visible to all member organisations** on the platform. Organisation membership controls onboarding (invite quota, `max_users`) and contribution attribution, but does not gate read access to approved content. Any authenticated member, regardless of organisation, can browse and search all approved content.

**Implementation impact:**
- Content list endpoints (`GET /documents`, `GET /questions`, etc.) do not apply an `org_id` filter for member reads.
- The `org_id` field is recorded on contributions for attribution and analytics only.
- If org-scoped content siloing is needed in future, an `org_visibility` field (`public` | `org_only`) can be added to content tables without breaking the current model — this is explicitly deferred to Phase 3.
- No schema changes required for MVP.

---

### DC-3: External URL documents — ingestion behaviour

**Decision:** When a document is submitted as an external URL (i.e. `external_url` is set and `file_key` is null), the record is stored as **metadata-only**. The Docling ingestion pipeline is **not triggered**. The document is not chunked, not embedded, and not indexed into OpenSearch.

**Rationale:** Crawling and scraping external URLs requires web scraping infrastructure, robots.txt compliance, and ongoing link-rot management — all out of scope for MVP. Embedding third-party content also raises copyright concerns.

**Implementation impact:**
- `document_ingestion_job` must check whether `file_key` is null before invoking Docling. If null, the job exits after writing a `document.approved` outbox event (which triggers notifications only — no chunking or indexing).
- External URL documents will **not appear in search results** (no OpenSearch entry). They are accessible only via direct browse (`GET /documents` list with metadata).
- The document detail page (`GET /documents/{id}`) should surface the external URL as a clickable link.
- A `source_type` field (`uploaded` | `external_url`) should be added to the `documents` table to make this distinction explicit in API responses and the moderator queue UI.
- Phase 2 consideration: if web scraping is introduced, `source_type=external_url` documents can be retroactively ingested by re-triggering `document_ingestion_job` with a scrape mode.

**Schema change required:**
```sql
ALTER TABLE documents
  ADD COLUMN source_type TEXT NOT NULL DEFAULT 'uploaded'
  CHECK (source_type IN ('uploaded', 'external_url'));
```

---

### DC-4: Include `ica_news` in RAG retrieval pipeline

**Decision:** The LangGraph RAG pipeline (`/ai/ask`) **includes `ica_news`** as a retrieval source, with a lower priority weight than documents and verified Q&A.

**Source priority weights (updated):**

| Source | Index | RRF Weight | Condition |
|---|---|---|---|
| Document chunks | `ica_document_chunks` (`law_status=active`) | 1.0 | Always retrieved first |
| Verified Q&A pairs | `ica_questions` (`is_verified=true`) | 0.8 | Retrieved in parallel with docs |
| Approved news articles | `ica_news` | 0.4 | Retrieved when doc + Q&A combined hits < 5 |
| Community posts | `ica_posts` | 0.3 | Retrieved only when doc + Q&A + news combined hits < 3 |

**Implementation impact:**
- Add a **News Retriever Node** to the LangGraph workflow, placed after the Verified Q&A Retriever Node and before the Source Merger.
- The node runs a k-NN query against `ica_news` using the same pre-filters (country, category). Invoked only when doc + Q&A combined hits < 5.
- Update the Source Merger & Ranker Node to include news results with weight 0.4 in the RRF calculation.
- Update the Audit Logger Node to record `ica_news` source IDs when news articles contribute to a generated answer.
- `ica_news` index already carries `content_vector` (k-NN field) — no index schema changes required.
- The `news_broadcast_job` and approval pipeline for news are unchanged.

**Updated LangGraph node sequence:**
```
Intent Classifier
    ↓              ↓
Doc Retriever   Verified Q&A Retriever
    ↓              ↓
        [hits < 5?]
             ↓ yes
        News Retriever (ica_news)
             ↓
        [hits < 3?]
             ↓ yes
        Post Retriever (ica_posts)
             ↓
    Source Merger & Ranker (weighted RRF)
        ↓
    Confidence Scorer → ...
```

---

### DC-5: Docling failure path for approved documents

**Decision:** If `document_ingestion_job` fails to extract text from an approved document (due to encryption, corruption, or OCR failure beyond the 120-second timeout), the document is **rejected** and both the assigned **Moderator** and the platform **Admin** are notified. The submitting member is also notified.

**Rationale:** The platform's primary purpose is to build a searchable legal knowledge corpus. A document that cannot be parsed cannot be searched or used in RAG retrieval. Retaining it as an approved but unsearchable record would silently degrade corpus quality. Rejecting it with a clear reason gives the submitter the opportunity to re-upload a readable version.

**Implementation impact:**

In `document_ingestion_job`, on Docling failure (exception or timeout):

1. Set `documents.status = 'rejected'` in PostgreSQL.
2. Write to `moderation_logs`:
   - `actor_id` = system user UUID (a dedicated `system` user created at seed time)
   - `action` = `'reject'`
   - `entity_type` = `'document'`
   - `entity_id` = document UUID
   - `remarks` = `'Automatic rejection: Docling failed to extract text. Reason: {error_detail}. Please re-upload a readable PDF.'`
3. Write three `outbox_events` rows (atomic with the status update):
   - `notify.submitter` — notifies the document submitter that their upload was rejected with reason
   - `notify.moderator` — notifies the moderator who approved the document
   - `notify.admin` — notifies all Admin-role users via `notification_dispatch_job`
4. Do **not** trigger chunking, embedding, or OpenSearch indexing.
5. The document is excluded from all search results (no OpenSearch entry was created).

**Seed data required:** Add a `system` user row (role=`admin`, status=`active`, email=null) at migration time. This user is the actor for all automated moderation actions.

```sql
-- Applied in initial Alembic migration (after organizations seed)
INSERT INTO users (id, email, full_name, role, org_id, status)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  NULL,
  'System',
  'admin',
  (SELECT id FROM organizations LIMIT 1),
  'active'
);
```

**Notification message templates:**

| Recipient | Message |
|---|---|
| Submitter | "Your document '{title}' could not be processed. The file appears to be encrypted or corrupted and text could not be extracted. Please re-upload a readable PDF version." |
| Moderator | "A document you approved ('{title}', submitted by {member_name}) was automatically rejected because text extraction failed. The submitter has been notified." |
| Admin | "Docling ingestion failure: document '{title}' (ID: {id}) rejected after extraction failure. Error: {error_detail}. Review if this indicates a systemic issue." |

---

## Scalability & Production Hardening (SAD v1.5 Alignment)

This section consolidates the 57 production-readiness items resolved during five scalability review rounds against SAD v1.0. Each subsection is binding for implementation. References to SAD section numbers (`§6.4`, `§12.9`, etc.) are pointers into the architecture document.

---

### §5.10 — Transactional Outbox (Hardened)

The outbox pattern guarantees at-least-once delivery of domain events to Celery workers. Hardening across five review rounds:

**State machine (NG-11):** `PENDING → IN_PROGRESS → PUBLISHED`, or `IN_PROGRESS → FAILED → DEAD_LETTER`. `DEAD_LETTER` rows trigger Prometheus alert `outbox_dead_letter_total > 0` (PagerDuty) before nightly deletion.

**Poll query (R5-G01 priority-ordered):**
```sql
SELECT * FROM outbox_events
WHERE status = 'PENDING'
ORDER BY priority ASC, created_at ASC
LIMIT 10
FOR UPDATE SKIP LOCKED;
```
- Concurrent pollers cannot claim the same event (P0 idempotency).
- Each task dispatched with `task_id=str(outbox_event.id)` — Celery broker rejects duplicate task IDs.
- All downstream jobs (`notification_dispatch_job`, `search_index_job`, `post_index_job`, etc.) are **idempotent** — re-execution produces no side effects.

**Priority taxonomy (R5-G01):**

| Priority | Use | Event types |
|---|---|---|
| 0 — Critical | Compliance / safety | `document_retracted`, `content_flagged`, `user_deactivated`, moderation Reject/Flag/Retract |
| 5 — Default | Approval pipeline | `document_approved`, `question_approved`, `answer_posted`, `search_index_job`, `embedding_generation_job` |
| 10 — Low | Fan-out / audit | `notification_dispatch`, `search_cache_invalidate`, `ai_query_audit` |

**Stuck-event recovery (R4-G05):** `outbox_stuck_recovery_job` runs every 10 min and resets `IN_PROGRESS` rows older than 10 minutes back to `PENDING`. Safe to run concurrently with the main poller (`FOR UPDATE SKIP LOCKED` prevents double-claiming).

**Payload discipline (R4-G11):** `payload` JSONB capped at 4KB by `CHECK` constraint and a shared `OutboxPayload` Pydantic root validator. Allowed fields: `{entity_id, entity_type, old_status, new_status, actor_id, country, category_id}`. Forbidden: document bodies, chunk text, PDF bytes.

**Cleanup (GAP-4):** Nightly `outbox_events_cleanup_job` hard-deletes `WHERE status IN ('PUBLISHED','DEAD_LETTER') AND published_at < NOW() - INTERVAL '7 days'`. AI audit rows (`event_type LIKE 'ai_query.%'`) retained 30 days. Catch-up guard (R4-G12) ensures the job runs after any Beat outage.

---

### §5.12 — Entity Read-Through Cache (NEW, R5-G07)

Search cache covers search-query results. CloudFront caches reference data. But individual entity reads previously hit PostgreSQL every time — a trending document could pull thousands of reads per minute. The entity cache plugs this gap.

| Property | Value |
|---|---|
| Storage | `redis-cache` db=0 |
| Key | `entity:{type}:{id}` — `type ∈ {document, question, answer, news, knowledge_article}` |
| TTL | 300 seconds |
| Cacheable | Approved, non-personalised entities only |
| Not cacheable | Per-user responses (`/notifications`, `/documents/my`, `/auth/me`) |
| Invalidation | `search_cache_invalidate_job` extended to also `DEL entity:{type}:{id}` for affected scope, in the same Redis pipeline |
| Stampede protection | `SETNX lock:entity:{type}:{id}` (TTL 5s) prevents thundering-herd on cache expiry; second caller waits for first to populate |
| Auth | JWT + RBAC checks always run **before** returning cached content |

SLA (§12.3): cache-hit ≤30ms; cache-miss ≤100ms.

---

### §6.4 — Database Index Strategy (NEW, NG-6 + R4-G06 + R5-G01)

15 mandatory indices. Each is `CREATE INDEX CONCURRENTLY` in production. Listed in priority order:

| # | Table | Index | Priority | Serves |
|---|---|---|---|---|
| 1 | `outbox_events` | `(status, priority, created_at)` partial WHERE `status IN ('PENDING','IN_PROGRESS')` | CRITICAL | Outbox poller; priority-ordered dispatch |
| 2 | `notifications` | `(user_id, is_read, created_at DESC)` | CRITICAL | `GET /notifications`; `unread-count`; cleanup job |
| 3 | `notification_preferences` | `(country_code, category_id)` | CRITICAL | `news_broadcast_job` fan-out subscriber lookup |
| 4 | `documents` | `(status, country, category_id, created_at DESC)` | CRITICAL | `GET /documents` list + moderation queue |
| 5 | `questions` | `(status, country, category_id, created_at DESC)` | CRITICAL | `GET /questions` list + moderation queue |
| 6 | `posts` | `(status, created_at DESC, id DESC)` | CRITICAL | `GET /posts` keyset pagination |
| 7 | `revoked_tokens` | `(expires_at)` B-tree | High (R4-G06) | Nightly `DELETE WHERE expires_at < NOW()` |
| 8 | `documents` | `(submitted_by, status)` | High | `GET /documents/my` |
| 9 | `questions` | `(assigned_to, status)` | High | Expert assignment view |
| 10 | `answers` | `(question_id, is_accepted)` | High | Answer thread + accepted marker |
| 11 | `news_articles` | `(status, is_featured, country, created_at DESC)` | High | News list + featured-pin lookup |
| 12 | `moderation_logs` | `(entity_type, entity_id, created_at DESC)` | High | Audit history for an entity |
| 13 | `content_versions` | `(entity_type, entity_id, version_number DESC)` | High | Version history endpoints |
| 14 | `invites` | `(org_id, expires_at, used_at)` | High | Invite list + quota enforcement |
| 15 | `post_likes` | `(post_id, user_id)` unique | High | Idempotent like toggle |

Missing index #3 alone makes every news broadcast a full table scan. Missing index #4–6 makes the moderation queue unusable at volume.

---

### §6.5 — PostgreSQL Maintenance & Observability (NEW, R5-G06 + R5-G11)

**Per-table autovacuum overrides (R5-G06)** — applied via Alembic migration `ALTER TABLE ... SET`:

| Table | `autovacuum_vacuum_scale_factor` | Extra |
|---|---|---|
| `outbox_events` | 0.05 | `autovacuum_vacuum_cost_delay=10ms` |
| `notifications` | 0.05 | — |
| `revoked_tokens` | 0.1 | — |
| `posts` | 0.1 | — |
| `moderation_logs`, `content_versions` | default (append-only) | — |

SLO alert: `pg_dead_tuple_ratio{table="outbox_events"} > 0.10 for 30m` → Slack.

**`pg_stat_statements` (R5-G11)** — RDS parameter group:
- `shared_preload_libraries=pg_stat_statements`
- `pg_stat_statements.max=10000`
- `pg_stat_statements.track=top`

Daily `pg_stats_export_job` exports top-20 slowest query templates to CloudWatch. SLO alert: `pg_query_p95_latency{queryid=...} > 100ms for 30m` → Slack. Quarterly review documented in operational runbook.

**Read replica lag SLA (R5-G08):**
- Lag < 10s → `DashboardService` routes to replica
- Lag ≥ 10s → fallback to primary (consistency over performance)
- `replica_lag_monitor_job` (every 60s) caches `pg_last_xact_replay_timestamp()` delta in `redis-cache:pg_replica_lag_seconds`
- Alert `pg_replica_lag_seconds > 30 for 5m` → Slack
- Counter `dashboard_replica_lag_fallback_total` tracks fallback frequency

---

### §7.1 — Authentication Hardening (NG-1, R4-G06)

**Revoked-token Redis cache (NG-1).** Every authenticated request must verify the JWT's `jti` is not revoked. PostgreSQL lookup on every request was a critical hot read (~10k req/30min cycle on the primary write instance).

**Fix:**
- JWT logout writes the JTI to **both** `revoked_tokens` table AND `redis-cache` key `revoked:{jti}` with TTL = token's remaining lifetime (max 30 min for access tokens)
- `get_current_user` checks Redis first (≤1ms). Hit = revoked. Miss = valid (negative caching: only revoked tokens are cached)
- On `redis-cache` failure, falls back to the PostgreSQL table gracefully

Combined with `revoked_tokens(expires_at)` index (R4-G06), nightly pruning is a fast index scan rather than a full table scan.

---

### §7.4 — API Security (Hardened: GAP-3, NG-12, NG-18, R5-G09)

| Control | Mechanism | Notes |
|---|---|---|
| Rate limiting (GAP-3) | `slowapi` + `redis-cache` storage_uri | Shared counter across all replicas; per-endpoint numeric limits (table above) |
| AWS WAF (NG-12) | Attached to CloudFront | OWASP Managed Rules + Known Bad Inputs; IP rate rule (>100 4xx in 5min); SQLi/XSS query-string patterns; geo-restriction if compliance requires; `/metrics` internal-only enforcement |
| Request body cap (R5-G09) | **Three layers**: WAF (5MB on `/api/*`) → ALB (5MB) → FastAPI middleware (100KB default per endpoint; 1MB for bulk/batch) | File upload path explicitly exempted (direct-to-S3 bypasses the API) |
| Service-to-service TLS (NG-18) | `sslmode=require` (PG), HTTPS+cert validation (OpenSearch), `rediss://` (Redis) | Certificates managed via AWS Certificate Manager |
| File upload limits (NG-14) | Signed-URL `content-length-range` constraint on S3 PUT | API never receives file bytes |

---

### §8.7 — Embedding Model Migration Playbook (R5-G12)

Switching the embedding model without a coordinated cut-over causes silent search-quality collapse — cross-model vectors are not comparable. The 6-step playbook:

| Step | Operation | Duration |
|---|---|---|
| 1. Add v2 field | Partial OpenSearch mapping update — `chunk_vector_v2` field added (non-breaking) | Minutes |
| 2. Dual-write | Set `EMBEDDING_DUAL_WRITE=true` — new content embeds both vectors | Deploy time |
| 3. Backfill | `embedding_backfill_job` (rate-limited Celery beat) re-embeds existing chunks under the new model | Hours–days |
| 4. Verify | Shadow-query comparison: top-K against both vectors; quality metrics (recall@10, MRR) | Manual review |
| 5. Cut-over | Set `EMBEDDING_MODEL_VERSION=v2` — `SearchService` queries `chunk_vector_v2` (reversible) | Minutes |
| 6. Cleanup | After 7-day stability window: drop old field; turn off dual-write | Days |

Without this playbook, an emergency model change (provider deprecation) requires multi-day re-index with active platform degradation.

---

### §8.9 — Search Cache Invalidation (Hardened: R4-G01, R4-G02)

See expanded "Cache invalidation" subsection in §10 Redis Search Result Cache above. Two key invariants:

1. **No O(keyspace) scans.** Cache keys are tracked in a Redis Set per content scope (`scope:country:{c}:category:{cat}`). Invalidation does `SMEMBERS` + pipelined `DEL` — O(keys in that scope only).
2. **No stale-reseeding race.** Cache invalidation runs as the **last step of a Celery `chain()`** — `search_index_job → opensearch_refresh_job → search_cache_invalidate_job`. The cache is never cleared until `POST /<index>/_refresh` returns 200, guaranteeing the next search query sees fresh OpenSearch data.

---

### §8.10 — OpenSearch Index Lifecycle Management (NEW, R5-G04 + R4-G07 + R4-G08 + M-6)

**Bulk API mandate (R4-G07).** All indexing jobs (`search_index_job`, `post_index_job`, `qa_embedding_job`, `embedding_generation_job`) MUST use `opensearch-py` `helpers.bulk()`. Individual `PUT /_doc` calls are forbidden. Bulk request size capped at 5MB or 200 operations per call. `helpers.bulk()` handles automatic chunking and partial-failure retry internally.

**HNSW parameters (M-3):** `engine=lucene`, `space_type=cosinesimil`, `m=16`, `ef_construction=512`, `ef_search=256`.

**Refresh interval (M-6):** `refresh_interval=30s` during bulk ingestion, `1s` in steady state. Toggled by `search_index_job` around `helpers.bulk()` invocations.

**ISM policy (R5-G04):**

| Phase | Trigger | Action |
|---|---|---|
| Hot | New writes | Full replicas; queryable; default refresh_interval |
| Warm | Index age > 90d OR primary shard > 30GB | Drop replicas to 0; `force_merge` to 1 segment; `refresh_interval=60s` |
| Cold | Index age > 1y | Move to Ultra Warm or close index |
| Delete | `law_status=retracted` for > 7y | Auto-delete (aligns with §3.16 S3 lifecycle) |

**Rollover aliases** for time-series indices (`ica_news`, `ica_posts`): write alias rolls to new index when `size > 30GB OR age > 90d OR doc count > 10M`. Read alias spans all rolled-over indices.

**Index alias strategy for regional split (R4-G08):** All regional indices registered under shared aliases (`ica_documents_all`, `ica_document_chunks_all`, `ica_questions_all`, `ica_news_all`). `SearchService` ALWAYS queries the alias — never an individual index name. Adding a new region is a pure ops action (`POST /_aliases`) with zero application code changes.

**Reindex playbook for `ica_documents` / `ica_document_chunks`** (not time-series): create new index with target shard count → background `_reindex` → alias swap → cleanup.

**Snapshot DR (NG-10):** Daily automated snapshots to S3 at 02:00 UTC; 7-day retention; quarterly restore test required. RTO ≤1h via snapshot restore. Full re-index from PostgreSQL is a fallback only (~17h at 2M chunks — does NOT meet ≤4h SLA on its own).

---

### §11.9 — Notification Badge Load Mitigation (R5-G05)

Naive `GET /notifications/unread-count` polling at 30s × 5,000 sessions = ~167 req/s sustained load, consuming ~5 vCPU continuously. **Polling intervals < 60s are prohibited** (§12.1 rule).

**MVP — Piggyback header.** Every authenticated response includes `X-Notification-Unread-Count` header. Value read from `redis-cache:unread:{user_id}` (TTL 60s; invalidated by `notification_dispatch_job` and `PATCH /notifications/{id}/read`). Frontend reads from the header — no dedicated polling endpoint required.

**Phase 3 — SSE.** `GET /notifications/stream` (Server-Sent Events) pushes badge count and notification events on a long-lived HTTP connection. ALB idle timeout tuned to 300s. Degrades gracefully to the header path.

---

### §12.6 — SLO & Observability Alert Rules

All alerts emit to Prometheus AlertManager and route to PagerDuty (P0) or Slack (P1+).

| Alert | Expression | Severity | Source |
|---|---|---|---|
| Search p95 high | `histogram_quantile(0.95, http_request_duration_seconds{path="/search"}) > 1.5 for 10m` | P1 — Slack | SLA budget |
| Outbox backlog | `outbox_pending_count > 1000 for 10m` | P1 — Slack | §5.10 |
| Outbox dead-letter | `outbox_dead_letter_total > 0` | P0 — PagerDuty | GAP-4 |
| OpenSearch cluster status | `opensearch_cluster_status != "green" for 5m` | P0 — PagerDuty | R4-G09 |
| OpenSearch disk usage | `opensearch_disk_usage_percent > 85 for 15m` | P1 — Slack | R4-G09 |
| OpenSearch JVM heap | `opensearch_jvm_heap_used_percent > 85 for 10m` | P1 — Slack | R4-G09 |
| PG replica lag | `pg_replica_lag_seconds > 30 for 5m` | P1 — Slack | R5-G08 |
| PG dead-tuple ratio | `pg_dead_tuple_ratio{table="outbox_events"} > 0.10 for 30m` | P2 — Slack | R5-G06 |
| PG slow query | `pg_query_p95_latency{queryid=...} > 100ms for 30m` | P2 — Slack | R5-G11 |
| Celery DLQ growing | `celery_dead_letter_total > 0` | P0 — PagerDuty | §5.10 |
| Moderation overdue | `moderation_queue_depth{age>48h} > 0` | P2 — Slack | Product SLA |

**Trace propagation:** `X-Request-ID` set by ALB and propagated through OpenTelemetry. Celery task dispatch injects `traceparent` into task headers so a single user request can be traced from API → outbox → worker → OpenSearch.

---

### §12.7 — Backup & DR (Hardened: SR-6, NG-10)

| Component | Backup | RPO | RTO |
|---|---|---|---|
| PostgreSQL (RDS Multi-AZ) | Automated snapshots + PITR + read replica | <1 min | <5 min (managed failover) |
| `redis-broker` | Multi-AZ replication + AOF persistence | <1 min | <60s (automatic failover) |
| `redis-cache` | None — self-healing on restart | n/a | n/a (cache miss is recoverable) |
| OpenSearch | Daily snapshots to S3 (02:00 UTC); 7-day retention; quarterly restore test | <24h | **≤1h via snapshot restore** (NG-10) |
| S3 | Bucket versioning + cross-region replication | <15 min | <5 min |

---

### §12.9 — External Dependency Circuit Breakers (NEW, GAP-8)

| Dependency | Retry policy | Circuit-breaker fallback |
|---|---|---|
| OpenAI — embeddings | 3 retries (2s, 4s, 8s) → DEAD_LETTER | Fall back to `all-MiniLM-L6-v2` local model via `EMBEDDING_FALLBACK_PROVIDER` |
| OpenAI — LLM | 2 retries → low-confidence path | Return `pending_expert_review` to member |
| Translation API | 3 retries → cache `_UNAVAILABLE` for 1h | Proceed with original query; notify member |
| SendGrid / SES | 3 retries → DEAD_LETTER | Switch to `EMAIL_FALLBACK_PROVIDER`; in-app notification already written |
| Docling | 1 attempt, 120s timeout | Automatic rejection via DC-5 |

Implemented via `tenacity` + `pybreaker`. Each dependency exposes a Prometheus circuit-state gauge (`closed | half_open | open`) for §12.6 dashboards.

---

### Gap Resolution Index

| Gap ID | Round | Where addressed in this plan |
|---|---|---|
| GAP-1 Redis split | R1 | Tech Stack; env vars; Docker Compose; Production diagram; K8s table |
| GAP-2 Beat HA via Redbeat | R1 | Docker Compose `celery-beat`; K8s table |
| GAP-3 Shared rate limiter | R1 | Security Configuration → Rate Limiting (`redis-cache` storage) |
| GAP-4 Outbox cleanup | R1 | Background Jobs `outbox_events_cleanup_job`; §5.10 |
| GAP-5 Docling `ingestion` queue | R1 | Background Jobs queue table; Docker Compose `celery-ingestion` |
| GAP-6 CloudFront API caching | R1 | Production diagram; Production Checklist |
| GAP-7 PgBouncer deployed | R1 | Tech Stack; Docker Compose `pgbouncer`; K8s table; env vars |
| GAP-8 Circuit breakers | R1 | §12.9 above; env vars (`EMBEDDING_FALLBACK_PROVIDER`, etc.) |
| GAP-9 Translation cache TTL=7d | R1 | §11 Multi-Language; `query_translation_cache_job` |
| M-1 `/metrics` protection | R1 | Module 15 endpoint; Production Checklist |
| M-2 Dashboard on read replica | R1 | env vars (`ANALYTICS_DATABASE_URL`); §6.5 replica lag SLA |
| M-3 HNSW params | R1 | §8.10 |
| M-4 Platform config cache | R1 | Tech Stack `redis-cache` line |
| M-5 Notifications archival | R1 | `notification_cleanup_job`; index #2 in §6.4 |
| M-6 Refresh interval tuning | R1 | §8.10 |
| SR-1…SR-9 Stale references | R2/R3 | Tech Stack, env vars, architecture diagram, background pipeline, production diagram |
| NG-1 Revoked token cache | R2 | §7.1 above |
| NG-2 `post_index_job` | R2 | Background Jobs table |
| NG-3 News fan-out batching | R2 | `news_broadcast_job` description |
| NG-4 `posts.likes_count` strategy | R2 | Key Design Decisions footnote — Phase 1/2: `UPDATE` row lock or `SELECT FOR UPDATE SKIP LOCKED`; Phase 3: Redis counter `likes:{post_id}` flushed every 60s |
| NG-5 Cursor pagination | R2 | Pagination Standards section |
| NG-6 Index strategy | R3 | §6.4 above |
| NG-7 `content_versions.snapshot` cap | R3 | Schema CHECK constraint ≤2KB |
| NG-8 Expand-contract migrations | R3 | CD Workflow Step 2 |
| NG-9 N+1 prevention | R3 | (See "Repository policy" below) |
| NG-10 OpenSearch snapshot RTO | R3 | §8.10 + §12.7 |
| NG-11 Outbox idempotency | R3 | §5.10 above |
| NG-12 AWS WAF | R3 | §7.4 above; Production Checklist |
| NG-13 Partitioning | R3 | Schema `moderation_logs PARTITION BY RANGE` |
| NG-14 Direct-to-S3 upload | R3 | File Upload Security section (rewritten) |
| NG-15 S3 lifecycle rules | R3 | File Upload Security section |
| NG-16 KEDA/HPA thresholds | R3 | K8s workload table |
| NG-17 Health probe split | R3 | Module 15 endpoints |
| NG-18 Service-to-service TLS | R3 | env vars (`sslmode=require`, `rediss://`); §7.4 |
| R4-G01 Cache scope Set | R4 | §8.9 above |
| R4-G02 Refresh-before-invalidate chain | R4 | §8.9; `opensearch_refresh_job` |
| R4-G03 PgBouncer `pool_size=50` | R4 | Tech Stack; Docker Compose |
| R4-G04 K8s pod resources | R4 | K8s workload table |
| R4-G05 Graceful shutdown + stuck recovery | R4 | K8s table `terminationGracePeriodSeconds=180`; `outbox_stuck_recovery_job` |
| R4-G06 `revoked_tokens(expires_at)` index | R4 | §6.4 row #7 |
| R4-G07 Bulk API | R4 | §8.10 |
| R4-G08 Index aliases | R4 | §8.10 |
| R4-G09 OpenSearch alerts | R4 | §12.6 |
| R4-G10 Celery reliability config | R4 | Celery Reliability Configuration table |
| R4-G11 Outbox payload 4KB cap | R4 | Schema CHECK + `OutboxPayload` validator |
| R4-G12 Beat catch-up guard | R4 | `last_run:{job_name}` Redis key on each cleanup job |
| R5-G01 Outbox priority | R5 | Schema + §5.10 |
| R5-G02 Per-queue prefetch | R5 | Celery queue table; Docker Compose worker commands |
| R5-G03 `task_ignore_result` | R5 | Celery Reliability Configuration table |
| R5-G04 OpenSearch ISM | R5 | §8.10 |
| R5-G05 Notification badge piggyback | R5 | §11.9 above; Module 10 endpoints |
| R5-G06 Autovacuum overrides | R5 | §6.5 |
| R5-G07 Entity cache | R5 | §5.12 above |
| R5-G08 Replica lag SLA | R5 | §6.5 |
| R5-G09 Body size limit | R5 | §7.4 above |
| R5-G10 Cache warm-up | R5 | CD Workflow Step 6 |
| R5-G11 `pg_stat_statements` | R5 | §6.5; Production Checklist |
| R5-G12 Embedding migration | R5 | §8.7 above; env vars (`EMBEDDING_DUAL_WRITE`, `EMBEDDING_MODEL_VERSION`) |

---

### Repository / N+1 Policy (NG-9)

Mandatory for all backend code under `backend/app/repositories/` and `backend/app/services/`:

- Every list endpoint MUST use `selectinload()` or `joinedload()` on every relationship field accessed in the response schema
- Code review checklist: list endpoints verified with `SQLAlchemy echo=True` logging to confirm ≤2 queries per request
- Bare `relationship` access inside a response loop is a **blocking** review issue
- New repository methods returning lists default to `selectinload` on `.options(...)`

A `GET /documents` returning 50 documents with `category.name` traversal must issue 2 queries (the list + a single `IN (...)` for categories), not 51.

---

*End of Scalability & Production Hardening section.*
