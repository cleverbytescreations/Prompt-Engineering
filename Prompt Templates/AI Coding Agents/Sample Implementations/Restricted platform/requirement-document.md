# ICA Restricted Social Platform — Scope & Requirements Document

**Document Version:** 1.1  
**Date:** 2026-05-13  
**Status:** Draft — Updated (gap analysis pass, 14 requirements added)  
**Prepared for:** ICA (International Cooperative Alliance)  
**Document Type:** Software Requirements Specification (SRS)

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Scope of the Application](#2-scope-of-the-application)
3. [User Roles and Access Levels](#3-user-roles-and-access-levels)
4. [Functional Requirements](#4-functional-requirements)
5. [Detailed Requirement Table](#5-detailed-requirement-table)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [Workflow Requirements](#7-workflow-requirements)
8. [Reporting Requirements](#8-reporting-requirements)
9. [MVP Scope](#9-mvp-scope)
10. [Future Enhancements](#10-future-enhancements)
11. [Acceptance Criteria](#11-acceptance-criteria)
12. [Clarifications Required](#12-clarifications-required)

---

## 1. Introduction

### 1.1 Purpose of the Platform

The ICA Restricted Social Platform is an invite-only knowledge collaboration and legal intelligence platform built exclusively for members of the International Cooperative Alliance (ICA) and affiliated legal professionals. It provides a curated, moderated environment for sharing, discovering, and discussing cooperative law, legal policy, and regulatory developments across jurisdictions.

### 1.2 Background

ICA member organisations operate across diverse legal environments and rely on timely, authoritative legal knowledge. Currently, legal knowledge is fragmented across email threads, national repositories, and informal networks. This platform consolidates that knowledge into a single governed system with AI-assisted discovery, enforced quality standards through human moderation, and multilingual accessibility for a global membership.

### 1.3 Target Users

| User Segment | Description |
|---|---|
| ICA Legal Office Staff | Platform administrators and legal experts who manage operations, post authoritative content, and answer member questions |
| Legal Professionals / Moderators | Subject-matter experts and appointed moderators who review, validate, and approve user-generated content |
| ICA Member Organisations | Staff members of ICA-affiliated cooperatives who consume legal knowledge, submit questions, share documents, and engage in the professional community |

### 1.4 Business Objectives

| # | Objective |
|---|---|
| BO-1 | Centralise cooperative law knowledge from across ICA member jurisdictions into a searchable, versioned legal repository |
| BO-2 | Provide a moderated Q&A forum linking members to ICA legal expertise |
| BO-3 | Distribute curated legal news and policy updates to relevant member segments in near-real time |
| BO-4 | Leverage AI to improve search quality, reduce moderator workload through pre-screening, and provide contextual RAG-based answers |
| BO-5 | Enforce access integrity through invite-only onboarding, RBAC, and a full audit trail of all content decisions |
| BO-6 | Support multilingual access (English, Spanish, French) without duplicating content management effort |
| BO-7 | Evolve approved Q&A pairs into a self-growing legal knowledge base over time |

---

## 2. Scope of the Application

### 2.1 In-Scope Features

| # | Feature Area | Summary |
|---|---|---|
| S-1 | Invite-only member registration and JWT-based authentication | |
| S-2 | Organisation and user management with RBAC | |
| S-3 | Legal document repository — upload, metadata tagging, versioning, download | |
| S-4 | AI-assisted document ingestion pipeline (OCR via **Docling**, chunking, embedding, indexing) | |
| S-5 | Moderated Q&A forum with expert assignment and answer acceptance | |
| S-6 | News and legal update submission with moderation and category-targeted broadcast | |
| S-7 | Social feed with posts, likes, and threaded comments | |
| S-8 | Unified moderation queue with Approve / Reject / Request-Changes / Flag / Retract actions | |
| S-9 | Hybrid search (BM25 + k-NN) via OpenSearch with country/category/status pre-filtering | |
| S-10 | RAG-based AI legal assistant (`/ai/ask`) using LangGraph orchestration | |
| S-11 | Multi-language support via English-pivot translation pipeline (EN / ES / FR baseline) | |
| S-12 | In-app notifications with subscription preferences | |
| S-13 | Admin dashboard: user management, invite management, taxonomy management, platform analytics | |
| S-14 | Moderation audit trail and content versioning | |
| S-15 | Law retraction/supersession lifecycle management | |

### 2.2 Out-of-Scope Items

| # | Item | Rationale |
|---|---|---|
| OS-1 | Native mobile application (iOS / Android) | Web-first MVP; PWA capabilities address mobile access |
| OS-2 | External legal database API integrations (e.g., LexisNexis, Westlaw) | Phase 3 future enhancement |
| OS-3 | Real-time video/audio conferencing between members | Considered as a **LiveKit** integration candidate in Phase 3 |
| OS-4 | Public / unauthenticated access to any platform content | Platform is invite-only; no guest access |
| OS-5 | Payment or subscription billing | Membership is managed externally by ICA |
| OS-6 | Custom LLM training or fine-tuning | External models (OpenAI / sentence-transformers) are used |
| OS-7 | Social features such as following, private messaging, or direct chat | May be considered in Phase 3 |

### 2.3 Assumptions

| # | Assumption |
|---|---|
| A-1 | All members are pre-vetted by ICA; the platform does not perform KYC or legal verification of members |
| A-2 | English is the primary processing language; all AI pipelines use English as the internal pivot language |
| A-3 | Document uploads are in PDF format or provided as an external URL; other formats (DOCX, HTML) are out of scope for MVP |
| A-4 | Each member belongs to exactly one organisation at registration time |
| A-5 | Moderation SLA targets (e.g., review within 48 hours) are defined operationally by ICA and configured by Admin, not enforced by the system with hard blocks |
| A-6 | The platform operates under GDPR-compatible data handling principles; full GDPR tooling (e.g., data portability export) is a Phase 2 obligation |
| A-7 | OpenAI `text-embedding-3-small` is used for cloud embedding; a local fallback via `sentence-transformers/all-MiniLM-L6-v2` is available for development and cost-sensitive deployments |
| A-8 | The Docling framework is used for document ingestion — it replaces a custom OCR stack and provides structured extraction from PDFs, scanned images, and tabular data |

### 2.4 Dependencies

| # | Dependency | Owner |
|---|---|---|
| D-1 | OpenSearch single-node cluster (Docker Compose for dev; managed cluster for prod) | Infrastructure |
| D-2 | PostgreSQL 15+ | Infrastructure |
| D-3 | Redis 7+ (db=0 Celery broker, db=1 search cache, db=2 translation cache) | Infrastructure |
| D-4 | MinIO (dev) / AWS S3 (prod) for file storage | Infrastructure |
| D-5 | Celery workers with at least 2 concurrent queues: `default` and `embeddings` | Backend |
| D-6 | SMTP provider or SendGrid for password reset and notification emails | External |
| D-7 | OpenAI API key (embedding + LLM generation) or equivalent local model | External / AI |
| D-8 | Docling library (`python-docling`) for document parsing and OCR | Backend |

### 2.5 Constraints

| # | Constraint |
|---|---|
| C-1 | Search response SLA: `GET /search` ≤ 1,500 ms p95; `POST /ai/ask` ≤ 2,500 ms p95 (with warm translation cache) |
| C-2 | No member-facing full-text search against PostgreSQL; all member search goes through OpenSearch |
| C-3 | All user-generated content must be in `pending` state and pass moderation before public visibility |
| C-4 | AI-generated answers are assistive only; they cannot be marked as authoritative without human verification by a credentialled legal professional |
| C-5 | Invite codes are single-use and tied to a specific organisation; max_users per organisation is enforced at invite generation |
| C-6 | PII fields (email, full name) are stored only in the `users` table; delete operations anonymise rather than hard-delete to preserve audit integrity |
| C-7 | AI audit logs stored in `outbox_events` are subject to a 30-day TTL enforced by a nightly Celery cleanup job |

---

## 3. User Roles and Access Levels

### 3.1 Role Summary

| Role | Code | Description |
|---|---|---|
| Super Admin / ICA Legal Office | A | Platform owner. Full access to all features, configuration, analytics, and user management. Posts official content without moderation. |
| Moderator / Legal Expert | M | Reviews and approves all user-generated content. Answers questions. Has access to moderation queue and audit logs for their assigned content types. |
| Member / Professional User | U | Registered ICA member. Can submit content (subject to moderation), search, view approved content, and interact with the community. |
| System (AI / Celery) | SYS | Internal actor. Executes background jobs: ingestion, embedding, translation, notification dispatch, AI answer generation. No human login. |

### 3.2 Permission Matrix

| Feature | Admin (A) | Moderator (M) | Member (U) |
|---|:---:|:---:|:---:|
| Invite users | ✓ | — | — |
| Manage organisations | ✓ | — | — |
| Manage roles | ✓ | — | — |
| Manage taxonomy (categories, tags) | ✓ | — | — |
| Access platform analytics | ✓ | — | — |
| View AI usage & cost | ✓ | — | — |
| Configure platform settings | ✓ | — | — |
| View full moderation audit log | ✓ | — | — |
| Access moderation queue | ✓ | ✓ | — |
| Approve / Reject / Retract content | ✓ | ✓ | — |
| Assign questions to experts | ✓ | ✓ | — |
| Post official updates (no moderation) | ✓ | — | — |
| Answer questions | ✓ | ✓ | — |
| Submit documents, questions, news, posts | ✓ | ✓ | ✓ |
| View approved content | ✓ | ✓ | ✓ |
| Use AI search (`/ai/ask`) | ✓ | ✓ | ✓ |
| Manage own profile | ✓ | ✓ | ✓ |
| Manage notification preferences | ✓ | ✓ | ✓ |

---

## 4. Functional Requirements

### 4.1 Module 1 — Authentication and Onboarding

- The system shall support invite-only registration. A user may only register after entering a valid, unexpired, single-use invite code.
- Invite codes shall be tied to a specific organisation; the user is automatically associated with that organisation on signup.
- The system shall enforce `max_users` per organisation at both invite generation time and signup time.
- Authentication shall use email + password with JWT access tokens and a separate refresh token.
- Password reset shall be delivered via email (SMTP / SendGrid) with a time-limited token.
- On first login, the system shall guide the member through a setup step to capture interest preferences (countries, categories).
- JWTs shall be invalidated on logout; the refresh token shall allow seamless re-authentication without re-entering credentials.
- Any authenticated user shall be able to update their own profile — full name, biography, preferred language, and avatar — via `PATCH /auth/me`.

### 4.2 Module 2 — User and Organisation Management

- Admins shall be able to create, update, deactivate, and list user accounts.
- Admins shall be able to change a user's role (Member → Moderator, etc.).
- Admins shall be able to create, update, and list organisations with configurable `max_users`.
- Admins shall be able to view a user's full contribution history (questions, documents, posts).
- Members shall access their own submission history across all content types: my documents (`GET /documents/my`), my questions (`GET /questions/my`), my news (`GET /news/my`), and my posts (`GET /posts/my`).
- Members shall be able to check the current moderation status of any of their own submissions (`GET /{type}/{id}/status`) to track progress through Pending → Approved / Rejected / Revision Required.
- User deletion shall anonymise PII fields rather than hard-delete the record, preserving audit integrity.

### 4.3 Module 3 — Invite Management

- Admins shall generate single-use invite codes scoped to a specific organisation.
- Each invite shall have a configurable expiry period.
- Admins shall be able to list, view the status of, and revoke any invite.
- Used and expired invites shall remain in the system for audit purposes.

### 4.4 Module 4 — Legal Knowledge Repository

- Members shall upload legal documents as a PDF file or as an external URL.
- Each document submission shall capture mandatory metadata: title, country (ISO 3166-1), law type / category, and language.
- Optional metadata: tags, summary, publication date.
- Uploaded documents shall enter a `pending` state awaiting moderator review.
- Moderators shall be able to approve, reject, request changes, or flag a submission.
- Moderators shall be able to edit metadata at review time and apply a `category_id` during approval.
- Admins and Moderators shall be able to retract an already-approved document, setting its `law_status` to `retracted` or `superseded`.
- Every edit to a document (pre- or post-approval) shall create an append-only version row in `content_versions`.
- Members shall browse and download approved documents with filters: country, category, law type, date range, and law status.
- The system shall use **Docling** to extract structured text and tables from uploaded PDFs, including scanned documents requiring OCR, as the first stage of the ingestion pipeline.
- Approved documents shall be asynchronously processed through the full ingestion pipeline: Docling extraction → chunking (512-token / 64-token overlap) → embedding → OpenSearch indexing.

### 4.5 Module 5 — Question and Answer Forum

- Any authenticated member may submit a question tagged with country, category, and optional tags.
- Submitted questions shall enter a `pending` moderation queue.
- Moderators shall approve, reject, or request changes on questions.
- Moderators and Admins shall assign an approved question to a specific legal expert for answering.
- Any member, moderator, or admin may post an answer to an approved question.
- The question author or a moderator/admin may mark one answer as accepted.
- Approved question + accepted answer pairs shall be automatically embedded and indexed into the `ica_questions` OpenSearch index, making them searchable and retrievable by the RAG pipeline.
- An `is_verified` flag shall be set only when a credentialled lawyer has validated the answer; this upgrades the Q&A pair's weight in RAG retrieval.
- Members shall browse, filter, and search all approved Q&A pairs (`GET /questions`).
- Moderators and Admins shall access AI-generated answer suggestions for an approved question (`GET /ai/suggestions/{question_id}`) to assist with quality assessment before assigning to an expert.
- Moderators and Admins shall promote an approved, answered Q&A pair to a knowledge article (`POST /questions/{id}/promote`), elevating it to a curated knowledge entry with enhanced discovery visibility.
- Note: Threaded discussion within Q&A threads (comments on individual answers, beyond top-level answers) is not in scope for MVP or Phase 2. It is deferred to Phase 3. See §10.

### 4.6 Module 6 — News and Legal Updates

- Members and Admins may submit news articles or legal update posts tagged with country, category, and publication date.
- Submitted articles enter a `pending` moderation state.
- Moderators shall approve, reject, or request changes on news articles.
- On approval, a `news_broadcast_job` shall fan out in-app notifications to all members who have subscribed to the article's country/category scope.
- Members shall browse and filter approved news by country, category, and date range.
- Admins shall post official ICA news without requiring moderation.
- Admins shall be able to feature or pin approved news articles for prominent display on the platform home feed (`PATCH /news/{id}/feature`). Pinned articles appear above the standard chronological listing.

### 4.7 Module 7 — Social Feed and Posts

- Members shall browse the social feed of all approved posts (`GET /posts`), presented in reverse-chronological order.
- Members shall create short-form posts (insights, commentary, knowledge sharing) visible in the platform feed.
- Posts shall enter a `pending` moderation state before appearing in the feed.
- Members shall be able to like/unlike posts and add threaded comments.
- Moderators and Admins shall delete inappropriate comments.
- Approved posts shall be embedded and indexed for semantic search.

### 4.8 Module 8 — Moderation

- A unified moderation queue shall aggregate all pending submissions across content types: documents, questions, news, posts.
- Each queue item shall display submitter name, organisation, submission date, content type, and AI pre-screen result.
- Moderation actions available: Approve, Reject (with mandatory remarks), Request Changes (revision without full rejection), Flag (hold for senior/admin review), Retract (post-approval withdrawal for documents).
- During document review, moderators shall perform an authenticity validation step — confirming the document is a genuine legal instrument (not a fabrication, test submission, or duplicate) — before approving. This judgement is recorded in the moderation remarks field.
- Moderators shall assign or confirm a `category_id` for news articles and posts as part of the approve action, ensuring all approved content is properly categorised at review time.
- All moderation decisions shall be logged in an immutable audit trail recording: actor, action, timestamp, content reference, and remarks.
- The moderation stats endpoint shall expose queue counts by type to support workload monitoring.

### 4.9 Module 9 — Search and Discovery

- The global search endpoint (`GET /search`) shall support hybrid BM25 + semantic (k-NN) search across documents, questions, news, and posts.
- Search shall accept filters: type, country (multi-value), category (multi-value), date range, law status (`active` | `retracted` | `superseded`), and search mode (`hybrid` | `keyword` | `semantic`).
- Search results for documents shall surface `law_status` prominently; retracted/superseded documents shall be excluded from default results (`status=active` default).
- Non-English queries shall be automatically detected and translated to English before retrieval; the English translation shall be cached in Redis to avoid repeat translation cost.
- Search responses shall include cache hit indicator, query language, search mode, and latency in milliseconds.
- The AI assistant endpoint (`POST /ai/ask`) shall use a LangGraph-orchestrated RAG pipeline (see Section 7.7) to answer natural language legal questions with inline citations.
- Low-confidence RAG answers shall be routed to the moderation queue for expert review rather than returned to the member.
- The system shall provide AI-generated summaries of individual documents on demand (`POST /ai/summarize/{document_id}`), surfaced on the document detail page.
- The system shall provide AI-generated summaries of Q&A answer threads on demand (`POST /ai/summarize/question/{question_id}`), surfaced to the question author and moderators.
- The system shall surface AI-powered related content for each approved item: related documents (`GET /documents/{id}/related`), related questions (`GET /questions/{id}/related`), related news (`GET /news/{id}/related`), and related posts (`GET /posts/{id}/related`), using k-NN similarity against the respective OpenSearch index.

### 4.10 Module 10 — Multi-Language Support

- Members shall set a preferred language on their profile (EN / ES / FR for MVP).
- Content list endpoints shall accept a `?lang=` parameter to return translated titles and summaries.
- The AI translation pipeline (Celery `translation_job`) shall translate input queries to English for processing and translate responses back to the member's preferred language.
- Translation results shall be cached in Redis (db=2, TTL 24 hours) to minimise repeated API calls.
- Non-English question text submitted via `POST /questions` shall be stored in the original submission language. The system shall automatically translate the question body to English during the `qa_embedding_job` AI indexing pipeline to ensure cross-language RAG retrieval. The original-language text is always returned to the submitter; English is used internally for vector embedding only.

### 4.11 Module 11 — Notifications

- The system shall deliver in-app notifications for the following events: content approval, content rejection, question answered, answer accepted, content flagged, and news broadcast.
- Members shall configure notification preferences by country and category to control which news broadcasts they receive.
- Notification endpoints shall support: list, unread count, mark as read, mark all as read, and delete.
- Email notifications shall be sent for critical events: password reset, initial invite, account deactivation.

### 4.12 Module 12 — Admin Dashboard and Analytics

- Admins shall access a dashboard aggregating: total users (by role, by organisation), total content items (by type and status), moderation throughput, and AI query volume.
- Admins shall view AI usage and cost breakdown: embedding calls, translation API calls, RAG queries, and estimated cost by time range.
- Admins shall configure platform settings: AI confidence thresholds, moderation SLA targets, max content per org, invite expiry periods, and supported languages.
- Admins shall manage the taxonomy: create, update, and delete categories, tags, and supported countries.

### 4.13 Module 13 — Document Ingestion Pipeline (Docling)

The document ingestion pipeline shall leverage **Docling** as the primary document parsing engine:

- **Docling** shall handle PDF parsing including: native text extraction, OCR for scanned pages, table structure recognition, and metadata extraction (title, author, date where embedded).
- Docling output shall be normalised into a JSON representation before chunking, preserving paragraph boundaries and table cells as discrete chunk candidates.
- The pipeline shall fall back to raw text extraction if Docling processing exceeds a configurable timeout (default 120 seconds).
- Chunking shall produce 512-token segments with 64-token overlap, respecting paragraph boundaries where possible.
- Per-chunk embeddings (dims=384) shall be stored in OpenSearch `ica_document_chunks`; a document-level centroid vector shall be stored in `ica_documents`.

### 4.14 Module 14 — Live Expert Sessions (LiveKit — Phase 2)

**LiveKit** shall be integrated in Phase 2 to enable real-time expert engagement:

- Admins and Moderators shall schedule live Q&A sessions with ICA legal experts using LiveKit rooms.
- Members shall join scheduled live sessions for jurisdictional legal briefings and policy discussions.
- Session recordings (audio/video) shall be optionally stored in S3 and linked back to relevant Q&A threads or news articles.
- LiveKit webhooks shall trigger content creation events (e.g., session summary auto-created as a news article in pending state).

---

## 5. Detailed Requirement Table

| Req ID | Module | Requirement Description | Role | Priority | Complexity | Remarks |
|---|---|---|---|---|---|---|
| REQ-001 | Auth | User registers via valid single-use invite code tied to an organisation | U | Must Have | Low | Invite validated before account creation |
| REQ-002 | Auth | Email + password login with JWT access and refresh tokens | A, M, U | Must Have | Low | |
| REQ-003 | Auth | Password reset via time-limited email link | A, M, U | Must Have | Low | SMTP / SendGrid |
| REQ-004 | Auth | First-login setup: capture country and category preferences | U | Must Have | Low | Stored on user profile |
| REQ-005 | Auth | JWT invalidated on logout; refresh token endpoint | A, M, U | Must Have | Low | |
| REQ-006 | User Mgmt | Admin creates, updates, deactivates user accounts | A | Must Have | Low | |
| REQ-007 | User Mgmt | Admin assigns or changes user role | A | Must Have | Low | |
| REQ-008 | User Mgmt | User deletion anonymises PII (no hard delete) | A | Must Have | Low | GDPR compliance |
| REQ-009 | User Mgmt | Admin views user contribution history | A, M | Should Have | Low | |
| REQ-010 | Org Mgmt | Admin creates and manages organisations with max_users limit | A | Must Have | Low | |
| REQ-011 | Invite | Admin generates single-use invite codes per organisation | A | Must Have | Low | Configurable expiry |
| REQ-012 | Invite | Admin revokes outstanding invites | A | Must Have | Low | |
| REQ-013 | Repository | Member uploads PDF document or external URL with metadata | U | Must Have | Medium | Country, law type, language required |
| REQ-014 | Repository | Uploaded document enters pending state | SYS | Must Have | Low | Moderation-first |
| REQ-015 | Repository | Moderator approves, rejects, requests changes, or flags a document | M, A | Must Have | Medium | |
| REQ-016 | Repository | Moderator can retract an approved document (sets law_status) | M, A | Must Have | Medium | Active / Retracted / Superseded |
| REQ-017 | Repository | Every document edit creates an append-only version row | SYS | Must Have | Medium | Content versioning |
| REQ-018 | Repository | Member browses and filters approved documents | U | Must Have | Low | |
| REQ-019 | Repository | Member downloads approved documents | U | Must Have | Low | |
| REQ-020 | Repository | Docling extracts structured text and tables from PDFs (including scanned) | SYS | Must Have | High | Replaces custom OCR |
| REQ-021 | Repository | Approved documents are asynchronously chunked and embedded via Celery | SYS | Must Have | High | 512-token chunks, 64-token overlap |
| REQ-022 | Repository | Document chunks and centroid vectors indexed into OpenSearch | SYS | Must Have | High | ica_documents + ica_document_chunks indices |
| REQ-023 | Q&A | Member submits question with country, category, and optional tags | U | Must Have | Low | Enters pending state |
| REQ-024 | Q&A | Moderator approves, rejects, or requests changes on questions | M, A | Must Have | Low | |
| REQ-025 | Q&A | Moderator assigns question to a legal expert | M, A | Must Have | Low | |
| REQ-026 | Q&A | Expert or member posts an answer; one answer is marked accepted | M, A, U | Must Have | Medium | |
| REQ-027 | Q&A | Approved Q&A pair is embedded and indexed into ica_questions | SYS | Must Have | High | Enables RAG retrieval |
| REQ-028 | Q&A | is_verified flag upgraded by credentialled lawyer; increases RAG weight | M, A | Should Have | Medium | |
| REQ-029 | News | Member submits news article with country, category, and date | U | Must Have | Low | Enters pending state |
| REQ-030 | News | Moderator approves, rejects, or requests changes on news articles | M, A | Must Have | Low | |
| REQ-031 | News | On approval, fan-out broadcast notification sent to subscribed members | SYS | Must Have | Medium | news_broadcast_job |
| REQ-032 | News | Admin posts official ICA news bypassing moderation queue | A | Must Have | Low | |
| REQ-033 | Social Feed | Member creates short-form post; post enters pending state | U | Should Have | Low | |
| REQ-034 | Social Feed | Members like/unlike posts and add threaded comments | U | Should Have | Low | |
| REQ-035 | Social Feed | Moderators delete inappropriate comments | M, A | Should Have | Low | |
| REQ-036 | Moderation | Unified queue aggregates all pending content across types | M, A | Must Have | Medium | |
| REQ-037 | Moderation | Moderation actions: Approve, Reject (with remarks), Request Changes, Flag, Retract | M, A | Must Have | Medium | |
| REQ-038 | Moderation | All moderation decisions written to immutable audit log | SYS | Must Have | Low | |
| REQ-039 | Moderation | AI pre-screen flags potentially inappropriate content before queue entry | SYS | Should Have | High | ai_content_flag_job |
| REQ-040 | Search | Hybrid BM25 + k-NN search across all content types | U | Must Have | High | OpenSearch |
| REQ-041 | Search | Filters: type, country, category, date range, law status, search mode | U | Must Have | Medium | |
| REQ-042 | Search | Retracted/superseded documents excluded by default (status=active) | SYS | Must Have | Low | |
| REQ-043 | Search | Non-English query auto-detected, translated to English, cached in Redis | SYS | Should Have | High | translation_job + Redis db=2 |
| REQ-044 | Search | Search response cached in Redis (5-min TTL); cache invalidated on content change | SYS | Should Have | Medium | SearchCacheMiddleware |
| REQ-045 | AI / RAG | AI assistant answers natural language legal questions with citations | U | Should Have | High | LangGraph RAG pipeline |
| REQ-046 | AI / RAG | Low-confidence AI answers routed to moderation queue for expert review | SYS | Should Have | High | Confidence threshold = 0.50 |
| REQ-047 | AI / RAG | AI answer audit log: query, sources, confidence, reasoning path | SYS | Must Have | Medium | 30-day TTL enforced by cleanup job |
| REQ-048 | AI / RAG | Docling-structured chunks used as primary RAG retrieval corpus | SYS | Should Have | High | Improves passage quality |
| REQ-049 | Multi-Lang | Member sets preferred language on profile | U | Should Have | Low | EN / ES / FR for MVP |
| REQ-050 | Multi-Lang | Content endpoints accept ?lang= for translated titles/summaries | U | Should Have | High | |
| REQ-051 | Notifications | In-app notifications for approval, rejection, answered, flagged, broadcast | U | Must Have | Medium | notification_dispatch_job |
| REQ-052 | Notifications | Member configures notification preferences by country/category | U | Should Have | Low | Controls news broadcast receipt |
| REQ-053 | Admin | Admin dashboard: user counts, content counts, moderation throughput | A | Must Have | Medium | |
| REQ-054 | Admin | AI usage and cost report: token counts, embedding calls, RAG queries | A | Should Have | Medium | |
| REQ-055 | Admin | Admin configures: AI confidence thresholds, invite expiry, supported languages | A | Should Have | Low | |
| REQ-056 | Admin | Admin manages taxonomy: categories, tags, countries | A | Must Have | Low | |
| REQ-057 | Audit | Content versioning for documents, questions, and news (append-only) | SYS | Must Have | Medium | |
| REQ-058 | Audit | Moderation audit log accessible to Admins; item-level log accessible to Moderators | A, M | Must Have | Low | |
| REQ-059 | LiveKit | Schedule and host live expert Q&A sessions (Phase 2) | A, M | Could Have | High | LiveKit integration |
| REQ-060 | LiveKit | Members join live sessions; recordings optionally stored in S3 | U | Could Have | High | Phase 2 |
| REQ-061 | Q&A | Moderators and Admins access AI-generated answer suggestions for an approved question (`GET /ai/suggestions/{question_id}`) | M, A | Should Have | Medium | Phase 2; assists expert assignment |
| REQ-062 | Q&A | Moderators and Admins promote an approved Q&A pair to a knowledge article (`POST /questions/{id}/promote`) | M, A | Should Have | Medium | Phase 2; elevates to curated knowledge entry |
| REQ-063 | Auth | Any authenticated user updates their own profile (name, bio, preferred language, avatar) via `PATCH /auth/me` | A, M, U | Must Have | Low | |
| REQ-064 | User Mgmt | Member accesses own submission history across all content types (`/documents/my`, `/questions/my`, `/news/my`, `/posts/my`) | A, M, U | Must Have | Low | |
| REQ-065 | User Mgmt | Member checks current moderation status of any of their own submissions (`GET /{type}/{id}/status`) | A, M, U | Must Have | Low | Pending / Approved / Rejected / Revision Required |
| REQ-066 | Multi-Lang | Non-English question submissions stored in original language; translated to English for AI indexing via `qa_embedding_job` | SYS | Should Have | Medium | Extends CL-7 to Q&A submissions |
| REQ-067 | AI / RAG | AI-generated summary of a document on demand (`POST /ai/summarize/{document_id}`) | A, M, U | Should Have | Medium | Phase 2 |
| REQ-068 | AI / RAG | AI-generated summary of a Q&A answer thread on demand (`POST /ai/summarize/question/{question_id}`) | A, M, U | Should Have | Medium | Phase 2 |
| REQ-069 | Search / AI | AI-powered related content surfaced per item for documents, questions, news, and posts (k-NN similarity) | A, M, U | Should Have | Medium | Phase 2; GET /{type}/{id}/related |
| REQ-070 | Q&A | Member browses and filters all approved Q&A pairs (`GET /questions`) | A, M, U | Must Have | Low | |
| REQ-071 | Social Feed | Member browses social feed of all approved posts (`GET /posts`) | A, M, U | Must Have | Low | |
| REQ-072 | Moderation | Moderator assigns or confirms `category_id` for news and posts as part of the approve action | M, A | Must Have | Low | Ensures all approved content is categorised |
| REQ-073 | Moderation | Document review includes an authenticity validation step recorded in the moderator's remarks | M, A | Should Have | Low | Validates document is a genuine legal instrument |
| REQ-074 | News | Admin features or pins an approved news article for prominent display (`PATCH /news/{id}/feature`) | A | Could Have | Low | News curation capability |

---

## 6. Non-Functional Requirements

### 6.1 Security

| # | Requirement |
|---|---|
| SEC-1 | All API endpoints are HTTPS only; HTTP is not supported in production |
| SEC-2 | JWT tokens use RS256 signing; signing keys are rotated on a configurable schedule |
| SEC-3 | Passwords are hashed using bcrypt with a minimum work factor of 12 |
| SEC-4 | All file upload paths validate MIME type and file size (default max: 50 MB per document) |
| SEC-5 | SQL injection is prevented via SQLAlchemy ORM parameterised queries |
| SEC-6 | The Docling ingestion pipeline runs in an isolated Celery worker process; uploaded files are not executed |
| SEC-7 | AI prompt inputs are sanitised to prevent prompt injection; raw user queries are not passed verbatim to LLM without wrapping |
| SEC-8 | LiveKit rooms (Phase 2) require authenticated session tokens scoped to the specific room and role |

### 6.2 Authentication and Authorisation

| # | Requirement |
|---|---|
| AZ-1 | RBAC is enforced at the API gateway layer; no role escalation is possible via API manipulation |
| AZ-2 | JWT access tokens expire after 30 minutes; refresh tokens expire after 7 days |
| AZ-3 | Invite codes are single-use, organisation-scoped, and expire after 72 hours (Admin-configurable) |
| AZ-4 | Admin operations (role change, user deactivation, config update) are rate-limited to prevent automated abuse |

### 6.3 Data Privacy

| # | Requirement |
|---|---|
| PV-1 | PII (email, full name) is stored only in the `users` table and not duplicated to audit logs or search indices |
| PV-2 | User deletion anonymises PII fields (null email, null name, status=deleted) while preserving contribution records |
| PV-3 | AI audit logs in `outbox_events` do not store raw user queries beyond 30 days (nightly Celery cleanup job) |
| PV-4 | Document content bodies are not treated as PII; contributor attribution is retained post-anonymisation with placeholder name |

### 6.4 Auditability

| # | Requirement |
|---|---|
| AU-1 | All moderation decisions (approve, reject, request changes, flag, retract) are written to an immutable audit log with actor, timestamp, action, and remarks |
| AU-2 | All content mutations create a version row; version history is never deleted |
| AU-3 | AI-generated answers log: query, source document IDs, chunk IDs, Q&A IDs used, confidence score, and reasoning path |
| AU-4 | Invite usage (issued, redeemed, revoked, expired) is tracked in the `invites` table and never hard-deleted |

### 6.5 Performance

| # | Requirement |
|---|---|
| PF-1 | `GET /search` response time ≤ 1,500 ms at p95 under expected load |
| PF-2 | `POST /ai/ask` response time ≤ 2,500 ms at p95 with warm translation cache |
| PF-3 | Cached search responses (`cache_hit=true`) must be served in ≤ 50 ms |
| PF-4 | Non-English query translation (cache miss) must complete within ≤ 500 ms |
| PF-5 | Dashboard aggregate endpoint (`GET /dashboard`) must respond within ≤ 500 ms |
| PF-6 | Docling document processing must complete within 120 seconds for a 50-page PDF; the pipeline marks the job as failed beyond this threshold |

### 6.6 Scalability

| # | Requirement |
|---|---|
| SC-1 | The OpenSearch cluster scales from 1 shard (single-node dev) to a 3-node cluster when document chunk count exceeds 200,000 |
| SC-2 | Celery worker count is horizontally scalable without code changes |
| SC-3 | The platform must handle 500 concurrent authenticated users without degrading search SLA |
| SC-4 | File storage scales transparently from MinIO (dev) to AWS S3 (prod) via a configurable provider abstraction |

### 6.7 Availability

| # | Requirement |
|---|---|
| AV-1 | Target uptime: 99.5% monthly (production environment) |
| AV-2 | Celery worker failures must not cause API request failures; queued jobs shall be retried with exponential back-off (max 3 retries) |
| AV-3 | Search must degrade gracefully: if OpenSearch is unavailable, the API returns a 503 with a user-friendly message rather than a 500 error |

### 6.8 Maintainability

| # | Requirement |
|---|---|
| MT-1 | Backend follows Clean Architecture: API → Service → Repository layers with no business logic in route handlers |
| MT-2 | All database schema changes are managed via Alembic migrations; no manual schema edits are permitted |
| MT-3 | Environment-specific configuration is managed via `.env` files and Pydantic settings; no hardcoded credentials |
| MT-4 | Frontend uses MSW mock service worker (`NEXT_PUBLIC_DEMO_MODE=true`) for UI development without a running backend |

### 6.9 Backup and Recovery

| # | Requirement |
|---|---|
| BR-1 | PostgreSQL daily backups with 30-day retention |
| BR-2 | MinIO / S3 document storage versioning enabled; objects are never permanently deleted without Admin confirmation |
| BR-3 | Recovery point objective (RPO): ≤ 24 hours; recovery time objective (RTO): ≤ 4 hours |

### 6.10 Compliance

| # | Requirement |
|---|---|
| CO-1 | GDPR right-to-erasure fulfilled via user anonymisation path (`DELETE /users/{id}`) |
| CO-2 | All content moderated before public visibility; no unvetted UGC is accessible to members |
| CO-3 | AI is explicitly labelled as assistive; generated answers carry a disclaimer that they do not constitute legal advice |
| CO-4 | Audit trail is tamper-proof at the database level (append-only; no UPDATE/DELETE permissions on audit tables) |

---

## 7. Workflow Requirements

### 7.1 Member Onboarding Workflow

```
Admin generates invite code (org-scoped, max_users checked)
  → Invite sent to prospective member (email, out-of-band)
  → Member opens invite URL → POST /auth/verify-invite
  → Valid: member completes registration form → POST /auth/signup
  → Account created with role=Member, org=invite.org_id
  → First-login setup: member selects countries and categories of interest
  → Member lands on personalised dashboard
```

**SLA target:** Invite generation is instant. Registration is instant. Admin is notified (in-app) when an invite is redeemed.

### 7.2 Legal Document Submission and Approval Workflow

```
Member uploads PDF / URL → POST /documents
  → Document record created: status=pending
  → ai_content_flag_job: AI pre-screens for relevance and appropriateness
  → Document appears in moderation queue: GET /moderation/queue/documents
  → Moderator reviews document + Docling-extracted summary
      ├── Approve → POST /moderation/approve
      │     → status=approved; contributor notified (notification_dispatch_job)
      │     → document_ingestion_job: Docling → chunking → embedding_generation_job → search_index_job
      │     → search_cache_invalidate_job: purge Redis keys for country/category scope
      ├── Reject → POST /moderation/reject (remarks required)
      │     → status=rejected; contributor notified with reason
      ├── Request Changes → POST /moderation/request-changes
      │     → status=revision_required; contributor notified; contributor can re-submit
      └── Flag → POST /moderation/flag
            → status=flagged; item held; Admin notified for senior review
```

### 7.3 Document Retraction Workflow

```
Moderator / Admin identifies approved document as retracted/superseded in real world
  → POST /moderation/retract (with law_status: retracted | superseded, remarks required)
  → Document record updated: law_status=retracted/superseded
  → search_cache_invalidate_job: purge affected search cache keys
  → Document excluded from default search results (status=active default)
  → Contributor notified; retraction recorded in moderation audit log
```

### 7.4 Question Submission and Moderation Workflow

```
Member submits question → POST /questions
  → Question record created: status=pending
  → ai_content_flag_job: AI pre-screens relevance
  → Appears in moderation queue: GET /moderation/queue/questions
  → Moderator reviews
      ├── Approve → question status=approved; member notified
      │     ├── Moderator assigns to legal expert: PATCH /questions/{id}/assign
      │     └── Expert (or any moderator/admin) posts answer: POST /questions/{id}/answers
      ├── Reject → status=rejected; member notified with reason
      └── Request Changes → status=revision_required; member notified
```

### 7.5 Answer Publishing and Knowledge Base Evolution Workflow

```
Expert posts answer to approved question
  → Answer record created (pending or directly approved if posted by Admin/Moderator)
  → Question author or Moderator marks answer as accepted: PATCH /answers/{id}/accept
  → qa_embedding_job: embed question + answer_summary → index into ica_questions (is_verified=false)
  → Member notified: "Your question has been answered"
  → [Optional] Credentialled lawyer reviews answer
      → PATCH /answers/{id}/verify (Admin / designated expert only)
      → qa_verify_embedding_job: re-index with is_verified=true (higher RAG weight)
```

### 7.6 News Publishing Workflow

```
Member or Admin submits news article → POST /news
  → [Admin] status=approved immediately (no moderation required)
  → [Member] status=pending; enters moderation queue
  → Moderator approves → news_broadcast_job triggered
      → Fan-out in-app notification to all members subscribed to article's country/category
  → Member notified: "Your submission has been approved"
```

### 7.7 AI RAG Answer Workflow (LangGraph)

```
Member submits natural language question → POST /ai/ask
  → Translation check: if lang ≠ EN → translate to English (Redis cache, then translation_job)
  → LangGraph workflow dispatched via ai_answer_job (Celery):
      [Intent Classifier Node]
        → factual | procedural | jurisdictional | out-of-scope
      [Doc Retriever Node] ← k-NN on ica_document_chunks (law_status=active, country/category filter)
      [Verified Q&A Retriever Node] ← k-NN on ica_questions (is_verified=true)
      [Post Retriever Node] ← k-NN on ica_posts (only if combined hits < 3)
      [Source Merger & Ranker Node]
        → Reciprocal rank fusion: docs(1.0) + verified Q&A(0.8) + posts(0.3)
      [Confidence Scorer Node]
        → confidence ≥ 0.75 → [LLM Generation Node] → answer with inline citations
        → confidence < 0.50 → [Flag for Expert Review Node] → "pending expert review" returned to member
      [Audit Logger Node] → log to outbox_events (query, sources, confidence, reasoning path)
  → Translate response to member's preferred language if needed
  → Return answer with citations, confidence indicator, and disclaimer
```

### 7.8 Admin Review and Configuration Workflow

```
Admin monitors platform via GET /admin/stats
  → Reviews AI usage and cost: GET /admin/ai-usage
  → Reviews moderation throughput: GET /moderation/stats
  → Adjusts platform config if needed: PUT /admin/config
      (AI confidence thresholds, moderation SLA targets, invite expiry, supported languages)
  → Reviews full audit log: GET /moderation/logs
```

---

## 8. Reporting Requirements

### 8.1 User Activity Reports

| Report | Endpoint | Description | Role |
|---|---|---|---|
| Platform user summary | `GET /admin/stats` | Total users by role and by organisation | A |
| User contribution history | `GET /users/{id}/contributions` | Questions, documents, news, posts by a specific user | A, M |
| New registrations by period | `GET /admin/stats` (filtered) | Invites redeemed over time | A |

### 8.2 Content Usage Reports

| Report | Endpoint | Description | Role |
|---|---|---|---|
| Content volume by type | `GET /admin/stats` | Counts of docs, questions, news, posts by status | A |
| Download activity | Server-side log aggregation | Most-downloaded documents over a time range | A |
| AI query volume | `GET /admin/ai-usage` | RAG queries, embedding calls, translation calls by period | A |
| AI cost estimate | `GET /admin/ai-usage` | Estimated USD cost breakdown by AI service | A |

### 8.3 Country-wise Legal Content Reports

| Report | Endpoint | Description | Role |
|---|---|---|---|
| Documents by country | `GET /documents?country=XX` | Document count and list per jurisdiction | A, M |
| Q&A by country | `GET /questions?country=XX` | Question and answer counts per jurisdiction | A, M |
| News by country | `GET /news?country=XX` | News volume per jurisdiction | A, M |
| Retracted laws by country | `GET /search?status=retracted&country=XX` | Laws marked retracted or superseded per jurisdiction | A, M |

### 8.4 Q&A Status Reports

| Report | Endpoint | Description | Role |
|---|---|---|---|
| Question status distribution | `GET /moderation/stats` | Pending / Approved / Rejected / Revision counts | A, M |
| Unanswered questions | `GET /questions?answer_status=unanswered` | Questions approved but without an accepted answer | A, M |
| Verified Q&A pairs | `GET /questions?is_verified=true` | Q&A pairs validated by credentialled lawyers | A, M |

### 8.5 Moderator Activity Reports

| Report | Endpoint | Description | Role |
|---|---|---|---|
| Moderation throughput | `GET /moderation/stats` | Decisions made per day/week by content type | A |
| Moderation audit log | `GET /moderation/logs` | Full immutable audit trail of all decisions | A |
| Per-item moderation history | `GET /moderation/logs/{type}/{id}` | Decision history for a specific content item | A, M |
| Flagged items pending senior review | `GET /moderation/queue/flagged` | Content held for Admin resolution | A |

---

## 9. MVP Scope

The MVP (Phase 1) delivers the core platform with full moderation workflow, repository, Q&A, and news — without the AI layer.

### 9.1 MVP Modules

| Module | Included in MVP | Notes |
|---|---|---|
| Authentication and Invite Onboarding | Yes | Full JWT + invite flow |
| Member Profile Management (PATCH /auth/me) | Yes | Name, bio, preferred language, avatar |
| User and Organisation Management | Yes | Admin-managed |
| Member Submission History (/*/my endpoints) | Yes | Self-service history across all content types |
| Submission Status Tracking (/{type}/{id}/status) | Yes | Member tracks own submission moderation state |
| Legal Document Repository | Yes | Upload, metadata, moderation, download, versioning |
| Document Moderator Authenticity Validation | Yes | Recorded in moderation remarks |
| Document Ingestion Pipeline (Docling) | Yes | OCR + chunking + embedding + OpenSearch indexing |
| Q&A Forum | Yes | Submit, moderate, answer, accept; browse approved Q&A |
| News and Legal Updates | Yes | Submit, moderate, broadcast notification |
| Moderator Categorisation at Approval | Yes | Category assigned during approve action |
| Social Feed and Posts | Yes | Browse feed; create; likes and comments |
| Moderation Queue (Unified) | Yes | All content types; full action set |
| Hybrid Search (OpenSearch) | Yes | BM25 + k-NN; keyword + semantic |
| In-App Notifications | Yes | Approval, rejection, answered, news broadcast |
| Admin Dashboard | Yes | Users, content counts, moderation stats |
| Taxonomy Management | Yes | Categories, tags, countries |
| Audit Trail and Content Versioning | Yes | |
| Multi-Language Support | No | Phase 2 |
| Non-English Q&A Submission (original + EN translation for indexing) | No | Phase 2 |
| AI RAG Assistant (`/ai/ask`) | No | Phase 2 |
| AI Content Pre-Screening | No | Phase 2 |
| AI Document Summarisation (`/ai/summarize`) | No | Phase 2 |
| AI Q&A Thread Summarisation | No | Phase 2 |
| AI Answer Suggestions for Moderators (`/ai/suggestions`) | No | Phase 2 |
| Related Content (k-NN per content item) | No | Phase 2 |
| Promote Q&A to Knowledge Article | No | Phase 2 |
| News Curation / Pinning (Admin) | No | Phase 2 (Could Have) |
| Advanced Analytics / AI Cost Dashboard | No | Phase 2 |
| Q&A Threaded Discussions (comments on answers) | No | Phase 3 |
| Knowledge Graph Evolution | No | Phase 3 — see §10 for deferral rationale |
| LiveKit Live Sessions | No | Phase 3 |

### 9.2 MVP Acceptance Criteria (Summary)

- A member can register via invite, log in, upload a document, and see it appear in the repository after moderator approval.
- A member can update their profile and view their own submission history with current moderation status for each item.
- A member can submit a question, have it assigned to an expert, receive an answer, and be notified.
- A member can browse the social feed, create a post, like and comment on posts.
- A moderator can action all pending items from a single queue using all five moderation actions, including categorising news/posts at approval time.
- Hybrid search returns results within 1,500 ms for a simple query against a corpus of 500 documents.
- An Admin can manage users, generate invites, view platform content counts, and feature a news article.

---

## 10. Future Enhancements

### Phase 2

| # | Feature | Description |
|---|---|---|
| FE-1 | Multi-language support (EN / ES / FR) | Translation pipeline via English pivot; content endpoints accept `?lang=` |
| FE-2 | AI RAG legal assistant | LangGraph-orchestrated `/ai/ask` with LLM answer generation and inline citations |
| FE-3 | AI content pre-screening | Celery job flags inappropriate or off-topic content before moderation queue entry |
| FE-4 | AI answer suggestions for moderators | Surface RAG-generated answer suggestions on the Q&A moderation view (`GET /ai/suggestions/{question_id}`) — REQ-061 |
| FE-5 | AI document and Q&A summarisation | Auto-generated summary for documents and Q&A threads (`POST /ai/summarize/{document_id}`, `POST /ai/summarize/question/{question_id}`) — REQ-067, REQ-068 |
| FE-6 | Related content suggestions | AI-powered related content per item using k-NN (`GET /{type}/{id}/related`) — REQ-069 |
| FE-7 | AI cost and usage dashboard | Token counts, embedding calls, translation costs by time range |
| FE-8 | GDPR data portability export | Member can request a full export of their own data |
| FE-9 | Docling table and structured data extraction surfaced in UI | Extracted tables from PDFs rendered natively on document detail page |
| FE-18 | Promote Q&A to knowledge article | Moderator/Admin promotes an approved Q&A pair to a curated knowledge entry with enhanced discovery prominence (`POST /questions/{id}/promote`) — REQ-062 |
| FE-19 | News curation and pinning | Admin features or pins approved news articles on the platform home feed (`PATCH /news/{id}/feature`) — REQ-074 |
| FE-20 | Non-English Q&A submission (original language store + EN index) | Question text stored in submission language; `qa_embedding_job` translates to English for vector indexing — REQ-066 |

### Phase 3

| # | Feature | Description |
|---|---|---|
| FE-10 | LiveKit live expert sessions | Real-time video/audio Q&A sessions between members and ICA legal experts; recordings stored in S3 |
| FE-11 | External legal API integrations | Pull in data from national legal databases or legal news aggregators |
| FE-12 | Native mobile application | iOS and Android clients built on the same REST API |
| FE-13 | Advanced analytics and recommendations | Personalised content recommendations based on member activity and preferences |
| FE-14 | Knowledge graph visualisation | Visual map of connected laws, Q&A pairs, and jurisdictions. **Deferral rationale:** Requires entity extraction from legal text, a graph database (e.g. Neo4j), and law-to-law relationship modelling — infrastructure beyond the Phase 1/2 scope. The use-case document labels this a "core differentiator" but the build cost warrants phased delivery after the knowledge corpus reaches sufficient size. |
| FE-15 | Private messaging and direct collaboration | Member-to-member messaging or document co-authoring |
| FE-16 | Expanded language support | Arabic, Portuguese, and other ICA member languages beyond EN/ES/FR |
| FE-17 | Organisation-level content siloing | `org_visibility` field (`public` | `org_only`) on content tables for restricted sharing |
| FE-21 | Q&A threaded discussions (comments on answers) | Threaded comments on individual Q&A answers, enabling follow-up discussion within a question thread. **Scope note:** The use-case document lists this as "optional phase". It is explicitly deferred to Phase 3 and is out of scope for MVP and Phase 2. |

---

## 11. Acceptance Criteria

### AC-1: Authentication and Onboarding

- [ ] A new user cannot register without a valid, unexpired invite code.
- [ ] An expired or already-used invite code returns a 400 error with a clear message.
- [ ] A registered user can log in and receive a JWT access token and refresh token.
- [ ] Password reset email is received within 2 minutes; the reset link expires after 1 hour.
- [ ] On first login, the user is redirected to the setup page before accessing the dashboard.

### AC-2: Legal Document Repository

- [ ] A member can upload a PDF file up to 50 MB and submit it with mandatory metadata.
- [ ] The uploaded document appears in the moderation queue immediately after submission.
- [ ] A moderator can approve, reject, request changes, and flag a document from the moderation queue.
- [ ] After approval, the document is visible in `GET /documents` within 30 seconds (post-indexing).
- [ ] A retracted document does not appear in `GET /search` results when `status=active` (the default).
- [ ] Document version history is accessible to Admins and Moderators and includes all edits.
- [ ] Docling successfully extracts text from a scanned PDF (100% text coverage not required; minimum 80% on clean scans).

### AC-3: Question and Answer Forum

- [ ] A member can submit a question that appears in the moderation queue.
- [ ] A moderator can approve, reject, or assign a question to a legal expert.
- [ ] An expert can post an answer and the question author is notified in-app.
- [ ] Marking an answer as accepted triggers the `qa_embedding_job` and the Q&A pair appears in OpenSearch within 60 seconds.
- [ ] An approved Q&A pair is retrievable by `POST /ai/ask` after indexing.

### AC-4: News and Updates

- [ ] A member can submit a news article that enters the moderation queue.
- [ ] On approval, members who subscribed to the article's country/category receive an in-app notification.
- [ ] Admin-posted news bypasses moderation and is immediately visible in `GET /news`.

### AC-5: Moderation Queue

- [ ] The unified moderation queue displays pending items across all four content types on a single screen.
- [ ] Approve, Reject (with mandatory remarks), Request Changes, Flag, and Retract actions are all functional.
- [ ] All moderation actions are recorded in the audit log with actor identity and timestamp.
- [ ] The flagged items queue is accessible only to Admins.

### AC-6: Hybrid Search

- [ ] `GET /search?q=cooperative+law&country=IN` returns only results from India with `law_status=active`.
- [ ] A keyword-only query (`search_mode=keyword`) uses BM25 only; a semantic query uses k-NN only.
- [ ] The default hybrid query returns results from both BM25 and k-NN via reciprocal rank fusion.
- [ ] A cached search response (`cache_hit=true`) is served in under 50 ms.
- [ ] A French query with `?lang=fr` is translated to English, searched, and results are returned within the SLA.

### AC-7: AI RAG Assistant

- [ ] `POST /ai/ask` returns an answer with at least one inline source citation (doc_id or q_id) for a question within the indexed corpus.
- [ ] A low-confidence query returns a "pending expert review" message rather than a fabricated answer.
- [ ] The AI audit log entry for each query is readable by Admin within 5 seconds of the response being returned.
- [ ] The response always includes a disclaimer that the answer does not constitute legal advice.

### AC-8: Notifications

- [ ] A member receives an in-app notification when their submitted content is approved or rejected.
- [ ] A member receives a notification when their question receives an accepted answer.
- [ ] Notifications preferences (country/category filter) are respected; a member who has not subscribed to a country does not receive that country's news broadcast.

### AC-9: Admin Dashboard

- [ ] The Admin dashboard displays total users (by role), total documents (by status), pending moderation counts, and AI query volume.
- [ ] An Admin can change a user's role from the user list without requiring a page reload.
- [ ] An Admin can generate and revoke invite codes from the Invites management screen.
- [ ] An Admin can pin/feature a news article and it appears prominently above the standard feed.

### AC-10: Member Self-Service (Profile, History, Status)

- [ ] A member can update their profile (name, bio, preferred language, avatar) and changes persist after logout and re-login.
- [ ] A member can view their own documents, questions, news, and posts from a single "My Submissions" view.
- [ ] Each submission in "My Submissions" displays its current moderation status (Pending / Approved / Rejected / Revision Required).
- [ ] A status endpoint (`GET /{type}/{id}/status`) returns the correct status for all content types.

### AC-11: Social Feed

- [ ] `GET /posts` returns only approved posts in reverse-chronological order.
- [ ] A member can browse the feed, like/unlike a post, and add a comment without leaving the feed page.
- [ ] A pending or rejected post is not visible to other members in the feed.

### AC-12: AI Features (Phase 2)

- [ ] `GET /ai/suggestions/{question_id}` returns at least one AI-generated answer suggestion sourced from indexed documents or verified Q&A.
- [ ] `POST /ai/summarize/{document_id}` returns a summary of at least 100 words for a document with extractable text.
- [ ] `POST /ai/summarize/question/{question_id}` returns a summary of the accepted answer thread.
- [ ] `GET /documents/{id}/related` returns at least 3 related documents when the corpus contains similar content.
- [ ] `POST /questions/{id}/promote` creates a knowledge article entry and the Q&A pair appears in a dedicated knowledge articles view.
- [ ] A question submitted in French (`?lang=fr`) is stored in French, embedded in English, and retrievable via both English and French semantic queries.

---

## 12. Clarifications Required

| # | Area | Question / Ambiguity | Impact |
|---|---|---|---|
| CL-1 | Law Retraction | Should members be notified when a document they downloaded is subsequently retracted/superseded? Currently, the notification system covers content status changes at submission time, not post-approval retraction. | Medium — may require a retraction broadcast notification |
| CL-2 | Q&A Verification | Who specifically qualifies as a "credentialled lawyer" for setting `is_verified=true`? Is this any Moderator role, a specific sub-role, or a list managed by Admin config? | High — drives role model and access control design |
| CL-3 | Social Feed Moderation | Should posts support rich media (images, file attachments), or is text-only sufficient for MVP? Impacts storage, Docling pipeline scope, and moderation UI. | Medium |
| CL-4 | Org-level Content Scoping | The design notes that org-siloed content (`org_visibility=org_only`) is a future option. Is there any MVP requirement for any content type to be restricted to a single organisation's members? | High — affects core content visibility model |
| CL-5 | External URL Documents | When a document is submitted as an external URL (not a file upload), how does the ingestion pipeline operate? Is the URL crawled and the content fetched, or is it stored as metadata-only without chunking/embedding? | High — affects Docling pipeline scope for MVP |
| CL-6 | LiveKit Session Recordings | For Phase 2 LiveKit sessions, what are the retention policies for recordings? Are recordings subject to the same moderation workflow as other content? | Medium — Phase 2 scoping |
| CL-7 | Multi-language Content | When a document is uploaded in Spanish, is the original content stored and displayed in Spanish, with AI providing an English translation on demand, or is the document re-indexed in English only? | High — affects storage schema and retrieval design |
| CL-8 | Moderation SLA Enforcement | Should the system surface overdue items (e.g., pending > 48 hours) with a visual indicator in the moderation queue, or is SLA tracking entirely operational (outside the system)? | Low — UX decision |
| CL-9 | AI for News vs Q&A | Should the RAG pipeline (`POST /ai/ask`) also retrieve from the `ica_news` index, or is it limited to documents and verified Q&A? News articles may contain relevant legal commentary but are less authoritative than documents. | Medium — affects LangGraph source configuration |
| CL-10 | Docling Fallback | If Docling fails to extract sufficient text from a PDF (e.g., encrypted or corrupted file), should the document be automatically rejected, or should it be approved as metadata-only with a flag indicating no searchable content? | Medium — affects moderation UX and search quality |
| CL-11 | Non-English Q&A Submissions | REQ-066 specifies that non-English questions are stored in the original language and translated for AI indexing. Does the same rule apply to **answers**? If an expert answers in Spanish, should the answer body be stored in Spanish and translated for embedding, or must answers always be submitted in English? | Medium — affects `qa_embedding_job` design and moderator answer review UX |
| CL-12 | Knowledge Article UI | REQ-062 introduces a "knowledge article" content type created via promote. Should knowledge articles have a distinct URL, layout, and search index entry, or are they simply promoted Q&A pairs rendered with a different visual treatment on the existing questions detail page? | Medium — affects frontend routing and OpenSearch index design |
| CL-13 | News Curation Scope | REQ-074 introduces a feature/pin capability for news. Should this support (a) a single globally pinned article, (b) multiple pinned articles with an ordered priority, or (c) category-scoped pinning (pin within a country or category feed)? | Low — UX and data model decision |
