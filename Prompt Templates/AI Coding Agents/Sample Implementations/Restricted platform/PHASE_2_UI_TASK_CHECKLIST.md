# Implementation Task Checklist (UI Task list) — Phase 2

> Scope: Phase-2 features per SAD §14.1 — AI RAG Assistant, AI answer suggestions, AI summarisation, related content, AI content pre-screening surfacing, Q&A discussion comments, Q&A promote to knowledge article, news curation/pinning, AI cost dashboard, multi-language (EN/ES/FR) UI + `?lang=` content fetches, GDPR data portability export, Docling structured-data display on document detail.
> All Phase-1 foundation is assumed in place (Next.js App Router, MUI, Tailwind, React Query, Zustand, MSW, typed API client, auth guard).
> Phase-3 features (LiveKit, Knowledge Graph, native mobile, SSE notifications, private messaging, org-level siloing) are **out of scope**.

---

## 1. Frontend Tasks

### Module 0 — Phase-2 Foundation & Cross-cutting

- [ ] **T0.1 — Add Spanish + French locale catalogues**
      Description: Extend `next-intl` from EN to EN/ES/FR; locale switcher in header; **mandatory** route-level locale prefix (`/en`, `/es`, `/fr`).
      Files / Components to be changed: `frontend/i18n.ts`, `frontend/messages/{en,es,fr}.json`, `frontend/middleware.ts`, `frontend/components/layout/LocaleSwitcher.tsx`, `frontend/components/layout/Header.tsx`, `frontend/store/auth.ts`.
      Implementation Notes: Locale resolved from (1) URL prefix `/es/...`, (2) JWT `preferred_lang` claim, (3) `Accept-Language` (fallback only when no prefix). Switching locale = `router.replace` to the new-prefix URL + fire-and-forget `PATCH /auth/me { preferred_lang }`; **no hard reload** (React Query keys are locale-scoped per T0.2). Persist locale in Zustand auth store.
      Acceptance Criteria: Toggling to FR rewrites URL to `/fr/...` and translates static UI; deep links carry locale; new login adopts JWT `preferred_lang`.

- [ ] **T0.2 — Plumb `?lang=` into all content fetchers**
      Description: Update `lib/api/{documents,questions,news}.ts` + React Query hooks to send `?lang=<userLocale>` when locale ≠ `en`.
      Files: `frontend/lib/api/documents.ts`, `frontend/lib/api/questions.ts`, `frontend/lib/api/news.ts`, `frontend/hooks/useDocuments.ts`, `useQuestions.ts`, `useNews.ts`.
      Implementation Notes: Cache key per locale (React Query). Server contract (mirrored in API T-B5.3 / T-B6.1 / T-B7.4): root-level **`translated_from: "en" | null`** flag plus **`translation_unavailable: boolean`** for circuit-open signalling. Display a small "translated" badge when `translated_from != null`.
      Acceptance Criteria: With locale=fr, list/detail responses arrive with translated titles/bodies; `translated_from` badge visible on translated items.

- [ ] **T0.3 — AI disclaimer + assistive-label component**
      Description: Reusable disclaimer banner mandated by SAD §9.9.
      Files: `frontend/components/ai/AiDisclaimer.tsx`.
      Implementation Notes: Shown on every page that renders AI output. Copy comes from i18n catalogue.
      Acceptance Criteria: Snapshot test asserts banner text present on `/search` (AI tab), Q&A suggestions, summary modals.

