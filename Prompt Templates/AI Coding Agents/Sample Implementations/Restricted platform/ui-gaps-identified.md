# ICA Platform — UI Gaps Identified

> Identified via Playwright end-to-end use case coverage audit on 2026-04-17.
> Status: `[ ]` = Not started, `[~]` = In progress, `[x]` = Done
> Reference: `ui-tasks.md` for existing task numbering, `ui-implementation-plan.md` for API contracts.

---

## Summary of Confirmed Gaps

Four use cases from the product spec have **no frontend implementation** and require new work:

| Gap ID | Use Case Area | Missing Feature | Priority |
|--------|--------------|-----------------|----------|
| GAP-01 | Q&A Module (UC3) | Approved Q&A → Knowledge Base promotion workflow | High |
| GAP-02 | Knowledge Repository (UC2 / UC10) | Document ingestion pipeline status indicator (OCR → indexing) | Medium |
| GAP-03 | Multi-Language Module (UC7) | AI-powered content translation (question/answer/news body text) | Medium |
| GAP-04 | Moderation Module (UC8) | Route pending question to named legal expert from review panel | High |

---

## GAP-01 — Q&A Knowledge Base Promotion Workflow

### Background
The product spec states:
- *"Approved Q&A becomes part of the knowledge base (self-learning system)"*
- *"ICA Legal Experts: Convert answers into reusable knowledge"*

Currently, when a question is approved and an answer is accepted, there is no UI action to explicitly promote that Q&A pair into the knowledge base. The pipeline exists implicitly in mock data (approved Q&As appear in RAG search results) but there is no moderator/expert-facing trigger.

### Tasks

#### GAP-01.1 — "Add to Knowledge Base" Action on Accepted Answers

- [x] Add an **"Add to Knowledge Base"** icon button to `components/questions/AnswerCard.tsx`
  - Visible only when: answer is accepted (`is_accepted: true`) AND current role is `Admin` or `Moderator`
  - Button state: default (add), loading (spinner), done (green checkmark with "In Knowledge Base" label)
  - Tooltip: "Promote this Q&A pair to the reusable knowledge base"
- [x] Add mock API handler `POST /questions/{id}/promote` in `mocks/handlers/questions.ts`
  - Returns `{ promoted: true, knowledge_base_id: "kb-{id}" }`
  - Simulates 300ms latency
- [x] Add React Query mutation `usePromoteToKnowledgeBase(questionId)` in `hooks/useQuestions.ts`
  - On success: show toast "Q&A added to knowledge base", update answer card to show "In Knowledge Base" badge
  - On error: show error toast
- [x] Add `is_in_knowledge_base: boolean` field to `Answer` type in `types/index.ts`
- [x] Update mock answer fixtures in `mocks/data/answers.ts` — mark 2–3 accepted answers as `is_in_knowledge_base: true` to demonstrate the done state

#### GAP-01.2 — Knowledge Base Badge on Question Cards

- [x] Add a **"Knowledge Base"** chip to `components/questions/QuestionCard.tsx` and `QuestionDetailPage.tsx`
  - Shown when question has at least one answer with `is_in_knowledge_base: true`
  - Use a distinct icon (e.g. book/library icon) and teal colour to differentiate from status badges
- [x] Add `has_knowledge_base_entry: boolean` field to `Question` type in `types/index.ts`
- [x] Update mock questions in `mocks/data/questions.ts` — mark 2 approved questions as `has_knowledge_base_entry: true`

#### GAP-01.3 — Knowledge Base Filter in Repository Search (Optional)

- [x] Add a **"Knowledge Base Entries"** toggle chip to the FilterBar on `/questions`
  - When active, filters to only show questions with `has_knowledge_base_entry: true`
- [x] Update `mocks/handlers/questions.ts` to support `?knowledge_base=true` query param filter

---

## GAP-02 — Document Ingestion Pipeline Status Indicator

### Background
The product spec states:
- *"AI: OCR processing for scanned PDFs → extract structured content → index into vector DB"*
- *"Document ingestion pipeline: OCR → chunking → embedding"*

