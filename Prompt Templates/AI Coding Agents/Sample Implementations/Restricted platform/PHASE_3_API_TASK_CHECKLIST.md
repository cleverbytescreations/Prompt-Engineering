# Implementation Task Checklist (API) — Phase 3

> Scope: Phase-3 additions per SAD §14.2 — LiveKit live expert sessions, knowledge graph (Neo4j/Neptune), native-mobile push delivery (FCM/APNS), external legal API integrations (`legal_import_job`), advanced analytics & personalised recommendations, organisation-level content siloing (`org_visibility`), expanded language support, private messaging (WebSocket), microservices extraction of Search and AI services, and SSE `/notifications/stream`.
> Builds on Phase-1 & Phase-2 infrastructure. All additions are deployment-additive.

---

## 1. Backend Tasks

### Module 0 — Foundation Updates

- [ ] **T-B0.1 — Add `org_visibility` to JWT context resolution**
      Description: Every authenticated request resolves the user's org and exposes `(user_id, org_id, role)` to services for visibility filtering.
      Files: `backend/app/core/deps.py`, `backend/app/core/security.py`.
      Acceptance Criteria: Service-layer queries see `current_user.org_id`.

- [ ] **T-B0.2 — WebSocket support in FastAPI**
      Description: Enable WebSocket endpoints (messaging, presence) with JWT-over-query/sub-protocol auth and per-connection rate limits.
      Files: `backend/app/core/ws.py`, `backend/app/main.py`.
      Acceptance Criteria: WS handshake authenticates via Bearer token; unauthorised handshakes return 401 close code.

- [ ] **T-B0.3 — Server-Sent Events transport**
      Description: SSE response helper; ALB idle timeout tuned to 300 s; periodic ping every 25 s to keep connection alive.
      Files: `backend/app/core/sse.py`.
      Acceptance Criteria: Stream survives 5-minute idle period; reconnect with `Last-Event-ID` resumes from cursor.

- [ ] **T-B0.4 — Service-discovery + gateway readiness (microservices prep)**
      Description: Introduce internal API gateway config (Kong/AWS API Gateway) routing `/api/v1/search/*` and `/api/v1/ai/*` to dedicated services; rest stays on the monolith.
      Files: `infra/kong/kong.yml`, `backend/app/main.py` (service-split flag).
      Implementation Notes: Service extraction is reversible — both monolith and split modes pass the same integration tests.
      Acceptance Criteria: Same contract honoured in monolith and split mode.

---

### Module 10 — Notifications (Phase-3)

- [ ] **T-B10.1 — `GET /notifications/stream` (SSE)**
      Description: Long-lived stream pushing notification events + badge counts. Falls back to piggyback header when client disconnects.
      Files: `backend/app/api/v1/notifications.py`, `backend/app/services/notification_stream_service.py`, `backend/app/core/sse.py`.
      Implementation Notes: Per-user Redis pub/sub channel `notif:{user_id}`. `notification_dispatch_job` publishes here in addition to inserting rows.
      Acceptance Criteria: Two clients of the same user receive the same event; ALB 300 s ping verified.

- [ ] **T-B10.2 — Push subscription endpoints**
      Description: `POST /users/me/push-subscriptions`, `DELETE /users/me/push-subscriptions/{id}`, `GET /users/me/push-subscriptions`.
      Files: `backend/app/api/v1/push.py`, `backend/app/services/push_service.py`, `backend/app/repositories/push_subscriptions_repo.py`, Alembic migration.
      Implementation Notes: Stores FCM / APNS tokens with platform, device id, last-seen.
      Acceptance Criteria: Token round-trips; duplicate token de-duped.

- [ ] **T-B10.3 — Extend `notification_dispatch_job` with push channel**
      Description: Add FCM and APNS delivery alongside in-app and email.
      Files: `backend/app/workers/notifications/dispatch.py`, `backend/app/services/push_providers/{fcm.py,apns.py}`.
      Acceptance Criteria: Notification delivered to mobile device under 5 s p95.

---

### Module 17 — Live Expert Sessions (LiveKit)