- [ ] **T0.4 — Add AI module to MSW handlers**
      Description: Stub `/ai/ask`, `/ai/suggestions/{id}`, `/ai/summarize/{document_id}`, `/ai/summarize/question/{question_id}`, `/ai/translate`, `/ai/translate/languages`, `/{type}/{id}/related`, `GET /admin/ai-audit` (≥ 3 fixture rows covering high/mid/low confidence bands, one flagged, one insufficient), and `GET /admin/ai-usage` (≥ 7 days of daily rows across at least 3 event types — `ai_query.completed`, `ai_summarize`, `ai_translate`, `ai_embedding` — plus a `top_users` array with ≥ 5 fixture users so all three T14.1 visualisations render: line chart, stacked bar, top-users table).
      Files: `frontend/mocks/handlers/ai.ts`, `frontend/mocks/data/aiFixtures.ts`, `frontend/mocks/data/aiUsageFixtures.ts`.
      Acceptance Criteria: With `NEXT_PUBLIC_DEMO_MODE=true`, every new Phase-2 endpoint resolves to deterministic mock data; the audit log page (T14.4) renders all three confidence bands; the AI usage dashboard (T14.1) renders line/bar/table against fixture data; switching `?granularity=day|week|month` returns correctly bucketed rows.

---

### Module 5 — Repository (Phase-2 enhancements)

- [ ] **T5.1 — Related documents panel on `/repository/[id]`**
      Description: Side panel listing semantically related documents via `GET /documents/{id}/related`.
      Files: `frontend/components/repository/RelatedDocumentsPanel.tsx`, `frontend/app/(app)/repository/[id]/page.tsx`, `frontend/hooks/useRelatedDocuments.ts`.
      Implementation Notes: `k=10`, exclude self. Skeleton while loading; collapses on small screens.
      Acceptance Criteria: Each card links to its detail; "no related items" empty state when ≤ 0 hits.

- [ ] **T5.2 — Document AI summary modal**
      Description: "Generate summary" action triggers `POST /ai/summarize/{document_id}`; result rendered in modal with disclaimer + copy-to-clipboard.
      Files: `frontend/components/repository/SummaryDialog.tsx`, `frontend/hooks/useDocumentSummary.ts`.
      Implementation Notes: Show loading state up to 10 s. 429 toast copy: *"AI summary limit reached. Try again in {Retry-After}s."* with live countdown derived from the `Retry-After` header. If `documents.summary` already exists server-side, returns it immediately (no re-summarise). Expose a **`Regenerate`** action gated to Admin/Moderator role only. Cache by `document_id` for current session.
      Acceptance Criteria: Repeated open within session does not re-call API; disclaimer visible; member role does not see Regenerate.

- [ ] **T5.3 — Docling structured-data panel on `/repository/[id]`**
      Description: Surface Docling-extracted tables, sections (TOC), and key/value pairs from the `structured_data` block on the document detail response (API T-B5.4). Adds a "Structured data" tab on the document page with sub-views: **Tables** (paginated, each rendered as MUI `<Table>` with caption + page-anchor link back to the PDF preview), **Sections** (collapsible outline / mini-TOC), and **Key fields** (definition list).
      Files / Components: `frontend/app/(app)/repository/[id]/page.tsx`, `frontend/components/repository/StructuredDataTab.tsx`, `frontend/components/repository/ExtractedTable.tsx`, `frontend/components/repository/DocumentOutline.tsx`, `frontend/components/repository/KeyValueList.tsx`, `frontend/hooks/useDocumentStructuredData.ts`, `frontend/lib/api/documents.ts`.
      Implementation Notes: Tab hidden when response omits `structured_data` (server returns it only when Docling produced output). For documents with > 20 tables, lazy-load via `GET /documents/{id}/structured-data` paginated endpoint; otherwise read from inline detail payload. Each table supports CSV copy/export client-side. Translated captions/headers honour `?lang=` and show the same "translated" badge pattern as T0.2; cell values are never translated (verbatim). Tables must be horizontally scrollable on small screens with sticky headers. Click on a section row scrolls the PDF preview pane to the matching page anchor.
      Acceptance Criteria: Tab appears only when structured data exists; tables render with correct row/column counts against MSW fixtures; CSV export downloads a valid file; section click scrolls preview; in `fr` locale, captions/headers show "translated" badge while cell values remain in source language; axe scan clean.

