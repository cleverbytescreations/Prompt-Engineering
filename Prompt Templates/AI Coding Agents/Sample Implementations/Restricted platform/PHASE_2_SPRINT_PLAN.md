# Phase 2 Sprint Plan

> Scope: Phase 2, four 2-week sprints, 8 weeks total (Weeks 13–20).
> References: [PHASE_2_API_TASK_CHECKLIST.md](PHASE_2_API_TASK_CHECKLIST.md), [PHASE_2_UI_TASK_CHECKLIST.md](PHASE_2_UI_TASK_CHECKLIST.md).
> Each sprint ends with an end-to-end demoable slice and a 10% payment milestone.

---

## Planning Principles

The contractual sprint headlines are preserved. Internal task sequencing is structured to remove three dependency risks:

1. **Module 0 foundation + first `/ai/*` endpoint land in Sprint 7**, not bunched into a "pre-work" phase. Sprint 8's RAG pipeline cannot start without JWT `preferred_lang`, the `?lang=` dependency, translation cache (Redis db=1), AI envelope/disclaimer middleware, and `/ai/translate` itself.
2. **Cross-cutting items split per sprint**, not batched at the end — OpenAPI annotations, outbox catalogue, runbooks, and tests ship with the sprint that introduces the feature, instead of piling onto Sprint 10.
3. **Sprint 10 absorbs five task groups not in the original sprint table** (Docling structured-data, Q&A discussion comments, Knowledge Article retrieval routes, AI query audit log, embedding migration playbook). These are in the checklists but had no explicit sprint home — they land in Sprint 10 as part of "Intelligent Knowledge Services + Final Release".

---

## Sprint Outcomes (Contractual Headlines — Unchanged)

| Sprint | Duration | Usable Module / Release Outcome | Payment |
|---|---:|---|---:|
| S7  | Wk 13–14 | Multi-language Access Release | 10% |
| S8  | Wk 15–16 | AI Legal Assistant Release | 10% |
| S9  | Wk 17–18 | AI Moderator Assistance Release | 10% |
| S10 | Wk 19–20 | Intelligent Knowledge Services + Final Release | 10% |

---

## Sprint 7 — Multi-language Access Release + Phase-2 Foundation
**Weeks 13–14 · Payment 10%**

**Demoable slice**: user switches locale to FR → URL becomes `/fr/...` → documents/Q&A/news lists render with translated titles + summaries + "translated from EN" badge → user submits a French question and sees the storage notice → admin uses `/admin/translate` to translate arbitrary text → JWT carries `preferred_lang` after profile save.

### Backend
- **Foundation (Module 0)**: T-B0.1 (JWT `preferred_lang` claim), T-B0.2 (`?lang=` dependency), T-B0.3 (Redis db=1 translation cache), T-B0.4 (AI envelope + disclaimer middleware)
- **Translation endpoints**: T-B11.2 (`/ai/translate`), T-B11.3 (`/ai/translate/languages`), T-B11.4 (`/search` honours `?lang=`)
- **Content translation**: T-B5.3 (documents), T-B6.1 (Q&A), T-B7.4 (news)
- **Translation pipeline**: T-I4.1 (provider abstraction + circuit breaker), T-I4.2 (`translation_job`), T-I4.3 (`query_translation_cache_job`), T-I4.6 (non-EN Q&A embedding)
- **Database**: T-D3.6 (`platform_config` seed: `supported_languages=["en","es","fr"]`)
- **API**: T-A2.1 *(Sprint-7 slice — `/ai/translate*`, `?lang=` endpoints, content endpoints)*
- **Security**: T-S5.5 (translation provider key rotation runbook)
- **Logging**: T-L6.4 (translation cache hit-ratio metric + alert)
- **Testing**: T-T7.3 (translation cache + circuit breaker), T-T7.4 (`?lang=` content)
- **Docs**: T-DOC8.3 (translation pipeline runbook), T-DOC8.5 *(Sprint-7 slice — `?lang=` semantics, translate envelope)*
- **Infra**: T-INF9.2 *(Sprint-7 slice — `TRANSLATION_PROVIDER`, `AWS_TRANSLATE_REGION`, translation-related env vars)*
- **Outbox catalogue**: T-I4.14 *(Sprint-7 slice — no new event types this sprint; verify Phase-1 catalogue still passes startup check)*

