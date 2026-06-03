# Implementation Task Checklist (UI Task list) — Phase 3

> Scope: Phase-3 enhancements per SAD §14.2 — LiveKit live expert sessions, knowledge graph explorer, native mobile (iOS/Android), expanded language support (Arabic, Portuguese, etc.), organisation-level content siloing, private messaging, advanced analytics & personalised recommendations, SSE notifications stream, and external legal API integration surfacing.
> All Phase-1 and Phase-2 foundations assumed in place.
> Microservices extraction (Search/AI as independent FastAPI services behind Kong) is a backend-only concern with no UI impact and is **excluded** from this checklist.

---

## 1. Frontend Tasks

### Module 0 — Phase-3 Foundation & Cross-cutting

- [ ] **T0.1 — Add Arabic, Portuguese & extended locale catalogues + RTL support**
      Description: Extend `next-intl` to support `ar`, `pt`, and any additional Phase-3 languages; add RTL theme overrides for Arabic.
      Files / Components to be changed: `frontend/i18n.ts`, `frontend/messages/{ar,pt,...}.json`, `frontend/middleware.ts`, `frontend/lib/theme.ts`, `frontend/app/layout.tsx`, `frontend/components/layout/LocaleSwitcher.tsx`.
      Implementation Notes: Set `<html dir="rtl">` when locale ∈ `{ar, he, ...}`. MUI v6 `direction='rtl'` cache; Tailwind `dir-aware` classes via `rtl:` variant. Pull active languages dynamically from `/ai/translate/languages` rather than hard-coding.
      Acceptance Criteria: Switching to `ar` flips layout to RTL; Latin-locale pages remain LTR; all interactive elements remain keyboard-navigable.

- [ ] **T0.2 — SSE client for `/notifications/stream`**
      Description: Replace Phase-1 piggyback-header badge with an `EventSource` connection that pushes notification events and badge counts in real time. Graceful degradation to the header path when SSE unavailable.
      Files: `frontend/lib/sse/notificationsStream.ts`, `frontend/components/layout/NotificationBell.tsx`, `frontend/hooks/useUnreadCount.ts`, `frontend/store/notifications.ts`.
      Implementation Notes: Auto-reconnect with exponential backoff. ALB idle timeout 300 s — server pings every 25 s. Close stream on logout.
      Acceptance Criteria: New notifications appear within 1 s without page refresh; falling back works when stream blocked.

- [ ] **T0.3 — Org-visibility awareness across content lists**
      Description: All content list/detail components handle `org_visibility ∈ {public, org_only}` from server responses — render an org-only chip and filter the user's view accordingly.
      Files: `frontend/components/shared/OrgVisibilityChip.tsx`, all list views (`/repository`, `/questions`, `/news`, `/feed`, `/search`), `frontend/lib/api/*.ts`.
      Acceptance Criteria: Member of org A does not see org-only items belonging to org B; chip rendered on own-org private items.

- [ ] **T0.4 — Push notification permission UX (PWA install + service worker)**
      Description: Add Web Push (FCM/APNS via service worker) opt-in modal; manage subscription tokens via `POST /users/me/push-subscriptions`.
      Files: `frontend/public/sw.js`, `frontend/lib/push/{subscribe,unsubscribe}.ts`, `frontend/components/profile/PushNotificationToggle.tsx`.
      Implementation Notes: Only ask permission post a meaningful user action (not on first load). Token rotation handled on revisit.
      Acceptance Criteria: Subscribed token round-trips to server; revoking permission unsubscribes server-side.

- [ ] **T0.5 — MSW handlers for Phase-3 endpoints**
      Description: Add mocks for sessions, knowledge graph, messaging, recommendations, push subscriptions, external import sources.
      Files: `frontend/mocks/handlers/{sessions,knowledgeGraph,messaging,recommendations,push,imports}.ts`, `frontend/mocks/data/*.ts`.
      Acceptance Criteria: All new Phase-3 features render in demo mode without a backend.

---

### Module 5 — Repository (Phase-3 enhancements)

- [ ] **T5.1 — External legal source attribution & filter**
      Description: Display `is_official=true` badge for documents ingested via `legal_import_job`; add "Official sources only" filter to `/repository`.
      Files: `frontend/components/repository/DocumentCard.tsx`, `frontend/components/repository/RepositoryFilters.tsx`.
      Acceptance Criteria: Toggle filters to official-only and back; badge renders with source label.