- [ ] **T5.4 — Structured-data fixtures in MSW**
      Description: Extend MSW document fixtures to include a `structured_data` payload with at least one document carrying tables + sections + key/values, and one document without (to exercise the "no structured data" empty state).
      Files: `frontend/mocks/data/documentsFixtures.ts`, `frontend/mocks/handlers/documents.ts`.
      Acceptance Criteria: With `NEXT_PUBLIC_DEMO_MODE=true`, `/repository/[id]` for the seeded document shows the new tab populated; the empty-state document hides it.

---

### Module 6 — Q&A (Phase-2 enhancements)

- [ ] **T6.1 — AI answer suggestions for moderators/experts**
      Description: On `/questions/[id]`, A/M see a "AI suggestions" panel calling `GET /ai/suggestions/{question_id}` (top ranked source passages, no LLM answer).
      Files: `frontend/components/questions/AiSuggestionsPanel.tsx`, `frontend/hooks/useAiSuggestions.ts`.
      Implementation Notes: Member role does not see the panel. Each passage links to source doc/Q&A. Mark passages as "used" when expert pastes them into the answer composer.
      Acceptance Criteria: Suggestions render with disclaimer; member-role view hides panel.

- [ ] **T6.2 — Q&A thread summary action**
      Description: "Summarise thread" CTA on questions with ≥ 3 answers; calls `POST /ai/summarize/question/{question_id}`.
      Files: `frontend/components/questions/ThreadSummaryDialog.tsx`.
      Acceptance Criteria: Returned summary rendered with disclaimer; cached per question per session.

- [ ] **T6.3 — Promote Q&A to Knowledge Article (A/M)**
      Description: Action button on approved + verified Q&A; calls `POST /questions/{id}/promote`. Show resulting knowledge-article link in toast deep-linking to **`/knowledge/[id]`** (per T18.1).
      Files: `frontend/components/questions/PromoteToKnowledgeButton.tsx`, `frontend/hooks/usePromoteQuestion.ts`.
      Implementation Notes: Button visible only when `is_accepted` + `is_verified` and user role ∈ {A, M}. Idempotent: repeat returns existing article id. If `/knowledge/[id]` route not yet shipped, fall back to source Q&A link with an info banner.
      Acceptance Criteria: Promotion succeeds; toast links to `/knowledge/[id]`; button disables once promoted.

- [ ] **T6.4 — Q&A discussion comments thread**
      Description: Inline thread under question detail; supports list (`GET /questions/{id}/comments`), post (`POST`), delete (`DELETE /questions/{id}/comments/{cid}`).
      Files: `frontend/components/questions/QuestionCommentsThread.tsx`, `frontend/components/questions/QuestionCommentComposer.tsx`, `frontend/hooks/useQuestionComments.ts`.
      Implementation Notes: No moderation; delete restricted to comment author or Admin. Cursor format = **opaque base64 of `{created_at, id}`** (matches API T-A2.4). Optimistic post: prepend new comment with temp id, reconcile via `setQueryData` on success, rollback + toast on failure. Polled/new comments merged by id (no duplicates).
      Acceptance Criteria: New comment appears instantly; question author receives in-app notification (verified via bell); pagination stable under concurrent inserts.

- [ ] **T6.5 — Related questions panel**
      Description: Sidebar on `/questions/[id]` calling `GET /questions/{id}/related`.
      Files: `frontend/components/questions/RelatedQuestionsPanel.tsx`.
      Acceptance Criteria: Cards link to related Q&A; empty state handled.

- [ ] **T6.6 — Non-English question submission notice**
      Description: When user composes question in a non-EN locale, show inline notice: "Stored in your language; translated to English for search indexing."
      Files: `frontend/components/questions/AskQuestionForm.tsx`.
      Acceptance Criteria: Notice appears only when `preferred_lang ≠ 'en'`.

---

### Module 7 — News (Phase-2 enhancements)