### Frontend
- **Foundation (Module 0)**: T0.1 (EN/ES/FR locale catalogues + locale switcher), T0.2 (`?lang=` plumbed into all content fetchers), T0.3 (AiDisclaimer component), T0.4 *(Sprint-7 slice — `/ai/translate*`, `/ai/translate/languages` MSW stubs only; `/ai/ask`, `/ai/suggestions`, `/ai/summarize`, audit, usage stubs land in their respective sprints)*
- **Search & translation UI**: T11.2 (search lang picker), T11.3 (standalone translate utility), T11.5 (translation fallback / circuit-open notice)
- **Q&A**: T6.6 (non-EN question submission notice)
- **Profile**: T16.2 (preferred-language editor)
- **Admin**: T14.2 (manage supported languages)

### Why grouped here
Module 0 cannot slip — every Phase-2 endpoint depends on the `?lang=` dependency and AI envelope middleware. `/ai/translate` is the simplest `/ai/*` endpoint and exercises the disclaimer middleware end-to-end, derisking Sprint 8's `/ai/ask`.

### Acceptance gate
- Toggling to FR rewrites URL to `/fr/...` and translates static UI + content list/detail responses (T-T7.4).
- Translation cache hit-ratio metric exposed on `/metrics`; alert wired (T-L6.4).
- Circuit-breaker outage path returns original content with `translation_unavailable=true` flag (T-T7.3).
- `GET /admin/config` reflects `supported_languages=["en","es","fr"]`.

---

## Sprint 8 — AI Legal Assistant Release
**Weeks 15–16 · Payment 10%**

**Demoable slice**: user on `/search` opens AI Ask tab → asks a French question → LangGraph runs synchronously → answer returns back-translated to French with ≥1 citation, confidence indicator, and AI disclaimer → low-confidence path renders "pending expert review" notice and creates a moderation log row → admin sees the audit event in `outbox_events`.

### Backend
- **RAG core**: T-B11.1 (`/ai/ask` LangGraph orchestration), T-B11.5 (BACKTRANS node)
- **LangGraph runtime**: T-I4.4 (workflow wiring, server-side prompt template)
- **AI envelope**: T-A2.2 (standard AI response schema), T-A2.3 *(Sprint-8 slice — `/ai/ask` 20/min rate limit)*
- **Security**: T-S5.1 (prompt-injection mitigation), T-S5.2 (AI authority guard — service + CI check)
- **Logging**: T-L6.1 (Audit Logger node), T-L6.2 (Prometheus token counters), T-L6.3 (confidence histogram), T-L6.5 (moderation log for AI-flagged content)
- **Outbox catalogue**: T-I4.14 *(Sprint-8 slice — register `ai_query.completed|flagged|insufficient` event types + handlers)*
- **API**: T-A2.1 *(Sprint-8 slice — `/ai/ask` endpoint annotations + examples)*
- **Testing**: T-T7.1 (LangGraph unit tests per node), T-T7.2 (`/ai/ask` integration), T-T7.11 *(Sprint-8 slice — `/ai/ask` rate-limit only)*, T-T7.12 (prompt-injection regression), T-T7.13 (load test, p95 ≤ 2,500 ms)
- **Docs**: T-DOC8.2 (LangGraph runbook), T-DOC8.4 (AI compliance & disclaimer docs)
- **Infra**: T-INF9.1 (`celery-ai` worker + KEDA), T-INF9.2 *(Sprint-8 slice — `OPENAI_API_KEY`, `OPENAI_LLM_MODEL`, `AI_RATE_LIMIT_ASK`)*