Currently, after a user uploads a document, they are redirected to `/repository/my` showing a `Pending` status badge. There is no indication of whether the backend has:
- Successfully extracted text via OCR
- Chunked and embedded the document for semantic search
- Failed at any pipeline stage

This is a real usability gap: a user cannot tell if their document is searchable or if processing failed.

### Tasks

#### GAP-02.1 — Processing Status Field & Types

- [ ] Add `processing_status` field to `Document` type in `types/index.ts`:
  ```ts
  processing_status?: 'queued' | 'ocr_processing' | 'indexing' | 'ready' | 'failed'
  processing_error?: string
  ```
- [ ] Update mock documents in `mocks/data/documents.ts`:
  - 1 document with `processing_status: 'ocr_processing'`
  - 1 document with `processing_status: 'indexing'`
  - 1 document with `processing_status: 'failed'`, `processing_error: 'OCR extraction failed: scanned image quality too low'`
  - Approved documents: `processing_status: 'ready'`
  - Pending documents: `processing_status: 'queued'`

#### GAP-02.2 — Processing Status Badge in My Documents

- [ ] Add a **pipeline status stepper** or **status chip** to `components/repository/MyDocumentsPage.tsx`
  - Show below the existing `StatusBadge` when `processing_status` is not `ready`
  - States and colours:
    - `queued` — grey chip: "Queued for processing"
    - `ocr_processing` — blue chip with spinner: "OCR in progress…"
    - `indexing` — blue chip with spinner: "Indexing for search…"
    - `ready` — no chip shown (processing complete)
    - `failed` — red chip: "Processing failed" with an info icon; clicking opens a tooltip/popover showing `processing_error`
- [ ] Update React Query hook `useMyDocuments()` to include `processing_status` in response shape

#### GAP-02.3 — Processing Status in Document Detail

- [ ] Show a dismissible **info banner** in `components/repository/DocumentDetailPage.tsx` when `processing_status !== 'ready'`:
  - `ocr_processing` / `indexing`: amber info banner — "This document is being processed for semantic search. It will be fully searchable once indexing is complete."
  - `failed`: red error banner — "Document processing encountered an error. Contact an administrator if the problem persists." with the `processing_error` text shown in a collapsed `<details>` block

#### GAP-02.4 — Moderator View: Processing Status in Review Panel

- [ ] Show the `processing_status` chip in `components/moderation/ReviewPanel.tsx` for document-type items
  - Displayed in the Document Info section alongside category/type metadata
  - Moderators should know if OCR failed before approving a document that may not be searchable

#### GAP-02.5 — Mock Handler Update

- [ ] Update `mocks/handlers/documents.ts`:
  - `GET /documents/my` — include `processing_status` in each document response
  - `GET /documents/{id}` — include `processing_status`
  - `POST /documents` — simulate initial state `queued`, then mock a status progression on polling (optional)

---

## GAP-03 — AI-Powered Content Translation

### Background
The product spec states:
- *"Member: View content in preferred language / Ask questions in native language"*
- *"AI: Translate input → English (processing) → output → user language"*
- *"Maintain multilingual knowledge access"*

Current state: switching language to Français/Español correctly translates **all UI labels** (nav, buttons, headings, form hints) but the **actual content** — question titles, question bodies, answer text, news headlines, news body text, document descriptions — remains in its original English.

This is a significant gap for the core ICA use case of enabling non-English speaking cooperative law practitioners to access the platform.

### Tasks

#### GAP-03.1 — Translated Content Fields in Types

- [ ] Add optional translated content fields to core types in `types/index.ts`:
  ```ts
  // Question
  title_translated?: string
  body_translated?: string

  // Answer
  body_translated?: string

  // NewsArticle
  title_translated?: string
  summary_translated?: string
  body_translated?: string

  // Document
  description_translated?: string
  ```
- [ ] Add `translation_locale?: string` to indicate which locale the translated fields are for

#### GAP-03.2 — Mock Translated Fixtures

