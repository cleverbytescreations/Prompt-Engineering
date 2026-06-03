-- =============================================================================
-- ICA Restricted Legal Platform — PostgreSQL DDL
-- Aligned to Solution-Architecture-Document.md §6 and implementation-plan.md
-- "Data Model — Table Schemas".
--
-- Scope:
--   Phase 1 (MVP): core platform tables (auth, content, moderation, notifications,
--                  outbox, audit/versioning, admin config).
--   Phase 2 (forward-prep): knowledge_articles, question_comments, ai_usage_events
--                  — created up-front so feature flags can ship without migrations.
--
-- Conventions:
--   * snake_case table and column names, plural table names
--   * primary keys UUID v4 (gen_random_uuid) unless reference data uses natural keys
--   * status values lowercase ('pending', 'approved', ...) per SAD/plan
--   * audit columns: created_at, updated_at (TIMESTAMPTZ, default now())
--   * append-only tables (moderation_logs, content_versions, outbox_events) carry
--     only created_at; application role must not be granted UPDATE/DELETE.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email

-- =============================================================================
-- 1. Reference / lookup data
-- =============================================================================

-- ISO 3166-1 alpha-2 country reference. Managed by Admin; never hard-deleted.
CREATE TABLE countries (
    code        CHAR(2) PRIMARY KEY,                         -- ISO 3166-1 alpha-2
    name        TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Hierarchical content categorisation. Scoped to a content type, or NULL = global.
CREATE TABLE categories (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    parent_id     UUID REFERENCES categories(id) ON DELETE SET NULL,
    content_type  TEXT CHECK (content_type IN ('document','question','news','post')),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (content_type, name, parent_id)
);
CREATE INDEX idx_categories_parent       ON categories(parent_id);
CREATE INDEX idx_categories_content_type ON categories(content_type) WHERE content_type IS NOT NULL;

-- Flat tag list shared across documents, questions, posts.
CREATE TABLE tags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 2. Identity, organisations, invites, token revocation
-- =============================================================================

CREATE TABLE organizations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    max_users   INTEGER NOT NULL DEFAULT 100 CHECK (max_users > 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_by  UUID,                                        -- FK added after users table
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_organizations_name_active ON organizations (lower(name)) WHERE is_active = TRUE;

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           CITEXT UNIQUE,                           -- nullable post-anonymisation
    password_hash   TEXT,                                    -- nullable for SSO future; required for password auth
    full_name       TEXT,                                    -- nullable post-anonymisation
    role            TEXT NOT NULL CHECK (role IN ('admin','moderator','member')),
    org_id          UUID NOT NULL REFERENCES organizations(id),
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','inactive','deleted')),
    preferred_lang  TEXT NOT NULL DEFAULT 'en',              -- BCP-47; 'en' | 'es' | 'fr'
    avatar_url      TEXT,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_org_status ON users(org_id, status);
CREATE INDEX idx_users_role       ON users(role) WHERE status = 'active';

-- Defer organizations.created_by FK until users exists.
ALTER TABLE organizations
    ADD CONSTRAINT fk_organizations_created_by
    FOREIGN KEY (created_by) REFERENCES users(id);

-- Single-use, org-scoped invite codes. Never hard-deleted (audit trail).
CREATE TABLE invites (
    code        TEXT PRIMARY KEY,
    org_id      UUID NOT NULL REFERENCES organizations(id),
    invited_email CITEXT,
    invited_role TEXT CHECK (invited_role IN ('admin','moderator','member')),
    created_by  UUID NOT NULL REFERENCES users(id),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    used_by     UUID REFERENCES users(id),
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_invites_org_validity ON invites(org_id, expires_at, used_at);

-- JWT logout invalidation. JTI of revoked access/refresh tokens.
-- Validator checks this table on every request while the token has not yet expired.
-- Nightly Celery job DELETEs WHERE expires_at < now() (see §6.5 maintenance).
CREATE TABLE revoked_tokens (
    token_jti   TEXT PRIMARY KEY,                            -- JWT 'jti' claim
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_type  TEXT NOT NULL CHECK (token_type IN ('access','refresh')),
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_revoked_tokens_expires ON revoked_tokens(expires_at);

-- User interest preferences set in onboarding (`/auth/me/preferences`).
CREATE TABLE user_preferences (
    user_id                  UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    interest_country_codes   CHAR(2)[] NOT NULL DEFAULT '{}',
    interest_category_ids    UUID[]    NOT NULL DEFAULT '{}',
    receive_digest_email     BOOLEAN   NOT NULL DEFAULT TRUE,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Short-lived (1h) opaque tokens for /auth/forgot-password → /auth/reset-password.
-- Stored as SHA-256 hash; raw token only sent via email.
-- Nightly Celery job DELETEs WHERE expires_at < now() OR used_at IS NOT NULL.
CREATE TABLE password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);
CREATE INDEX idx_password_reset_tokens_active  ON password_reset_tokens(token_hash, expires_at);

-- =============================================================================
-- 3. Legal Document Repository
-- =============================================================================

CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    summary         TEXT,
    country         CHAR(2) NOT NULL REFERENCES countries(code),
    category_id     UUID REFERENCES categories(id),
    law_type        TEXT,
    language        TEXT NOT NULL DEFAULT 'en',              -- BCP-47
    -- Source per DC-3: either uploaded file (file_key) or external_url, never both.
    source_type     TEXT NOT NULL DEFAULT 'uploaded'
                    CHECK (source_type IN ('uploaded','external_url')),
    file_key        TEXT,                                    -- S3/MinIO object key
    external_url    TEXT,
    -- Moderation lifecycle
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    -- Law validity lifecycle (separate from moderation status)
    law_status      TEXT NOT NULL DEFAULT 'active'
                    CHECK (law_status IN ('active','retracted','superseded')),
    replacement_document_id UUID REFERENCES documents(id),
    retracted_at    TIMESTAMPTZ,
    retraction_reason TEXT,
    submitted_by    UUID NOT NULL REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    approved_by     UUID REFERENCES users(id),
    version         INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (source_type = 'uploaded'     AND file_key     IS NOT NULL AND external_url IS NULL) OR
        (source_type = 'external_url' AND external_url IS NOT NULL AND file_key     IS NULL)
    )
);

-- Document metadata for chunks. Vectors live in OpenSearch (ica_document_chunks).
-- This is the authoritative inventory; OpenSearch is a derived index.
CREATE TABLE document_chunks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index     INTEGER NOT NULL CHECK (chunk_index >= 0),  -- 0-based within document
    chunk_text      TEXT NOT NULL,                              -- extracted text (~512 tokens)
    token_count     INTEGER NOT NULL CHECK (token_count >= 0),
    page_number     INTEGER CHECK (page_number > 0),
    section_title   TEXT,
    is_embedded     BOOLEAN NOT NULL DEFAULT FALSE,             -- set by embedding_generation_job
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (document_id, chunk_index)
);
CREATE INDEX idx_document_chunks_doc     ON document_chunks(document_id);
CREATE INDEX idx_document_chunks_pending ON document_chunks(is_embedded) WHERE is_embedded = FALSE;

CREATE TABLE document_tags (
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    tag_id      UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (document_id, tag_id)
);
CREATE INDEX idx_document_tags_tag ON document_tags(tag_id);

-- =============================================================================
-- 4. Q&A
-- =============================================================================

CREATE TABLE questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    country         CHAR(2) NOT NULL REFERENCES countries(code),
    category_id     UUID REFERENCES categories(id),
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged','answered','closed')),
    submitted_by    UUID NOT NULL REFERENCES users(id),
    assigned_to     UUID REFERENCES users(id),               -- expert assigned to answer
    accepted_answer_id UUID,                                 -- FK added after answers exists
    version         INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at       TIMESTAMPTZ
);