- [ ] **T-B17.1 — `POST /sessions` — create LiveKit room**
      Description: Create `sessions` row in PostgreSQL; create LiveKit room via server SDK; return session metadata.
      Files: `backend/app/api/v1/sessions.py`, `backend/app/services/session_service.py`, `backend/app/services/livekit_client.py`, `backend/app/repositories/sessions_repo.py`, Alembic migration.
      Implementation Notes: Schema: `id`, `title`, `topic`, `country`, `category_id`, `scheduled_at`, `started_at`, `ended_at`, `recording_url`, `status`, `host_id`, `created_at`.
      Acceptance Criteria: Restricted to A/M; participants notified via outbox.

- [ ] **T-B17.2 — `POST /sessions/{id}/token` — mint participant tokens**
      Description: Generate scoped LiveKit JWT for a participant (publish + subscribe permissions tied to role).
      Files: `backend/app/api/v1/sessions.py`, `backend/app/services/livekit_client.py`.
      Acceptance Criteria: Generated token authenticates against LiveKit server; expires after configurable TTL.

- [ ] **T-B17.3 — Session CRUD + listing endpoints**
      Description: `GET /sessions`, `GET /sessions/{id}`, `PATCH /sessions/{id}`, `DELETE /sessions/{id}`, `GET /sessions/my`.
      Files: `backend/app/api/v1/sessions.py`, `backend/app/services/session_service.py`.
      Acceptance Criteria: Filtering by status (upcoming/active/past) works.

- [ ] **T-B17.4 — LiveKit webhook receiver**
      Description: `POST /webhooks/livekit` consumes `room_started`, `participant_joined`, `room_finished`, `recording_ready`; dispatches `session_event_job`.
      Files: `backend/app/api/v1/webhooks.py`, `backend/app/services/livekit_webhook_service.py`.
      Implementation Notes: Verify webhook signature; idempotent processing (event-id dedupe in Redis).
      Acceptance Criteria: Replayed webhook does not duplicate state.

- [ ] **T-B17.5 — `session_event_job`**
      Description: On `recording_ready`, transcribe (Whisper or equivalent), summarise, auto-create pending news/summary entries (A/M can edit and approve).
      Files: `backend/app/workers/sessions/session_event.py`.
      Acceptance Criteria: Post-session, a pending news draft appears in moderation queue.

- [ ] **T-B17.6 — Recording storage and retrieval**
      Description: LiveKit stores to S3; backend issues short-lived pre-signed GET for playback (`GET /sessions/{id}/recording`).
      Files: `backend/app/services/storage_service.py`, `backend/app/api/v1/sessions.py`.
      Acceptance Criteria: Recording URL expires after configurable TTL.

---

### Module 18 — Knowledge Graph

- [ ] **T-B18.1 — `GET /knowledge-graph/explore`**
      Description: Returns subgraph rooted at `root` (entity id or doc id) with `depth` and `entity_type` filters.
      Files: `backend/app/api/v1/knowledge_graph.py`, `backend/app/services/knowledge_graph_service.py`, `backend/app/repositories/graph_repo.py`.
      Implementation Notes: Default `depth=2`; cap at 3 to limit blast radius.
      Acceptance Criteria: 200-node subgraph returned ≤ 500 ms p95.

- [ ] **T-B18.2 — `GET /knowledge-graph/search`**
      Description: Entity name fuzzy search (Neo4j full-text index).
      Files: `backend/app/api/v1/knowledge_graph.py`, `backend/app/services/knowledge_graph_service.py`.
      Acceptance Criteria: Substring match returns ≤ 20 ranked entities.

- [ ] **T-B18.3 — `GET /knowledge-graph/entities/{id}`**
      Description: Entity detail + linked documents/Q&A/news ids.
      Files: `backend/app/api/v1/knowledge_graph.py`.
      Acceptance Criteria: Linked content list returned with content type + id.

- [ ] **T-B18.4 — Entity extraction pipeline**
      Description: Celery `entity_extraction_job` (SpaCy or LLM-based) runs after `embedding_generation_job`; writes nodes/edges to Neo4j (or Neptune).
      Files: `backend/app/workers/graph/entity_extraction.py`, `backend/app/services/graph_writer.py`.
      Implementation Notes: Extract law-to-law, concept-to-concept, jurisdiction relationships from approved documents. Idempotent re-runs.
      Acceptance Criteria: Approved doc adds expected nodes/edges; reprocessing does not duplicate.

---

### Module 19 — Private Messaging

