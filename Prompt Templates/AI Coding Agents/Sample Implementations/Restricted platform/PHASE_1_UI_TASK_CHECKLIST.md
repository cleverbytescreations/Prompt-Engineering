# Implementation Task Checklist (UI Task list) — Phase 1 (MVP)

> Scope: Next.js 16 (App Router) frontend covering all MVP modules defined in SAD §13 — Auth, Repository, Q&A, News, Social Feed, Search, Moderation, Notifications, Admin, Profile, Taxonomy.
> Stack: Next.js, React, TypeScript, MUI, Tailwind, React Query, Zustand, MSW (for `NEXT_PUBLIC_DEMO_MODE=true`).
> All AI/Phase-2/Phase-3 endpoints (`/ai/*`, `?lang=`, `news/{id}/feature`, `questions/{id}/promote`, `users/me/export`, related-content, Q&A discussion comments) are **out of scope** for this checklist.

---

## 1. Frontend Tasks

### Module 0 — Foundation & Cross-cutting UI

- [x] **T0.1 — Bootstrap Next.js 16 App Router project**
      Description: Initialize the `frontend/` workspace with TypeScript strict mode, App Router, Turbopack, and ESLint + Prettier defaults.
      Files / Components to be changed: `frontend/package.json`, `frontend/next.config.ts`, `frontend/tsconfig.json`, `frontend/eslint.config.mjs`, `frontend/.prettierrc`, `frontend/app/layout.tsx`, `frontend/app/page.tsx`, `frontend/app/globals.css`, `frontend/empty-module.js`.
      Implementation Notes: Path alias `@/* → ./`. `next.config.ts` sets `output: 'standalone'` for Docker. Stub `empty-module.js` for `react-pdf` canvas under Turbopack. Root `/` redirects to `/dashboard`.
      Acceptance Criteria: `npm run dev` boots; `npm run build` succeeds; lint passes; root URL redirects to `/dashboard`.

- [x] **T0.2 — Install and configure MUI + Tailwind theme**
      Description: Add MUI v6 (CSS variables mode) and Tailwind v3+, harmonised via a single design-token source.
      Files: `frontend/lib/theme.ts`, `frontend/tailwind.config.ts`, `frontend/postcss.config.js`, `frontend/app/globals.css`, `frontend/components/Providers.tsx`.
      Implementation Notes: ICA brand palette (primary blue, accent legal-gold, neutral greys). MUI `ThemeProvider` wraps the app in `Providers.tsx`. Tailwind preflight disabled to avoid clashes with MUI baseline.
      Acceptance Criteria: A `<Button variant="contained">` in `/dashboard` reflects ICA primary colour; a Tailwind utility class on the same page also renders correctly.

- [x] **T0.3 — Set up React Query + Zustand global providers**
      Description: Wire `QueryClientProvider`, `QueryClient` defaults (staleTime 30s, refetchOnWindowFocus false), and Zustand stores for auth and role-switching.
      Files: `frontend/components/Providers.tsx`, `frontend/store/auth.ts`, `frontend/store/roleSwitcher.ts`, `frontend/store/index.ts`.
      Implementation Notes: Auth store holds in-memory `accessToken`, `user`, `role`. Never persisted to `localStorage`. Refresh token is in HttpOnly cookie (server-handled).
      Acceptance Criteria: React Query devtools renders in dev; Zustand store hydrates on first render with `null` user.

- [x] **T0.4 — Typed API client (`lib/api/`)**
      Description: Build a typed `fetch`-based client with auto JWT injection, refresh-on-401 retry, error envelope decoding, and `X-Notification-Unread-Count` header capture.
      Files: `frontend/lib/api/client.ts`, `frontend/lib/api/errors.ts`, `frontend/lib/api/headers.ts`, per-module files (`auth.ts`, `users.ts`, `documents.ts`, `questions.ts`, `news.ts`, `posts.ts`, `moderation.ts`, `notifications.ts`, `search.ts`, `admin.ts`, `taxonomy.ts`, `dashboard.ts`).
      Implementation Notes: Base URL = `NEXT_PUBLIC_API_URL`. On 401 `TOKEN_EXPIRED`, call `/auth/refresh-token`, replay original request once. Decode `{detail, error_code, field_errors}`. Pipe unread-count header into auth store badge.
      Acceptance Criteria: A failing request raises a typed `ApiError` exposing `error_code`; a 401 triggers exactly one refresh-and-retry.

- [x] **T0.5 — MSW mock layer behind `NEXT_PUBLIC_DEMO_MODE`**
      Description: Initialise MSW in the browser when `NEXT_PUBLIC_DEMO_MODE=true`. Provide handlers and demo fixture data for every Phase-1 endpoint.
      Files: `frontend/mocks/browser.ts`, `frontend/mocks/handlers/*.ts` (one per module), `frontend/mocks/data/*.ts`, `frontend/public/mockServiceWorker.js`, `frontend/components/Providers.tsx`.
      Implementation Notes: Lazy-import `worker.start()` in a client-only effect. Provide stable UUIDs for fixtures. Include sample PDFs under `frontend/public/sample-docs/`.
      Acceptance Criteria: With `NEXT_PUBLIC_DEMO_MODE=true` the app works end-to-end against mocks; with `false` no mock service worker registers.

- [x] **T0.6 — App layout, Sidebar, Header, Role Switcher**
      Description: Build the authenticated `(app)` group layout with sidebar nav (role-aware), header (user menu, notification bell badge, search shortcut), and a dev role-switcher.
      Files: `frontend/components/layout/AppLayout.tsx`, `Sidebar.tsx`, `Header.tsx`, `RoleSwitcher.tsx`, `NotificationBell.tsx`, `frontend/app/(app)/layout.tsx`.
      Implementation Notes: Sidebar items derived from user role (A/M/U). Bell reads unread count from auth-store header value. RoleSwitcher visible only in demo mode. Under the "Questions" nav group, include an **"Assigned to me"** link (`/questions/assigned`, T6.6) visible to all authenticated users; show a small count badge next to the link when the user has unanswered assigned questions (resolved via the same `GET /questions/assigned` query already cached on the page).
      Acceptance Criteria: Member role hides `/moderation` and `/admin/*` items; Admin sees all items; bell badge updates after any authenticated request; "Assigned to me" link visible to every authenticated role and shows a count badge when unanswered assignments exist.