### Frontend
- **AI Ask UI**: T11.1 (`/search` AI Ask tab + answer + citations + confidence indicator)
- **Back-translation UI**: T11.4 ("Translated from XX" badge + "Show original" toggle)
- **MSW**: T0.4 *(Sprint-8 slice — `/ai/ask` fixtures covering high/mid/low confidence bands)*

### Why grouped here
`/ai/ask` is the centrepiece of the AI Legal Assistant release. All security guards, audit logging, and load-testing infrastructure for the LLM pipeline land here so Sprint 9's lighter AI features (suggestions, summarisation) can reuse the same envelope, rate-limit, and audit primitives.

### Acceptance gate
- High-confidence `/ai/ask` returns answer + ≥1 citation within p95 ≤ 2,500 ms on documented UAT hardware (T-T7.13).
- Low-confidence path returns expert-review envelope + writes `moderation_logs` row with `action='escalate'` (T-T7.2).
- Exactly one `outbox_events` row per invocation; 30-day TTL prunes correctly (T-L6.1 + T-I4.10 Phase-1 cleanup).
- Prompt-injection adversarial cases handled (T-T7.12).
- CI grep rule fires if any `workers/ai/` module imports `qa_service.set_verified` (T-S5.2).
- Non-EN ask returns back-translated answer + snippets; circuit-open returns English with fallback flag (T-B11.5).

---

## Sprint 9 — AI Moderator Assistance Release
**Weeks 17–18 · Payment 10%**

**Demoable slice**: member submits a question → AI pre-screen runs within 60s and writes `ai_prescreen` JSONB → moderation queue row shows an AI flag chip with reason → moderator opens the question → AI Suggestions panel renders ranked source passages (no LLM answer) → moderator pastes a citation into the answer composer → on a long thread, "Summarise thread" returns a ≤300-word summary with disclaimer → on a document detail page, "Generate summary" returns a 200-word summary cached for 30 days.

### Backend
- **AI assistance endpoints**: T-B5.2 (`/ai/summarize/{document_id}`), T-B6.4 (`/ai/summarize/question/{question_id}`), T-B6.6 (`/ai/suggestions/{question_id}` — abbreviated RAG)
- **Content pre-screening**: T-I4.5 (`ai_content_flag_job`), T-B9.1 (moderation queue surfaces `ai_prescreen`)
- **Database**: T-D3.5 (add `ai_prescreen` JSONB to documents/questions/news_articles/posts), T-D3.8 *(Sprint-9 slice — `ai_prescreen` keyword field on `ica_document_chunks`, `ica_questions`, `ica_news`, `ica_posts` templates)*
- **AI workers — usage emission**: T-I4.9 (all AI workers insert into `ai_usage_events`)
- **Security**: T-S5.6 (restrict `/ai/suggestions` to A/M)
- **API**: T-A2.1 *(Sprint-9 slice — `/ai/summarize*`, `/ai/suggestions` annotations)*, T-A2.3 *(Sprint-9 slice — `/ai/summarize/*` 10/min, `/ai/translate` 60/min rate limits)*
- **Outbox catalogue**: T-I4.14 *(Sprint-9 slice — register `document.updated` for summary cache invalidation)*
- **Testing**: T-T7.11 *(Sprint-9 slice — `/ai/suggestions` member-role 403 + summarize rate limits)*
- **Infra**: T-INF9.2 *(Sprint-9 slice — `AI_RATE_LIMIT_SUMMARIZE`, `AI_RATE_LIMIT_TRANSLATE`)*

### Frontend
- **Q&A AI panels**: T6.1 (AI suggestions panel for A/M), T6.2 (thread summary dialog)
- **Repository AI**: T5.2 (document summary modal)
- **Moderation UI**: T9.1 (AI pre-screen flag chip), T9.2 (link from queue to AI suggestions)
- **MSW**: T0.4 *(Sprint-9 slice — `/ai/summarize/*` + `/ai/suggestions/{id}` fixtures)*

### Why grouped here
All three moderator-facing AI features (pre-screen, suggestions, summarisation) reuse the AI envelope + audit + rate-limit primitives delivered in Sprint 8. `ai_usage_events` writes land here because Sprint 10's dashboard needs a populated table to aggregate.