- [ ] **T-B19.1 — Conversations + messages tables**
      Description: `conversations(id, type, created_at, last_message_at)`, `conversation_participants(conversation_id, user_id, joined_at, read_at)`, `messages(id, conversation_id, sender_id, body, created_at)`.
      Files: `backend/alembic/versions/03xx_messaging.py`, `backend/app/models/{conversation.py,message.py}`.
      Acceptance Criteria: Migration round-trips; indexes on `(conversation_id, created_at)` and `(user_id, conversation_id)` present.

- [ ] **T-B19.2 — REST endpoints (history fetch)**
      Description: `GET /conversations`, `POST /conversations`, `GET /conversations/{id}/messages` (cursor), `POST /conversations/{id}/messages`, `PATCH /conversations/{id}/read`.
      Files: `backend/app/api/v1/messaging.py`, `backend/app/services/messaging_service.py`, `backend/app/repositories/messaging_repo.py`.
      Acceptance Criteria: History fetch stable under concurrent inserts.

- [ ] **T-B19.3 — WebSocket endpoint `/ws/messaging`**
      Description: Per-user socket; subscribe to all conversations the user participates in. Server pushes new-message events; client publishes send events.
      Files: `backend/app/api/v1/ws_messaging.py`, `backend/app/services/messaging_ws.py`.
      Implementation Notes: Redis pub/sub channel `conv:{id}`. Audit log entry per message (compliance).
      Acceptance Criteria: Two users connected exchange messages in real time; reconnect resumes with last-seen cursor.

- [ ] **T-B19.4 — Message audit log**
      Description: Append-only audit table (compliance per SAD §14.2 messaging note).
      Files: Alembic migration `messaging_audit`.
      Acceptance Criteria: Every message yields an audit row; immutable.

---

### Module 20 — External Legal API Integrations

- [ ] **T-B20.1 — `import_sources` table + admin CRUD endpoints**
      Description: Manage external connectors: jurisdiction, base URL, auth secret ref, schedule.
      Files: `backend/app/api/v1/admin_imports.py`, `backend/app/services/import_sources_service.py`, Alembic migration.
      Acceptance Criteria: Admin-only CRUD verified.

- [ ] **T-B20.2 — `legal_import_job` Celery worker (ingestion queue)**
      Description: Periodic fetch; feeds documents into Docling → chunk → embed → index pipeline; tagged `is_official=true`.
      Files: `backend/app/workers/imports/legal_import.py`.
      Implementation Notes: Respect robots.txt + per-source rate limits; circuit-breaker on failures.
      Acceptance Criteria: Source pull yields approved-status documents (auto-approved when `is_official=true`); rerun is idempotent.

- [ ] **T-B20.3 — `documents.is_official` column + filter support**
      Description: Add `is_official BOOLEAN NOT NULL DEFAULT FALSE`; surface in list filters.
      Files: `backend/alembic/versions/03xx_documents_is_official.py`, `backend/app/services/document_service.py`.
      Acceptance Criteria: `GET /documents?official=true` returns only official docs.

---

### Module 21 — Advanced Analytics & Recommendations

- [ ] **T-B21.1 — `GET /recommendations` (cross-content rail)**
      Description: Personalised content list for dashboard.
      Files: `backend/app/api/v1/recommendations.py`, `backend/app/services/recommendation_service.py`.
      Implementation Notes: Use member preferences + activity history; cold-start falls back to popularity.
      Acceptance Criteria: Returns ≤ 20 items; cold-start path covered by tests.

- [ ] **T-B21.2 — `GET /recommendations/{type}` (per content type)**
      Description: Per-type recs (`documents|questions|news|posts`).
      Files: `backend/app/api/v1/recommendations.py`.
      Acceptance Criteria: Each type returns ≤ 20 items.

- [ ] **T-B21.3 — Feature store + lightweight ML serving layer**
      Description: Redis-backed user/item feature vectors; FastAPI scoring endpoint or in-process scorer.
      Files: `backend/app/services/recommendation_scorer.py`, `backend/app/core/feature_store.py`.
      Acceptance Criteria: p95 ≤ 200 ms for personalised list.

- [ ] **T-B21.4 — OpenSearch Percolator queries (real-time interest matching)**
      Description: Index user-interest queries as percolators; new approved content runs against percolator index to generate targeted notifications.
      Files: `backend/app/workers/notifications/percolator_match.py`, `backend/app/repositories/opensearch_repo.py`.
      Acceptance Criteria: Member subscribed to a niche interest receives notification on matching approval.

