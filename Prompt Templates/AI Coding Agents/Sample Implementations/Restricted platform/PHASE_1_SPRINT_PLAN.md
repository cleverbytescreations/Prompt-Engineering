# Phase 1 Sprint Plan (Replanned)

> Scope: Phase 1 MVP, six 2-week sprints, 12 weeks total.
> References: [PHASE_1_API_TASK_CHECKLIST.md](PHASE_1_API_TASK_CHECKLIST.md), [PHASE_1_UI_TASK_CHECKLIST.md](PHASE_1_UI_TASK_CHECKLIST.md).
> Each sprint ends with an end-to-end demoable slice and a 10% payment milestone.

---

## Replanning Principles

The contractual sprint headlines are preserved. Only the **internal task sequencing** changes, to remove three dependency risks in the original plan:

1. **Moderation lands with its first content type** (documents), not before any user-generated content exists.
2. **Cross-cutting infrastructure** (outbox, notifications, taxonomy, storage, OpenSearch indexing) is laid down early, then extended per sprint — instead of bunched into Sprint 6.
3. **Search pipeline builds incrementally** across S3–S5 as each content type is added. Sprint 6 is reserved purely for hardening, DR, and acceptance testing.

---

## Sprint Outcomes (Contractual Headlines — Unchanged)

| Sprint | Duration | Usable Module / Release Outcome | Payment |
|---|---:|---|---:|
| S1 | Wk 1–2 | Platform Foundation + Secure Login Base | 10% |
| S2 | Wk 3–4 | Admin, Organisation & User Management Release | 10% |
| S3 | Wk 5–6 | Legal Knowledge Repository Release | 10% |
| S4 | Wk 7–8 | Moderation Workflow Release (extended to Q&A + News) | 10% |
| S5 | Wk 9–10 | Q&A + News Release (delivered alongside S4 moderation) → consolidated into Social Feed + Search + Dashboard | 10% |
| S6 | Wk 11–12 | MVP Stabilisation + Deployment Hardening | 10% |

> Note: in the replan, S4 and S5 swap emphasis slightly — S4 lands moderation **plus** Q&A + News (since moderation needs content to moderate), and S5 lands Social Feed + Search + Dashboard. The combined deliverables across S4+S5 match the original contract scope exactly.

---

## Sprint 1 — Platform Foundation + Secure Login + Infra Spine
**Weeks 1–2 · Payment 10%**

**Demoable slice**: invite-only signup → login → logout → password reset, running on the full dev stack via `docker compose up`.

### Backend
- **Foundation**: T-B0.1, T-B0.2, T-B0.3, T-B0.4, T-B0.5
- **Auth**: T-B1.1, T-B1.2, T-B1.3, T-B1.4, T-B1.5, T-B1.6
- **Database (full schema baseline)**: T-D3.1, T-D3.2, T-D3.4, T-D3.6, T-D3.7, T-D3.10
- **Infra spine** *(moved earlier)*: T-I4.1 storage, T-I4.2 Redis, T-I4.4 Celery, T-I4.X3 docker-compose
- **Security**: T-S5.1, T-S5.5, T-S5.6
- **Logging**: T-L6.1, T-L6.2

### Frontend
- **Foundation**: T0.1, T0.2, T0.3, T0.4, T0.5, T0.6, T0.7, T0.8, T0.9, T0.10
- **Auth UI**: T1.1, T1.2, T1.3, T1.4, T1.5, T1.6

### Why early
Full schema in S1 unblocks moderation/Q&A in later sprints with no migration churn. Compose + Celery + storage in S1 means no infra surprises from S3 onwards.

### Acceptance gate
- Invite → signup → login → reset flows pass against PG (not SQLite) — T-B1.5 integration suite.
- `docker compose up` brings the stack to healthy in <2 min.
- Auth UI renders in EN/ES/FR.

---