- [x] **T0.7 — Shared UI primitives**
      Description: Reusable components — `StatusBadge`, `AnswerTierBadge`, `FilterBar`, `Pagination`, `CursorPager`, `EmptyState`, `ErrorState`, `LoadingSkeleton`, `ConfirmDialog`, `RichTextEditor`, `FilePicker`, `TagInput`, `CountryPicker`, `CategoryPicker`.
      Files: `frontend/components/shared/*.tsx`.
      Implementation Notes: `StatusBadge` colour-coded for `pending|approved|rejected|revision_required|flagged|retracted`. `AnswerTierBadge` renders three mutually exclusive answer tiers derived from the answer payload — `community` (no badge), `expert_verified` (`is_verified=true`, green "Expert Verified" chip), `ica_official` (`is_ica_official=true`, gold "Official ICA Position" chip with shield icon; takes visual precedence over expert_verified when both flags are true). `CursorPager` consumes `next_cursor`. `RichTextEditor` uses a lightweight option (e.g. TipTap or react-markdown-editor); 5,000-char cap.
      Acceptance Criteria: Storybook-style preview page renders each component in each variant without console warnings; `AnswerTierBadge` renders the correct chip for all three tier states.

- [x] **T0.8 — Route guard / auth middleware**
      Description: Protect `(app)/*` routes — unauthenticated users are redirected to `/auth/login?next=...`. Role-gate `/moderation/*` (A,M) and `/admin/*` (A only).
      Files: `frontend/middleware.ts`, `frontend/app/(app)/layout.tsx`, `frontend/lib/auth/guard.ts`.
      Implementation Notes: Read access-token presence + role from Zustand on client navigations; server redirects via Next middleware where possible (no SSR token introspection — rely on cookie sniff + client check).
      Acceptance Criteria: Anon user visiting `/dashboard` is redirected; Member visiting `/admin/users` sees a 403 page.

- [x] **T0.9 — Global error boundary, 404 page, toast system**
      Description: App-wide error boundary, `not-found.tsx`, and a toast notifier hooked to mutation errors.
      Files: `frontend/app/error.tsx`, `frontend/app/not-found.tsx`, `frontend/components/shared/Toast.tsx`, `frontend/lib/utils/toast.ts`.
      Implementation Notes: Toast surfaces `error_code` from `ApiError`. Sentry init wrapped behind `NEXT_PUBLIC_SENTRY_DSN`.
      Acceptance Criteria: Forcing an error in a page shows the error boundary; an API 429 surfaces a toast with retry-after text.

- [x] **T0.10 — i18n (`next-intl`, EN / ES / FR for application UI in Phase 1)**
      Description: Wire `next-intl` with full EN / ES / FR support for all application menu items, navigation labels, button text, form labels, validation messages, error messages, and static UI copy. Content translation (`?lang=` for documents, Q&A, news) remains Phase 2 and is out of scope here.
      Files: `frontend/i18n.ts`, `frontend/messages/en.json`, `frontend/messages/es.json`, `frontend/messages/fr.json`, `frontend/middleware.ts`, `frontend/components/layout/LanguageSwitcher.tsx`, `frontend/hooks/useLocale.ts`.
      Implementation Notes: All user-facing static strings must come from the message catalogue — no hard-coded UI copy. No locale-prefixed URLs; active locale stored in `localStorage` and read by `next-intl` provider on app load. `LanguageSwitcher` renders a 3-option dropdown (EN / ES / FR) placed in the authenticated Header and on the login/signup pages. Switching locale updates `localStorage`, calls `PATCH /auth/me` with `preferred_lang` for authenticated users (best-effort, non-blocking), and re-renders via `next-intl` context — no full-page reload. On first load, resolve locale priority: JWT `preferred_lang` claim → `localStorage` → browser `Accept-Language` → `en`.
      Acceptance Criteria: Every static UI string (nav items, buttons, labels, toasts, error messages, empty states) is translated for all three locales; switching to ES/FR re-renders the full UI without page reload; `LanguageSwitcher` is visible on login page (unauthenticated) and in the authenticated Header; a missing key in `es.json` or `fr.json` falls back to `en.json` without throwing.

---

### Module 1 — Authentication & Onboarding (UI)

- [x] **T1.1 — `/auth/login` page**
      Description: Email + password login with client-side validation, server error mapping, "Forgot password" link.
      Files: `frontend/app/(auth)/auth/login/page.tsx`, `frontend/components/auth/LoginForm.tsx`, `frontend/hooks/useAuth.ts`.
      Implementation Notes: On success, store access token in Zustand and redirect to `next` query param or `/dashboard`. Map `UNAUTHORIZED` to "Invalid credentials"; map 429 to "Too many attempts — try again in X seconds".
      Acceptance Criteria: 5+ rapid invalid attempts surface rate-limit toast; success redirects.

- [x] **T1.2 — `/auth/signup` page (invite-gated)**
      Description: Two-step form — step 1: enter invite code (calls `POST /auth/verify-invite`); step 2: create account (`POST /auth/signup`).
      Files: `frontend/app/(auth)/auth/signup/page.tsx`, `frontend/components/auth/SignupForm.tsx`, `frontend/components/auth/InviteCodeStep.tsx`.
      Implementation Notes: Show org name returned from verify-invite. Password rules: ≥10 chars, mixed case, number. After signup, auto-login then route to `/auth/setup`.
      Acceptance Criteria: Invalid invite shows `INVALID_INVITE` message; valid invite advances; signup completes and routes to setup.