---

### Module 22 — Organisation-level Content Siloing

- [ ] **T-B22.1 — Add `org_visibility` to content tables**
      Description: Add `org_visibility TEXT NOT NULL DEFAULT 'public' CHECK (org_visibility IN ('public','org_only'))` to `documents`, `questions`, `news_articles`, `posts`.
      Files: `backend/alembic/versions/03xx_org_visibility.py`.
      Acceptance Criteria: Migration round-trips; backfill sets existing rows to `public`.

- [ ] **T-B22.2 — Visibility filter in all list/detail/search queries**
      Description: When item is `org_only`, only members of the contributor's org can list/detail/search it. Apply at SQL and OpenSearch query level.
      Files: `backend/app/services/{document,qa,news,post,search}_service.py`, `backend/app/repositories/opensearch_repo.py`.
      Implementation Notes: OpenSearch filter `(org_visibility=public) OR (org_visibility=org_only AND contributor_org=requester_org)`.
      Acceptance Criteria: Member of org A does not see org-only content of org B in any endpoint.

- [ ] **T-B22.3 — Per-org default visibility + per-item override**
      Description: `organizations.default_visibility`; per-item override at creation.
      Files: Alembic + services.
      Acceptance Criteria: Defaults applied; overrides honoured.

---

### Module 23 — Expanded Language Support

- [ ] **T-B23.1 — Extend `supported_languages` to include Arabic, Portuguese, etc.**
      Description: Update `platform_config` seed and translation provider config.
      Files: `backend/alembic/versions/03xx_supported_languages.py`.
      Acceptance Criteria: `/ai/translate/languages` returns expanded list.

- [ ] **T-B23.2 — RTL-aware text storage and indexing**
      Description: Validate UTF-8 + bidi marks; OpenSearch analyzer configuration per language (Arabic stemmer, Portuguese stop words).
      Files: `backend/app/workers/indexing/templates/*.json`.
      Acceptance Criteria: Arabic query returns relevant Arabic-content results.

---

### Module 24 — Microservices Extraction (Search + AI)

- [ ] **T-B24.1 — Extract `SearchService` as standalone FastAPI app**
      Description: New `services/search/` repo (or workspace) with same `/api/v1/search` contract; deploys independently; gateway routes to it.
      Files: `services/search/` project, shared `core/` package, `infra/kong/routes.yml`.
      Acceptance Criteria: Search responses identical between monolith and extracted service.

- [ ] **T-B24.2 — Extract `AIService` as standalone FastAPI app**
      Description: New `services/ai/` with `/api/v1/ai/*` + LangGraph workers; shared OpenSearch + Redis access via internal network.
      Files: `services/ai/` project, `infra/kong/routes.yml`.
      Acceptance Criteria: `/ai/ask` & co. identical behaviour, monitored independently.

- [ ] **T-B24.3 — Inter-service auth (mTLS or signed service JWT)**
      Description: Service-to-service auth between gateway, monolith, search, AI services.
      Files: `backend/app/core/service_auth.py`, gateway config.
      Acceptance Criteria: External clients cannot bypass the gateway.

---

## 2. API Tasks

- [ ] **T-A2.1 — OpenAPI annotations for all Phase-3 endpoints**
      Description: Sessions, knowledge graph, messaging, recommendations, push, imports, SSE.
      Files: `backend/app/api/v1/*.py`, `backend/app/schemas/*.py`.
      Acceptance Criteria: Exported `Docs/openapi-phase3.yaml` committed and used by frontend codegen.

- [ ] **T-A2.2 — Cursor pagination for `/conversations`, `/messages`, `/sessions`**
      Description: Reuse Phase-1 cursor utility.
      Files: `backend/app/core/pagination.py`.
      Acceptance Criteria: Stable under concurrent inserts.

- [ ] **T-A2.3 — Rate limits for messaging + sessions**
      Description: WS message send: 60/min/user; session-creation: 10/hour/user; recording GET: 30/min/user.
      Files: `backend/app/core/rate_limit.py`.
      Acceptance Criteria: 429 returned and propagated to WS clients via control frame.