### Acceptance gate
- Pending submission receives `ai_prescreen` flag within 60s (T-I4.5).
- `/ai/summarize/{document_id}` repeat call ≤ 50 ms (cache hit); cache cleared on `document.updated` outbox event (T-B5.2).
- Member call to `/ai/suggestions/{id}` returns 403 (T-T7.11).
- AI Suggestions panel hidden for member role on `/questions/[id]` (T6.1).
- AI flag chip rendered on every queue row where job has run; no extra DB join in queue endpoint (T-B9.1).

---

## Sprint 10 — Intelligent Knowledge Services + Final Release
**Weeks 19–20 · Payment 10%**

**Demoable slice**: A/M promotes a verified Q&A → knowledge article appears at `/knowledge/[id]` with back-link → article surfaces in `/search` with discriminator chip → user opens a document detail page → Docling structured-data tab renders extracted tables + section outline + key/value pairs → user adds a comment to a question → question author receives in-app notification → admin opens `/admin/analytics` AI usage section → line chart + stacked bar + top-users table render → admin opens `/admin/ai-audit` → filtered audit rows render with colour-banded confidence → user requests `/profile/export` → background job produces `.tar.gz` → notification with download link arrives.

### Backend — Sprint-plan headline items
- **Related content (k-NN)**: T-B5.1 (documents), T-B6.2 (Q&A), T-B7.3 (news), T-B8.1 (posts)
- **Promote Q&A → knowledge article**: T-B6.3 (`/questions/{id}/promote`), T-A2.5 (idempotent promote)
- **News pinning/featuring**: T-B7.1 (`PATCH /news/{id}/feature` + reorder), T-B7.2 (`?featured=` filter), T-D3.3 (`is_featured`, `featured_order` migration + partial index), T-I4.7 (search cache invalidation)
- **AI usage/cost dashboard**: T-B14.1 (`GET /admin/ai-usage`), T-D3.4 (`ai_usage_events` table + indexes), T-B14.2 (`PUT /admin/config` BCP-47 validation)
- **GDPR data export**: T-B16.1 (`/users/me/export` + polling), T-D3.9 (`gdpr_export_jobs` table), T-I4.8 (`gdpr_export_job` worker, `.tar.gz` + manifest), T-S5.3 (1/day rate limit), T-S5.4 (24h pre-signed URL TTL + CORS)

### Backend — Five extra task groups absorbed into Sprint 10
- **Docling structured-data**: T-B5.4 (`structured_data` on document detail + paginated endpoint), T-D3.10 (verify Phase-1 persistence + optional GIN index)
- **Q&A discussion comments**: T-B6.5 (CRUD endpoints + notification), T-D3.2 (`question_comments` migration), T-A2.4 (cursor pagination)
- **Knowledge Article retrieval routes**: T-B6.7 (`GET /knowledge-articles` list + detail), T-D3.1 (`knowledge_articles` migration), T-D3.8 *(Sprint-10 slice — `ica_knowledge_articles` template + `is_featured`/`featured_order` on `ica_news`)*, T-I4.12 (indexing pipeline + search discriminator)
- **AI query audit log**: T-B14.3 (`GET /admin/ai-audit`), T-B14.4 (`ai_audit_retention_days` config + wire T-I4.10), T-D3.11 (partial indexes on `outbox_events` for AI audit), T-I4.10 (confirm 30-day TTL scoped to `ai_query.%`)
- **Embedding migration playbook (R5-G12)**: T-D3.7 (`chunk_vector_v2` field), T-I4.11 (`embedding_backfill_job` + 6-step playbook)