- [x] **T1.3 — `/auth/forgot-password` & `/auth/reset-password` pages**
      Description: Request reset email; reset using tokenised link.
      Files: `frontend/app/(auth)/auth/forgot-password/page.tsx`, `frontend/app/(auth)/auth/reset-password/page.tsx`, `frontend/components/auth/ForgotPasswordForm.tsx`, `frontend/components/auth/ResetPasswordForm.tsx`.
      Implementation Notes: Reset page reads token from `?token=` query; calls `POST /auth/reset-password`. Generic "if the email exists…" success message (no enumeration).
      Acceptance Criteria: Submitting forgot-password always succeeds visually; reset with invalid token shows clear error.

- [x] **T1.4 — `/auth/setup` onboarding preferences page**
      Description: Multi-select country & category interests + digest opt-in; calls `POST /auth/me/preferences`.
      Files: `frontend/app/(app)/auth/setup/page.tsx`, `frontend/components/auth/PreferencesForm.tsx`.
      Implementation Notes: Pull options from `GET /countries` and `GET /categories`. "Skip for now" routes to `/dashboard`.
      Acceptance Criteria: Submitting saves prefs; on next visit, prefs are pre-populated when re-opened from profile.

- [x] **T1.5 — Logout + token refresh wiring**
      Description: Hook `POST /auth/logout` to user menu; ensure refresh-on-401 retry path established in T0.4 invalidates on logout failures.
      Files: `frontend/components/layout/Header.tsx`, `frontend/hooks/useLogout.ts`.
      Implementation Notes: Logout always clears auth store and routes to `/auth/login`, even if server returns 401.
      Acceptance Criteria: Click logout → auth store cleared, cookie cleared, redirected to login.

- [x] **T1.6 — Change-password page / dialog**
      Description: Authenticated user changes password — current + new + confirm; calls `POST /auth/me/change-password`.
      Files: `frontend/app/(app)/profile/security/page.tsx`, `frontend/components/auth/ChangePasswordForm.tsx`, `frontend/hooks/useChangePassword.ts`.
      Implementation Notes: Reachable from `/profile/edit` and user-menu "Security" link. Enforces same client-side password rules as signup (≥10 chars, mixed case, number). On success, server revokes other tokens — surface "Other sessions signed out" toast.
      Acceptance Criteria: Wrong current password surfaces `UNAUTHORIZED` inline; success keeps user logged in on the active session.

---

### Module 2 — User Management (UI, Admin/Moderator views)

- [ ] **T2.1 — `/admin/users` list page**
      Description: Filterable, paginated user list with status & role inline edit.
      Files: `frontend/app/(app)/admin/users/page.tsx`, `frontend/components/admin/UsersTable.tsx`, `frontend/components/admin/UsersFilters.tsx`, `frontend/hooks/useUsers.ts`.
      Implementation Notes: Offset pagination (default 10, max 50). Filters: **role**, **status**, **org** (dropdown sourced from `GET /organizations`), search by name/email. Inline role/status uses `PATCH /users/{id}/role|status` with optimistic update.
      Acceptance Criteria: Admin can toggle a member to inactive; Moderator sees the list read-only; org-filter dropdown is populated and filters server-side.

- [ ] **T2.2 — `/profile/[id]` view**
      Description: Public user profile with contributions tabs (Documents, Questions, Posts, News).
      Files: `frontend/app/(app)/profile/[id]/page.tsx`, `frontend/components/profile/ProfileHeader.tsx`, `frontend/components/profile/ContributionsTabs.tsx`.
      Implementation Notes: Calls `GET /users/{id}` and `GET /users/{id}/contributions`.
      Acceptance Criteria: Self-profile shows an "Edit" CTA; others' profiles do not.

- [ ] **T2.3 — `/profile/edit` page**
      Description: Edit own profile (full name, avatar, preferred language).
      Files: `frontend/app/(app)/profile/edit/page.tsx`, `frontend/components/profile/EditProfileForm.tsx`.
      Implementation Notes: `PATCH /auth/me`. Avatar upload via signed URL (out of scope for Phase 1 if direct upload not implemented — show URL field).
      Acceptance Criteria: Saved changes appear immediately in header user menu.

---

### Module 3 — Organisation Management (UI)

- [ ] **T3.1 — `/admin/orgs` page**
      Description: Org list + create/edit dialogs; member-count column.
      Files: `frontend/app/(app)/admin/orgs/page.tsx`, `frontend/components/admin/OrgsTable.tsx`, `frontend/components/admin/OrgFormDialog.tsx`.
      Implementation Notes: Create/edit via dialog; delete with confirm dialog (soft-delete via `DELETE /organizations/{id}`).
      Acceptance Criteria: Creating an org with duplicate name surfaces `CONFLICT`; deleted orgs disappear from list.

- [ ] **T3.2 — Org members drawer**
      Description: Slide-in panel listing members of the selected org.
      Files: `frontend/components/admin/OrgMembersDrawer.tsx`.
      Implementation Notes: `GET /organizations/{id}/members`. Click member to navigate to `/profile/[id]`.
      Acceptance Criteria: Drawer opens with paginated members list.

---

### Module 4 — Invite Management (UI)

- [ ] **T4.1 — `/admin/invites` page**
      Description: Generate invite codes (org + role + expiry); list with status (pending/used/expired/revoked); revoke action.
      Files: `frontend/app/(app)/admin/invites/page.tsx`, `frontend/components/admin/InviteGeneratorForm.tsx`, `frontend/components/admin/InvitesTable.tsx`.
      Implementation Notes: On generate, copy-to-clipboard the invite code + signup URL. Revoke with confirmation.
      Acceptance Criteria: Generated code appears in table; revoke updates status to `revoked`; clipboard copy works.

---

### Module 5 — Knowledge Repository (UI)

