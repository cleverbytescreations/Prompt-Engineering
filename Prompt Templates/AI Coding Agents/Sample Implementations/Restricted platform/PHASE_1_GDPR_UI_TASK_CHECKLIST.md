# Implementation Task Checklist (UI Task list) — Phase 1 GDPR

> Scope: Next.js 16 (App Router) frontend work required to expose the Phase 1 GDPR features
> defined in `Docs/GDPR-rule-implementation-plan.md` — personal-data export, consent capture
> & withdrawal, the privacy notice, self-service erasure, processing restriction, and GDPR
> notification rendering. Backend/API/DB tasks live in `PHASE_1_GDPR_API_TASK_CHECKLIST.md`.
>
> Stack: Next.js 16, React, TypeScript, MUI, Tailwind, React Query, Zustand, MSW
> (`NEXT_PUBLIC_DEMO_MODE=true`), next-intl. No business logic in the UI; data fetching via
> React Query; all user-facing strings via the next-intl message catalogue.
>
> **Task ID scheme:** `T{module}.{seq}` — module = GDPR UI area (1–5). Effort tags:
> `[S]` ≤1 day, `[M]` 2–3 days, `[L]` 4–5 days. All tasks start unchecked.
>
> UI modules:
> - **Module 1 — Data Export UI** (Right of Access & Portability)
> - **Module 2 — Consent & Privacy Notice UI**
> - **Module 3 — Privacy & Data Controls UI** (erasure, restriction, objection)
> - **Module 4 — GDPR Notifications UI**
> - **Module 5 — Cross-cutting UI** (i18n, testing, accessibility, states)

---

## 1. Frontend Tasks

### Module 1 — Data Export UI

- [ ] **T1.1 [S] — Typed API client functions for export endpoints**
      Description: Add the `lib/api` functions for the GDPR export endpoints.
      Files / Components to be changed: `frontend/lib/api/gdpr.ts`, `frontend/types/gdpr.ts`.
      Implementation Notes: `requestDataExport()` → `POST`-style call to `GET /users/me/export` returning `{ job_id, status }`; `getExportStatus(jobId)` → `GET /users/me/export/{job_id}` returning `{ job_id, status, download_url?, expires_at? }`. Define `ExportJobStatus = 'pending' | 'running' | 'completed' | 'failed'`. Reuse the shared typed client (refresh-on-401, error-envelope decode). Map `429` to a typed `ApiError` with `error_code: 'RATE_LIMITED'`.
      Acceptance Criteria: Both functions are typed end-to-end; a `429` surfaces a typed `ApiError`.

- [ ] **T1.2 [S] — `useGdprExport` React Query hook**
      Description: Hook that triggers an export and polls until a terminal state.
      Files / Components to be changed: `frontend/hooks/useGdprExport.ts`.
      Implementation Notes: `useMutation` for the trigger; `useQuery` for status with `refetchInterval: 5000` that **stops on `completed`/`failed`** (`refetchInterval: (data) => isTerminal ? false : 5000`). Do not rely on window-focus refetch. Expose `request()`, `status`, `downloadUrl`, `expiresAt`, `isPolling`, `error`.
      Acceptance Criteria: After `request()` the hook polls every 5 s and stops once the job reaches `completed` or `failed`.

- [ ] **T1.3 [M] — `/profile/export` page + `GdprExportPanel`**
      Description: Authenticated page letting a user request and download their personal data.
      Files / Components to be changed: `frontend/app/(app)/profile/export/page.tsx`, `frontend/components/profile/GdprExportPanel.tsx`.
      Implementation Notes: "Request my data" button → `useGdprExport.request()`. Show a progress state while `pending`/`running`; on `completed` render a download button (`download_url`) with a "link valid for 24 hours" hint; on `failed` show an `ErrorState` with retry. Surface `429` as "You can request one export per day." Explain that the archive contains metadata only (no original PDFs).
      Acceptance Criteria: Request → progress → download link appears; a same-day second request shows the rate-limit message; failure shows retry.