- [ ] **T-A2.4 — Webhook signature verification helper**
      Description: HMAC verification utility used by LiveKit webhook (and future webhooks).
      Files: `backend/app/core/webhooks.py`.
      Acceptance Criteria: Invalid signature → 401; replay-protected via Redis-key dedupe.

- [ ] **T-A2.5 — Backwards-compatible `/health/ready` includes Neo4j + LiveKit + WS broker**
      Description: Extend readiness probe to include new dependencies.
      Files: `backend/app/api/v1/system.py`.
      Acceptance Criteria: Probe degrades correctly when any new dep is unreachable.

---

## 3. Database Tasks

- [ ] **T-D3.1 — Migration: `sessions` + indexes**
      Description: Table per T-B17.1; index on `(scheduled_at)`, `(host_id)`, `(status)`.
      Files: `backend/alembic/versions/03xx_sessions.py`, `backend/app/models/session.py`.
      Acceptance Criteria: Round-trip clean.

- [ ] **T-D3.2 — Migration: `conversations`, `conversation_participants`, `messages`, `messaging_audit`**
      Description: Schema per T-B19.1 + audit table.
      Files: `backend/alembic/versions/03xx_messaging.py`.
      Acceptance Criteria: Indexes verified; audit append-only enforced via grants.

- [ ] **T-D3.3 — Migration: `push_subscriptions`**
      Description: `id, user_id, platform, token, last_seen_at, created_at`; unique on (user_id, token).
      Files: `backend/alembic/versions/03xx_push_subscriptions.py`.
      Acceptance Criteria: Duplicate insert → upsert.

- [ ] **T-D3.4 — Migration: `import_sources`**
      Description: Source connectors metadata.
      Files: `backend/alembic/versions/03xx_import_sources.py`.
      Acceptance Criteria: CRUD validated.

- [ ] **T-D3.5 — Migration: `org_visibility` on content tables + `documents.is_official` + `organizations.default_visibility`**
      Description: Add columns + indexes for visibility filtering.
      Files: `backend/alembic/versions/03xx_org_visibility.py`.
      Acceptance Criteria: Backfill correct; queries planned via index.

- [ ] **T-D3.6 — Migration: `recommendation_events` (analytics)**
      Description: Event log for click-through and dwell-time signals.
      Files: `backend/alembic/versions/03xx_recommendation_events.py`.
      Acceptance Criteria: Append-only writes verified.

- [ ] **T-D3.7 — Neo4j (or Amazon Neptune) provisioning**
      Description: Cluster setup, schema (node types: `Law`, `Concept`, `Jurisdiction`, `Document`; edges: `REFERENCES`, `RELATED_TO`, `IN_JURISDICTION`), full-text index on entity names.
      Files: `infra/neo4j/*`, `backend/app/repositories/graph_repo.py`.
      Acceptance Criteria: Cluster healthy; sample queries pass.

- [ ] **T-D3.8 — Partition `messages` and `moderation_logs` for scale**
      Description: Quarterly RANGE partitions on `created_at` for `messages` (analogous to Phase-1 moderation_logs setup).
      Files: `backend/alembic/versions/03xx_messages_partitioning.py`.
      Acceptance Criteria: Partition manager script extended to cover `messages`.

- [ ] **T-D3.9 — PostgreSQL scale-out alignment**
      Description: Move to multi-AZ RDS, read replicas in two AZs, PgBouncer pool_size adjustments for messaging WS traffic.
      Files: `infra/terraform/postgres.tf` (or equivalent).
      Acceptance Criteria: Failover tested without breaking active sessions/messages.

---

## 4. Integration Tasks

- [ ] **T-I4.1 — LiveKit server deployment (self-hosted or LiveKit Cloud)**
      Description: Helm chart or LiveKit Cloud configuration; egress recording configured to S3.
      Files: `infra/livekit/*`.
      Acceptance Criteria: Recording artefacts land in S3 with correct prefix and lifecycle.

- [ ] **T-I4.2 — Neo4j client integration**
      Description: `py2neo` (or `neo4j` driver) wrapper with retry, connection pool, transaction context.
      Files: `backend/app/repositories/graph_repo.py`.
      Acceptance Criteria: Pool exhaustion gracefully degrades.