- [ ] **T5.1 — `/repository` list page**
      Description: Browse approved documents with country/category/tag filters and search box.
      Files: `frontend/app/(app)/repository/page.tsx`, `frontend/components/repository/DocumentsList.tsx`, `frontend/components/repository/DocumentCard.tsx`, `frontend/components/repository/RepositoryFilters.tsx`.
      Implementation Notes: Offset pagination 10/page. Filter bar reads `GET /countries`, `GET /categories`, `GET /tags`. Empty state CTA → upload.
      Acceptance Criteria: Filter combinations update URL query string; back/forward restore state.

- [ ] **T5.2 — `/repository/[id]` detail page**
      Description: View metadata, summary, country/category/tags, version & moderation status; download CTA; PDF inline preview.
      Files: `frontend/app/(app)/repository/[id]/page.tsx`, `frontend/components/repository/DocumentDetail.tsx`, `frontend/components/repository/PdfPreview.tsx`.
      Implementation Notes: Uses `react-pdf` (configure canvas stub `empty-module.js`). Download triggers signed-URL fetch via `GET /documents/{id}/download`.
      Acceptance Criteria: 50MB PDF renders progressively; download button opens file in new tab.

- [ ] **T5.3 — `/repository/upload` page**
      Description: Multipart form: title, country, category, tags, law_type, language, source_type toggle (file vs external URL), optional summary, PDF picker (≤50 MB).
      Files: `frontend/app/(app)/repository/upload/page.tsx`, `frontend/components/repository/UploadForm.tsx`, `frontend/components/repository/DropZone.tsx`.
      Implementation Notes: Validate MIME = `application/pdf`, magic-byte check via `FileReader`. Show progress; on success surface "Submitted — pending moderation".
      Acceptance Criteria: A non-PDF file is rejected client-side; oversized file triggers `FILE_TOO_LARGE`.

- [ ] **T5.4 — `/repository/my` page**
      Description: Current user's uploads with status badges.
      Files: `frontend/app/(app)/repository/my/page.tsx`, `frontend/components/repository/MyDocumentsTable.tsx`.
      Implementation Notes: Calls `GET /documents/my`. Click row → detail.
      Acceptance Criteria: Each row shows correct moderation status and last-updated time.

- [ ] **T5.5 — Document version history viewer (Admin/Moderator)**
      Description: Drawer showing `GET /documents/{id}/versions` and per-version snapshot.
      Files: `frontend/components/repository/VersionsDrawer.tsx`.
      Implementation Notes: Diff metadata against current. Member role does not see the version button.
      Acceptance Criteria: Selecting a version row loads `GET /documents/{id}/versions/{vid}` payload.

---

### Module 6 — Question & Answer (UI)

- [ ] **T6.1 — `/questions` list page**
      Description: Approved Q&A list with country/category filters and answer-status badges.
      Files: `frontend/app/(app)/questions/page.tsx`, `frontend/components/questions/QuestionsList.tsx`, `frontend/components/questions/QuestionCard.tsx`.
      Implementation Notes: Offset pagination 10/page. Show answer count and `AnswerTierBadge` at its highest tier — if any answer has `is_ica_official=true` show the gold "Official ICA Position" chip; else if any answer has `is_verified=true` show the green "Expert Verified" chip; otherwise show no badge.
      Acceptance Criteria: A question with an official ICA answer shows the gold chip; a question with only a verified (non-official) answer shows the green chip; a question with only community answers shows no chip.

- [ ] **T6.2 — `/questions/ask` page**
      Description: Form: title, body (rich text, 5,000-char cap), country, category, tags.
      Files: `frontend/app/(app)/questions/ask/page.tsx`, `frontend/components/questions/AskQuestionForm.tsx`.
      Implementation Notes: On submit → `POST /questions`; route to detail with toast "Pending moderation".
      Acceptance Criteria: Form validates required fields; long body truncates at limit with counter.

- [ ] **T6.3 — `/questions/[id]` detail page**
      Description: Question body, answers list, post-answer composer, accept/verify/mark-official actions (role-gated), version history (A/M).
      Files: `frontend/app/(app)/questions/[id]/page.tsx`, `frontend/components/questions/QuestionDetail.tsx`, `frontend/components/questions/AnswerList.tsx`, `frontend/components/questions/AnswerComposer.tsx`, `frontend/components/questions/AssignExpertDialog.tsx`.
      Implementation Notes: Author may `accept` an answer (A,M,U); A/M may `verify` (calls `PATCH /answers/{id}/verify`); Admin only may `mark-official` (calls `PATCH /answers/{id}/mark-official`) — button hidden for non-Admin roles. `mark-official` button only enabled when the answer is already `is_verified=true`; tooltip explains the precondition when disabled. Each answer renders `AnswerTierBadge` inline. Assign-expert dialog visible to A/M (uses `PATCH /questions/{id}/assign`). Inline edit pre-moderation (PUT). No Q&A discussion comments in Phase 1.
      Acceptance Criteria: Author can accept exactly one answer; A/M verify sets the green "Expert Verified" badge; Admin mark-official sets the gold "Official ICA Position" badge; mark-official on an unverified answer returns 422 and surfaces a toast; non-Admin users do not see the mark-official button; marking a second answer official removes the gold badge from the prior one.

- [ ] **T6.4 — `/questions/my` page**
      Description: User's own questions with status badges.
      Files: `frontend/app/(app)/questions/my/page.tsx`, `frontend/components/questions/MyQuestionsTable.tsx`.
      Acceptance Criteria: Status badge reflects pending/approved/rejected/revision_required.

- [ ] **T6.5 — Question version history drawer (Admin/Moderator)**
      Description: Drawer showing `GET /questions/{id}/versions` with per-version snapshot view via `GET /questions/{id}/versions/{vid}`.
      Files: `frontend/components/questions/QuestionVersionsDrawer.tsx`.
      Implementation Notes: Triggered from `/questions/[id]` (T6.3) for A/M only. Member role does not see the button. Diff metadata against current version.
      Acceptance Criteria: Selecting a version row loads the snapshot payload; non-A/M users do not see the trigger.