- [ ] Add French translations to 3 questions in `mocks/data/questions.ts`:
  - `title_translated`, `body_translated` for `locale: 'fr'`
- [ ] Add French translations to 2 news articles in `mocks/data/news.ts`
- [ ] Add Spanish translations to 2 questions for `locale: 'es'`

#### GAP-03.3 — Translation-Aware Display Hooks

- [ ] Create `hooks/useTranslatedContent.ts` — utility hook:
  ```ts
  function useTranslatedContent<T extends { title?: string; title_translated?: string }>(
    item: T
  ): T
  ```
  - Reads current locale from Zustand auth store
  - If `locale !== 'en'` and `item.title_translated` exists, returns object with translated fields swapped in
  - Falls back to original fields if no translation available

#### GAP-03.4 — Apply Translation in Content Components

- [ ] Update `components/questions/QuestionDetailPage.tsx` — use `useTranslatedContent()` for question title and body
- [ ] Update `components/questions/QuestionCard.tsx` — translated title in list view
- [ ] Update `components/questions/AnswerCard.tsx` — translated answer body
- [ ] Update `components/news/NewsDetailPage.tsx` — translated headline and body
- [ ] Update `components/news/NewsCard.tsx` — translated headline in list view
- [ ] Update `components/repository/DocumentDetailPage.tsx` — translated description

#### GAP-03.5 — "Machine Translated" Disclaimer

- [ ] Add a small **"Machine translated" chip** (grey, with a globe icon) next to translated content in detail views
  - Shown only when translated content is being displayed (locale ≠ 'en' and translation exists)
  - Tooltip: "This content was automatically translated. The original language version is authoritative."
- [ ] Add a **"View original"** toggle link next to the chip to switch back to original language for that item without changing the global locale preference

#### GAP-03.6 — "Ask in your language" Affordance on Q&A

- [ ] Add a locale hint below the Question Title input in `components/questions/AskQuestionPage.tsx`:
  - When locale ≠ 'en': show info text — "You can write in [language]. Your question will be processed in English for search indexing."
- [ ] Update `mocks/handlers/questions.ts` — accept `locale` field in `POST /questions` payload (no-op in mock, just pass through)

---

## GAP-04 — Route Question to Legal Expert from Moderation Panel

### Background
The product spec states:
- *"Moderator: Route to legal experts if needed"*
- *"ICA Legal Experts: Answer questions / Provide authoritative interpretations"*

Currently the moderation review panel only has **Approve**, **Request Changes**, and **Reject** buttons. There is no "Route to Expert" or "Assign to Expert" action. This means moderators have no structured way to flag a question for a specific legal expert — they can only approve it (making it public for anyone to answer) or reject it.

### Tasks

#### GAP-04.1 — "Route to Expert" Button in Review Panel

- [ ] Add a **"Route to Expert"** button to `components/moderation/ReviewPanel.tsx`
  - Positioned between "Request Changes" and "Reject" — or as a secondary action below the 3 primary buttons
  - Style: outlined teal/blue button with a "person with arrow" icon
  - Visible only for `Question`-type moderation items (not documents, news, or posts)
  - On click: opens an inline expert assignment UI (see GAP-04.2)

#### GAP-04.2 — Expert Assignment Dropdown in Review Panel

- [ ] Add an **expert selector** that appears when "Route to Expert" is clicked:
  - MUI `Autocomplete` dropdown listing users with role `Admin` (ICA Legal Office / Experts)
  - Populated from mock users filtered by role
  - Optional note textarea: "Add a routing note for the expert (e.g. jurisdiction-specific context)"
  - Confirm button: **"Send to Expert"** — triggers mock API call
  - Cancel button: dismisses the selector back to the 3-button state
- [ ] Add mock API handler `POST /questions/{id}/route` in `mocks/handlers/questions.ts`:
  - Payload: `{ expert_id: string, note?: string }`
  - Returns `{ routed: true, routed_to: { id, name, email }, note }`
  - Simulates 300ms latency