- [ ] **T-I4.3 — Redis pub/sub for SSE + WS fan-out**
      Description: Per-user `notif:{user_id}`, per-conversation `conv:{id}` channels; publisher hooks from notification dispatch and messaging endpoints.
      Files: `backend/app/core/pubsub.py`.
      Acceptance Criteria: Multi-replica API delivers events without missed messages.

- [ ] **T-I4.4 — FCM + APNS clients**
      Description: Token-based delivery with retry; certificate / key rotation runbook.
      Files: `backend/app/services/push_providers/{fcm.py,apns.py}`, `Docs/runbook-push.md`.
      Acceptance Criteria: Delivery confirmed on real devices in staging.

- [ ] **T-I4.5 — `entity_extraction_job`**
      Description: After embedding, extract entities + relations; write to Neo4j idempotently.
      Files: `backend/app/workers/graph/entity_extraction.py`.
      Acceptance Criteria: Re-runs are safe; counts increase only when new info available.

- [ ] **T-I4.6 — `legal_import_job` (scheduled)**
      Description: Pull external sources per `import_sources.schedule`; per-source rate limit + circuit breaker; surface failures to admin.
      Files: `backend/app/workers/imports/legal_import.py`, `backend/app/workers/celery_beat_schedule.py`.
      Acceptance Criteria: Run logs visible in `/admin/imports`; failures alert.

- [ ] **T-I4.7 — `session_event_job`**
      Description: Triggered by LiveKit webhook; transcribes recording; creates pending news/summary entries.
      Files: `backend/app/workers/sessions/session_event.py`.
      Acceptance Criteria: Pending draft appears within 5 min post-session.

- [ ] **T-I4.8 — Percolator-based real-time interest matching**
      Description: Maintain OpenSearch `interest_percolators` index; new approved content runs percolator query to identify interested users; dispatch targeted notifications.
      Files: `backend/app/workers/notifications/percolator_match.py`.
      Acceptance Criteria: Member with specific interest receives notification on match.

- [ ] **T-I4.9 — Recommendation feature pipeline**
      Description: Periodic Celery job aggregates user activity into feature vectors stored in Redis.
      Files: `backend/app/workers/recommendations/feature_pipeline.py`.
      Acceptance Criteria: Vectors refresh hourly; size bounded.

- [ ] **T-I4.10 — Gateway / service-mesh routing**
      Description: Kong (or AWS API GW) routes `/api/v1/search/*` → SearchService and `/api/v1/ai/*` → AIService; rest stays on monolith.
      Files: `infra/kong/kong.yml`, `infra/terraform/api_gateway.tf`.
      Acceptance Criteria: Routing verified end-to-end; canary path supported.

---

## 5. Security Tasks

- [ ] **T-S5.1 — LiveKit token scoping**
      Description: Issued participant tokens are narrowly scoped (single room, role-based publish/subscribe permissions, short TTL).
      Files: `backend/app/services/livekit_client.py`.
      Acceptance Criteria: Token cannot publish to another room; expires correctly.

- [ ] **T-S5.2 — WebSocket auth + per-connection rate limit**
      Description: JWT enforced at handshake; per-socket rate limit (60 msg/min); abusive close codes returned.
      Files: `backend/app/core/ws.py`.
      Acceptance Criteria: Flood test → connection throttled then closed.

- [ ] **T-S5.3 — Webhook signature verification (LiveKit + future webhooks)**
      Description: HMAC verification + replay protection.
      Files: `backend/app/core/webhooks.py`.
      Acceptance Criteria: Tampered payload rejected.

- [ ] **T-S5.4 — Message audit log immutability**
      Description: DB grants prevent UPDATE/DELETE on `messaging_audit` from app role.
      Files: Alembic grants migration.
      Acceptance Criteria: App role attempt to UPDATE/DELETE fails.

- [ ] **T-S5.5 — Org siloing enforcement tests**
      Description: Property-based tests confirming `org_only` content never leaks across org boundaries via any endpoint.
      Files: `backend/tests/security/test_org_siloing.py`.
      Acceptance Criteria: Hundreds of randomised cases pass.

- [ ] **T-S5.6 — Push token rotation + revocation on logout**
      Description: Logout invalidates push subscriptions tied to that device.
      Files: `backend/app/services/push_service.py`, logout handler.
      Acceptance Criteria: Post-logout pushes do not deliver.