- [ ] **T1.4 [S] — MSW handlers + fixtures for export endpoints**
      Description: Demo-mode mocks for the export flow.
      Files / Components to be changed: `frontend/mocks/handlers/gdpr.ts`, `frontend/mocks/data/gdpr.ts`, `frontend/mocks/browser.ts`.
      Implementation Notes: Mock `GET /users/me/export` (returns a job, `202`) and `GET /users/me/export/{job_id}` (advances `pending → running → completed` over a few polls, then returns a stable fake `download_url`). Add a handler variant returning `429` for the rate-limit demo.
      Acceptance Criteria: With `NEXT_PUBLIC_DEMO_MODE=true` the export page completes end-to-end against mocks.

### Module 2 — Consent & Privacy Notice UI

- [ ] **T2.1 [M] — Public `/privacy` page (Privacy Notice)**
      Description: Publicly reachable page rendering the Privacy Notice.
      Files / Components to be changed: `frontend/app/privacy/page.tsx`, `frontend/components/legal/PrivacyNotice.tsx`, `frontend/middleware.ts`.
      Implementation Notes: Render the Privacy Notice content authored in `Docs/gdpr/privacy-notice.md` (API task T5.8.1) — keep copy in the next-intl catalogue or a typed content module. The route must sit **outside the `(app)` auth guard**; add `/privacy` to the public-path allowlist in `middleware.ts`. Page must be linkable from the signup form and the footer.
      Acceptance Criteria: `/privacy` loads without authentication; content is readable and responsive at 375 px.

- [ ] **T2.2 [M] — Signup consent checkboxes**
      Description: Add required consent capture to the signup form.
      Files / Components to be changed: `frontend/components/auth/SignupForm.tsx`, `frontend/app/(auth)/auth/signup/page.tsx`.
      Implementation Notes: Two **required, unticked** checkboxes — "I accept the [Privacy Notice](/privacy)" and "I accept the Terms" — plus one **optional, unticked** "Email me news digests" checkbox (Art. 7 — no pre-ticked consent). The submit button stays disabled until both required boxes are ticked; client-side validation mirrors the server `CONSENT_REQUIRED` error. Links open `/privacy` (and terms) in a new tab.
      Acceptance Criteria: Signup cannot be submitted without both required checkboxes; the digest checkbox defaults to off.

- [ ] **T2.3 [S] — Extend signup API payload & types**
      Description: Send the consent flags to the backend on signup.
      Files / Components to be changed: `frontend/lib/api/auth.ts`, `frontend/types/auth.ts`.
      Implementation Notes: Add `accept_privacy_policy`, `accept_terms`, `accept_email_digest` to the signup request type and payload. Decode a `422 CONSENT_REQUIRED` envelope into a form-level error.
      Acceptance Criteria: A successful signup sends all three flags; a server `CONSENT_REQUIRED` maps to a visible form error.

- [ ] **T2.4 [S] — MSW handler update for signup consent**
      Description: Reflect the consent contract in demo mode.
      Files / Components to be changed: `frontend/mocks/handlers/auth.ts`.
      Implementation Notes: The mocked `POST /auth/signup` returns `422 CONSENT_REQUIRED` when either required flag is missing/false; otherwise succeeds.
      Acceptance Criteria: Demo-mode signup without consent reproduces the `422` path.

### Module 3 — Privacy & Data Controls UI

- [ ] **T3.1 [S] — Typed API client functions for consent, restriction & erasure**
      Description: `lib/api` functions for the remaining GDPR endpoints.
      Files / Components to be changed: `frontend/lib/api/gdpr.ts`, `frontend/types/gdpr.ts`.
      Implementation Notes: `getConsents()` → `GET /users/me/consents`; `updateConsent({ consent_type, granted })` → `POST /users/me/consents`; `setProcessingRestriction(restricted)` → `POST /users/me/restrict-processing`; `deleteOwnAccount(password)` → `DELETE /users/me`. Types `ConsentType`, `ConsentItem`.
      Acceptance Criteria: All four functions are typed and decode the standard error envelope.