### Backend — Cross-cutting (Sprint-10 closeout)
- **Outbox catalogue**: T-I4.14 *(Sprint-10 slice — register `knowledge_article.created`, `news.featured_changed`, `gdpr_export.requested|completed`, `question_comment.deleted`; assert every Phase-2 event type resolves to a registered handler)*
- **Notifications**: T-I4.13 (`question_commented`, `gdpr_export.requested`, `gdpr_export.completed` types + EN/ES/FR templates)
- **API**: T-A2.1 *(Sprint-10 slice — all remaining endpoints: related, promote, comments, knowledge articles, news feature, AI usage, AI audit, GDPR export; export full `Docs/openapi-phase2.yaml`)*
- **Testing**: T-T7.5 (promote idempotency), T-T7.6 (Q&A comments), T-T7.7 (news feature), T-T7.8 (related-content latency), T-T7.9 (AI usage dashboard aggregation), T-T7.10 (GDPR export), T-T7.14 (embedding migration dry-run), T-T7.15 (Docling structured-data)
- **Logging**: T-L6.6 (GDPR job audit events)
- **Docs**: T-DOC8.1 (OpenAPI export in CI), T-DOC8.5 *(Sprint-10 slice — related-content shapes, comments contract, promote contract, GDPR export flow)*, T-DOC8.6 (data model reference), T-DOC8.7 (deployment delta), T-DOC8.8 (UAT acceptance gate)
- **Infra**: T-INF9.2 *(Sprint-10 slice — `EMBEDDING_DUAL_WRITE`, `EMBEDDING_MODEL_VERSION`, `GDPR_EXPORT_URL_TTL`)*

### Frontend — Sprint-plan headline items
- **Related content panels**: T5.1 (documents), T6.5 (Q&A), T7.3 (news), T8.1 (posts)
- **Promote Q&A**: T6.3 (promote button), T18.3 (toast deep-link target)
- **News pinning/featuring**: T7.1 (feature toggle dialog + drag reorder), T7.2 (featured carousel + filter)
- **AI usage dashboard**: T14.1 (`/admin/analytics` AI usage section — line chart + stacked bar + top-users table + CSV export), T14.3 (AI confidence thresholds editor)
- **GDPR export**: T16.1 (`/profile/export` page + polling)

### Frontend — Five extra task groups absorbed into Sprint 10
- **Docling structured-data**: T5.3 (StructuredDataTab + ExtractedTable + DocumentOutline + KeyValueList), T5.4 (MSW fixtures with/without structured data)
- **Q&A discussion comments**: T6.4 (comments thread + composer + optimistic post)
- **Knowledge Article routes**: T18.1 (`/knowledge/[id]` detail), T18.2 (`/knowledge` list + search-result card variant)
- **AI query audit log**: T14.4 (`/admin/ai-audit` page + filters + CSV export), T14.5 (`ai_audit_retention_days` editor in `/admin/config`)
- **Notifications (Phase-2 types)**: T10.1 (`question_commented`), T10.2 (`gdpr_export.*`)

### Frontend — Cross-cutting (Sprint-10 closeout)
- **MSW**: T0.4 *(Sprint-10 slice — `/admin/ai-audit`, `/admin/ai-usage`, `/{type}/{id}/related`, structured-data fixtures)*
- **Cross-cutting**: T17.1 (Playwright smoke + Phase-1 regression), T17.2 (a11y re-audit), T17.3 (README + onboarding docs)

### Why grouped here
The five extra task groups have no earlier sprint home and all align with "Intelligent Knowledge Services": Docling surfaces existing extracted data, Q&A comments complete the social Q&A loop, Knowledge Article routes complete the promote flow (promote endpoint is half-built without `/knowledge/[id]`), AI audit log is the governance counterpart to the AI usage dashboard, and the embedding migration playbook is operational readiness for production. Sprint 10 is the natural release-hardening window for all of them.