- [ ] **T5.2 — Knowledge Graph link on document detail**
      Description: "Explore in Knowledge Graph" CTA on `/repository/[id]` opens the graph explorer rooted at the document's law concepts.
      Files: `frontend/components/repository/KnowledgeGraphLink.tsx`, `frontend/app/(app)/repository/[id]/page.tsx`.
      Acceptance Criteria: Clicking navigates to `/knowledge-graph?root=<doc-id>`.

---

### Module 6 — Q&A (Phase-3 enhancements)

- [ ] **T6.1 — Live expert session CTA on questions**
      Description: For approved questions assigned to an expert, surface "Request live session" button; Admin/Moderator can create one.
      Files: `frontend/components/questions/RequestLiveSessionButton.tsx`, `frontend/components/sessions/CreateSessionDialog.tsx`.
      Acceptance Criteria: Creating a session navigates to the new session room.

---

### Module 8 — Social Feed (Phase-3 enhancements)

- [ ] **T8.1 — Personalised feed recommendations**
      Description: Add "Recommended for you" rail on `/feed` populated from `GET /recommendations/posts`.
      Files: `frontend/components/feed/RecommendedPostsRail.tsx`, `frontend/hooks/useRecommendations.ts`.
      Acceptance Criteria: Logged-in member with activity history sees personalised items; new accounts see fallback popular items.

---

### Module 10 — Notifications (Phase-3 enhancements)

- [ ] **T10.1 — Live SSE-driven notifications panel**
      Description: Convert `/notifications` to subscribe to the stream — new notifications animate in without manual refresh.
      Files: `frontend/app/(app)/notifications/page.tsx`, `frontend/components/notifications/NotificationsList.tsx`, `frontend/store/notifications.ts`.
      Acceptance Criteria: A new server-fired notification appears in <1 s without polling.

- [ ] **T10.2 — Push-notification preferences in `/profile/edit`**
      Description: Per-channel toggles: in-app, email, push. Calls `PUT /notifications/preferences` with extended schema.
      Files: `frontend/components/profile/NotificationPreferences.tsx`.
      Acceptance Criteria: Toggle persists; permission state synced with browser.

---

### Module 11 — Search & AI (Phase-3 enhancements)

- [ ] **T11.1 — Knowledge Graph results panel on `/search`**
      Description: Render related entities (laws, concepts, jurisdictions) as a side panel when the query matches graph entities; calls `GET /knowledge-graph/search`.
      Files: `frontend/components/search/KnowledgeGraphSidePanel.tsx`, `frontend/hooks/useKnowledgeGraphSearch.ts`.
      Acceptance Criteria: Entities cluster by type; clicking an entity opens `/knowledge-graph` rooted there.

- [ ] **T11.2 — Recommendations carousel on dashboard**
      Description: Personalised content rail (docs, questions, news) from `GET /recommendations`.
      Files: `frontend/components/dashboard/RecommendationsCarousel.tsx`.
      Acceptance Criteria: Cards link to each item; carousel hidden when service unavailable.

---

### Module 14 — Admin (Phase-3 enhancements)

- [ ] **T14.1 — `/admin/imports` — external legal source manager**
      Description: List, configure, run, and inspect `legal_import_job` source connectors (URL, jurisdiction, cadence, last-run, status).
      Files: `frontend/app/(app)/admin/imports/page.tsx`, `frontend/components/admin/ImportSourcesTable.tsx`, `frontend/components/admin/ImportSourceFormDialog.tsx`, `frontend/components/admin/ImportRunLog.tsx`.
      Acceptance Criteria: Admin can add a source, trigger a run, and view the resulting ingestion job log.

- [ ] **T14.2 — `/admin/sessions` — live session management**
      Description: List rooms, participants, recording status; revoke tokens; access recording URLs.
      Files: `frontend/app/(app)/admin/sessions/page.tsx`, `frontend/components/admin/SessionsTable.tsx`.
      Acceptance Criteria: Active rooms visible; revoke ends a participant's session.

- [ ] **T14.3 — `/admin/analytics` Phase-3 dashboards**
      Description: Add panels for: live-session minutes, knowledge-graph node/edge counts, push-notification opt-in rate, recommendation CTR.
      Files: `frontend/components/admin/Phase3AnalyticsPanels.tsx`.
      Acceptance Criteria: Panels source from `/admin/stats` extensions.

- [ ] **T14.4 — Org-visibility controls**
      Description: Admin per-org default `org_visibility` setting; content composers expose a per-item override.
      Files: `frontend/components/admin/OrgVisibilityDefaultDialog.tsx`, content composers (`UploadForm`, `AskQuestionForm`, `CreateNewsForm`, `CreatePostForm`).
      Acceptance Criteria: Per-org default applied on new content; per-item override respected.