- [ ] **T3.2 [S] — `useConsents` & `useAccountControls` hooks**
      Description: React Query hooks backing the privacy controls page.
      Files / Components to be changed: `frontend/hooks/useConsents.ts`, `frontend/hooks/useAccountControls.ts`.
      Implementation Notes: `useConsents` — query for current consents + mutation to toggle one, with optimistic update and invalidation. `useAccountControls` — mutations for restriction toggle and account deletion; on deletion success clear the Zustand auth store and route to `/auth/login`.
      Acceptance Criteria: Toggling a consent updates the UI optimistically and reconciles with the server response.

- [ ] **T3.3 [M] — `/profile/privacy` page + `PrivacyControls`**
      Description: One page where the data subject exercises their GDPR rights.
      Files / Components to be changed: `frontend/app/(app)/profile/privacy/page.tsx`, `frontend/components/profile/PrivacyControls.tsx`.
      Implementation Notes: Sections — (1) **Consents**: list each consent with grant/withdraw toggles (`privacy_policy`/`terms` shown read-only with a note that withdrawal = account deletion; `email_digest` toggleable); (2) **Restrict processing**: a switch wired to `setProcessingRestriction` with an explanatory caption; (3) **Export my data**: a link/CTA to `/profile/export`; (4) **Delete my account**: opens `DeleteAccountDialog` (T3.4). Use shared `LoadingSkeleton`/`ErrorState` primitives.
      Acceptance Criteria: Each control round-trips to its endpoint; withdrawing `email_digest` and reloading shows the change persisted.

- [ ] **T3.4 [M] — `DeleteAccountDialog` (self-service erasure)**
      Description: Confirmation dialog for irreversible account deletion.
      Files / Components to be changed: `frontend/components/profile/DeleteAccountDialog.tsx`.
      Implementation Notes: Require the user to (a) type a confirmation phrase (e.g. "DELETE") and (b) enter their current password. Show a clear irreversibility warning ("your profile is anonymised; your contributions remain attributed to 'Anonymised'"). On success clear the auth store, drop the session, and route to `/auth/login`. Map `401` to an inline "Incorrect password" error; map `429` to a rate-limit message.
      Acceptance Criteria: Deletion proceeds only with the correct phrase + password; a wrong password shows an inline error; success logs the user out.

- [ ] **T3.5 [S] — Navigation links to `/profile/privacy`**
      Description: Make the privacy controls discoverable.
      Files / Components to be changed: `frontend/components/layout/Header.tsx`, `frontend/app/(app)/profile/edit/page.tsx`.
      Implementation Notes: Add a "Privacy & data" entry to the user menu and a link from `/profile/edit`. `/profile/privacy` must also be reachable by direct URL.
      Acceptance Criteria: The page is reachable from the user menu, from `/profile/edit`, and by direct URL.

- [ ] **T3.6 [S] — MSW handlers for consent, restriction & erasure**
      Description: Demo-mode mocks for the privacy controls.
      Files / Components to be changed: `frontend/mocks/handlers/gdpr.ts`, `frontend/mocks/data/gdpr.ts`.
      Implementation Notes: Mock `GET/POST /users/me/consents`, `POST /users/me/restrict-processing`, and `DELETE /users/me` (incl. a `401` variant for the wrong-password path). Persist toggles in the in-memory fixture for the session so reloads reflect changes.
      Acceptance Criteria: All privacy controls work end-to-end in demo mode, including the wrong-password error path.

### Module 4 — GDPR Notifications UI

- [ ] **T4.1 [S] — `GdprExportNotification` component + NotificationsList wiring**
      Description: Render GDPR export lifecycle events in the notifications list.
      Files / Components to be changed: `frontend/components/notifications/GdprExportNotification.tsx`, `frontend/components/notifications/NotificationsList.tsx`, `frontend/lib/notifications/types.ts`.
      Implementation Notes: Add notification types `gdpr_export_completed` and `gdpr_export_failed`. The "completed" entry exposes a download link with a "valid for 24 hours" hint; "failed" links to `/profile/export` to retry. Fall back to the generic notification renderer for unknown types.
      Acceptance Criteria: A `gdpr_export_completed` notification renders a working, TTL-labelled download link.