- [ ] Add React Query mutation `useRouteToExpert(questionId)` in `hooks/useQuestions.ts`
  - On success: remove item from queue (optimistic update), show toast "Question routed to [Expert Name]", close panel
  - On error: show error toast, keep panel open

#### GAP-04.3 — "Routed" Status Badge

- [ ] Add `routed` as a valid moderation status in `StatusBadge` component (`components/shared/StatusBadge.tsx`)
  - Colour: indigo/purple chip
  - Label: "Routed to Expert"
- [ ] Update `Question` type in `types/index.ts`:
  ```ts
  moderation_status?: 'pending' | 'approved' | 'rejected' | 'revision_requested' | 'routed'
  routed_to?: { id: string; name: string }
  routing_note?: string
  ```

#### GAP-04.4 — Routed Questions View for Experts (Admin Role)

- [ ] Add a **"Routed to Me"** tab or filter to `components/questions/QuestionListPage.tsx`
  - Visible only when role is `Admin`
  - Shows questions with `moderation_status: 'routed'` where `routed_to.id === currentUser.id`
  - Each card shows a routing note if present
- [ ] Update `mocks/handlers/questions.ts` — support `?routed_to_me=true` query param
- [ ] Update mock questions in `mocks/data/questions.ts` — add 1 question with `moderation_status: 'routed'` routed to the admin user

#### GAP-04.5 — Notification on Expert Assignment

- [ ] Update `mocks/data/notifications.ts` — add 1 notification of type `routing`:
  - Message: `'A question has been routed to you for expert review: "Are non-member investor shares permissible..."'`
  - `read: false`
- [ ] Update `mocks/handlers/notifications.ts` to include this in the notifications list
- [ ] Ensure the notification links to the question detail page

---

## Implementation Priority & Suggested Order

| Order | Gap | Effort | Rationale |
|-------|-----|--------|-----------|
| 1 | GAP-04 Route to Expert | Medium (1–2 days) | Core moderation workflow; blocks legal expert Q&A flow |
| 2 | GAP-01 Q&A Knowledge Base | Medium (1–2 days) | Core differentiator per spec — "self-learning system" |
| 3 | GAP-02 OCR Pipeline Status | Small (0.5–1 day) | Usability fix; prevents user confusion after upload |
| 4 | GAP-03 Content Translation | Large (3–5 days) | Most complex; requires type changes + multi-component edits + mock data in 2 languages |

---

## Files Affected Summary

| File | Gaps |
|------|------|
| `types/index.ts` | GAP-01, GAP-02, GAP-03, GAP-04 |
| `mocks/data/questions.ts` | GAP-01, GAP-03, GAP-04 |
| `mocks/data/answers.ts` | GAP-01, GAP-03 |
| `mocks/data/documents.ts` | GAP-02 |
| `mocks/data/news.ts` | GAP-03 |
| `mocks/data/notifications.ts` | GAP-04 |
| `mocks/handlers/questions.ts` | GAP-01, GAP-03, GAP-04 |
| `mocks/handlers/documents.ts` | GAP-02 |
| `mocks/handlers/notifications.ts` | GAP-04 |
| `components/questions/AnswerCard.tsx` | GAP-01, GAP-03 |
| `components/questions/QuestionCard.tsx` | GAP-01, GAP-03 |
| `components/questions/QuestionDetailPage.tsx` | GAP-01, GAP-03 |
| `components/questions/QuestionListPage.tsx` | GAP-04 |
| `components/questions/AskQuestionPage.tsx` | GAP-03 |
| `components/moderation/ReviewPanel.tsx` | GAP-02, GAP-04 |
| `components/repository/MyDocumentsPage.tsx` | GAP-02 |
| `components/repository/DocumentDetailPage.tsx` | GAP-02, GAP-03 |
| `components/news/NewsCard.tsx` | GAP-03 |
| `components/news/NewsDetailPage.tsx` | GAP-03 |
| `components/shared/StatusBadge.tsx` | GAP-04 |
| `hooks/useQuestions.ts` | GAP-01, GAP-04 |
| `hooks/useTranslatedContent.ts` (new) | GAP-03 |