---

### Module 18 — Live Expert Sessions (LiveKit)

- [ ] **T18.1 — `/sessions` list page**
      Description: Upcoming/active/past sessions filterable by jurisdiction, topic, and expert.
      Files: `frontend/app/(app)/sessions/page.tsx`, `frontend/components/sessions/SessionsList.tsx`, `frontend/components/sessions/SessionCard.tsx`.
      Acceptance Criteria: Pagination + filters working; status badges accurate.

- [ ] **T18.2 — `/sessions/[id]` LiveKit room page**
      Description: Audio/video room using `@livekit/components-react`; controls — mic, camera, screen share, end. Tokens minted via `POST /sessions/{id}/token`.
      Files: `frontend/app/(app)/sessions/[id]/page.tsx`, `frontend/components/sessions/LiveRoom.tsx`, `frontend/components/sessions/Controls.tsx`, `frontend/components/sessions/ParticipantsList.tsx`.
      Implementation Notes: Lazy-load LiveKit SDK to keep bundle small. Show recording indicator. Graceful disconnect handler.
      Acceptance Criteria: Two browsers join the same room and exchange audio/video; recording status reflected accurately.

- [ ] **T18.3 — `/sessions/create` (A/M)**
      Description: Form: title, jurisdiction, topic, scheduled time, participants (members + experts). Calls `POST /sessions`.
      Files: `frontend/app/(app)/sessions/create/page.tsx`, `frontend/components/sessions/CreateSessionForm.tsx`.
      Acceptance Criteria: Created session appears on listing and notifies invitees.

- [ ] **T18.4 — Session recording playback**
      Description: Past-session detail page with recording playback (pre-signed S3 URL) and auto-generated summary/news draft from `session_event_job`.
      Files: `frontend/components/sessions/SessionRecordingPlayer.tsx`, `frontend/components/sessions/AutoSummaryPanel.tsx`.
      Acceptance Criteria: Recording plays inline; draft news/summary visible and editable.

- [ ] **T18.5 — Pre-flight device check**
      Description: Mic/camera permission test before joining.
      Files: `frontend/components/sessions/DeviceCheckDialog.tsx`.
      Acceptance Criteria: Missing permissions block join with actionable error.

---

### Module 19 — Knowledge Graph

- [ ] **T19.1 — `/knowledge-graph` explorer page**
      Description: Interactive graph visualisation (e.g. `react-flow` or `sigma.js`) backed by `GET /knowledge-graph/explore` with `root`, `depth`, `entity_type` query params.
      Files: `frontend/app/(app)/knowledge-graph/page.tsx`, `frontend/components/knowledgeGraph/GraphCanvas.tsx`, `frontend/components/knowledgeGraph/EntityDrawer.tsx`, `frontend/components/knowledgeGraph/GraphControls.tsx`.
      Implementation Notes: Limit default depth to 2. Click node → drawer with linked documents/Q&A. Cluster by jurisdiction / law type.
      Acceptance Criteria: Graph renders 200+ nodes smoothly; entity drawer fetches `GET /knowledge-graph/entities/{id}`.

- [ ] **T19.2 — Search-to-graph deep linking**
      Description: From search side panel (T11.1), open the explorer rooted at the entity.
      Files: `frontend/components/search/KnowledgeGraphSidePanel.tsx`.
      Acceptance Criteria: Query params persist; back button returns to previous search.

- [ ] **T19.3 — Saved graph views**
      Description: User can save current explorer state (root, depth, filters); restore later.
      Files: `frontend/components/knowledgeGraph/SavedViews.tsx`, `frontend/hooks/useSavedGraphViews.ts`.
      Acceptance Criteria: Saved view restores root + filters exactly.

---

### Module 20 — Private Messaging

- [ ] **T20.1 — `/messages` conversations list**
      Description: Cursor-paginated list of conversations with last-message preview, unread count, search.
      Files: `frontend/app/(app)/messages/page.tsx`, `frontend/components/messaging/ConversationsList.tsx`, `frontend/components/messaging/ConversationListItem.tsx`.
      Acceptance Criteria: Conversation order updates as new messages arrive.