## Sprint 2 — Admin, Org, User Mgmt + Outbox + Notifications Spine + Taxonomy
**Weeks 3–4 · Payment 10%**

**Demoable slice**: admin creates org → issues invite → user signs up → admin changes role/status → user receives in-app + email notification. Taxonomy seeded and editable.

### Backend
- **Org / Invite / User**: T-B2.1, T-B3.1, T-B4.1
- **Outbox infra** *(moved up from S6)*: T-B1.6, T-I4.5 poller, T-I4.6 stuck recovery, T-L6.7
- **Notifications spine** *(moved up from S5)*: T-B10.1, T-B10.2, T-B10.3, T-I4.13 (Module 1–4 event types only)
- **Taxonomy** *(moved up from S6)*: T-B13.1
- **Seed data**: T-D3.5
- **Storage versioning**: T-DR9.3 baseline (versioning on)

### Frontend
- **User mgmt UI**: T2.1, T2.2, T2.3
- **Org UI**: T3.1, T3.2
- **Invite UI**: T4.1
- **Notifications UI**: T10.1, T10.2, T10.3
- **Taxonomy UI**: T13.1
- **Admin shell**: minimal `/admin` landing carved from T14.1 (placeholder cards; full analytics ships S6)

### Why early
Outbox + notifications + taxonomy are referenced by every later module. Building the dispatcher with 4–5 event types in S2 makes adding new rows in S3–S5 trivial.

### Acceptance gate
- Role-change event flows: PG outbox row → poller → notification dispatcher → in-app row + email.
- Two outbox pollers run concurrently without double-dispatch.
- Org/invite/user CRUD reachable for Admin; read-only for Moderator.

---

## Sprint 3 — Knowledge Repository + Moderation Workflow
**Weeks 5–6 · Payment 10%**

**Demoable slice**: member uploads PDF → moderator approves/rejects/retracts → submitter notified → approved doc browsable by country/category/tag → downloadable via signed URL → searchable in OpenSearch (metadata + first vector hits).

### Backend
- **Documents**: T-B5.1, T-B5.2, T-B5.3, T-B5.4
- **Moderation** *(lands with first content type)*: T-B9.1, T-B9.2, T-L6.6, T-D3.3 partitioned logs
- **Search pipeline start**: T-I4.3 OS client wrapper, T-I4.7 Docling ingestion, T-I4.8 chunking, T-I4.9 embeddings, T-D3.8 (documents index template)
- **Entity cache**: T-I4.X1 (documents only)
- **File security**: T-S5.3
- **Notifications catalogue extension**: `document_approved/rejected/changes_requested/retracted/downloaded` rows added to T-I4.13

### Frontend
- **Repository UI**: T5.1, T5.2, T5.3, T5.4, T5.5
- **Moderation UI**: T9.1, T9.2 (documents tab only — other tabs activate in S4), T9.4, T9.5, T9.6

### Why this sequencing
Moderation queue now has real content to moderate. The search pipeline starts in S3 instead of being a Sprint 6 cliff — ingest + chunk + embed is exercised on documents alone, then reused for Q&A (S4) and posts (S5).

### Acceptance gate
- Upload → approve → embed → searchable end-to-end through `docker compose`.
- Scanned PDF yields ≥80% text coverage (MVP-10).
- Retracted document removed from `/repository` default list within 1s.

---

## Sprint 4 — Q&A + News (Moderation Extended)
**Weeks 7–8 · Payment 10%**

**Demoable slice**: member asks question → moderator approves → assigns expert → expert is notified → posts answer → admin verifies + marks official → author + asker notified → news submitted/approved/browsed.

### Backend
- **Q&A**: T-B6.1 (incl. assignment + `/questions/assigned`), T-B6.2 (incl. mark-official + outbox events)
- **News**: T-B7.1
- **Q&A indexing**: T-I4.10, T-D3.8 (questions + news index templates)
- **Moderation**: queue extended to questions + news (infra already built in S3)
- **Notifications catalogue extension**: `question_*`, `answer_*`, `news_*` rows added to T-I4.13
- **OpenSearch ops**: T-D3.9 ISM + snapshot policies