- [ ] **T6.6 — `/questions/assigned` page (Assigned to me)**
      Description: Dedicated page listing all questions assigned to the currently authenticated user, with sortable columns for `assigned_at`, question status, assigned-by user, and answer count. Calls `GET /questions/assigned` (API T-B6.1) with cursor pagination. Each row links to the question detail (T6.3).
      Files: `frontend/app/(app)/questions/assigned/page.tsx`, `frontend/components/questions/AssignedQuestionsTable.tsx`, `frontend/hooks/useAssignedQuestions.ts`, `frontend/lib/api/questions.ts`.
      Implementation Notes: Default sort `assigned_at DESC`. Show a prominent **"Awaiting your response"** banner above unanswered rows (rows where the current user has not yet posted an answer). Pending-state badges (T0.7 `StatusBadge`) used for question status. Empty-state copy: *"No questions are currently assigned to you."* Page is reachable for any authenticated user (members can be designated experts), but always returns only the user's own assigned set per API authorisation. URL deep-link to specific question opens detail in same tab.
      Acceptance Criteria: A user with N assigned questions sees N rows; clicking a row navigates to `/questions/[id]`; rows where the current user has not yet posted an answer are highlighted; empty state renders when no assignments exist; pagination cursor stable under concurrent assignments.

- [ ] **T6.7 — Assignment status display on question detail**
      Description: Extend `/questions/[id]` (T6.3) to display the current assignee inline at the top of the question card — *"Assigned to: {expert_name}"* with avatar, role chip, and timestamp (*assigned by {moderator} on {date}*). Visible to all authenticated users. If reassignment occurs, the display updates after refetch.
      Files: `frontend/components/questions/QuestionDetail.tsx`, `frontend/components/questions/AssignmentStatusBanner.tsx`.
      Implementation Notes: When the current viewing user IS the assignee and has not yet answered, surface a secondary CTA — *"You have been asked to respond"* — anchored above the answer composer. When unassigned, the banner is hidden entirely (no "Unassigned" placeholder). Avatar links to `/profile/[id]`.
      Acceptance Criteria: Detail page shows assignee block when `assigned_to` is set; assignee CTA visible only to the assigned user; reassignment (via the AssignExpertDialog) updates the displayed assignee within one refetch cycle.

---

### Module 7 — News & Updates (UI)

- [ ] **T7.1 — `/news` list page**
      Description: Approved news with country/category filters; show language and published_at.
      Files: `frontend/app/(app)/news/page.tsx`, `frontend/components/news/NewsList.tsx`, `frontend/components/news/NewsCard.tsx`.
      Acceptance Criteria: Filtering by country updates the list immediately.

- [ ] **T7.2 — `/news/[id]` detail page**
      Description: Article body, source link, country/category, version history (A/M).
      Files: `frontend/app/(app)/news/[id]/page.tsx`, `frontend/components/news/NewsDetail.tsx`.
      Acceptance Criteria: Source URL opens externally with `rel="noopener noreferrer"`.

- [ ] **T7.3 — `/news/create` page**
      Description: Submit news article (title, body, country, category, source_url, language).
      Files: `frontend/app/(app)/news/create/page.tsx`, `frontend/components/news/CreateNewsForm.tsx`.
      Acceptance Criteria: Submitting creates a pending record visible in `/news/my`.

- [ ] **T7.4 — `/news/my` page**
      Description: User's submitted news with statuses.
      Files: `frontend/app/(app)/news/my/page.tsx`, `frontend/components/news/MyNewsTable.tsx`.
      Acceptance Criteria: Status badges correct.

- [ ] **T7.5 — News version history drawer (Admin/Moderator)**
      Description: Drawer showing `GET /news/{id}/versions` with per-version snapshot view via `GET /news/{id}/versions/{vid}`.
      Files: `frontend/components/news/NewsVersionsDrawer.tsx`.
      Implementation Notes: Triggered from `/news/[id]` (T7.2) for A/M only. Mirrors `T5.5` and `T6.5` behaviour.
      Acceptance Criteria: Selecting a version row loads the snapshot payload; non-A/M users do not see the trigger.

---

### Module 8 — Social Feed (UI)

- [ ] **T8.1 — `/feed` page (cursor pagination)**
      Description: Infinite-scroll feed of approved posts with like and comment controls.
      Files: `frontend/app/(app)/feed/page.tsx`, `frontend/components/feed/PostsFeed.tsx`, `frontend/components/feed/PostCard.tsx`, `frontend/components/feed/PostComments.tsx`, `frontend/components/feed/CommentComposer.tsx`.
      Implementation Notes: Use `useInfiniteQuery` against `next_cursor`. Optimistic like toggle (`POST /posts/{id}/like`). Comments lazy-load.
      Acceptance Criteria: Scrolling loads next page; like count reflects optimistic + reconciled state.

- [ ] **T8.2 — `/post/create` page**
      Description: Composer (body ≤2,000 chars, optional category, tags).
      Files: `frontend/app/(app)/post/create/page.tsx`, `frontend/components/feed/CreatePostForm.tsx`.
      Acceptance Criteria: Submit returns a pending-state confirmation.

- [ ] **T8.3 — `/post/my` page**
      Description: Current user's posts with statuses.
      Files: `frontend/app/(app)/post/my/page.tsx`, `frontend/components/feed/MyPostsTable.tsx`.
      Acceptance Criteria: Pending and rejected posts visible only here.

- [ ] **T8.4 — Post detail dialog/page**
      Description: Full post view + comment thread (use `GET /posts/{id}` and comment endpoints).
      Files: `frontend/components/feed/PostDetailDialog.tsx`.
      Acceptance Criteria: Comment delete CTA appears only for author/Admin/Moderator.

---

### Module 9 — Moderation (UI, A/M)