- [ ] **T4.2 [S] — MSW fixtures for GDPR notification types**
      Description: Seed demo notifications for the GDPR export lifecycle.
      Files / Components to be changed: `frontend/mocks/data/notifications.ts`, `frontend/mocks/handlers/notifications.ts`.
      Implementation Notes: Add `gdpr_export_completed` and `gdpr_export_failed` sample rows to the notifications fixture.
      Acceptance Criteria: The notifications page in demo mode shows both GDPR notification variants.

### Module 5 — Cross-cutting UI

- [ ] **T5.1 [S] — i18n message catalogue entries for GDPR strings**
      Description: Add all GDPR UI copy to the next-intl catalogue.
      Files / Components to be changed: `frontend/messages/en.json`.
      Implementation Notes: Namespace keys (e.g. `gdpr.export.*`, `gdpr.consent.*`, `gdpr.privacy.*`, `gdpr.delete.*`). No hard-coded user-facing strings in the new components. Lay out keys so ES/FR can be added in Phase 2 without structural change.
      Acceptance Criteria: Every new GDPR component renders strings via `useTranslations`; no literal strings remain.

- [ ] **T5.2 [M] — Unit & component tests (Vitest + RTL)**
      Description: Cover the GDPR components and hooks.
      Files / Components to be changed: `frontend/components/profile/GdprExportPanel.test.tsx`, `frontend/components/profile/PrivacyControls.test.tsx`, `frontend/components/profile/DeleteAccountDialog.test.tsx`, `frontend/components/auth/SignupForm.test.tsx`, `frontend/hooks/useGdprExport.test.ts`.
      Implementation Notes: Test the poll-until-terminal logic, signup submit-disabled-until-consented, delete dialog phrase+password gating, and consent toggle optimistic update. Mock the API layer.
      Acceptance Criteria: All tests pass; the new files meet the project's frontend coverage threshold.

- [ ] **T5.3 [S] — Playwright smoke E2E for GDPR flows**
      Description: End-to-end coverage of the GDPR journeys against MSW.
      Files / Components to be changed: `frontend/e2e/gdpr.spec.ts`, `frontend/playwright.config.ts`.
      Implementation Notes: Three flows — (1) request data export → download link appears; (2) signup blocked without consent, then succeeds with consent; (3) withdraw `email_digest` consent and delete account from `/profile/privacy`.
      Acceptance Criteria: All three flows pass headless in demo mode.

- [ ] **T5.4 [S] — Accessibility audit of GDPR pages**
      Description: Ensure the new pages meet the project a11y bar.
      Files / Components to be changed: `frontend/app/privacy/page.tsx`, `frontend/app/(app)/profile/export/page.tsx`, `frontend/app/(app)/profile/privacy/page.tsx`, `DeleteAccountDialog.tsx`.
      Implementation Notes: Keyboard navigation, focus management in the delete dialog (focus trap, return focus on close), aria labels on toggles/checkboxes, colour-contrast pass. Run `@axe-core/react` in dev.
      Acceptance Criteria: Zero critical axe violations on `/privacy`, `/profile/export`, and `/profile/privacy`.

- [ ] **T5.5 [S] — Empty/error states & responsive check for GDPR pages**
      Description: Apply shared state primitives and verify mobile layout.
      Files / Components to be changed: `GdprExportPanel.tsx`, `PrivacyControls.tsx`, `NotificationsList.tsx`.
      Implementation Notes: Use the shared `EmptyState`/`ErrorState`/`LoadingSkeleton` primitives for loading and forced-API-failure states (no bespoke "No data" strings). Verify no horizontal scroll at 375 px on all three GDPR pages.
      Acceptance Criteria: Each GDPR page renders the shared states correctly and has no horizontal scroll at 375 px.
