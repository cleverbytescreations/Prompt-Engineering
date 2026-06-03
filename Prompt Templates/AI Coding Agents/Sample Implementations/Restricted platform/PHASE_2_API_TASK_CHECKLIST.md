# Implementation Task Checklist (API) — Phase 2

> Scope: Phase-2 additions per SAD §14.1 — AI layer (LangGraph RAG, summarisation, content pre-screen, related content), multi-language pipeline + translation cache, `?lang=` content translation, `preferred_lang` JWT claim, Q&A discussion comments, Q&A promote to knowledge article, news featuring/pinning, AI cost dashboard, GDPR data portability export, Docling structured-data surfacing on document detail.
> Builds on Phase-1 infrastructure (FastAPI, Alembic, PgBouncer, Redis broker + cache, OpenSearch, MinIO/S3, Celery, outbox).
> No re-architecture — every Phase-2 feature is additive.

---

## 1. Backend Tasks

### Module 0 — Foundation Updates

- [ ] **T-B0.1 — Add `preferred_lang` claim to JWT**
      Description: Include `preferred_lang` from `users.preferred_lang` in access & refresh token payloads; readable by FastAPI dependency for downstream services.
      Files: `backend/app/core/security.py`, `backend/app/services/auth_service.py`, `backend/app/core/deps.py`.
      Acceptance Criteria: Decoded token exposes `preferred_lang`; changing profile language is reflected after refresh.

- [ ] **T-B0.2 — Common `?lang=` query parameter dependency**
      Description: Shared FastAPI dependency parsing `lang` (BCP-47), defaulting to JWT claim, validating against `supported_languages` from `platform_config`.
      Files: `backend/app/core/i18n.py`, `backend/app/core/deps.py`.
      Acceptance Criteria: Unsupported lang returns 400 `VALIDATION_ERROR`; default fallback works.

- [ ] **T-B0.3 — Enable `redis-cache` db=1 for translation cache**
      Description: Activate cache client on db=1; configure `allkeys-lru`, TTL 7 days; key pattern `trans:{lang}:{sha256(text)}`.
      Files: `backend/app/core/redis.py`, `backend/app/core/cache.py`.
      Acceptance Criteria: Setting a key on db=1 isolated from db=0 verified by integration test.

- [ ] **T-B0.4 — AI disclaimer + assistive header response middleware**
      Description: All AI endpoints emit a standard `X-AI-Assistive: true` response header; bodies wrap content in `{ ai: { disclaimer, model, confidence?, sources? }, ... }`.
      Files: `backend/app/api/v1/ai.py`, `backend/app/core/middleware.py`.
      Implementation Notes: No streaming endpoints in Phase 2. `confidence` and `sources` are **omitted entirely** (Pydantic `exclude_none=True`) when not applicable — do not emit `null`. Schema marks both as `Optional`.
      Acceptance Criteria: Every `/ai/*` response includes header and envelope; non-applicable fields are absent from the body.

---

### Module 5 — Repository (Phase-2 endpoints)

- [ ] **T-B5.1 — `GET /documents/{id}/related`**
      Description: k-NN query on `ica_documents.doc_vector` excluding self; k=10.
      Files: `backend/app/api/v1/documents.py`, `backend/app/services/related_service.py`, `backend/app/repositories/opensearch_repo.py`.
      Implementation Notes: 200 ms SLA; only `law_status='active'`.
      Acceptance Criteria: p95 ≤ 200 ms; returns ≤ 10 results.

- [ ] **T-B5.2 — `POST /ai/summarize/{document_id}`**
      Description: Fetch top-scored chunks from `ica_document_chunks` → LLM summarisation → 200-word summary. Cached in `redis-cache` db=0 with key `ai:summary:doc:{document_id}:{lang}` and TTL 30 days (invalidated when source document is re-edited/re-versioned).
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/ai_summarize_service.py`, `backend/app/workers/ai/summarize.py`.
      Implementation Notes: Rate-limited 10/min/user. Persist `documents.summary` if first run. Cache invalidation listens for `document.updated` outbox event.
      Acceptance Criteria: Repeat call ≤ 50 ms (cache hit); first call ≤ 5 s; cache cleared on document update.

- [ ] **T-B5.3 — `?lang=` translation for documents list/detail**
      Description: `GET /documents`, `GET /documents/{id}` translate `title` + `summary` (and other text metadata) when `lang ≠ document.language`. Use translation cache; fall back to original on circuit-open.
      Files: `backend/app/services/document_service.py`, `backend/app/services/translation_service.py`.
      Acceptance Criteria: Response payload contains translated fields and a `translated_from` indicator.

- [ ] **T-B5.4 — Surface Docling structured data on document detail**
      Description: Extend `GET /documents/{id}` to return Docling-extracted structured content (tables, headings, key/value pairs, figures) alongside the existing payload under a new `structured_data` block. Also expose `GET /documents/{id}/structured-data` for paginated/large-document streaming.
      Files: `backend/app/api/v1/documents.py`, `backend/app/services/document_service.py`, `backend/app/repositories/documents_repo.py`, `backend/app/schemas/document.py`.
      Implementation Notes: Docling output is already persisted by the Phase-1 ingestion pipeline (per SAD §6 — OCR/Docling extraction). This task only surfaces it; no re-extraction. Shape: `structured_data: { tables: [{ id, page, caption?, rows: string[][], headers?: string[] }], sections: [{ id, level, heading, anchor }], key_values: [{ key, value, page }] }`. Honour `?lang=` — translate `caption`, `headers`, and `heading` via translation cache; cell values left untouched (numeric/legal-text fidelity). Omit the block entirely (`exclude_none=True`) when Docling did not produce structured output (e.g., scanned-only PDFs with no tables). Read-only; restricted to authenticated users who can already view the document.
      Acceptance Criteria: Detail response includes `structured_data` when present; absent when Docling produced no tables/sections; translated headers/captions carry `translated_from`; `GET /documents/{id}/structured-data` paginates tables when count > 20.

---

### Module 6 — Q&A (Phase-2 endpoints)

- [ ] **T-B6.1 — `?lang=` translation for `/questions` list & detail**
      Description: Translate `title` + `body` + `answer_summary` when locale ≠ stored language; original-language indicator preserved.
      Files: `backend/app/services/qa_service.py`, `backend/app/services/translation_service.py`.
      Acceptance Criteria: Non-EN locale receives translated copy; original remains intact in DB.

- [ ] **T-B6.2 — `GET /questions/{id}/related`**
      Description: k-NN on `ica_questions.content_vector`, exclude self.
      Files: `backend/app/api/v1/questions.py`, `backend/app/services/related_service.py`.
      Acceptance Criteria: ≤ 200 ms p95.

- [ ] **T-B6.3 — `POST /questions/{id}/promote` (knowledge article)**
      Description: Promote approved + verified Q&A. Inserts `knowledge_articles` row; idempotent (returns existing if already promoted).
      Files: `backend/app/api/v1/questions.py`, `backend/app/services/knowledge_article_service.py`, `backend/app/repositories/knowledge_articles_repo.py`, Alembic migration for table.
      Implementation Notes: Restricted to A/M. Outbox `knowledge_article.created`. Schema is **denormalised** — store `title`, `body`, `language`, `country_id`, `category_id`, `summary`, `content_vector_id` directly. `question_id` is a UNIQUE FK reference only; the source Q&A is not the source of truth post-promotion (avoids per-render joins and preserves the snapshot).
      Acceptance Criteria: Unverified Q&A → 422; promote a second time → 200 with same article id; promoted record carries the denormalised payload.

- [ ] **T-B6.4 — `POST /ai/summarize/question/{question_id}`**
      Description: Summarise question + all answers via LLM.
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/ai_summarize_service.py`, `backend/app/workers/ai/summarize.py`.
      Implementation Notes: Rate-limited 10/min/user; cached under `ai:summary:question:{question_id}:{lang}` with TTL 7 days; invalidated on `answer.created/updated` or `question.updated` outbox events.
      Acceptance Criteria: Returns ≤ 300-word summary with disclaimer envelope; cache cleared when a new answer is posted.