- [ ] **T20.2 — `/messages/[conversationId]` thread page**
      Description: Real-time messaging UI over WebSocket; composer with attachment support (optional MVP3 stretch).
      Files: `frontend/app/(app)/messages/[conversationId]/page.tsx`, `frontend/components/messaging/MessageThread.tsx`, `frontend/components/messaging/MessageComposer.tsx`, `frontend/lib/ws/messagingSocket.ts`.
      Implementation Notes: WebSocket reconnect on drop; optimistic send + ack. Typing indicator.
      Acceptance Criteria: Two users exchange messages in real time; reload preserves history.

- [ ] **T20.3 — Start-new-conversation modal**
      Description: User search → start conversation with one or more members.
      Files: `frontend/components/messaging/NewConversationDialog.tsx`.
      Acceptance Criteria: Creates conversation and routes to its thread.

- [ ] **T20.4 — Read receipts + unread badge integration**
      Description: Per-conversation read state; total unread badge integrated with header notification bell.
      Files: `frontend/store/messaging.ts`, `frontend/components/layout/Header.tsx`.
      Acceptance Criteria: Read state updates when thread scrolled to bottom.

---

### Module 21 — Native Mobile (out-of-bounds for web frontend tasks)

- [ ] **T21.1 — Shared TypeScript types package**
      Description: Extract `frontend/types/` into a reusable `@ica/shared-types` package consumable by the native app (React Native variant).
      Files: `packages/shared-types/`, `frontend/tsconfig.json`, build pipelines.
      Acceptance Criteria: Both web and mobile builds consume the same type definitions.

- [ ] **T21.2 — React Native (Expo) project bootstrap**
      Description: Initialise `mobile/` Expo project mirroring the Phase-1+2 routes; share API client and Zustand stores where feasible.
      Files: `mobile/`, `mobile/app/_layout.tsx`, `mobile/lib/api/*`, `mobile/store/*`.
      Implementation Notes: Reuse `lib/api/` typed client logic. Push notifications via Expo Notifications → FCM/APNS.
      Acceptance Criteria: Mobile app logs in, lists Q&A, opens detail, posts a question, receives a push.

- [ ] **T21.3 — Mobile push notification handling**
      Description: Register device token with backend (`POST /users/me/push-subscriptions`); handle foreground/background notification taps.
      Files: `mobile/lib/push.ts`, `mobile/App.tsx`.
      Acceptance Criteria: Tap on a notification deep-links to the relevant screen.

- [ ] **T21.4 — Mobile-specific UX shortcuts**
      Description: Bottom-tab nav (Dashboard, Search, Feed, Messages, Profile); pull-to-refresh on lists.
      Files: `mobile/app/(tabs)/*`.
      Acceptance Criteria: Lighthouse-equivalent UX score ≥ 90 on iOS + Android emulators.

- [ ] **T21.5 — Mobile store submission readiness**
      Description: Bundle identifiers, icons, splash screens, privacy manifest, App Store / Play Console listings.
      Files: `mobile/app.json`, store assets in `mobile/store/`.
      Acceptance Criteria: TestFlight + Play Internal Testing builds accepted.

---

### Module 22 — Cross-cutting (Phase-3)

- [ ] **T22.1 — Playwright E2E for Phase-3 flows**
      Description: Add flows — create session + join; explore knowledge graph; send/receive a message; subscribe to push; toggle org-visibility on a document.
      Files: `frontend/e2e/phase3-*.spec.ts`.
      Acceptance Criteria: All flows green against MSW.

- [ ] **T22.2 — Accessibility audit for media-heavy pages**
      Description: Captions for live sessions (optional), keyboard nav for graph explorer, screen-reader hints for live regions in messaging.
      Files: relevant components.
      Acceptance Criteria: Zero critical axe violations; manual screen-reader spot check passes.

- [ ] **T22.3 — Performance budgets enforced in CI**
      Description: Lighthouse CI thresholds: TTI ≤ 3 s on `/dashboard`, `/feed`, `/sessions`; bundle-size budgets per route.
      Files: `.github/workflows/lighthouse-ci.yml`, `lighthouserc.json`.
      Acceptance Criteria: CI fails if any route regresses past the budget.

- [ ] **T22.4 — Frontend README + mobile onboarding**
      Description: Document Phase-3 features, env vars (`NEXT_PUBLIC_LIVEKIT_URL`, `NEXT_PUBLIC_PUSH_PUBLIC_KEY`, `NEXT_PUBLIC_GRAPH_ENABLED`), mobile build instructions.
      Files: `frontend/README.md`, `mobile/README.md`.
      Acceptance Criteria: New dev runs web + mobile in demo mode within 30 min.