- [ ] **T-S5.7 — External import source secret management**
      Description: Store source credentials in Secrets Manager; never log or echo back.
      Files: `backend/app/services/import_sources_service.py`.
      Acceptance Criteria: GET endpoint returns redacted secret reference only.

- [ ] **T-S5.8 — mTLS / service JWT for inter-service auth**
      Description: Search & AI services require service auth from gateway/monolith.
      Files: `backend/app/core/service_auth.py`, `infra/kong/*`.
      Acceptance Criteria: Direct client bypassing gateway is rejected.

- [ ] **T-S5.9 — Knowledge graph access control**
      Description: Apply org_visibility filtering and link-anonymisation on `/knowledge-graph/*` to avoid leakage of org-only docs.
      Files: `backend/app/services/knowledge_graph_service.py`.
      Acceptance Criteria: Cross-org member does not see linked org-only documents.

---

## 6. Logging and Audit Tasks

- [ ] **T-L6.1 — Session lifecycle events to outbox**
      Description: `session.created|started|ended|recording_ready` events; audit log of participant join/leave.
      Files: `backend/app/services/session_service.py`.
      Acceptance Criteria: Auditable timeline reconstructable for any session.

- [ ] **T-L6.2 — Messaging audit + compliance**
      Description: Each message logged to `messaging_audit` with sender_id, conversation_id, timestamp, message hash.
      Files: `backend/app/services/messaging_service.py`.
      Acceptance Criteria: Audit row count matches message count.

- [ ] **T-L6.3 — Push delivery metrics**
      Description: Counters per platform (FCM/APNS) for sent/delivered/failed.
      Files: `backend/app/core/metrics.py`.
      Acceptance Criteria: Dashboards populated; alert on failure-rate spike.

- [ ] **T-L6.4 — Knowledge graph write metrics**
      Description: Counter for entity/relation writes per ingest; alert on stalled pipeline.
      Files: `backend/app/core/metrics.py`.
      Acceptance Criteria: Stall detection within 10 min.

- [ ] **T-L6.5 — Recommendation event capture**
      Description: Click-through + dwell events posted to `recommendation_events` for offline analysis.
      Files: `backend/app/api/v1/recommendations.py`, `backend/app/services/recommendation_event_service.py`.
      Acceptance Criteria: Events visible in analytics replica with no PII leakage.

- [ ] **T-L6.6 — Import source run logs**
      Description: Persist run summary + errors per `legal_import_job` invocation; expose in `/admin/imports`.
      Files: `backend/app/workers/imports/legal_import.py`, `backend/app/models/import_run.py`, Alembic.
      Acceptance Criteria: Failures surfaced with stack traces.

- [ ] **T-L6.7 — Microservice trace propagation**
      Description: Ensure OTel trace context propagated through gateway to Search/AI services.
      Files: `backend/app/core/tracing.py`, gateway config.
      Acceptance Criteria: Single trace spans gateway → monolith → search → AI.

---

## 7. Testing Tasks

- [ ] **T-T7.1 — Session lifecycle integration test**
      Description: Create session → mint token → simulate webhook events → verify recording stored + draft news created.
      Files: `backend/tests/integration/test_sessions.py`.
      Acceptance Criteria: All states transition correctly.

- [ ] **T-T7.2 — WebSocket messaging tests**
      Description: Two clients exchange messages; reconnect mid-thread; verify cursor resume.
      Files: `backend/tests/integration/test_messaging_ws.py`.
      Acceptance Criteria: No lost or duplicated messages.

- [ ] **T-T7.3 — SSE notifications tests**
      Description: Subscribe; trigger an event; assert receipt within 1 s.
      Files: `backend/tests/integration/test_sse_notifications.py`.
      Acceptance Criteria: Passes.

- [ ] **T-T7.4 — Org-visibility integration tests**
      Description: Cross-org access attempts on all content types and search.
      Files: `backend/tests/integration/test_org_visibility.py`.
      Acceptance Criteria: All cross-org attempts blocked.

- [ ] **T-T7.5 — Knowledge graph endpoint tests**
      Description: Explore, search, entity detail with realistic seed graph.
      Files: `backend/tests/integration/test_knowledge_graph.py`.
      Acceptance Criteria: Latency budget met.