CREATE TABLE answers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id     UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    body            TEXT NOT NULL,
    posted_by       UUID NOT NULL REFERENCES users(id),
    is_accepted     BOOLEAN NOT NULL DEFAULT FALSE,
    -- is_verified set by Moderator/Admin per DC-1
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    verified_by     UUID REFERENCES users(id),
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Composite key for accepted_answer FK to guarantee answer belongs to question.
CREATE UNIQUE INDEX ux_answers_question_id_id ON answers (question_id, id);

ALTER TABLE questions
    ADD CONSTRAINT fk_questions_accepted_answer
    FOREIGN KEY (id, accepted_answer_id) REFERENCES answers(question_id, id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE question_tags (
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    tag_id      UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (question_id, tag_id)
);
CREATE INDEX idx_question_tags_tag ON question_tags(tag_id);

-- =============================================================================
-- 5. News
-- =============================================================================

-- is_featured / featured_order back PATCH /news/{id}/feature (GAP-04).
-- Phase 2 pinning UI uses featured_order ASC (NULLs last).
CREATE TABLE news_articles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    summary         TEXT,
    source_url      TEXT,
    country         CHAR(2) NOT NULL REFERENCES countries(code),
    category_id     UUID REFERENCES categories(id),
    language        TEXT NOT NULL DEFAULT 'en',
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    is_featured     BOOLEAN NOT NULL DEFAULT FALSE,
    featured_order  INTEGER,                                 -- lower = higher; null = not featured
    submitted_by    UUID NOT NULL REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    approved_by     UUID REFERENCES users(id),
    published_at    TIMESTAMPTZ,
    version         INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 6. Social feed (posts, comments, likes)
-- =============================================================================

CREATE TABLE posts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    body            TEXT NOT NULL,
    category_id     UUID REFERENCES categories(id),
    submitted_by    UUID NOT NULL REFERENCES users(id),
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','revision_required','flagged')),
    -- Denormalised counter; updated atomically via UPDATE ... SET likes_count = likes_count + 1.
    -- Source of truth remains post_likes; under viral load see SAD §6.1 (Redis flush strategy).
    likes_count     INTEGER NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE comments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    author_id   UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comments_post ON comments(post_id, created_at);

-- Per-user like tracking for idempotent like/unlike toggle (H-3).
-- POST /posts/{id}/like checks this table before incrementing posts.likes_count.
CREATE TABLE post_likes (
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE post_tags (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);
CREATE INDEX idx_post_tags_tag ON post_tags(tag_id);

-- =============================================================================
-- 7. Notifications
-- =============================================================================

CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,                           -- e.g. 'question_answered','news_published'
    reference_type  TEXT,                                    -- 'document'|'question'|'news'|'post'|...
    reference_id    UUID,
    title           TEXT,
    body            TEXT,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Composite subscription filter feeding news_broadcast_job.
-- A row with NULL country or NULL category means "any". Coalesce in PK so that
-- the (user_id, NULL, NULL) "subscribe to all" row is uniquely representable.
CREATE TABLE notification_preferences (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    country_code    CHAR(2) REFERENCES countries(code),      -- null = all countries
    category_id     UUID REFERENCES categories(id),          -- null = all categories
    email_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    in_app_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, COALESCE(country_code, '--'), COALESCE(category_id::text, '--'))
);

-- =============================================================================
-- 8. Audit, versioning, transactional outbox
-- =============================================================================

-- Append-only content version history. Never UPDATEd or DELETEd by application role.
-- (NG-7) snapshot stores metadata DIFF ONLY (≤2KB) — never document body or chunk text.
CREATE TABLE content_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type     TEXT NOT NULL CHECK (entity_type IN ('document','question','news','post')),
    entity_id       UUID NOT NULL,
    version_number  INTEGER NOT NULL CHECK (version_number > 0),
    snapshot        JSONB NOT NULL
                    CHECK (octet_length(snapshot::text) <= 2048),
    edited_by       UUID NOT NULL REFERENCES users(id),
    edited_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_type, entity_id, version_number)
);
-- NG-13: range-partition by edited_at quarterly when row count > 1M.

