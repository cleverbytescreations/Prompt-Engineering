# GDPR Rule Implementation Plan — Phase 1

> Purpose: bring **all** GDPR obligations into Phase 1 scope. Today Phase 1 covers security
> (Art. 32) and erasure-by-anonymisation (Art. 17), but **data portability/access is deferred
> to Phase 2** and **consent, privacy notice, restriction/objection, and breach-notification
> have no task at all**. This plan closes every gap.
>
> Drivers already in the docs: AG-7 ("enforce data privacy and GDPR compliance by design"),
> requirement CO-1, SAD §7.6. Conflicting items to be revised: requirement **A-6** and
> assumption that "full GDPR tooling … is a Phase 2 obligation".
>
> Task IDs and the Description / Files / Implementation Notes / Acceptance Criteria format
> mirror `PHASE_1_API_TASK_CHECKLIST.md` so tasks can be pasted straight into the checklists.

---

## 1. GDPR coverage matrix

| GDPR requirement | Article | Current Phase 1 status | Action |
|---|---|---|---|
| Lawfulness, fairness, transparency | 5(1)(a), 13–14 | ❌ No privacy notice | **NEW** — T-B16.2, T16.2 |
| Purpose limitation | 5(1)(b) | ✅ By design | Document in Records of Processing (T-DOC8.9) |
| Data minimisation | 5(1)(c) | ✅ PII isolated to `users` (SAD §7.6) | Document only |
| Accuracy | 5(1)(d) | ✅ Profile edit — T-B1.4, T2.3 | None |
| Storage limitation | 5(1)(e) | ✅ TTL cleanup jobs T-I4.15, ISM T-D3.9 | Consolidate into Retention Policy (T-DOC8.9) |
| Integrity & confidentiality | 5(1)(f), 32 | ✅ Strong — T-S5.1…5.10 | None |
| Accountability | 5(2) | ⚠️ Audit exists; no Records of Processing | **NEW doc** — T-DOC8.9 |
| Right to be informed | 13–14 | ❌ Absent | **NEW** — T-B16.2, T16.2 |
| Right of access | 15 | ❌ Deferred to Phase 2 | **PULL FORWARD** — T-B16.1 |
| Right to rectification | 16 | ✅ T-B1.4, T2.3 | None |
| Right to erasure | 17 | ⚠️ Admin-only (`DELETE /users/{id}`); data subject cannot self-request | **EXTEND** — T-B16.3 (self-service) |
| Right to restrict processing | 18 | ❌ Absent | **NEW** — T-B16.3 |
| Right to data portability | 20 | ❌ Deferred to Phase 2 | **PULL FORWARD** — T-B16.1 |
| Right to object | 21 | ⚠️ Partial via notification prefs (T-B10.3) | **NEW** — T-B16.3 ties prefs to a consent record |
| Automated decision-making | 22 | N/A — no AI in Phase 1 | Document scope note in T-DOC8.9 |
| Consent & withdrawal | 6, 7 | ❌ Absent | **NEW** — T-B16.2 |
| Data protection by design/default | 25 | ✅ By design | Document in DPIA (T-DOC8.9) |
| Breach notification (72 h) | 33–34 | ⚠️ Detection only (Sentry, T-L6.8 alerts) | **NEW** — T-L6.9 + runbook in T-DOC8.9 |
| Records of processing | 30 | ❌ Absent | **NEW doc** — T-DOC8.9 |
| DPIA | 35 | ❌ Absent | **NEW doc** — T-DOC8.9 |
| International transfers | Ch. V | ⚠️ Region-pinned; OpenAI is Phase 2 | Document in T-DOC8.9 |

Net new work: **4 backend tasks, 1 DB task, 1 worker task, 1 security task, 1 logging task,
1 test task, 1 documentation pack, 4 frontend tasks** — plus amendments to existing tasks and
upstream docs (§4).

---

## 2. New & pulled-forward tasks

### Module 16 — GDPR & Privacy Compliance (Backend)