- [ ] **T-B6.5 — Q&A discussion comments**
      Description: `GET /questions/{id}/comments` (cursor-paginated), `POST /questions/{id}/comments`, `DELETE /questions/{id}/comments/{cid}`. Fires `question_commented` notification to question author.
      Files: `backend/app/api/v1/question_comments.py`, `backend/app/services/question_comment_service.py`, `backend/app/repositories/question_comments_repo.py`, Alembic migration.
      Implementation Notes: No moderation. Delete restricted to comment author or Admin. **Hard delete** with an `outbox_events` audit row `question_comment.deleted` (`id`, `author_id`, `deleted_by_id`, `deleted_at`) — invite-only platform has low abuse risk; soft-delete adds list-filter complexity for no GDPR benefit (GDPR is satisfied by export + anonymisation). Not indexed in OpenSearch.
      Acceptance Criteria: Author of question receives in-app notification; non-author/non-admin DELETE → 403; deletion writes audit outbox row.

- [ ] **T-B6.6 — `GET /ai/suggestions/{question_id}`**
      Description: Abbreviated RAG (Doc Retriever + Verified Q&A Retriever only); skip LLM; return ranked source passages.
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/ai_suggestion_service.py`, `backend/app/workers/ai/answer.py` (suggestions mode).
      Implementation Notes: Restricted to A/M. Cache by `question_id`.
      Acceptance Criteria: Returns ≤ 10 passages with provenance (doc_id/chunk_id/q_id).

- [ ] **T-B6.7 — Knowledge Article retrieval endpoints**
      Description: `GET /knowledge-articles` (list, paginated, filterable by country/category/tag, supports `?lang=`) and `GET /knowledge-articles/{id}` (detail, supports `?lang=`).
      Files: `backend/app/api/v1/knowledge_articles.py`, `backend/app/services/knowledge_article_service.py`, `backend/app/repositories/knowledge_articles_repo.py`, `backend/app/schemas/knowledge_article.py`.
      Implementation Notes: Reads denormalised title/body from `knowledge_articles` plus source Q&A linkage. Indexed in OpenSearch (`ica_knowledge_articles`) — see T-D3.8 / T-I4.12.
      Acceptance Criteria: List + detail return Phase-2 promoted articles; translation applied when `lang ≠ article.language`; 404 for unknown id.

---

### Module 7 — News (Phase-2 endpoints)

- [ ] **T-B7.1 — `PATCH /news/{id}/feature` + `PATCH /news/feature/reorder`**
      Description: Admin-only. Single-item: `PATCH /news/{id}/feature` sets `is_featured`, `featured_order`. Batch reorder: `PATCH /news/feature/reorder` accepts `{ items: [{id, featured_order}, …] }`.
      Files: `backend/app/api/v1/news.py`, `backend/app/services/news_service.py`, Alembic migration adding `is_featured`, `featured_order`.
      Implementation Notes: Featured listing ordered by `featured_order ASC`. Reorder runs inside a single transaction with `SELECT … FOR UPDATE` on affected rows; concurrent reorder → 409 (client refetches and retries). Updates fire `news.featured_changed` outbox event for cache invalidation.
      Acceptance Criteria: `GET /news?featured=true` returns ordered list; non-admin → 403; conflicting reorder → 409.

- [ ] **T-B7.2 — `GET /news` `?featured=` filter + ordering**
      Description: Add `featured` query param to news list.
      Files: `backend/app/api/v1/news.py`, `backend/app/services/news_service.py`.
      Acceptance Criteria: Verified by integration test.

- [ ] **T-B7.3 — `GET /news/{id}/related`**
      Description: k-NN on `ica_news.content_vector`.
      Files: `backend/app/api/v1/news.py`, `backend/app/services/related_service.py`.
      Acceptance Criteria: ≤ 200 ms p95.

- [ ] **T-B7.4 — `?lang=` translation for news**
      Description: Translate title/body/summary on `GET /news` and `GET /news/{id}`.
      Files: `backend/app/services/news_service.py`.
      Acceptance Criteria: Same translation cache used; misses populate via worker.

---

### Module 8 — Social Feed (Phase-2 endpoints)

- [ ] **T-B8.1 — `GET /posts/{id}/related`**
      Description: k-NN on `ica_posts.content_vector`.
      Files: `backend/app/api/v1/posts.py`, `backend/app/services/related_service.py`.
      Acceptance Criteria: ≤ 200 ms p95.

---

### Module 9 — Moderation (Phase-2 enhancements)

- [ ] **T-B9.1 — Surface AI pre-screen flags on queue rows**
      Description: Extend moderation queue payload with AI pre-screen result (`status`, `reason`, `score`) when present on the submission record.
      Files: `backend/app/api/v1/moderation.py`, `backend/app/services/moderation_service.py`, schema migration adding `ai_prescreen` JSONB to documents/questions/news/posts.
      Implementation Notes: Storage model = **JSONB column `ai_prescreen` on each content table** (single-row read; no join in the hot path). Sidecar table deferred to Phase 3 if multi-scan history is ever needed. Pre-screen result is written by `ai_content_flag_job` (see Integration).
      Acceptance Criteria: Queue response includes `ai_prescreen` block where the job has run; no extra join executed.

---

### Module 11 — Search & AI (Phase-2 core endpoints)

- [ ] **T-B11.1 — `POST /ai/ask` (LangGraph RAG)**
      Description: Endpoint runs LangGraph **synchronously in-process** (no Celery hop — broker latency would consume 200–500 ms of the 2 500 ms budget) with a 5 s hard cap. LangGraph orchestrates Translation → Intent Classifier → Doc Retriever → Verified Q&A Retriever → (conditional News/Post Retrievers) → Source Merger (weighted RRF: doc 1.0, qa 0.8, news 0.4, posts 0.3) → Confidence Scorer (≥ 0.75 → LLM; 0.50–0.75 → 1 retry; < 0.50 → flag for review) → Audit Logger → Back-Translation.
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/ai_ask_service.py`, `backend/app/workers/ai/answer.py`, `backend/app/workers/ai/langgraph/{intent_classifier,doc_retriever,qa_retriever,news_retriever,post_retriever,merger,scorer,llm_generator,flag_for_review,audit_logger,back_translator}.py`.
      Implementation Notes: Rate-limited 20/min/user. Budget ≤ 2,500 ms (translation cache warm). Citations must reference `doc_id/chunk_id/q_id/news_id`. Low-confidence path writes a `moderation_logs` row with `action='escalate'`, `reason='ai_low_confidence'`, `entity_type='ai_query'`, `entity_id=audit_event_id`, and returns the "pending expert review" envelope. Each invocation writes one `ai_usage_events` row.
      Acceptance Criteria: High-confidence answers carry ≥ 1 citation; low-confidence returns expert-review notice without LLM output and creates the escalate row; audit row present in `outbox_events`.