-- Immutable moderation audit log. Range-partitioned by created_at.
-- Older partitions archived to S3 + Parquet via pg_dump after compliance retention period.
CREATE TABLE moderation_logs (
    id          UUID NOT NULL DEFAULT gen_random_uuid(),
    actor_id    UUID NOT NULL REFERENCES users(id),
    action      TEXT NOT NULL
                CHECK (action IN ('approve','reject','request_changes','flag','retract','submit','assign','comment','escalate','supersede')),
    entity_type TEXT NOT NULL,
    entity_id   UUID NOT NULL,
    remarks     TEXT,                                        -- required by app for reject / retract
    metadata    JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Default catch-all partition; Alembic adds quarterly partitions ahead of time.
CREATE TABLE moderation_logs_default PARTITION OF moderation_logs DEFAULT;

-- Initial quarterly partition (Q2 2026) — additional quarters created by migration.
CREATE TABLE moderation_logs_2026_q2 PARTITION OF moderation_logs
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

-- Transactional outbox for domain events. Written atomically with state changes.
-- Polled by Celery beat every 5s (priority-ordered, FOR UPDATE SKIP LOCKED).
-- State machine: PENDING → IN_PROGRESS → PUBLISHED, or → FAILED → DEAD_LETTER (NG-11).
-- payload capped at 4KB (R4-G11). Priority: 0=critical, 5=default, 10=low (R5-G01).
CREATE TABLE outbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      TEXT NOT NULL,
    entity_type     TEXT,
    entity_id       UUID,
    payload         JSONB NOT NULL DEFAULT '{}'::JSONB
                    CHECK (octet_length(payload::text) <= 4096),    -- payload is capped at 4KB — never embed document body or chunk text here, only IDs and metadata
    priority        SMALLINT NOT NULL DEFAULT 5,            -- lower = higher priority; 0=critical, 5=default, 10=low 
    status          TEXT NOT NULL DEFAULT 'PENDING'     --The poller transitions: PENDING → IN_PROGRESS → PUBLISHED, or → FAILED → DEAD_LETTER after retries
                    CHECK (status IN ('PENDING','IN_PROGRESS','PUBLISHED','FAILED','DEAD_LETTER')),
    retry_count     INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    last_error      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),     -- used by outbox_stuck_recovery_job
    published_at    TIMESTAMPTZ
)
WITH (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_vacuum_cost_delay   = 10
);