- [ ] **T-B16.1 — Data export endpoints (right of access + portability, Art. 15 & 20)**
      Description: `GET /users/me/export` triggers an async export job and responds `202 Accepted` + `{ job_id }`. `GET /users/me/export/{job_id}` returns job status (`pending|running|completed|failed`) and, when complete, a pre-signed S3 URL. Pulled forward verbatim from Phase 2 `T-B16.1`.
      Files: `backend/app/api/v1/users.py`, `backend/app/services/gdpr_service.py`, `backend/app/repositories/gdpr_jobs_repo.py`.
      Implementation Notes: Trigger rate-limited 1/day/user; poll endpoint 60/min/user (T-S5.11). URL TTL 24 h. Job state persisted in `gdpr_export_jobs` (T-D3.11). Worker in T-I4.16.
      Acceptance Criteria: First call returns `202` + `job_id`; polling reaches `completed` with a working pre-signed URL; second trigger within 24 h returns `429 RATE_LIMITED`.

- [ ] **T-B16.2 — Consent capture & withdrawal (Art. 6, 7, 13–14)**
      Description: Record explicit, versioned consent for `privacy_policy`, `terms_of_service`, and `email_digest`. Endpoints: `GET /users/me/consents`, `POST /users/me/consents` (grant/withdraw a consent type). Signup (`POST /auth/signup`) must record `privacy_policy` + `terms_of_service` acceptance atomically — signup is rejected without them.
      Files: `backend/app/api/v1/users.py`, `backend/app/services/consent_service.py`, `backend/app/repositories/consents_repo.py`, `backend/app/services/auth_service.py` (signup wiring).
      Implementation Notes: Each `user_consents` row stores `consent_type`, `granted` (bool), `policy_version` (string), `created_at`, `source_ip`, `user_agent` — append-only, never updated; withdrawal inserts a new row. `email_digest` consent is the lawful basis for `news_broadcast_job` (T-I4.14) — broadcast must skip users without an active `email_digest=true` row.
      Acceptance Criteria: Signup without consent flags returns `422 VALIDATION_ERROR`; withdrawing `email_digest` excludes the user from the next broadcast; consent history is fully reconstructable from append-only rows.

- [ ] **T-B16.3 — Self-service erasure, restriction & objection (Art. 17, 18, 21)**
      Description: `DELETE /users/me` — self-service account deletion reusing the anonymisation path from T-S5.10 (null PII, `status=deleted`, revoke all tokens), gated by current-password re-entry. `POST /users/me/restrict-processing` — toggles `users.processing_restricted`; while set, the account is excluded from all non-essential processing (digests, broadcasts, recommendation/embedding of *new* contributions) but content and audit records are retained.
      Files: `backend/app/api/v1/users.py`, `backend/app/services/user_service.py`, `backend/app/services/consent_service.py`.
      Implementation Notes: `DELETE /users/me` emits outbox `user.deleted` exactly as the admin path. `processing_restricted` is checked by `news_broadcast_job` (T-I4.14) and `notification_dispatch_job` (T-I4.13) alongside the consent check. Restriction is reversible; erasure is not.
      Acceptance Criteria: `DELETE /users/me` with wrong password → `401`; with correct password → PII nulled, all tokens revoked, contributions retained as "Anonymised"; a `processing_restricted` user receives no broadcast or digest but can still read the platform.

- [ ] **T-B16.4 — Breach detection hooks (Art. 33–34 technical surface)**
      Description: Wire the technical signals a breach-response process depends on: a structured `security.alert` log channel for auth-anomaly events (repeated `401`/lockout bursts, mass-export attempts, privileged-role changes) and an append-only `data_breach_log` table for the DPO to record assessed incidents (`detected_at`, `severity`, `affected_user_count`, `reported_to_authority_at`, `notes`).
      Files: `backend/app/core/logging.py`, `backend/app/services/security_event_service.py`, `backend/app/repositories/breach_log_repo.py`, `backend/alembic` (table in T-D3.11).
      Implementation Notes: No automated authority notification — the 72-hour decision is a human/DPO process documented in the breach runbook (T-DOC8.9). This task only guarantees the signals and the register exist.
      Acceptance Criteria: A burst of failed logins and a privileged role change both emit a `security.alert` log line; a row can be written to and read from `data_breach_log`.

### Database