### Acceptance gate
- All k-NN related endpoints p95 ≤ 200 ms (T-T7.8).
- Promote idempotent — second call returns same article id (T-T7.5); promoted article searchable within 60s with `knowledge_article` discriminator (T-I4.12).
- `/admin/ai-usage`: `sum(rows[].estimated_cost_usd) == totals.estimated_cost_usd` exactly; CSV export valid; non-Admin 403 (T-T7.9).
- `/admin/ai-audit`: filtered rows match seeded fixtures; `confidence_band=low` returns only `<0.50` rows; retention notice reflects `platform_config.ai_audit_retention_days` (T-B14.3).
- GDPR archive contains only requester's data; pre-signed URL valid then expires after 24h; 2nd request within 24h → 429 (T-T7.10 + T-S5.3).
- News featured listing uses partial index (`EXPLAIN ANALYZE`); concurrent reorder → 409 (T-D3.3 + T-B7.1).
- Docling structured-data tab appears only when present; cell values not translated; > 20 tables paginate via dedicated endpoint (T-T7.15).
- Embedding migration 6-step playbook completes on staging without data loss; cosine similarity v1↔v2 ≥ 0.85 on 1% sample; search recall@10 unchanged (T-T7.14).
- Outbox event catalogue startup check passes — every declared Phase-2 event type resolves to a registered handler (T-I4.14).
- Playwright smoke: AI Ask, Q&A comment, news feature toggle, GDPR export request — all green; Phase-1 regression specs green (T17.1).
- UAT acceptance gate (T-DOC8.8) signed off; full `Docs/openapi-phase2.yaml` exported in CI without drift.

---

## Cross-Sprint Task Index

For convenience, this table maps every Phase-2 task ID to its sprint. Tasks marked *(split)* deliver an incremental slice per sprint.

### Backend tasks

| Task | Sprint | Notes |
|---|---|---|
| T-B0.1, T-B0.2, T-B0.3, T-B0.4 | S7 | Module 0 foundation |
| T-B5.1 | S10 | `/documents/{id}/related` |
| T-B5.2 | S9 | `/ai/summarize/{document_id}` |
| T-B5.3 | S7 | Documents `?lang=` |
| T-B5.4 | S10 | Docling structured-data |
| T-B6.1 | S7 | Q&A `?lang=` |
| T-B6.2 | S10 | `/questions/{id}/related` |
| T-B6.3 | S10 | Promote to knowledge article |
| T-B6.4 | S9 | Q&A thread summarisation |
| T-B6.5 | S10 | Q&A discussion comments |
| T-B6.6 | S9 | `/ai/suggestions/{question_id}` |
| T-B6.7 | S10 | Knowledge article retrieval |
| T-B7.1, T-B7.2 | S10 | News feature/reorder |
| T-B7.3 | S10 | `/news/{id}/related` |
| T-B7.4 | S7 | News `?lang=` |
| T-B8.1 | S10 | `/posts/{id}/related` |
| T-B9.1 | S9 | Moderation queue AI pre-screen surface |
| T-B11.1 | S8 | `/ai/ask` LangGraph |
| T-B11.2, T-B11.3, T-B11.4 | S7 | Translate endpoints + search `?lang=` |
| T-B11.5 | S8 | BACKTRANS node |
| T-B14.1 | S10 | AI usage dashboard endpoint |
| T-B14.2 | S10 | `supported_languages` validation |
| T-B14.3, T-B14.4 | S10 | AI audit log + retention config |
| T-B16.1 | S10 | GDPR export endpoint |

### Database tasks

| Task | Sprint |
|---|---|
| T-D3.1, T-D3.2, T-D3.3, T-D3.4, T-D3.9, T-D3.11 | S10 |
| T-D3.5 | S9 |
| T-D3.6 | S7 |
| T-D3.7 | S10 (embedding migration) |
| T-D3.8 | S9 (slice — `ai_prescreen` fields), S10 (slice — `ica_knowledge_articles`, news featured fields) |
| T-D3.10 | S10 (Docling verification) |

### Integration tasks

| Task | Sprint |
|---|---|
| T-I4.1, T-I4.2, T-I4.3, T-I4.6 | S7 |
| T-I4.4 | S8 |
| T-I4.5 | S9 |
| T-I4.7, T-I4.8, T-I4.10, T-I4.11, T-I4.12, T-I4.13 | S10 |
| T-I4.9 | S9 (AI usage event emission) |
| T-I4.14 | *(split)* S7, S8, S9, S10 |