- [ ] **T9.1 — `/moderation` unified queue page**
      Description: Single queue across all content types with type filter & cursor pagination; per-row Approve/Reject/Request-changes/Flag/Retract.
      Files: `frontend/app/(app)/moderation/page.tsx`, `frontend/components/moderation/QueueTable.tsx`, `frontend/components/moderation/ModerationActionsMenu.tsx`, `frontend/components/moderation/ModerationStatsBar.tsx`.
      Implementation Notes: Reads `GET /moderation/queue`, `GET /moderation/stats`. Approve dialog allows assigning `category_id` for news/posts at approval. Reject/retract require remarks. Flag holds without rejecting.
      Acceptance Criteria: Performing each of five actions updates the row state and the stats bar.

- [ ] **T9.2 — Type-specific queue pages**
      Description: `/moderation/questions`, `/moderation/documents`, `/moderation/news`, `/moderation/posts` — per-type detail panels with inline preview.
      Files: `frontend/app/(app)/moderation/questions/page.tsx`, `documents/page.tsx`, `news/page.tsx`, `posts/page.tsx`, `frontend/components/moderation/QueueDetailPanel.tsx`.
      Acceptance Criteria: Selecting a row opens a detail pane with full content; bulk-select supports approve/reject (where applicable).

- [ ] **T9.3 — Flagged queue (Admin-only)**
      Description: View flagged content held for senior review.
      Files: `frontend/app/(app)/moderation/flagged/page.tsx`, `frontend/components/moderation/FlaggedQueue.tsx`.
      Acceptance Criteria: Hidden from Moderator nav; Admin sees only flagged items.

- [ ] **T9.4 — Moderation history viewer**
      Description: Drawer showing `GET /moderation/logs/{entity_type}/{id}` for a chosen item.
      Files: `frontend/components/moderation/HistoryDrawer.tsx`.
      Acceptance Criteria: Lists every action with actor, timestamp, remarks.

- [ ] **T9.5 — Retraction dialog (documents)**
      Description: Specialised dialog requiring `retraction_reason` and optional `replacement_document_id`.
      Files: `frontend/components/moderation/RetractDocumentDialog.tsx`.
      Acceptance Criteria: Retracted doc disappears from `/repository` default list (status=active).

- [ ] **T9.6 — Bulk-action toolbar for moderation queues**
      Description: Shared `BulkActionsToolbar` enabling row-multi-select on type-specific queue pages (T9.2) with bulk Approve / Reject. Per-action confirm dialog reuses single-row dialogs (remarks required for reject).
      Files: `frontend/components/moderation/BulkActionsToolbar.tsx`, `frontend/hooks/useBulkModeration.ts`.
      Implementation Notes: Sequential API calls (no bulk endpoint in Phase 1) with progress indicator and per-row success/failure summary. Bulk-flag and bulk-retract intentionally out of scope.
      Acceptance Criteria: Selecting N rows and clicking "Approve" processes each via `POST /moderation/approve`, shows progress, and surfaces a per-row outcome list.

---

### Module 10 — Notifications (UI)

- [ ] **T10.1 — Notification bell with `X-Notification-Unread-Count` integration**
      Description: Header bell badge driven by the piggyback header captured in T0.4.
      Files: `frontend/components/layout/NotificationBell.tsx`, `frontend/hooks/useUnreadCount.ts`.
      Implementation Notes: On page load only, call `GET /notifications/unread-count` once. **No interval polling below 60s.** Subsequent updates come from header on each authenticated response.
      Acceptance Criteria: Mocked header value reflected in bell immediately.

- [ ] **T10.2 — `/notifications` page**
      Description: List with mark-as-read, mark-all-read, delete. Renders type-specific icon + copy + deep link for every Phase-1 notification type registered in the backend catalogue (API T-I4.13): `question_answered`, `question_assigned`, `question_unassigned`, `answer_verified`, `answer_accepted`, `answer_marked_official`, `<entity>_approved`, `<entity>_rejected`, `<entity>_changes_requested`, `document_retracted`, `account_role_changed`, `account_status_changed`, `invite_consumed`.
      Files: `frontend/app/(app)/notifications/page.tsx`, `frontend/components/notifications/NotificationsList.tsx`, `frontend/components/notifications/NotificationRow.tsx`, `frontend/lib/notifications/types.ts`, `frontend/lib/notifications/icons.ts`.
      Implementation Notes: A central registry (`types.ts`) maps every notification `type` to `{icon, copyKey, deepLinkBuilder}`. Translation strings live in i18n catalogues (T0.10). `question_assigned` row shows a distinctive expert-routing icon and deep-links to `/questions/[id]` with anchor `#answer-composer`. `answer_marked_official` row shows the gold shield icon (matches `AnswerTierBadge`) and deep-links to the answer anchor. Unknown notification types fall back to a generic row with raw payload preview (defence in depth against backend additions).
      Acceptance Criteria: Read items dim; bell badge decrements optimistically; each registered type renders with its specific icon and copy; deep links navigate to the correct entity + anchor; unknown type renders the fallback row without crashing.

- [ ] **T10.3 — Notification preferences page (`/profile/notifications`)**
      Description: Country/category broadcast subscription toggles + email/in-app per channel, hosted at `/profile/notifications` and linked from `/profile/edit` and the user menu.
      Files: `frontend/app/(app)/profile/notifications/page.tsx`, `frontend/components/profile/NotificationPreferences.tsx`.
      Implementation Notes: Calls `GET/PUT /notifications/preferences`. Country / category options sourced via cached reference-data hooks (T15.7).
      Acceptance Criteria: Toggling a country and saving persists across reload; page reachable via direct URL and from both link entry points.

---

### Module 11 — Search (UI, Phase 1 = `/search` only — no `/ai/ask`)

- [ ] **T11.1 — `/search` page**
      Description: Global search bar + result list with type/country/category/date/status filters and `search_mode` selector (hybrid/keyword/semantic).
      Files: `frontend/app/(app)/search/page.tsx`, `frontend/components/search/SearchBar.tsx`, `frontend/components/search/SearchFilters.tsx`, `frontend/components/search/SearchResults.tsx`, `frontend/components/search/ResultCard.tsx`.
      Implementation Notes: Offset pagination, max page_size 20. Show `latency_ms` and `cache_hit` debug strip in dev. AI Ask path is hidden in Phase 1.
      Acceptance Criteria: Latency ≤ 1.5s SLA visible in dev strip; filters update URL query.