- [ ] **T-D3.11 — GDPR migration (`gdpr_export_jobs`, `user_consents`, `data_breach_log`, `users.processing_restricted`)**
      Description: One migration adding: `gdpr_export_jobs` (`id`, `user_id`, `status`, `s3_key`, `expires_at`, `created_at`, `completed_at`); `user_consents` (`id`, `user_id`, `consent_type`, `granted`, `policy_version`, `source_ip`, `user_agent`, `created_at`); `data_breach_log` (`id`, `detected_at`, `severity`, `affected_user_count`, `reported_to_authority_at`, `notes`, `created_by`); and column `users.processing_restricted boolean NOT NULL DEFAULT false`.
      Files: `backend/alembic/versions/0007_gdpr.py`, `backend/app/models/{gdpr_export_job,user_consent,data_breach_log}.py`, `backend/app/models/user.py` (column).
      Implementation Notes: `user_consents` and `data_breach_log` are append-only — include them in the T-D3.6 `ica_app` INSERT-only grant set. Index `user_consents(user_id, consent_type, created_at DESC)` for latest-consent lookups.
      Acceptance Criteria: Fresh DB migrates clean; `alembic downgrade` rolls back; latest-consent query uses the index.

### Integration

- [ ] **T-I4.16 — `gdpr_export_job` worker**
      Description: Celery job that assembles a JSONL archive of all of the requesting user's contributions (profile, documents, questions, answers, posts, comments, news, notifications, consent history), uploads it to S3, sets `gdpr_export_jobs.status='completed'` + `s3_key`, and notifies the user (in-app + email). Pulled forward from Phase 2 `T-I4.8`.
      Files: `backend/app/workers/gdpr/export.py`.
      Implementation Notes: **Metadata only** — original PDFs are not bundled (Art. 20 is satisfied by metadata + S3 keys; bundling co-authored originals would expose third-party data). Exclude all PII belonging to other users. On failure set `status='failed'` and notify.
      Acceptance Criteria: A seeded user with content across all modules gets a JSONL archive containing every entity they authored and no other user's PII; failure path sets `failed` and notifies.

### Security

- [ ] **T-S5.11 — Rate-limit & secure the GDPR export path**
      Description: slowapi limits — `GET /users/me/export` 1/day/user, `GET /users/me/export/{job_id}` 60/min/user. Pre-signed export URL TTL = 24 h via `GDPR_EXPORT_URL_TTL`. Pulled forward from Phase 2 `T-S5.3` + `T-S5.4`.
      Files: `backend/app/core/rate_limit.py`, `backend/app/services/gdpr_service.py`, `backend/.env.example`.
      Acceptance Criteria: Second export trigger within 24 h → `429`; expired pre-signed URL returns S3 `AccessDenied`.

### Logging & Audit

- [ ] **T-L6.9 — GDPR domain-event audit**
      Description: Emit outbox events for every GDPR-relevant transition: `gdpr_export.requested`, `gdpr_export.completed`, `consent.granted`, `consent.withdrawn`, `user.processing_restricted`, `user.processing_unrestricted`. `user.deleted` already exists (T-B2.1) and covers self-service erasure.
      Files: `backend/app/services/{gdpr_service,consent_service,user_service}.py`, per the outbox pattern.
      Acceptance Criteria: Each GDPR state transition produces exactly one outbox row in the same transaction; payloads are identifiers-only per SAD §5.10.

### Testing

- [ ] **T-T7.9 — GDPR compliance test suite**
      Description: Integration tests for: export job end-to-end (request → poll → download, third-party PII excluded); consent capture at signup + withdrawal; signup rejected without consent; self-service erasure anonymisation; `processing_restricted` excludes user from broadcast/digest; export rate limit.
      Files: `backend/tests/integration/test_gdpr.py`.
      Acceptance Criteria: All scenarios pass on the dockerised PG profile; counts as the GDPR slice of the MVP acceptance gate.

### Documentation

- [ ] **T-DOC8.9 — GDPR compliance pack**
      Description: A single deliverable folder covering the non-code obligations: (1) **Privacy Notice** content (Art. 13–14) — copy consumed by T16.2; (2) **Records of Processing Activities** (Art. 30) — processing activities, data categories, purposes, lawful bases, recipients, retention, transfers; (3) **Data Retention Policy** — consolidates SAD §3.16 / §8.10 (retracted 7 yr, rejected 30 d, AI logs 30 d, backups 30 d) into one register; (4) **Breach Notification Runbook** (Art. 33–34) — detection → assessment → 72-hour authority notification → data-subject notification, referencing T-B16.4 and `data_breach_log`; (5) **DPIA** (Art. 35) — initial assessment for Phase 1 scope, including the Art. 22 "no automated decision-making in Phase 1" note; (6) **International transfer note** — region pinning, OpenAI deferred to Phase 2.
      Files: `Docs/gdpr/privacy-notice.md`, `Docs/gdpr/records-of-processing.md`, `Docs/gdpr/retention-policy.md`, `Docs/gdpr/breach-runbook.md`, `Docs/gdpr/dpia-phase1.md`.
      Acceptance Criteria: All six artefacts exist and are reviewed/signed off by the DPO before UAT; each cross-links to the implementing task ID.