### API tasks

| Task | Sprint |
|---|---|
| T-A2.1 (OpenAPI annotations) | *(split)* S7, S8, S9, S10 |
| T-A2.2 (AI envelope schema) | S8 |
| T-A2.3 (AI rate limits) | *(split)* S8 (`/ai/ask`), S9 (`/ai/summarize`, `/ai/translate`), S10 (`/users/me/export` 1/day) |
| T-A2.4 | S10 |
| T-A2.5 | S10 |

### Security tasks

| Task | Sprint |
|---|---|
| T-S5.1, T-S5.2 | S8 |
| T-S5.3, T-S5.4 | S10 |
| T-S5.5 | S7 |
| T-S5.6 | S9 |

### Logging & audit tasks

| Task | Sprint |
|---|---|
| T-L6.1, T-L6.2, T-L6.3, T-L6.5 | S8 |
| T-L6.4 | S7 |
| T-L6.6 | S10 |

### Testing tasks

| Task | Sprint |
|---|---|
| T-T7.1, T-T7.2, T-T7.12, T-T7.13 | S8 |
| T-T7.3, T-T7.4 | S7 |
| T-T7.5, T-T7.6, T-T7.7, T-T7.8, T-T7.9, T-T7.10, T-T7.14, T-T7.15 | S10 |
| T-T7.11 | *(split)* S8 (`/ai/ask` rate limit), S9 (`/ai/suggestions` RBAC + summarize rate limits) |

### Docs tasks

| Task | Sprint |
|---|---|
| T-DOC8.1 | S10 |
| T-DOC8.2, T-DOC8.4 | S8 |
| T-DOC8.3 | S7 |
| T-DOC8.5 | *(split)* S7 (`?lang=` + translate), S10 (related, comments, promote, GDPR) |
| T-DOC8.6, T-DOC8.7, T-DOC8.8 | S10 |

### Infra tasks

| Task | Sprint |
|---|---|
| T-INF9.1 | S8 (`celery-ai` worker + KEDA) |
| T-INF9.2 | *(split)* S7 (translation env vars), S8 (LLM env vars + `AI_RATE_LIMIT_ASK`), S9 (summarize/translate rate-limit vars), S10 (embedding + GDPR vars) |

### Frontend tasks

| Task | Sprint |
|---|---|
| T0.1, T0.2, T0.3 | S7 |
| T0.4 | *(split)* S7 (translate stubs), S8 (`/ai/ask` stubs), S9 (summarize + suggestions stubs), S10 (audit, usage, related, structured-data stubs) |
| T5.1 | S10 |
| T5.2 | S9 |
| T5.3, T5.4 | S10 |
| T6.1, T6.2 | S9 |
| T6.3, T6.4, T6.5 | S10 |
| T6.6 | S7 |
| T7.1, T7.2, T7.3 | S10 |
| T8.1 | S10 |
| T9.1, T9.2 | S9 |
| T10.1, T10.2 | S10 |
| T11.1, T11.4 | S8 |
| T11.2, T11.3, T11.5 | S7 |
| T14.1, T14.3 | S10 |
| T14.2 | S7 |
| T14.4, T14.5 | S10 |
| T16.1 | S10 |
| T16.2 | S7 |
| T17.1, T17.2, T17.3 | S10 |
| T18.1, T18.2, T18.3 | S10 |

---

## Payment Milestone Summary

| Sprint | End-of-sprint payment trigger | Cumulative |
|---|---|---:|
| S7 | Multi-language access live in staging; translation cache hit ratio reported; `/ai/translate` returns translated text with disclaimer | 10% |
| S8 | `/ai/ask` p95 ≤ 2,500 ms on UAT hardware; high/mid/low confidence paths demoable; back-translation working for FR | 20% |
| S9 | AI pre-screen flagging visible in moderation queue; document + thread summaries live; AI suggestions panel restricted to A/M | 30% |
| S10 | All extra task groups complete; UAT acceptance gate signed off; Phase-1 regression suite green; production deployment delta verified | 40% |