- [ ] **T-B11.5 — LangGraph Back-Translation node (BACKTRANS)**
      Description: Per SAD §9.4, append a Back-Translation node that translates the LLM answer + snippet text from English into the requester's `preferred_lang` (or `?lang=` override), using `redis-cache` db=1 translation cache. Skipped when target lang = `en`.
      Files: `backend/app/workers/ai/langgraph/back_translator.py`, `backend/app/services/translation_service.py`.
      Implementation Notes: Best-effort — on circuit-open or budget exhaustion, return original English with `translation_unavailable=true` flag. Adds `translated_from` to response envelope.
      Acceptance Criteria: Non-EN ask returns translated answer + snippets; circuit-open path returns English with fallback flag; covered by T-T7.4.

- [ ] **T-B11.2 — `POST /ai/translate`**
      Description: Translate input text to target lang via translation provider; cache; return `{translated_text, source_lang, target_lang, cached}`.
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/translation_service.py`.
      Acceptance Criteria: Cache hit verified by header/flag; circuit breaker honoured.

- [ ] **T-B11.3 — `GET /ai/translate/languages`**
      Description: Return supported languages from `platform_config.supported_languages`.
      Files: `backend/app/api/v1/ai.py`, `backend/app/services/platform_config_service.py`.
      Acceptance Criteria: Reflects config updates without restart.

- [ ] **T-B11.4 — Update `GET /search` to honour `?lang=`**
      Description: Detect/declare query language; translate to English for retrieval via translation cache; back-translate snippets (best-effort, per-snippet 200 ms budget).
      Files: `backend/app/services/search_service.py`, `backend/app/services/translation_service.py`.
      Implementation Notes: Cache miss path calls `query_translation_cache_job` synchronously (≤ 500 ms budget); circuit breaker degrades to original query on outage. Snippet back-translation timeout → emit original English snippet with per-snippet `translation_unavailable: true`. `query_lang` returned in the **response body** (not header) for typed-client ergonomics.
      Acceptance Criteria: Non-EN query returns translated results; response body includes `query_lang`; degraded snippets carry per-snippet fallback flag.

---

### Module 14 — Admin (Phase-2 endpoints)

- [ ] **T-B14.1 — `GET /admin/ai-usage`**
      Description: Aggregate `ai_usage_events` over a date range and return three blocks in a single response: (1) **time-series rows** bucketed by `(date, event_type)` for the dashboard line/stacked-bar charts, (2) **period totals** across the full window, (3) **top-N users** ranked by estimated cost. Admin-only (403 for non-Admin); uses analytics replica DSN.
      Files: `backend/app/api/v1/admin.py`, `backend/app/services/ai_usage_service.py`, `backend/app/repositories/ai_usage_repo.py`, `backend/app/schemas/ai_usage.py`.
      Implementation Notes:
      - **Query parameters**:
        - `date_from`, `date_to` (ISO-8601 dates; defaults to last 30 days).
        - `granularity` — `day` (default) | `week` | `month`. Buckets `rows[].date` using `date_trunc()` server-side.
        - `event_type` — optional repeatable filter (`ai_query.completed`, `ai_summarize`, `ai_translate`, `ai_embedding`, etc.); when omitted, all event types are returned.
        - `top_users_limit` — integer 1–50, default 10. Controls the `top_users[]` array length.
        - `export=csv` — streams the time-series `rows[]` (with the same filters applied) as CSV; max 50,000 rows.
      - **Response shape** (consumed by UI T14.1):
        ```json
        {
          "period": { "from": "2026-04-21", "to": "2026-05-21", "granularity": "day" },
          "rows": [
            { "date": "2026-05-21", "event_type": "ai_query.completed",
              "input_tokens": 4120, "output_tokens": 890,
              "call_count": 14, "estimated_cost_usd": 0.38 }
          ],
          "totals": {
            "input_tokens": 122340, "output_tokens": 28910,
            "call_count": 412, "estimated_cost_usd": 11.74,
            "by_event_type": [
              { "event_type": "ai_query.completed", "call_count": 198, "estimated_cost_usd": 6.21 }
            ]
          },
          "top_users": [
            { "user_id": "...", "display_name": "...",
              "call_count": 47, "input_tokens": 18200, "output_tokens": 3940,
              "estimated_cost_usd": 1.82 }
          ]
        }
        ```
      - **Indexing**: rows[] query uses the existing `(event_type, created_at)` index on `ai_usage_events` (T-D3.4); top-users query uses `(user_id, created_at)` — add this index to T-D3.4 if not already present and document in T-D3.4's acceptance criteria.
      - `top_users[]` is server-ranked by `estimated_cost_usd DESC` then `call_count DESC` to break ties deterministically. Users with zero activity in the window are excluded.
      - `display_name` joined from `users` table at query time; if user is deleted, fall back to `"(deleted user)"`.
      - CSV export streams via `StreamingResponse` to avoid loading the full result set into memory.
      Acceptance Criteria: Default call (no params) returns last 30 days at day granularity; `granularity=week` returns ≤ 5 buckets per `event_type` for a 30-day window; `granularity=month` returns 1–2 buckets; `top_users_limit=5` truncates to 5; sum of `rows[].estimated_cost_usd` equals `totals.estimated_cost_usd` exactly; sum of `top_users[].estimated_cost_usd` ≤ `totals.estimated_cost_usd` (top-N is a subset); CSV export downloads valid file with headers `date,event_type,input_tokens,output_tokens,call_count,estimated_cost_usd`; non-Admin returns 403; invalid `granularity` returns 422.

- [ ] **T-B14.2 — Extend `PUT /admin/config` validation for `supported_languages`**
      Description: Validate BCP-47 codes; reject unknown values.
      Files: `backend/app/services/platform_config_service.py`.
      Acceptance Criteria: Invalid code → 422.

- [ ] **T-B14.3 — `GET /admin/ai-audit` — AI query audit log endpoint**
      Description: Cursor-paginated (default 20, max 50) endpoint returning AI query audit records from `outbox_events WHERE event_type LIKE 'ai_query.%'`. Supports filters: `event_type` (`ai_query.completed|flagged|insufficient`), `user_id`, `date_from` / `date_to` (ISO-8601), `confidence_band` (`high ≥ 0.75`, `mid 0.50–0.75`, `low < 0.50`). Each row exposes: `id`, `event_type`, `created_at`, `payload.query_hash`, `payload.confidence`, `payload.model`, `payload.source_ids` (doc_id/chunk_id/q_id/news_id list), `payload.reasoning_path` (node names traversed). Admin-only (403 for non-Admin). Uses analytics replica DSN.
      Files: `backend/app/api/v1/admin.py`, `backend/app/services/ai_audit_service.py`, `backend/app/repositories/ai_audit_repo.py`.
      Implementation Notes: Reads `outbox_events` — do not expose `payload` fields outside the enumerated list above (avoid leaking internal orchestration state). Retention window is 30 days per T-I4.10; document this limit in the OpenAPI description and response envelope (`retention_days: 30`). Cursor is base64 of `{created_at, id}` DESC.  Add `?export=csv` query param that streams the filtered window as CSV for compliance download (max 10,000 rows, honour same filters).
      Acceptance Criteria: Filtered results match seeded fixtures; `confidence_band=low` returns only `confidence < 0.50` rows; CSV export downloads a valid file with correct headers; non-Admin returns 403; `retention_days` present in response envelope.

- [ ] **T-B14.4 — Add `ai_audit_retention_days` to `platform_config` + wire T-I4.10**
      Description: Add `ai_audit_retention_days` (integer, default 30) to `platform_config` seed. Update `outbox_events_cleanup_job` (T-I4.10) to read this value at runtime instead of a hard-coded constant, so Admins can extend retention for compliance requirements without a code deploy. Validate ≥ 7 and ≤ 365 on `PUT /admin/config`.
      Files: `backend/alembic/versions/02xx_ai_audit_retention_config.py` (seed row), `backend/app/workers/maintenance/outbox_cleanup.py`, `backend/app/services/platform_config_service.py`.
      Implementation Notes: Cleanup job reads `platform_config` once per run (cached for the job's lifetime). Setting a longer retention does not retroactively recover already-pruned rows.
      Acceptance Criteria: Setting `ai_audit_retention_days=60` causes the cleanup job to retain rows up to 60 days; invalid values (< 7 or > 365) return 422; default 30 reproduced on fresh seed.

---

### Module 16 — Profile / GDPR (Phase-2 endpoints)

- [ ] **T-B16.1 — `GET /users/me/export` + `GET /users/me/export/{job_id}`**
      Description: `GET /users/me/export` triggers `gdpr_export_job` and responds with `202 Accepted` + `{ job_id }`. `GET /users/me/export/{job_id}` returns job status (`pending|running|completed|failed`) and, when completed, the pre-signed S3 URL. Polling endpoint rate-limited 60/min to prevent abuse.
      Files: `backend/app/api/v1/users.py`, `backend/app/services/gdpr_export_service.py`, `backend/app/workers/gdpr/export.py`, `backend/app/repositories/gdpr_jobs_repo.py`.
      Implementation Notes: Trigger endpoint rate-limited 1/day/user. URL TTL 24 h. Job state persisted in `gdpr_export_jobs` table (see T-D3.9). See T-I4.8 for archive format.
      Acceptance Criteria: Job produces archive containing only requester's records; status endpoint returns terminal state with URL; URL downloads successfully; TTL respected.

---

## 2. API Tasks

- [ ] **T-A2.1 — OpenAPI annotations for all Phase-2 endpoints**
      Description: Tag, document, error codes (401/403/404/409/422/429/503), examples for `/ai/*`, `/news/{id}/feature`, `/questions/{id}/promote`, `/users/me/export`, comments, related endpoints.
      Files: `backend/app/api/v1/*.py`, `backend/app/schemas/*.py`.
      Acceptance Criteria: `/docs` lists every Phase-2 endpoint; spec exported to `Docs/openapi-phase2.yaml`.

- [ ] **T-A2.2 — Standard AI response envelope**
      Description: `{ ai: { disclaimer, model, confidence?, sources? }, data: ... }` schema for `/ai/*` endpoints.
      Files: `backend/app/schemas/ai.py`.
      Acceptance Criteria: Schema reused by ask/suggest/summarize/translate.

- [ ] **T-A2.3 — Rate limits for AI endpoints**
      Description: Add slowapi decorators: `/ai/ask` 20/min/user, `/ai/summarize/*` 10/min/user, `/ai/translate` 60/min/user, `/users/me/export` 1/day/user.
      Files: `backend/app/core/rate_limit.py`, route decorators.
      Acceptance Criteria: 429 with `Retry-After` returned on overage.

- [ ] **T-A2.4 — Cursor pagination for `/questions/{id}/comments`**
      Description: Default 20, max 50, cursor on `(created_at, id)`.
      Files: `backend/app/api/v1/question_comments.py`, `backend/app/core/pagination.py`.
      Acceptance Criteria: Stable under concurrent inserts.

- [ ] **T-A2.5 — Idempotent promote endpoint**
      Description: `POST /questions/{id}/promote` returns 200 + existing article id if already promoted.
      Files: `backend/app/services/knowledge_article_service.py`.
      Acceptance Criteria: Repeat call returns identical body.

---

## 3. Database Tasks

- [ ] **T-D3.1 — Migration: `knowledge_articles`**
      Description: New table per SAD §14.1; `question_id` UNIQUE FK; `promoted_by`, `promoted_at`.
      Files: `backend/alembic/versions/02xx_knowledge_articles.py`, `backend/app/models/knowledge_article.py`.
      Acceptance Criteria: Round-trip migration clean.

- [ ] **T-D3.2 — Migration: `question_comments`**
      Description: New table; `question_id` FK CASCADE; `(question_id, created_at)` index. Not indexed in OpenSearch.
      Files: `backend/alembic/versions/02xx_question_comments.py`, `backend/app/models/question_comment.py`.
      Acceptance Criteria: Insert/list/delete CRUD works.

- [ ] **T-D3.3 — Migration: `news_articles.is_featured`, `featured_order`**
      Description: Add columns + partial index `WHERE is_featured = TRUE` ordered by `featured_order ASC`.
      Files: `backend/alembic/versions/02xx_news_featured.py`.
      Acceptance Criteria: Query plan for featured listing uses the partial index.

- [ ] **T-D3.4 — Migration: `ai_usage_events`**
      Description: Schema per IP §Data Model; indexes on `created_at`, `(event_type, created_at)` (for T-B14.1 time-series aggregation), and `(user_id, created_at)` (for T-B14.1 top-users ranking).
      Files: `backend/alembic/versions/02xx_ai_usage_events.py`, `backend/app/models/ai_usage_event.py`.
      Acceptance Criteria: Append-only writes from AI workers verified in integration; `EXPLAIN ANALYZE` on the T-B14.1 time-series query uses `(event_type, created_at)`; `EXPLAIN ANALYZE` on the top-users query uses `(user_id, created_at)` — no sequential scan in either plan.

- [ ] **T-D3.5 — Migration: AI pre-screen result column**
      Description: Add `ai_prescreen JSONB` to `documents`, `questions`, `news_articles`, `posts`. Single coordinated migration across all four tables (matches T-B9.1 decision; sidecar deferred to Phase 3).
      Files: `backend/alembic/versions/02xx_ai_prescreen.py`.
      Acceptance Criteria: `ai_content_flag_job` writes into this column; moderation queue reads it without joins.

- [ ] **T-D3.6 — Update `platform_config` seeds**
      Description: Set `supported_languages = ["en","es","fr"]`; ensure `ai_confidence_high=0.75`, `ai_confidence_low=0.50` present.
      Files: `backend/alembic/versions/02xx_phase2_seed.py`.
      Acceptance Criteria: Verified in `GET /admin/config`.

- [ ] **T-D3.7 — Add `chunk_vector_v2` (optional, behind `EMBEDDING_DUAL_WRITE`)**
      Description: Schema/index template change to support embedding-model migration (R5-G12). Field added to the **same `ica_document_chunks` index** (additional field, not a new alias) — avoids alias swap during cut-over and lets a single query verify v1↔v2 parity. Field deleted in cleanup step of the 6-step playbook.
      Files: `backend/app/workers/indexing/templates/ica_document_chunks.json`, migration playbook.
      Acceptance Criteria: Dual-write toggle works; query-time switch reversible; cleanup removes `chunk_vector_v2` cleanly.

- [ ] **T-D3.8 — OpenSearch templates for Phase 2**
      Description: (a) New index template `ica_knowledge_articles` (title, body, language, content_vector, country, category, tags, promoted_at). (b) Extend `ica_news` mapping with `is_featured` (boolean, filterable) and `featured_order` (integer, sortable). (c) Add `ai_prescreen` keyword-status field on `ica_document_chunks`, `ica_questions`, `ica_news`, `ica_posts` if queried via search filters.
      Files: `backend/app/workers/indexing/templates/{ica_knowledge_articles,ica_news,ica_document_chunks,ica_questions,ica_posts}.json`, `backend/alembic/versions/02xx_os_phase2_templates.py` (template-apply migration).
      Acceptance Criteria: New template created on bootstrap; existing indices rolled over or patched without data loss.

- [ ] **T-D3.10 — Verify Docling structured-data persistence**
      Description: Confirm Phase-1 `documents.structured_data` JSONB column (populated by the Docling extraction worker) is queryable and indexed for the detail endpoint; add a GIN index on `(structured_data)` only if existing query plans regress. No schema change expected — this task is a validation + index-tuning step.
      Files: `backend/alembic/versions/02xx_documents_structured_data_index.py` (only if index added), `backend/app/models/document.py` (verify field exposure).
      Acceptance Criteria: `GET /documents/{id}` retrieves `structured_data` without table scan; documented in data-model reference.

- [ ] **T-D3.9 — Migration: `gdpr_export_jobs`**
      Description: Track GDPR export job state for polling (`id`, `user_id`, `status`, `s3_key`, `expires_at`, `created_at`, `completed_at`).
      Files: `backend/alembic/versions/02xx_gdpr_export_jobs.py`, `backend/app/models/gdpr_export_job.py`.
      Acceptance Criteria: Polling endpoint (T-B16.1) returns persisted state across worker restarts.

- [ ] **T-D3.11 — Index: `outbox_events` for AI audit queries**
      Description: Add a partial compound index `idx_outbox_ai_audit (event_type, created_at DESC) WHERE event_type LIKE 'ai_query.%'` on `outbox_events` to support `GET /admin/ai-audit` (T-B14.3) cursor-paginated queries without full table scans. Also add `idx_outbox_ai_audit_user (payload->>'user_id', created_at DESC) WHERE event_type LIKE 'ai_query.%'` as a functional index on the JSONB `user_id` field to accelerate per-user filter queries.
      Files: `backend/alembic/versions/02xx_outbox_ai_audit_indexes.py`.
      Implementation Notes: Use `CREATE INDEX CONCURRENTLY` to avoid locking the outbox table on production deployment. Both indexes are partial (`WHERE event_type LIKE 'ai_query.%'`) so they do not slow down the main outbox poller queries which filter on `status`.
      Acceptance Criteria: `EXPLAIN ANALYZE` of the audit list query (filtered by event_type and date range) uses the partial index; functional index used for per-user filter; no regression on outbox poller query plan (T-I4.5).

---

## 4. Integration Tasks

- [ ] **T-I4.1 — Translation provider abstraction**
      Description: `TranslationProvider` interface with `openai` and `aws-translate` implementations selected by `TRANSLATION_PROVIDER`. Circuit breaker (3 retries → cache `_UNAVAILABLE` for 1 h).
      Files: `backend/app/core/translation/{openai_provider.py,aws_provider.py}`, `backend/app/services/translation_service.py`.
      Acceptance Criteria: Forced failures trip breaker; cached `_UNAVAILABLE` honoured on subsequent calls.

- [ ] **T-I4.2 — `translation_job` Celery worker**
      Description: Translate text → English (or back to user lang); cache result on `redis-cache` db=1 with TTL 7 days.
      Files: `backend/app/workers/translation/translate.py`.
      Acceptance Criteria: Cache hit ratio surfaced via metric.

- [ ] **T-I4.3 — `query_translation_cache_job`**
      Description: Specialised translation for `/search` and `/ai/ask` query strings; key `trans:{lang}:{sha256(query)}`.
      Files: `backend/app/workers/translation/query_translation.py`.
      Acceptance Criteria: Misses populate; hits served from cache ≤ 1 ms.

- [ ] **T-I4.4 — LangGraph workflow runtime**
      Description: Wire LangGraph nodes inside `ai_answer_job`; accept `mode=answer` or `mode=suggestions` (abbreviated graph).
      Files: `backend/app/workers/ai/answer.py`, `backend/app/workers/ai/langgraph/*`.
      Implementation Notes: **One `outbox_events` row per invocation** (terminal Audit Logger node only) — per-node rows would 6–10× the outbox table at scale. Per-node telemetry goes to **structured logs + Prometheus**, not the outbox. Reconciles with T-L6.1. Server-side prompt template wraps user query (prompt-injection mitigation).
      Acceptance Criteria: Graph init overhead ≤ 100 ms; retry loop exercised at most once; exactly one outbox row written per invocation.

- [ ] **T-I4.5 — `ai_content_flag_job`**
      Description: AI pre-screen for inappropriate/off-topic content on every submission; write result into `ai_prescreen` column or sidecar; surface via moderation queue endpoint.
      Files: `backend/app/workers/ai/content_flag.py`.
      Implementation Notes: Triggered by outbox event `{document|question|news|post}.submitted`.
      Acceptance Criteria: Pending items receive flag within 60 s of submission.

- [ ] **T-I4.6 — Update `qa_embedding_job` for non-English questions**
      Description: Translate non-EN question body to English before embedding; store original in PostgreSQL; embed only English.
      Files: `backend/app/workers/embeddings/qa_embedding.py`.
      Acceptance Criteria: A French question is searchable via English query without losing original text.

- [ ] **T-I4.7 — Cache invalidation on news feature toggle**
      Description: `PATCH /news/{id}/feature` enqueues `search_cache_invalidate_job` for affected scopes.
      Files: `backend/app/services/news_service.py`.
      Acceptance Criteria: `GET /news?featured=true` reflects new state within next request.

- [ ] **T-I4.8 — `gdpr_export_job`**
      Description: Package requester's contributions into a single **`.tar.gz`** archive containing one JSONL per entity type (`documents.jsonl`, `questions.jsonl`, `answers.jsonl`, `news.jsonl`, `posts.jsonl`, `comments.jsonl`) plus `manifest.json` (with S3 keys for original PDFs). Upload to S3; pre-signed URL TTL 24 h.
      Files: `backend/app/workers/gdpr/export.py`.
      Implementation Notes: **Metadata only** — original PDFs are *not* bundled (GDPR Art. 20 is satisfied by metadata + S3 keys; bundling originals could include co-authored material requiring separate consent). Excludes PII from other users. Notify requester via in-app + email when ready.
      Acceptance Criteria: Generated archive validates against schema; only requester's data present; manifest enumerates S3 keys for original PDFs.

- [ ] **T-I4.9 — AI usage event emission**
      Description: All AI workers (`ai_answer_job`, `ai_content_flag_job`, summarize, translate, embedding) insert one row into `ai_usage_events` with input/output tokens, model, estimated cost.
      Files: `backend/app/workers/ai/*`, `backend/app/services/ai_usage_service.py`.
      Acceptance Criteria: `/admin/ai-usage` totals match raw inserts.

- [ ] **T-I4.10 — `outbox_events_cleanup_job` 30-day TTL for AI rows**
      Description: Confirm Phase-1 cleanup job correctly prunes `event_type LIKE 'ai_query.%'` after 30 days; add Prometheus alert on dead-letter AI rows.
      Files: `backend/app/workers/maintenance/outbox_cleanup.py`.
      Implementation Notes: **TTL scope is restricted to `ai_query.%` only**. Other Phase-2 event types (`knowledge_article.created`, `news.featured_changed`, `gdpr_export.*`, `question_comment.deleted`, `document.updated`) are business-audit events and follow the standard outbox lifecycle (kept until dispatched + 7 d).
      Acceptance Criteria: Verified by integration test inserting AI rows dated > 30 d and non-AI rows dated > 30 d — only AI rows pruned.

- [ ] **T-I4.11 — Embedding migration playbook (R5-G12)**
      Description: Implement `embedding_backfill_job` (rate-limited beat job) and 6-step playbook: add v2 field → dual-write → backfill → verify → cut-over → cleanup.
      Files: `backend/app/workers/embeddings/backfill.py`, `Docs/runbook-embedding-migration.md`.
      Implementation Notes: Backfill rate **100 chunks/sec** with adaptive throttle if OpenSearch indexing latency p95 > 100 ms. Verification metric = **cosine similarity v1↔v2 ≥ 0.85 on a 1% sample** plus search recall@10 unchanged on the regression query set.
      Acceptance Criteria: Dry-run on staging completes all 6 steps without data loss; verification metrics pass thresholds.

- [ ] **T-I4.12 — Knowledge Article indexing pipeline**
      Description: On `knowledge_article.created` outbox event, embed body via `embedding_generation_job`, index into `ica_knowledge_articles` (template per T-D3.8), and invalidate search cache for affected scopes. Search service includes the new index in `/search` results with a `result_type=knowledge_article` discriminator.
      Files: `backend/app/workers/indexing/knowledge_article_index.py`, `backend/app/services/search_service.py`.
      Acceptance Criteria: Promoted article is searchable within 60 s and surfaces with the `knowledge_article` discriminator.

- [ ] **T-I4.13 — Notification type registration (Phase 2)**
      Description: Register Phase-2 notification types (`question_commented`, `gdpr_export.requested`, `gdpr_export.completed`) in the notification catalogue: enum, template copy (EN/ES/FR), channel routing (in-app + email), preference defaults.
      Files: `backend/app/services/notification_service.py`, `backend/app/models/notification.py`, `backend/app/workers/notifications/templates/{question_commented,gdpr_export_requested,gdpr_export_completed}.{html,txt}`, Alembic enum migration if applicable.
      Acceptance Criteria: All three types render correctly in `/notifications`; email channel honoured per user preference.

- [ ] **T-I4.14 — Outbox event catalogue update**
      Description: Single coordinated update registering all Phase-2 outbox event types (`knowledge_article.created`, `news.featured_changed`, `ai_query.completed|flagged|insufficient`, `gdpr_export.requested|completed`, `document.updated` for summary invalidation) in the dispatch table; verify each has a consumer wired and a Pydantic payload validator.
      Files: `backend/app/services/outbox_dispatch.py`, `backend/app/schemas/outbox/*.py`.
      Acceptance Criteria: Test asserts every declared event type resolves to a registered handler; unknown types raise at startup.

---

## 5. Security Tasks

- [ ] **T-S5.1 — Prompt-injection mitigation**
      Description: Wrap user input in server-controlled prompt template; reject overlong/suspicious payloads; never echo system instructions.
      Files: `backend/app/workers/ai/langgraph/llm_generator.py`, `backend/app/services/ai_safety.py`.
      Acceptance Criteria: A query containing override patterns ("ignore previous instructions") does not leak system prompt.

- [ ] **T-S5.2 — AI authority guard (defence in depth)**
      Description: Server-side guarantee that AI cannot set `is_verified=true` on answers (only `PATCH /answers/{id}/verify` by A/M can). Enforced at two layers: (1) **Service guard** in `qa_service.set_verified` rejects any caller context tagged `source=ai`; (2) **CI grep rule** that fails the build if any module under `backend/app/workers/ai/` imports `qa_service.set_verified`.
      Files: `backend/app/services/qa_service.py`, `backend/scripts/ci/check_ai_authority.sh`, CI workflow.
      Acceptance Criteria: Integration test attempting AI-tagged write → rejected; CI grep rule fires on a deliberately-bad PR.

- [ ] **T-S5.3 — Rate-limit GDPR export**
      Description: Hard cap 1 request per user per 24 h.
      Files: `backend/app/core/rate_limit.py`.
      Acceptance Criteria: 2nd request within 24 h → 429.

- [ ] **T-S5.4 — Pre-signed URL TTL for GDPR archive**
      Description: 24 h S3 URL TTL; bucket policy denies public list. CORS allows `GET, HEAD` from production frontend origin only; `Access-Control-Expose-Headers: Content-Length, Content-Type, ETag`; `MaxAgeSeconds: 3600`. No `PUT/POST` (uploads happen elsewhere).
      Files: `backend/app/services/storage_service.py`, `infra/s3/bucket_policy.json`, `infra/s3/cors.json`.
      Acceptance Criteria: URL expires after 24 h; bucket listing returns 403; cross-origin GET from frontend origin succeeds; PUT denied.

- [ ] **T-S5.5 — Translation provider key rotation runbook**
      Description: Document and verify key rotation for OpenAI / AWS Translate without downtime.
      Files: `Docs/runbook-key-rotation.md`.
      Acceptance Criteria: Staged rotation tested successfully.

- [ ] **T-S5.6 — Restrict `/ai/suggestions/{id}` to A/M**
      Description: RBAC dependency on the route.
      Files: `backend/app/api/v1/ai.py`.
      Acceptance Criteria: Member call → 403.

---

## 6. Logging and Audit Tasks

- [ ] **T-L6.1 — AI audit trail via Audit Logger node**
      Description: Every `/ai/ask` invocation writes `outbox_events` row with `event_type='ai_query.completed|flagged|insufficient'`, `query_hash`, source ids, confidence, reasoning path, model, timestamp.
      Files: `backend/app/workers/ai/langgraph/audit_logger.py`.
      Acceptance Criteria: One row per invocation; 30-day TTL job prunes correctly.

- [ ] **T-L6.2 — AI usage metrics**
      Description: Prometheus counters for tokens (input/output), embedding/translation calls, model breakdown.
      Files: `backend/app/core/metrics.py`.
      Acceptance Criteria: Exposed on `/metrics`; dashboard panels populated.

- [ ] **T-L6.3 — Confidence-distribution histogram**
      Description: Histogram of RAG confidence scores per invocation.
      Files: `backend/app/core/metrics.py`.
      Acceptance Criteria: Bucketed values visible; alert if low-confidence rate spikes.

- [ ] **T-L6.4 — Translation cache hit-ratio metric**
      Description: Gauge for translation cache hit ratio; alert below 0.6.
      Files: `backend/app/core/metrics.py`, `infra/prometheus/alerts.yml`.
      Acceptance Criteria: Alert fires in staging at deliberately low hit ratio.

- [ ] **T-L6.5 — Moderation log entry for AI-flagged content**
      Description: Low-confidence `/ai/ask` results that escalate to moderation queue also create a `moderation_logs` row with `action='escalate'`.
      Files: `backend/app/workers/ai/langgraph/flag_for_review.py`.
      Acceptance Criteria: Log row visible in `GET /moderation/logs`.

- [ ] **T-L6.6 — GDPR job audit**
      Description: Outbox events for `gdpr_export.requested` and `gdpr_export.completed`.
      Files: `backend/app/workers/gdpr/export.py`.
      Acceptance Criteria: Both events visible in audit query.

---

## 7. Testing Tasks

- [ ] **T-T7.1 — LangGraph unit tests per node**
      Description: Cover Intent Classifier, Doc Retriever, Verified Q&A Retriever, conditional News/Post Retrievers, Source Merger (RRF weights), Confidence Scorer (3 bands), LLM Generation (mocked), Flag-for-Review, Audit Logger.
      Files: `backend/tests/workers/ai/langgraph/test_*.py`.
      Acceptance Criteria: ≥ 90% coverage on `workers/ai/langgraph/`.

- [ ] **T-T7.2 — `/ai/ask` integration test (mocked LLM)**
      Description: End-to-end with seeded OpenSearch fixtures; verify high/mid/low confidence paths.
      Files: `backend/tests/integration/test_ai_ask.py`.
      Acceptance Criteria: All three paths exercised; audit row written.

- [ ] **T-T7.3 — Translation cache + circuit breaker tests**
      Description: HIT/MISS, `_UNAVAILABLE` cache entry, circuit-breaker reset behaviour.
      Files: `backend/tests/integration/test_translation.py`.
      Acceptance Criteria: Provider outages don't break content endpoints.

- [ ] **T-T7.4 — `?lang=` content translation tests**
      Description: Verify documents/questions/news endpoints translate as expected and fall back on circuit-open.
      Files: `backend/tests/integration/test_lang_content.py`.
      Acceptance Criteria: Response carries `translated_from`; fallback path verified.

- [ ] **T-T7.5 — Knowledge article promote idempotency**
      Description: Repeat promotion returns same id; unverified Q&A rejected.
      Files: `backend/tests/integration/test_promote_question.py`.
      Acceptance Criteria: Passes.

- [ ] **T-T7.6 — Q&A discussion comments tests**
      Description: CRUD, notification fires to question author, delete authorisation.
      Files: `backend/tests/integration/test_question_comments.py`.
      Acceptance Criteria: All assertions pass.

- [ ] **T-T7.7 — News feature/pin tests**
      Description: Admin toggles; non-admin denied; ordering verified.
      Files: `backend/tests/integration/test_news_feature.py`.
      Acceptance Criteria: Passes.

- [ ] **T-T7.8 — Related-content endpoint tests**
      Description: k-NN exclusion of self; latency budget met under load.
      Files: `backend/tests/integration/test_related.py`.
      Acceptance Criteria: ≤ 200 ms p95 in test harness.

- [ ] **T-T7.9 — AI cost dashboard tests**
      Description: `/admin/ai-usage` aggregation correctness over seeded `ai_usage_events` — covers time-series rows, period totals, top-users ranking, granularity bucketing, and CSV export.
      Files: `backend/tests/integration/test_admin_ai_usage.py`.
      Acceptance Criteria:
      - `sum(rows[].estimated_cost_usd) == totals.estimated_cost_usd` (exact).
      - `sum(rows[].input_tokens) == totals.input_tokens`; same for `output_tokens` and `call_count`.
      - `granularity=day` returns one bucket per (date, event_type); `granularity=week` and `month` bucket correctly per `date_trunc()`.
      - `event_type` filter applied — non-matching rows excluded from both `rows[]` and `totals`.
      - `top_users[]` ordered by `estimated_cost_usd DESC`, length ≤ `top_users_limit`, and deleted users surface as `"(deleted user)"`.
      - `export=csv` produces a valid CSV with header `date,event_type,input_tokens,output_tokens,call_count,estimated_cost_usd` and one row per `(date, event_type)` pair in the active filter window.
      - Non-Admin caller returns 403; invalid `granularity` returns 422.

- [ ] **T-T7.10 — GDPR export job test**
      Description: Trigger job, validate archive contents, expiry behaviour of pre-signed URL.
      Files: `backend/tests/integration/test_gdpr_export.py`.
      Acceptance Criteria: Archive includes only requester's data; URL valid then expires.

- [ ] **T-T7.11 — AI rate-limit + RBAC tests**
      Description: 21st `/ai/ask` in a minute returns 429; member call to `/ai/suggestions/{id}` returns 403.
      Files: `backend/tests/security/test_ai_limits.py`.
      Acceptance Criteria: Passes.

- [ ] **T-T7.12 — Prompt-injection regression tests**
      Description: Adversarial inputs; ensure system prompt not leaked, role unchanged.
      Files: `backend/tests/security/test_prompt_injection.py`.
      Acceptance Criteria: All adversarial cases handled.

- [ ] **T-T7.13 — Load test for `/ai/ask`**
      Description: 20 concurrent virtual users for 5 minutes, translation cache warm (100 pre-seeded entries); assert p95 ≤ 2,500 ms.
      Files: `backend/tests/load/locust_ai_ask.py`, `backend/tests/load/README.md`.
      Implementation Notes: Reproducible UAT baseline = **t3.large backend (2 vCPU / 8 GB)**, **t3.medium redis-cache**, **t3.large OpenSearch single-node**, **t3.medium Celery worker (`ai` queue, concurrency=4)**, all in the same AZ. Documented in `backend/tests/load/README.md`.
      Acceptance Criteria: SLA met on the documented UAT hardware spec.

- [ ] **T-T7.15 — Docling structured-data endpoint test**
      Description: Verify `GET /documents/{id}` returns `structured_data` when Docling output present; omitted when absent; translated headers/captions on `?lang=fr`; pagination path on `GET /documents/{id}/structured-data` for > 20 tables.
      Files: `backend/tests/integration/test_documents_structured_data.py`.
      Acceptance Criteria: All four assertions pass; covers no-structured-data fallback.

- [ ] **T-T7.14 — Embedding migration dry-run**
      Description: Exercise 6-step playbook on staging; verify backfill correctness and reversibility.
      Files: `backend/tests/migrations/test_embedding_migration.py`.
      Acceptance Criteria: Round-trip clean.

---

## 8. Documentation Tasks

- [ ] **T-DOC8.1 — Phase-2 OpenAPI export**
      Description: `Docs/openapi-phase2.yaml` regenerated in CI.
      Files: `backend/scripts/export_openapi.py`, CI workflow.
      Acceptance Criteria: CI fails on drift.

- [ ] **T-DOC8.2 — LangGraph runbook**
      Description: Node-by-node description, retry behaviour, expert-review escalation, audit trail layout, model/key rotation.
      Files: `Docs/runbook-langgraph.md`.
      Acceptance Criteria: On-call engineer can debug a failed `/ai/ask` from this document.

- [ ] **T-DOC8.3 — Translation pipeline runbook**
      Description: Cache semantics, TTL, circuit breaker, provider switching.
      Files: `Docs/runbook-translation.md`.
      Acceptance Criteria: Reviewed and signed off.

- [ ] **T-DOC8.4 — AI compliance & disclaimer docs**
      Description: Document where disclaimers render, how AI authority is constrained, audit policy, 30-day TTL on AI logs, GDPR alignment.
      Files: `Docs/ai-compliance-phase2.md`.
      Acceptance Criteria: Reviewed by legal stakeholder.

- [ ] **T-DOC8.5 — Update API consumer guide**
      Description: Add `?lang=` semantics, AI envelope, related-content shapes, comments contract, promote contract, GDPR export flow.
      Files: `Docs/api-consumer-guide-phase2.md`.
      Acceptance Criteria: Frontend team can integrate from this doc alone.

- [ ] **T-DOC8.6 — Updated data model reference**
      Description: Add `knowledge_articles`, `question_comments`, `ai_usage_events`, `ai_prescreen`, `news_articles.is_featured/featured_order`.
      Files: `Docs/data-model-phase2.md`.
      Acceptance Criteria: Matches Phase-2 Alembic migrations.

- [ ] **T-DOC8.7 — Phase-2 deployment delta**
      Description: New env vars (`TRANSLATION_PROVIDER`, `OPENAI_LLM_MODEL`, `EMBEDDING_DUAL_WRITE`, `EMBEDDING_MODEL_VERSION`), new Celery worker (`celery-ai`), feature flags.
      Files: `Docs/deployment-phase2.md`, `docker-compose.phase2.yml`.
      Acceptance Criteria: Reproducible Phase-1 → Phase-2 upgrade in staging.

- [ ] **T-DOC8.8 — Phase-2 acceptance gate**
      Description: Checklist mapping Phase-2 features to test IDs, latency SLAs, and compliance controls.
      Files: `Docs/uat-gate-phase2.md`.
      Acceptance Criteria: All Phase-2 features have measurable criteria and sign-off.

---

## 9. Infrastructure Tasks

- [ ] **T-INF9.1 — `celery-ai` worker service**
      Description: Add the Phase-2-only `celery-ai` worker to `docker-compose.phase2.yml` (queue=`ai`, concurrency=4, prefetch=1, time_limit=120 s) and to production manifests with a KEDA `ScaledObject` (trigger: `ai` queue length ≥ 10; min=0, max=4) per SAD §10.3.
      Files: `docker-compose.phase2.yml`, `infra/k8s/celery-ai-deployment.yaml`, `infra/k8s/celery-ai-keda.yaml`.
      Acceptance Criteria: Worker consumes the `ai` queue; scales to zero when idle; CI smoke deploy passes.

- [ ] **T-INF9.2 — Phase-2 environment variables**
      Description: Add `OPENAI_API_KEY`, `OPENAI_LLM_MODEL`, `TRANSLATION_PROVIDER`, `AWS_TRANSLATE_REGION`, `EMBEDDING_DUAL_WRITE`, `EMBEDDING_MODEL_VERSION`, `AI_RATE_LIMIT_ASK`, `AI_RATE_LIMIT_SUMMARIZE`, `AI_RATE_LIMIT_TRANSLATE`, `GDPR_EXPORT_URL_TTL` to `.env.example` and secret stores.
      Files: `backend/.env.example`, `infra/secrets/phase2.tfvars`.
      Acceptance Criteria: Backend boots in Phase-2 mode with all vars set; missing var fails fast with a clear error.