### Module 16 — GDPR & Privacy (Frontend)

- [ ] **T16.1 — `/profile/export` data export page**
      Description: Page with a "Request my data" button calling `GET /users/me/export`; polls `GET /users/me/export/{job_id}` and renders the download link with a 24 h TTL hint. Pulled forward from Phase 2 `T16.1`.
      Files: `frontend/app/(app)/profile/export/page.tsx`, `frontend/components/profile/GdprExportPanel.tsx`, `frontend/hooks/useGdprExport.ts`.
      Implementation Notes: React Query `refetchInterval: 5s`; stop on terminal state. Surface `429` as "You can request one export per day".
      Acceptance Criteria: Request → polling → download link appears; second same-day request shows the rate-limit message.

- [ ] **T16.2 — Privacy notice page + signup consent**
      Description: Public `/privacy` route rendering the Privacy Notice (content from T-DOC8.9). Amend the signup form to require two consent checkboxes — "I accept the Privacy Notice" and "I accept the Terms" — with links; submit is disabled until both are ticked, and the flags are sent to `POST /auth/signup`.
      Files: `frontend/app/privacy/page.tsx`, `frontend/components/auth/SignupForm.tsx`, `frontend/messages/en.json`.
      Implementation Notes: `/privacy` is outside the `(app)` auth guard (publicly reachable). Optional `email_digest` opt-in checkbox may also appear, unticked by default (no pre-ticked consent — Art. 7).
      Acceptance Criteria: Submitting signup without both required checkboxes is blocked client-side and server-side; `/privacy` loads without authentication.

- [ ] **T16.3 — `/profile/privacy` data & consent controls page**
      Description: One page giving the data subject control over their rights: view/withdraw consents (`GET/POST /users/me/consents`), toggle "Restrict processing of my data" (`POST /users/me/restrict-processing`), a link to `/profile/export` (access/portability), and a "Delete my account" flow (`DELETE /users/me`) with password confirmation and an irreversibility warning.
      Files: `frontend/app/(app)/profile/privacy/page.tsx`, `frontend/components/profile/PrivacyControls.tsx`, `frontend/components/profile/DeleteAccountDialog.tsx`, `frontend/hooks/useConsents.ts`.
      Implementation Notes: Linked from the user menu and `/profile/edit`. Delete dialog requires typing a confirmation phrase + password. On successful delete, clear auth store and route to `/auth/login`.
      Acceptance Criteria: Each control round-trips to its endpoint; withdrawing digest consent reflects on reload; account deletion logs the user out.

- [ ] **T16.4 — GDPR notification rendering**
      Description: Render `gdpr_export.requested` / `gdpr_export.completed` notifications in the notifications list; the "completed" entry exposes the download link with a TTL hint. Pulled forward from Phase 2 `T10.2`.
      Files: `frontend/components/notifications/NotificationsList.tsx`, `frontend/components/notifications/GdprExportNotification.tsx`.
      Acceptance Criteria: A completed export surfaces a notification with a working, TTL-labelled download link.

---

## 3. Amendments to existing Phase 1 tasks

| Task | Amendment |
|---|---|
| `T-B1.2` (signup) | Persist `privacy_policy` + `terms_of_service` consent rows in the same transaction as the user row; reject signup if absent. |
| `T-B2.1` (user CRUD) | Note that the anonymisation logic is shared with the new self-service `DELETE /users/me` (T-B16.3) — extract a single `UserService.anonymise()` method. |
| `T-I4.13` (`notification_dispatch_job`) | Skip users with `processing_restricted=true` for non-essential notifications. |
| `T-I4.14` (`news_broadcast_job`) | Filter recipients by active `email_digest` consent **and** `processing_restricted=false`. |
| `T-D3.6` (role separation) | Add `user_consents` and `data_breach_log` to the INSERT-only append-only grant set. |
| `T-T7.5` (MVP acceptance) | Add a GDPR criterion referencing T-T7.9. |
| `T-DOC8.6` (API consumer guide) | Document the export, consent, and restriction endpoints. |