- [ ] **T7.1 — Feature / pin news article (Admin)**
      Description: Admin-only toggle on `/news/[id]` calling `PATCH /news/{id}/feature` with `{ is_featured, featured_order }`. Reorder uses a batch endpoint `PATCH /news/feature/reorder` with `{ items: [{id, featured_order}, …] }` — one request after drag-end.
      Files: `frontend/components/news/FeatureToggleDialog.tsx`, `frontend/app/(app)/news/[id]/page.tsx`, `frontend/hooks/useFeatureNews.ts`, `frontend/hooks/useReorderFeaturedNews.ts`.
      Implementation Notes: Reordering UI uses a drag handle on `/news?featured=true` admin view. `featured_order` lower = higher position. On 409 (concurrent reorder), refetch and retry once.
      Acceptance Criteria: Featured items appear pinned at the top of `/news`; reorder persists via the batch endpoint; 409 surfaced as a retry toast.

- [ ] **T7.2 — News list — featured section + filter**
      Description: Top "Featured" carousel on `/news`; toggle to filter `?featured=true`.
      Files: `frontend/app/(app)/news/page.tsx`, `frontend/components/news/FeaturedNewsCarousel.tsx`.
      Acceptance Criteria: Carousel ordered by `featured_order` ascending.

- [ ] **T7.3 — Related news panel**
      Description: `/news/[id]` related-articles sidebar calling `GET /news/{id}/related`.
      Files: `frontend/components/news/RelatedNewsPanel.tsx`.
      Acceptance Criteria: ≤ 10 cards rendered; clicking navigates.

---

### Module 8 — Social Feed (Phase-2 enhancements)

- [ ] **T8.1 — Related posts panel on post detail**
      Description: Calls `GET /posts/{id}/related`.
      Files: `frontend/components/feed/RelatedPostsPanel.tsx`.
      Acceptance Criteria: Renders with empty-state fallback.

---

### Module 9 — Moderation (Phase-2 enhancements)

- [ ] **T9.1 — AI pre-screen flag on queue rows**
      Description: Show AI pre-screen result chip ("clean", "suspect: profanity", "suspect: off-topic") per row, sourced from submission record.
      Files: `frontend/components/moderation/QueueTable.tsx`, `frontend/components/moderation/AiFlagChip.tsx`.
      Implementation Notes: Chip colour-coded; click reveals reason text. Disclaimer applies — never the only basis for action.
      Acceptance Criteria: Pending items rendered with the chip; clean items show neutral state.

- [ ] **T9.2 — Moderator AI answer-suggestion link from queue**
      Description: For Q&A queue items, link "View AI suggestions" jumps to the AI Suggestions panel (T6.1).
      Files: `frontend/components/moderation/QueueDetailPanel.tsx`.
      Acceptance Criteria: Link visible only on `type=question` items.

---

### Module 10 — Notifications (Phase-2 enhancements)

- [ ] **T10.1 — `question_commented` notification type**
      Description: Render notifications of type `question_commented` with the commenter, question title, and deep link.
      Files: `frontend/components/notifications/NotificationsList.tsx`, `frontend/lib/notifications/types.ts`.
      Acceptance Criteria: Clicking the notification routes to the question detail and scrolls to the comment thread.

- [ ] **T10.2 — `gdpr_export.requested` / `gdpr_export.completed` notifications**
      Description: Render GDPR export lifecycle events; "completed" entry exposes the pre-signed download link with TTL hint.
      Files: `frontend/components/notifications/NotificationsList.tsx`, `frontend/components/notifications/GdprExportNotification.tsx`, `frontend/lib/notifications/types.ts`.
      Acceptance Criteria: Both event types render with the correct icon/copy; "completed" includes a working download button.

---

### Module 11 — Search & AI (Phase-2 — `/ai/ask` becomes available)

- [ ] **T11.1 — `/search` AI Ask tab**
      Description: Add tab to `/search` page that calls `POST /ai/ask` and renders an answer with inline citations, confidence indicator, and disclaimer.
      Files: `frontend/app/(app)/search/page.tsx`, `frontend/components/search/AiAskPanel.tsx`, `frontend/components/search/AiAnswer.tsx`, `frontend/components/search/CitationCard.tsx`, `frontend/hooks/useAiAsk.ts`.
      Implementation Notes: Rate-limited 20/min — surface 429 toast. Mid-band confidence (0.50–0.75) is handled server-side (single retry inside LangGraph) and is invisible to the client — a regular loading spinner covers the wait (budget ≤ 2 500 ms). Show "pending expert review" UI only when the final response is the low-confidence envelope. Each citation links to its source (doc chunk, Q&A, news).
      Acceptance Criteria: High-confidence path renders answer + ≥ 1 citation; low-confidence renders expert-review notice; disclaimer always present.