- [ ] **T-T7.6 — Recommendation correctness tests**
      Description: Validate ranking on synthetic activity histories; cold-start fallback exercised.
      Files: `backend/tests/integration/test_recommendations.py`.
      Acceptance Criteria: Top-K precision baseline met.

- [ ] **T-T7.7 — Legal import job tests**
      Description: Mock external source; verify ingestion → approval pipeline; rerun idempotency.
      Files: `backend/tests/integration/test_legal_import.py`.
      Acceptance Criteria: No duplicates on rerun.

- [ ] **T-T7.8 — Push notification provider tests**
      Description: Mock FCM/APNS; verify delivery payload + retry behaviour.
      Files: `backend/tests/integration/test_push.py`.
      Acceptance Criteria: Passes.

- [ ] **T-T7.9 — Microservices contract tests**
      Description: Pact-style contract tests between gateway/monolith and Search/AI services.
      Files: `backend/tests/contract/`.
      Acceptance Criteria: Drift detected and reported.

- [ ] **T-T7.10 — Load test for sessions + messaging**
      Description: 100 concurrent rooms / 1k concurrent WS messaging connections; SLA p95 < 500 ms server-side.
      Files: `backend/tests/load/locust_phase3.py`.
      Acceptance Criteria: Targets met on staging.

- [ ] **T-T7.11 — Security regression suite for WS, webhooks, multi-tenant siloing**
      Description: Replay attacks, malformed payloads, cross-tenant probes.
      Files: `backend/tests/security/test_phase3_security.py`.
      Acceptance Criteria: All attack vectors mitigated.

---

## 8. Documentation Tasks

- [ ] **T-DOC8.1 — Phase-3 OpenAPI export**
      Description: `Docs/openapi-phase3.yaml` regenerated in CI for both monolith and extracted services.
      Files: `backend/scripts/export_openapi.py`, CI workflow.
      Acceptance Criteria: Spec drift fails CI.

- [ ] **T-DOC8.2 — LiveKit runbook**
      Description: Server topology, recording lifecycle, webhook flow, key rotation.
      Files: `Docs/runbook-livekit.md`.
      Acceptance Criteria: On-call can diagnose failed session end-to-end.

- [ ] **T-DOC8.3 — Knowledge graph schema & runbook**
      Description: Node/edge types, extraction model, reprocessing playbook.
      Files: `Docs/runbook-knowledge-graph.md`, `Docs/schema-knowledge-graph.md`.
      Acceptance Criteria: Reviewed and signed off by data team.

- [ ] **T-DOC8.4 — Messaging compliance doc**
      Description: Retention, audit log, lawful access policies.
      Files: `Docs/messaging-compliance.md`.
      Acceptance Criteria: Reviewed by legal stakeholder.

- [ ] **T-DOC8.5 — Push notifications & mobile setup**
      Description: FCM/APNS provisioning, certificate rotation, token lifecycle.
      Files: `Docs/runbook-push.md`, `mobile/README.md`.
      Acceptance Criteria: New device tested on both platforms.

- [ ] **T-DOC8.6 — Microservices extraction runbook**
      Description: Promotion plan, rollback, traffic shifting (canary), gateway management.
      Files: `Docs/runbook-microservices.md`.
      Acceptance Criteria: Promotion + rollback rehearsed.

- [ ] **T-DOC8.7 — Org-visibility design doc**
      Description: Threat model, enforcement points (PG + OpenSearch + Neo4j), tests.
      Files: `Docs/design-org-visibility.md`.
      Acceptance Criteria: Endorsed by security review.

- [ ] **T-DOC8.8 — External legal source onboarding**
      Description: How to add and operate new sources; legal compliance checklist (robots.txt, ToS).
      Files: `Docs/runbook-legal-imports.md`.
      Acceptance Criteria: Sample onboarding for one source completed.

- [ ] **T-DOC8.9 — Updated data model + ERD (Phase-3)**
      Description: Document all new tables and relationships, including Neo4j entities.
      Files: `Docs/data-model-phase3.md`.
      Acceptance Criteria: Matches Alembic + Neo4j schema.

- [ ] **T-DOC8.10 — Phase-3 acceptance gate**
      Description: Maps each Phase-3 feature to tests + SLA + compliance controls.
      Files: `Docs/uat-gate-phase3.md`.
      Acceptance Criteria: Sign-off captured before prod promotion.