- [ ] **T11.2 — Header global search shortcut (`/` keypress)**
      Description: Cmd-K-style modal that focuses `q` and routes to `/search`.
      Files: `frontend/components/layout/SearchShortcut.tsx`.
      Acceptance Criteria: Pressing `/` outside an input opens the modal.

---

### Module 12 — Dashboard (UI)

- [ ] **T12.1 — `/dashboard` aggregated page**
      Description: Cards: latest news, my pending items, unread notifications, recent Q&A, recent documents.
      Files: `frontend/app/(app)/dashboard/page.tsx`, `frontend/components/dashboard/DashboardGrid.tsx`, `frontend/components/dashboard/*.tsx` (per card).
      Implementation Notes: Single call `GET /dashboard`.
      Acceptance Criteria: Empty fixtures render skeletons; populated fixtures render correct counts.

---

### Module 13 — Taxonomy / Reference (UI, Admin)

- [ ] **T13.1 — `/admin/taxonomy` page**
      Description: CRUD for tags and categories (hierarchical, content-type-scoped).
      Files: `frontend/app/(app)/admin/taxonomy/page.tsx`, `frontend/components/admin/TagsManager.tsx`, `frontend/components/admin/CategoriesManager.tsx`.
      Implementation Notes: Categories rendered as a tree (parent_id); content_type filter chips. Tags as flat list with usage counts where available.
      Acceptance Criteria: Creating, editing, deleting tags/categories reflects in the picker components on subsequent navigations.

---

### Module 14 — Admin Statistics & Config (UI)

- [ ] **T14.1 — `/admin/analytics` page**
      Description: Platform stats — counts by user role/org, content type, moderation throughput.
      Files: `frontend/app/(app)/admin/analytics/page.tsx`, `frontend/components/admin/StatsCards.tsx`, `frontend/components/admin/ModerationStatsChart.tsx`.
      Implementation Notes: `GET /admin/stats` and `GET /moderation/stats`. Charts via MUI X charts (or recharts).
      Acceptance Criteria: Numbers match server fixtures.

- [ ] **T14.2 — `/admin/config` page**
      Description: View and update platform configuration (invite_expiry_hours, max_content_per_org, moderation_sla_hours, supported_languages, ai_confidence thresholds).
      Files: `frontend/app/(app)/admin/config/page.tsx`, `frontend/components/admin/ConfigForm.tsx`.
      Implementation Notes: Form generated from `value_type`. Save calls `PUT /admin/config`.
      Acceptance Criteria: Editing a value persists and reloads correctly.

---

### Module 15 — Cross-cutting (UI)

- [ ] **T15.1 — Accessibility audit**
      Description: Keyboard nav, focus rings, aria labels, colour-contrast pass on every page.
      Files: project-wide.
      Implementation Notes: Use `@axe-core/react` in dev.
      Acceptance Criteria: Zero critical axe violations on the 10 key Phase 1 pages.

- [ ] **T15.2 — Responsive layouts (≥360px)**
      Description: Every authenticated page must render usably on a 360–375px viewport (iPhone SE baseline). Sidebar collapses to a temporary drawer below `md`; all admin/moderation tables become stacked card lists below `md`. Header (`components/layout/Header.tsx`) shrinks role switcher to compact form on `xs` (or hides the demo role switcher entirely); icon buttons use `flexShrink: 0` so avatar/notifications stay anchored to the right edge. Stat-card / chip rows use `flexWrap: 'wrap'` + `minWidth: 0` so they never force the parent wider than the viewport. Page-content scroll container (`AppLayout` main) uses `overflowX: 'hidden'` and `html, body { overflow-x: hidden }` is set globally as a defense-in-depth guard.
      Files: `frontend/app/globals.css`, `frontend/components/layout/AppLayout.tsx`, `frontend/components/layout/Header.tsx`, `frontend/components/layout/RoleSwitcher.tsx`, `frontend/components/layout/LanguageSwitcher.tsx`, all admin/moderation tables, all dashboard widgets, repository/questions/news list pages.
      Implementation Notes: Audit each top-level page in Chrome DevTools device mode at iPhone SE (375×667). Page must not scroll horizontally. Use MUI `sx` breakpoints (`{ xs, sm, md }`) — do not introduce a CSS-in-JS framework outside MUI/Tailwind.
      Acceptance Criteria: (1) No horizontal scroll on any page at 375px; (2) avatar + notifications visible without scrolling on every page; (3) admin tables render as stacked cards below `md`; (4) Lighthouse mobile score ≥ 90 on `/feed`, `/repository`, `/dashboard`.

- [ ] **T15.3 — Frontend env file + Sentry init**
      Description: `.env.local.example` documents all `NEXT_PUBLIC_*` vars; Sentry initialised behind `NEXT_PUBLIC_SENTRY_DSN`.
      Files: `frontend/.env.local.example`, `frontend/sentry.client.config.ts`.
      Acceptance Criteria: Missing `NEXT_PUBLIC_API_URL` produces a clear boot-time error.

- [ ] **T15.4 — Unit + component tests (Vitest + RTL)**
      Description: Cover forms, guard logic, API client refresh-on-401, pagination components.
      Files: `frontend/**/*.test.tsx`.
      Acceptance Criteria: ≥ 60% statement coverage on `frontend/lib/` and `frontend/components/shared/`.

- [ ] **T15.5 — Playwright smoke E2E (against MSW)**
      Description: Five flows — invite signup, upload+moderate, ask question, search, like+comment on a post.
      Files: `frontend/e2e/*.spec.ts`, `frontend/playwright.config.ts`.
      Acceptance Criteria: All five flows pass in headless mode.

- [ ] **T15.6 — UI documentation**
      Description: `frontend/README.md` covering dev setup, demo mode, MSW handlers, theming.
      Files: `frontend/README.md`.
      Acceptance Criteria: A new dev can run `npm install && npm run dev` with demo mode in <5 min using the README.