- [ ] **T11.4 — Back-translation / source-language badge on AI Ask & search snippets**
      Description: When the server returns back-translated answer or snippets (`translated_from` / `original_language` flags from API T-B11.1/T-B11.4 + BACKTRANS), render a "Translated from XX" badge with a "Show original" toggle.
      Files: `frontend/components/search/AiAnswer.tsx`, `frontend/components/search/CitationCard.tsx`, `frontend/components/search/SnippetView.tsx`.
      Acceptance Criteria: Toggle swaps between translated and original copy; badge hidden when source language equals requested locale.

- [ ] **T11.5 — Translation fallback / circuit-open UX**
      Description: When the translation circuit is open (server signals fallback to original language), list/detail and search responses render an inline notice ("Showing original language — translation temporarily unavailable").
      Files: `frontend/components/shared/TranslationFallbackNotice.tsx`, integrate in `RepositoryList`, `QuestionsList`, `NewsList`, `AiAnswer`.
      Acceptance Criteria: Notice appears only when server flag `translation_unavailable=true`; original copy remains readable.

- [ ] **T11.2 — Translation language picker for search query**
      Description: Allow user to set `lang=` on the search request (defaults to user's preferred_lang).
      Files: `frontend/components/search/SearchBar.tsx`.
      Acceptance Criteria: Response includes `query_lang` reflecting the chosen value.

- [ ] **T11.3 — Standalone translation utility**
      Description: Admin/Moderator utility page invoking `POST /ai/translate` for arbitrary text + `GET /ai/translate/languages`. Translations are always written to the translation cache server-side; show a small "cached" badge when the response carries `cached=true`.
      Files: `frontend/app/(app)/admin/translate/page.tsx`, `frontend/components/admin/TranslateTool.tsx`.
      Acceptance Criteria: Picks dest language from server list; result rendered with detected source language; "cached" badge appears on cache hits.

---

### Module 14 — Admin (Phase-2 enhancements)

- [ ] **T14.1 — `/admin/analytics` AI usage section**
      Description: Render AI cost & token usage from `GET /admin/ai-usage` with date-range filter, granularity selector, and top-users table.
      Files: `frontend/app/(app)/admin/analytics/page.tsx`, `frontend/components/admin/AiUsageCharts.tsx`, `frontend/components/admin/AiUsageTopUsersTable.tsx`, `frontend/hooks/useAiUsage.ts`.
      Implementation Notes: Three visualisations driven by a single `GET /admin/ai-usage` call (response shape per API T-B14.1):
      - **Line chart** — token volume over time from `rows[]`, two series (`input_tokens`, `output_tokens`) bucketed by the active `granularity`.
      - **Stacked bar** — cost by `event_type` from `rows[]`, stacked across the active period.
      - **Top-users table** — top 10 users by total tokens / cost from the response's `top_users[]` array (server-side ranked; the page never asks for raw per-user rows).
      Controls: date-range picker (default last 30 days), `granularity` toggle (`day | week | month`, default `day`), `event_type` multi-select filter. All controls reflected in the URL for deep-linking. Single **CSV export** button calls `GET /admin/ai-usage?export=csv` with the active filters — no client-side CSV generation. Totals panel uses the response's `totals` block (input/output tokens, call counts, estimated cost).
      Acceptance Criteria: Switching ranges or granularity refetches with new params; line chart re-buckets correctly between day/week/month; stacked bar shows one stack per `event_type`; top-users table renders ≤ 10 rows ranked by cost descending; CSV export downloads a file matching the active filter window; totals panel matches `response.totals` exactly.

- [ ] **T14.2 — `/admin/config` — manage supported languages**
      Description: Editor for `supported_languages` JSON array; affects locale switcher and `/ai/translate/languages`.
      Files: `frontend/components/admin/ConfigForm.tsx`.
      Acceptance Criteria: Adding `ar` makes it selectable in locale switcher after a hard reload.

- [ ] **T14.3 — `/admin/config` — AI confidence thresholds**
      Description: Editors for `ai_confidence_high` and `ai_confidence_low` (validated 0.0–1.0; high > low).
      Files: `frontend/components/admin/ConfigForm.tsx`, `frontend/lib/api/adminConfig.ts`.
      Implementation Notes: Save through the existing `PUT /admin/config` endpoint; surface server-side 422 validation inline.
      Acceptance Criteria: Saved values reflected in `GET /admin/config`; invalid range blocks submit.

- [ ] **T14.4 — `/admin/ai-audit` — AI query audit log page**
      Description: Admin-only page at `/admin/ai-audit` providing a browsable, filterable audit trail of all AI query invocations for governance and compliance monitoring. Reads from `GET /admin/ai-audit` (API T-B14.3). Displays a cursor-paginated table with columns: timestamp, user, event type (completed / flagged / insufficient), confidence score (colour-banded: green ≥ 0.75, amber 0.50–0.75, red < 0.50), model, and query hash. Row expansion reveals source ids (doc_id / chunk_id / Q&A id / news_id) and reasoning path (LangGraph nodes traversed). Includes a prominent retention notice: *"Records retained for {ai_audit_retention_days} days per platform configuration."*
      Files: `frontend/app/(app)/admin/ai-audit/page.tsx`, `frontend/components/admin/AiAuditTable.tsx`, `frontend/components/admin/AiAuditFilters.tsx`, `frontend/components/admin/AiAuditRowDetail.tsx`, `frontend/hooks/useAiAudit.ts`, `frontend/lib/api/admin.ts`.
      Implementation Notes: Filter controls: date-range picker (default last 7 days), `event_type` multi-select, `confidence_band` chip group (high/mid/low), user search (calls `GET /users` debounced). URL encodes all active filters so the page is deep-linkable. **CSV export** button passes current filters to `GET /admin/ai-audit?export=csv` and triggers a browser download — no client-side CSV generation. Cursor pagination (not offset) — "Load more" pattern consistent with moderation queue. Add MSW stub to `T0.4` handler file (`frontend/mocks/handlers/ai.ts`) with at least 3 fixture rows covering all three confidence bands. Sidebar nav entry under Admin section (visible to Admin role only).
      Acceptance Criteria: Table renders with correct colour bands per confidence score; row expansion shows source ids and reasoning path; date-range filter refetches; CSV download initiates for the active filter window; non-Admin role returns 403 and is redirected; retention notice reflects `platform_config.ai_audit_retention_days`; axe scan clean.

- [ ] **T14.5 — `/admin/config` — AI audit retention editor**
      Description: Add `ai_audit_retention_days` (integer, 7–365) to the existing `/admin/config` form (T14.2/T14.3 pattern). Input is a number field with min/max enforced client-side; server-side 422 surfaced inline. Help text: *"How long AI query audit records are retained. Minimum 7 days, maximum 365 days."*
      Files: `frontend/components/admin/ConfigForm.tsx`, `frontend/lib/api/adminConfig.ts`.
      Implementation Notes: Sourced from the same `GET/PUT /admin/config` endpoints. Value also displayed in the retention notice on the audit log page (T14.4) — update the cached config query key after a successful save so the notice reflects immediately without a reload.
      Acceptance Criteria: Saving 60 persists; saving 5 is blocked client-side; saving 400 returns 422 inline; audit log page retention notice updates within 1 request cycle after save.

---

### Module 16 — Profile (Phase-2 enhancements)

- [ ] **T16.1 — `/profile/export` GDPR export page**
      Description: Page with "Request export" button calling `GET /users/me/export`; renders pre-signed URL when job completes.
      Files: `frontend/app/(app)/profile/export/page.tsx`, `frontend/components/profile/GdprExportPanel.tsx`, `frontend/hooks/useGdprExport.ts`.
      Implementation Notes: Submit → `GET /users/me/export` returns `{ job_id }`. Poll via React Query against `GET /users/me/export/{job_id}` with `refetchInterval: 5s`; stop polling on terminal state (`completed | failed`). Do not rely on focus events. Provide download link with TTL hint (24 h).
      Acceptance Criteria: Submitting returns a pending state; polling resolves; once URL is present, "Download archive" button appears.

- [ ] **T16.2 — Profile/Settings preferred-language editor**
      Description: Dedicated control on `/profile/edit` (and signup wizard) issuing `PATCH /auth/me { preferred_lang }`.
      Files: `frontend/app/(app)/profile/edit/page.tsx`, `frontend/components/profile/LanguagePreferenceField.tsx`, `frontend/hooks/useUpdateProfile.ts`.
      Implementation Notes: Options sourced from `GET /ai/translate/languages`. Persists to Zustand auth store and refreshes JWT.
      Acceptance Criteria: Saving updates the JWT claim; locale switcher reflects new value without manual override.

---

### Module 18 — Knowledge Articles (Phase-2, new)

- [ ] **T18.1 — Knowledge Article detail route**
      Description: `/knowledge/[id]` page rendering a promoted Q&A pair with original-question link, accepted/verified answer, citations, and AI disclaimer.
      Files: `frontend/app/(app)/knowledge/[id]/page.tsx`, `frontend/components/knowledge/KnowledgeArticleView.tsx`, `frontend/hooks/useKnowledgeArticle.ts`, `frontend/lib/api/knowledgeArticles.ts`.
      Implementation Notes: Calls `GET /knowledge-articles/{id}` (API TM-API-1). Supports `?lang=` translation.
      Acceptance Criteria: Renders article body, back-link to source Q&A, and "Knowledge Article" badge.

- [ ] **T18.2 — Knowledge Article list + search-result variant**
      Description: `/knowledge` list page and a `KnowledgeArticleCard` variant for `/search` results to differentiate from regular Q&A (SAD §14.1).
      Files: `frontend/app/(app)/knowledge/page.tsx`, `frontend/components/knowledge/KnowledgeArticleCard.tsx`, `frontend/components/search/SearchResultsList.tsx`.
      Acceptance Criteria: Search results render a distinct chip for knowledge articles; list page paginates with React Query.

- [ ] **T18.3 — Promote toast deep-link target**
      Description: Update T6.3 toast to deep-link into `/knowledge/[id]` once the article exists.
      Files: `frontend/components/questions/PromoteToKnowledgeButton.tsx`.
      Acceptance Criteria: Clicking the toast opens the new knowledge article page.

---

### Module 17 — Cross-cutting (Phase-2)

- [ ] **T17.1 — Update Playwright smoke tests**
      Description: Add flows: AI Ask happy path, Q&A discussion comment, news feature toggle, GDPR export request. Re-run Phase-1 specs that touch routing (auth flows, deep-links to question/document/news detail, moderation queue navigation, dashboard), the Header (now hosts locale switcher), the notifications bell, and search query encoding (locale param) to catch regressions from the locale-prefix middleware.
      Files: `frontend/e2e/*.spec.ts`.
      Acceptance Criteria: All new flows green against MSW; Phase-1 regression specs remain green.

- [ ] **T17.2 — Accessibility re-audit for AI panels & translation UI**
      Description: Verify announcements for async AI responses (live regions), keyboard nav, focus management on modal AI summaries.
      Files: AI components above.
      Acceptance Criteria: Zero critical axe violations on the AI Ask page, summary dialogs, and translate tool.

- [ ] **T17.3 — Update frontend README + onboarding docs**
      Description: Document Phase-2 features, new env vars, locale switcher behaviour.
      Files: `frontend/README.md`.
      Acceptance Criteria: A new dev can locate and run AI features in demo mode.