-- =============================================================================
-- 9. Admin / platform configuration
-- =============================================================================

-- Platform configuration key-value store (GAP-02).
-- Sensitive values (API keys) are stored as env-var reference names, not raw values.
CREATE TABLE platform_config (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    value_type  TEXT NOT NULL CHECK (value_type IN ('string','integer','float','boolean','json')),
    description TEXT,
    updated_by  UUID REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 10. Phase 2 forward-prep tables
--     Created up-front so feature flags can ship without DDL migrations.
-- =============================================================================

-- Phase 2: Q&A pair promoted to a curated knowledge article.
CREATE TABLE knowledge_articles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL UNIQUE REFERENCES questions(id),
    promoted_by UUID NOT NULL REFERENCES users(id),
    promoted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Phase 2: discussion thread on approved questions (no moderation; not indexed).
CREATE TABLE question_comments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    author_id   UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_question_comments_question ON question_comments(question_id, created_at);

-- Phase 2: per-operation AI usage row for GET /admin/ai-usage (M-5).
CREATE TABLE ai_usage_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type          TEXT NOT NULL
                        CHECK (event_type IN ('rag_query','content_flag','summarize','translation','embedding')),
    user_id             UUID REFERENCES users(id),
    input_tokens        INTEGER NOT NULL DEFAULT 0 CHECK (input_tokens  >= 0),
    output_tokens       INTEGER NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
    embedding_calls     INTEGER NOT NULL DEFAULT 0 CHECK (embedding_calls >= 0),
    model               TEXT,
    estimated_cost_usd  NUMERIC(10,6),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_usage_events_created ON ai_usage_events(created_at);
CREATE INDEX idx_ai_usage_events_type    ON ai_usage_events(event_type, created_at);

-- =============================================================================
-- 11. Index strategy (SAD §6.4)
--     Composite indexes ordered to serve the most common WHERE/ORDER BY queries.
-- =============================================================================

-- Outbox poller hot path (CRITICAL)
CREATE INDEX idx_outbox_pending
    ON outbox_events(status, priority, created_at)
    WHERE status IN ('PENDING','IN_PROGRESS');

-- Notifications feed (CRITICAL)
CREATE INDEX idx_notifications_user
    ON notifications(user_id, is_read, created_at DESC);

-- Notification preferences fan-out (CRITICAL)
CREATE INDEX idx_notification_prefs_country_category
    ON notification_preferences(country_code, category_id);

-- Documents (CRITICAL + high)
CREATE INDEX idx_documents_status_country_category
    ON documents(status, country, category_id, created_at DESC);
CREATE INDEX idx_documents_submitted
    ON documents(submitted_by, status);
CREATE INDEX idx_documents_law_status
    ON documents(law_status) WHERE law_status <> 'active';

-- Questions (CRITICAL + high)
CREATE INDEX idx_questions_status_country_category
    ON questions(status, country, category_id, created_at DESC);
CREATE INDEX idx_questions_assigned
    ON questions(assigned_to, status) WHERE assigned_to IS NOT NULL;
CREATE INDEX idx_questions_submitted
    ON questions(submitted_by, status);

-- Answers
CREATE INDEX idx_answers_question_accepted
    ON answers(question_id, is_accepted);
CREATE INDEX idx_answers_question_verified
    ON answers(question_id, is_verified);

-- News (high)
CREATE INDEX idx_news_status_featured_country
    ON news_articles(status, is_featured, country, created_at DESC);

-- Posts feed (CRITICAL)
CREATE INDEX idx_posts_status_created
    ON posts(status, created_at DESC, id DESC);

-- Moderation logs lookup
CREATE INDEX idx_moderation_logs_entity
    ON moderation_logs(entity_type, entity_id, created_at DESC);

-- Content version history
CREATE INDEX idx_content_versions_entity
    ON content_versions(entity_type, entity_id, version_number DESC);

-- =============================================================================
-- 12. Seed / reference data
-- =============================================================================

-- Initial ISO 3166-1 alpha-2 countries (extend via Admin Taxonomy UI).
INSERT INTO countries(code, name) VALUES
    ('US','United States'),
    ('GB','United Kingdom'),
    ('CA','Canada'),
    ('AU','Australia'),
    ('IN','India'),
    ('ES','Spain'),
    ('FR','France'),
    ('DE','Germany'),
    ('MX','Mexico'),
    ('BR','Brazil'),
    ('AR','Argentina'),
    ('JP','Japan'),
    ('SG','Singapore'),
    ('AE','United Arab Emirates'),
    ('ZA','South Africa')
ON CONFLICT (code) DO NOTHING;

-- Platform configuration seed (applied via Alembic; values are runtime-tunable).
INSERT INTO platform_config(key, value, value_type, description) VALUES
    ('ai_confidence_high',   '0.75',                 'float',   'RAG high-confidence threshold for LLM generation'),
    ('ai_confidence_low',    '0.50',                 'float',   'RAG low-confidence threshold; below routes to expert review'),
    ('invite_expiry_hours',  '72',                   'integer', 'Default invite code validity (hours)'),
    ('supported_languages',  '["en","es","fr"]',     'json',    'Active BCP-47 language codes for translation'),
    ('max_content_per_org',  '500',                  'integer', 'Max approved content items per organisation'),
    ('moderation_sla_hours', '48',                   'integer', 'Target moderation review SLA (display only)')
ON CONFLICT (key) DO NOTHING;

COMMIT;

-- =============================================================================
-- Post-deploy operational notes (not executed here; applied separately):
--   * GRANT INSERT ON outbox_events, content_versions, moderation_logs TO ica_app;
--     (no UPDATE/DELETE for the application role on append-only tables)
--   * Per-table autovacuum overrides for notifications, revoked_tokens, posts
--     (see SAD §6.5 — applied via separate ALTER TABLE migrations).
--   * Quarterly moderation_logs partitions created proactively by Alembic.
--   * pg_stat_statements enabled via RDS parameter group at instance provisioning.
-- =============================================================================