## 4. Amendments to upstream documents

| Document | Change |
|---|---|
| `PHASE_1_API_TASK_CHECKLIST.md` line 4 | Remove "GDPR export" from the Phase-2 exclusion list; add "Module 16 — GDPR & Privacy Compliance" to scope. |
| `PHASE_1_UI_TASK_CHECKLIST.md` line 5 | Remove `users/me/export` from the out-of-scope list; add Module 16. |
| `PHASE_2_API_TASK_CHECKLIST.md` | Delete `T-B16.1`, `T-D3.9`, `T-I4.8`, `T-S5.3`, `T-S5.4`, `T-L6.6`, `T-T7.10` (now in Phase 1); keep Phase-2 GDPR notification type registration if still needed. |
| `PHASE_2_UI_TASK_CHECKLIST.md` | Delete `T16.1`, `T10.2` (now Phase 1). |
| `requirement-document.md` A-6 | Revise: GDPR data-portability export is **Phase 1**, not Phase 2. |
| `requirement-document.md` REQ list / FE-8 | Reclassify FE-8 (GDPR export) as a Phase-1 Must-Have. |
| `Solution-Architecture-Document.md` §1616, §1828, A-6 | Move `GET /users/me/export` from "(Phase 2)" to Phase 1; expand §7.6 Data Privacy with consent, restriction, and breach handling. |

---

## 5. Sequencing & effort

Rough effort — S ≤ 1 day, M ≈ 2–3 days, L ≈ 4–5 days.

| Order | Task | Effort | Depends on |
|---|---|---|---|
| 1 | T-D3.11 — GDPR migration | S | T-D3.1 |
| 2 | T-DOC8.9 — compliance pack (start early; legal/DPO review is the long pole) | L | — |
| 3 | T-B16.2 — consent capture & withdrawal | M | T-D3.11, T-B1.2 |
| 4 | T-B16.3 — self-service erasure, restriction, objection | M | T-D3.11, T-S5.10 |
| 5 | T-I4.16 — `gdpr_export_job` worker | M | T-D3.11, T-I4.5 |
| 6 | T-B16.1 — export endpoints | S | T-I4.16 |
| 7 | T-S5.11 — rate-limit + URL TTL | S | T-B16.1 |
| 8 | T-B16.4 — breach detection hooks | S | T-D3.11, T-L6.1 |
| 9 | T-L6.9 — GDPR domain-event audit | S | T-I4.5 |
| 10 | T16.2 — privacy notice + signup consent | M | T-B16.2, T-DOC8.9 |
| 11 | T16.1 / T16.3 / T16.4 — UI export, controls, notifications | M | T-B16.1/2/3 |
| 12 | T-T7.9 — GDPR test suite | M | all backend GDPR tasks |

Estimated total: **~3 person-weeks backend + ~1 person-week frontend**, excluding DPO/legal
review turnaround on the T-DOC8.9 artefacts (start that task first).

---

## 6. Explicitly not required in Phase 1 (with rationale)

- **Cookie consent banner** — the only cookie is the strictly-necessary HttpOnly refresh-token
  cookie (T-B1.1). Under the ePrivacy Directive strictly-necessary cookies need no consent;
  it is disclosed in the Privacy Notice instead. No banner task.
- **Art. 22 automated decision-making safeguards** — Phase 1 ships no AI/RAG; nothing makes
  automated decisions about users. Recorded as a scope note in the DPIA (T-DOC8.9); revisit in
  Phase 2 when the AI layer lands.
- **Standalone admin DSAR workflow** — self-service export (T-B16.1) and self-service erasure
  (T-B16.3) satisfy access/erasure requests directly; on an invite-only org platform a separate
  admin-mediated DSAR queue is unnecessary. Revisit only if non-self-service requests appear.
- **Cross-border transfer mechanism (SCCs)** — Phase 1 keeps all data in one pinned AWS region
  with no third-country processor. The OpenAI dependency arrives in Phase 2; transfer safeguards
  are assessed then. Documented in T-DOC8.9.