### Frontend
- **Q&A UI**: T6.1, T6.2, T6.3, T6.4, T6.5, T6.6 (`/questions/assigned`), T6.7 (assignment banner)
- **News UI**: T7.1, T7.2, T7.3, T7.4, T7.5
- **Moderation UI**: activate questions + news tabs in T9.2

### Why now
By S4 the moderation queue is mature; adding question + news types is a registration exercise, not new infrastructure. Expert assignment + verification + ICA-official flow get full polish here.

### Acceptance gate
- New approved Q&A appears in semantic index within 30s.
- Mark-official is gated on `is_verified=true` and atomically swaps prior official.
- Assignment + reassignment dispatch correct `question_assigned` / `question_unassigned` notifications.

---

## Sprint 5 — Social Feed + Hybrid Search + Member Dashboard
**Weeks 9–10 · Payment 10%**

**Demoable slice**: post + like + comment in approved feed; one search box returns blended results across docs/Q&A/news/posts under the 1.5s SLA; member dashboard summarises pending items, unread, and recent activity.

### Backend
- **Posts**: T-B8.1, T-B8.2, T-B8.3
- **Post indexing**: T-I4.11, T-D3.8 (posts index template)
- **Search endpoint** *(pipeline ~80% built by now)*: T-B11.1, T-B11.2, T-I4.12 chain
- **Member dashboard**: T-B12.1
- **News broadcast**: T-I4.14
- **Notifications catalogue final**: `post_*`, `invite_consumed` rows
- **Entity cache**: extend T-I4.X1 to Q&A, news, posts

### Frontend
- **Feed UI**: T8.1, T8.2, T8.3, T8.4
- **Search UI**: T11.1, T11.2
- **Dashboard UI**: T12.1
- **Reference-data hooks**: T15.7

### Why this is now achievable
Doc and Q&A embeddings already produce vectors in S3–S4. S5 adds posts and turns on the `/search` endpoint that queries the already-populated indices. RRF merge + cache + circuit breaker is the only net-new search work.

### Acceptance gate
- `/search` p95 ≤ 1500ms on 500-doc corpus (MVP-6) — T-T7.6 locust run.
- Approved post appears in `/search?type=posts` within 30s.
- 10k-subscriber news broadcast completes in seconds.

---

## Sprint 6 — MVP Stabilisation + Admin Analytics + Deployment Hardening
**Weeks 11–12 · Payment 10%**

**Demoable slice**: production-grade deploy with WAF, autoscaling, automated backups, executed DR drill, full E2E acceptance suite green, admin analytics dashboard.

### Backend
- **Admin**: T-B14.1, T-B14.2
- **Security hardening**: T-S5.X1 CloudFront + WAF, T-S5.7, T-S5.8, T-S5.9, T-S5.10
- **Autoscaling**: T-I4.X2 KEDA
- **Disaster recovery**: T-DR9.1, T-DR9.2, T-DR9.3 (complete), T-DR9.4
- **Maintenance jobs**: T-I4.15
- **Observability polish**: T-L6.3 OTel, T-L6.4 metrics, T-L6.5 Sentry, T-L6.8 alert rules

### Testing
- **Full suite**: T-T7.1, T-T7.2, T-T7.3, T-T7.4, T-T7.5 (MVP-1…10), T-T7.7 security, T-T7.8 migrations

### Frontend
- **Admin UI**: T14.1, T14.2
- **Cross-cutting**: T15.1 a11y, T15.2 responsive, T15.3 env + Sentry, T15.4 unit tests, T15.5 Playwright E2E, T15.6 README, T15.8 empty/error states, T15.9 manifest, T15.10 service worker, T15.11 icons