- [ ] **T15.7 — Reference-data cached hooks (countries, categories, tags)**
      Description: Shared React Query hooks `useCountries()`, `useCategories()`, `useTags()` with long `staleTime` (24 h) and global query keys, so `CountryPicker`, `CategoryPicker`, `TagInput`, and filter bars do not refetch per page.
      Files: `frontend/hooks/useReferenceData.ts`, `frontend/components/shared/CountryPicker.tsx`, `frontend/components/shared/CategoryPicker.tsx`, `frontend/components/shared/TagInput.tsx`.
      Implementation Notes: Pre-warm in `Providers.tsx` after auth. Manual invalidation on taxonomy mutations (T13.1).
      Acceptance Criteria: Navigating between `/repository`, `/questions`, `/news` triggers exactly one network request per reference list per session (verified in Network tab / MSW logs).

- [ ] **T15.8 — Empty-state and error-state audit**
      Description: Cross-page audit ensuring every list/table page uses the shared `EmptyState` and `ErrorState` primitives from T0.7 with a meaningful CTA (e.g. upload, ask, retry).
      Files: list/table components across `repository/`, `questions/`, `news/`, `feed/`, `notifications/`, `moderation/`, `admin/`.
      Acceptance Criteria: Each list page renders the shared `EmptyState` for an empty fixture and `ErrorState` for a forced API failure; no bespoke "No data" strings remain.

- [ ] **T15.9 — PWA web app manifest + viewport metadata**
      Description: Make the Next.js app installable. Ship a Next 16 `app/manifest.ts` file (served at `/manifest.webmanifest`) declaring `name`, `short_name`, `description`, `start_url: '/dashboard'`, `scope: '/'`, `display: 'standalone'`, `background_color: '#F5F0E6'`, `theme_color: '#1C3D4A'`, and `icons` (any + maskable). Add a `viewport` export in `app/layout.tsx` with `themeColor: '#1C3D4A'`, `width: 'device-width'`, `initialScale: 1`, `viewportFit: 'cover'`. Add Apple Web App meta (`appleWebApp.capable`, `statusBarStyle`, `title`) and `apple-touch-icon` link.
      Files: `frontend/app/manifest.ts` (new), `frontend/app/layout.tsx`.
      Implementation Notes: Use the Next.js file convention (`MetadataRoute.Manifest`) — do not write `public/manifest.json` directly. Reference icons from `/icons/icon.svg` (any) and `/icons/icon-maskable.svg` (maskable) shipped by T15.11.
      Acceptance Criteria: Chrome DevTools → Application → Manifest panel shows all fields without warnings; `/manifest.webmanifest` returns 200 with `application/manifest+json`; theme color visible in the mobile address bar.

- [ ] **T15.10 — Service worker + offline shell + install gating**
      Description: Ship a service worker at `public/sw.js` that pre-caches an app shell on `install`, cleans old caches on `activate`, and at runtime uses (a) **network-first** for navigations with a cached `/offline` fallback, (b) **network-first** for `/api/*` with runtime cache, (c) **cache-first** for static assets (`/_next/static`, `/icons/`, fonts, images). Skip the MSW worker URL. Add a client-side `PWARegister` component that calls `navigator.serviceWorker.register('/sw.js', { scope: '/', updateViaCache: 'none' })` **only when `NODE_ENV === 'production' && NEXT_PUBLIC_DEMO_MODE !== 'true'`** (MSW owns the worker slot in demo mode). Add `next.config.ts` headers for `/sw.js` (`Content-Type: application/javascript`, `Cache-Control: no-cache, no-store, must-revalidate`, `Service-Worker-Allowed: /`). Ship a static `app/offline/page.tsx`.
      Files: `frontend/public/sw.js` (new), `frontend/components/PWARegister.tsx` (new), `frontend/app/offline/page.tsx` (new), `frontend/next.config.ts`, `frontend/app/layout.tsx`.
      Implementation Notes: Hand-rolled SW — do not introduce `next-pwa` or `serwist` (Next 16 Turbopack support is not yet stable). Bump a `VERSION` constant in `sw.js` to force cache invalidation on releases. Never cache `/sw.js` or `/mockServiceWorker.js`.
      Acceptance Criteria: After `npm run build && NEXT_PUBLIC_DEMO_MODE=false npm run start`, DevTools → Application → Service Workers shows `/sw.js` activated; turning off the network and reloading a cached page works; visiting an uncached page offline renders the `/offline` shell; in dev (`npm run dev` with demo mode) no SW registers and MSW continues to work.

- [ ] **T15.11 — PWA icon set + Apple touch + favicon**
      Description: Add the icon assets referenced by the manifest and layout: `public/icons/icon.svg` (any-purpose, ICA mark on brand teal background), `public/icons/icon-maskable.svg` (full-bleed safe area), plus raster equivalents `icon-192.png`, `icon-512.png`, and `apple-touch-icon.png` (180×180) for older Android launchers and iOS install previews. Document regeneration steps in `public/icons/README.md`.
      Files: `frontend/public/icons/icon.svg` (new), `frontend/public/icons/icon-maskable.svg` (new), `frontend/public/icons/icon-192.png` (new), `frontend/public/icons/icon-512.png` (new), `frontend/public/icons/apple-touch-icon.png` (new), `frontend/public/icons/README.md` (new), `frontend/app/manifest.ts`, `frontend/app/layout.tsx`.
      Implementation Notes: Generate PNGs from the SVG source with `npx pwa-asset-generator icon.svg .` or https://realfavicongenerator.net/. Maskable variant must have ≥10% safe-area padding (Android adaptive icon spec).
      Acceptance Criteria: Lighthouse PWA audit passes "Installable" + "PWA Optimized" categories; Chrome on Android shows the maskable icon correctly on the home screen; iOS "Add to Home Screen" shows the apple-touch-icon (not a generic screenshot).