### Documentation
- T-DOC8.1, T-DOC8.2, T-DOC8.3 runbook, T-DOC8.4 ADRs, T-DOC8.5 deployment, T-DOC8.6 API consumer guide, T-DOC8.7 data model, T-DOC8.8 UAT gate

### Acceptance gate
- All 10 MVP-1…MVP-10 acceptance tests pass on a clean environment.
- One full DR drill executed before UAT sign-off (RTO ≤ 4h, RPO ≤ 15min).
- Lighthouse mobile ≥ 90 on `/feed`, `/repository`, `/dashboard`.
- Zero critical axe violations on 10 key pages.

---

## Key Task Movements vs Original Plan

| Item | Original | Replanned | Reason |
|---|---|---|---|
| Outbox poller + dispatcher (T-I4.5, T-I4.6, T-B1.6) | implicit S5/S6 | **S2** | Every state change emits events from S2 onward |
| Notifications module (T-B10.\*, T-I4.13) | S5 | **spine in S2**, rows added per sprint | Lets role/status/invite events fire from S2 |
| Taxonomy CRUD (T-B13.1, T13.1) | S6 | **S2** | Repo/Q&A filters need it in S3 |
| Moderation queue + actions (T-B9.\*) | S4 (before any UGC) | **S3 with documents** | Lands with its first content type |
| Doc ingestion + chunking + embedding (T-I4.7–9) | S6 | **S3** | Spreads search pipeline across three sprints |
| Q&A embedding (T-I4.10) | S6 | **S4** | Same |
| Post embedding (T-I4.11) | S6 | **S5** | Same |
| `/search` endpoint (T-B11.\*) | S6 | **S5** | Pipeline already populated by S5 |
| Full schema migration (T-D3.\*) | S1 partial + S6 additions | **S1 complete** | Avoid late migration churn |
| Admin dashboard base | S2 (undefined) | **S2 placeholder + S6 analytics** | Splits the ambiguity cleanly |
| Storage abstraction (T-I4.1) | mid-phase | **S1** | Documents in S3 need it |
| Redis clients (T-I4.2) | mid-phase | **S1** | Rate limiter + cache + broker needed S1 |
| Celery + reliability (T-I4.4) | mid-phase | **S1** | Every async path depends on it |
| docker-compose (T-I4.X3) | late | **S1** | Local dev unblocker |

---

## Risk Reductions vs Original Plan

| Risk in original plan | Mitigation in replan |
|---|---|
| **S4 moderation has nothing to moderate** | Moderation lands in S3 with documents; extends to Q&A/news in S4 |
| **S6 cliff**: search pipeline + DR + deployment + E2E in 2 weeks | Search pipeline spread across S3–S5; S6 is hardening + testing only |
| **Outbox/notification retrofit** across 6 modules in S5/S6 | Built once in S2 with 4 event types; new types are config in S3–S5 |
| **Late schema additions** for moderation_logs, partitioned tables, outbox | Full schema baseline in S1 |
| **Payment milestone defensibility** | Every sprint ends with a self-contained end-to-end demoable slice — no "trust us, it lands later" caveats |

---

## What Stays the Same

- Total scope (every task in both checklists is assigned to a sprint).
- Total weeks (12) and payment milestones (6 × 10%).
- The six contractual sprint-outcome names.
- All Phase 1 modules, endpoints, and SAD §13 acceptance criteria.

Only internal sequencing changes — the client-facing sprint headlines and deliverable list still read identically to the contract.

---

## Tracking

Each task in [PHASE_1_API_TASK_CHECKLIST.md](PHASE_1_API_TASK_CHECKLIST.md) and [PHASE_1_UI_TASK_CHECKLIST.md](PHASE_1_UI_TASK_CHECKLIST.md) is referenced by its task ID (T-B*, T-D*, T-I*, T-S*, T-L*, T-T*, T-DR*, T-DOC*, T0–T15). Sprint assignment shown above is the source of truth; checklist files remain organised by module for readability.
