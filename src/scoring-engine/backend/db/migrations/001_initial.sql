-- VectorSense Labs - Scoring Engine
-- 001: initial schema
-- Applied by `python -m app.migrate`. Each file runs once, in filename order, inside a transaction.

CREATE TABLE IF NOT EXISTS integrations (
    id                  VARCHAR(36) PRIMARY KEY,
    name                VARCHAR(200) NOT NULL,
    vendor              VARCHAR(200) NOT NULL,
    client_id           VARCHAR(64)  NOT NULL UNIQUE,
    secret_hash         VARCHAR(128) NOT NULL,
    secret_hint         VARCHAR(16)  NOT NULL,
    status              VARCHAR(16)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    webhook_url         TEXT,
    webhook_secret      VARCHAR(128),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    secret_rotated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_used_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS events (
    id                  VARCHAR(36) PRIMARY KEY,
    slug                VARCHAR(80)  NOT NULL UNIQUE,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    starts_at           TIMESTAMPTZ,
    ends_at             TIMESTAMPTZ,
    status              VARCHAR(16)  NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live', 'closed')),
    public_leaderboard  BOOLEAN      NOT NULL DEFAULT TRUE,
    public_name_format  VARCHAR(24)  NOT NULL DEFAULT 'first_last_initial'
                        CHECK (public_name_format IN ('full', 'first_last_initial', 'first_only')),
    public_show_reasons BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS use_cases (
    id                  VARCHAR(36) PRIMARY KEY,
    event_id            VARCHAR(36)  NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    code                VARCHAR(80)  NOT NULL,
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    sort_order          INTEGER      NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (event_id, code)
);

CREATE TABLE IF NOT EXISTS steps (
    id                  VARCHAR(36) PRIMARY KEY,
    use_case_id         VARCHAR(36)  NOT NULL REFERENCES use_cases(id) ON DELETE CASCADE,
    code                VARCHAR(80)  NOT NULL,
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    sort_order          INTEGER      NOT NULL DEFAULT 0,
    rubric_yaml         TEXT         NOT NULL DEFAULT '',
    rubric_json         JSONB        NOT NULL DEFAULT '{"checks": []}'::jsonb,
    rubric_version      INTEGER      NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (use_case_id, code)
);

CREATE TABLE IF NOT EXISTS participants (
    id                  VARCHAR(36) PRIMARY KEY,
    event_id            VARCHAR(36)  NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    external_id         VARCHAR(200) NOT NULL,
    public_id           VARCHAR(16)  NOT NULL UNIQUE,
    first_name          VARCHAR(120),
    last_name           VARCHAR(120),
    email               VARCHAR(320),
    upn                 VARCHAR(320),
    integration_id      VARCHAR(36)  REFERENCES integrations(id) ON DELETE SET NULL,
    first_lab_started_at TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (event_id, external_id)
);
CREATE INDEX IF NOT EXISTS ix_participants_event_name ON participants (event_id, lower(first_name), lower(last_name));

CREATE TABLE IF NOT EXISTS submissions (
    id                  VARCHAR(36) PRIMARY KEY,
    event_id            VARCHAR(36)  NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    use_case_id         VARCHAR(36)  NOT NULL REFERENCES use_cases(id) ON DELETE CASCADE,
    step_id             VARCHAR(36)  NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
    participant_id      VARCHAR(36)  NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
    integration_id      VARCHAR(36)  REFERENCES integrations(id) ON DELETE SET NULL,
    idempotency_key     VARCHAR(200) NOT NULL,
    lab_profile_id      VARCHAR(200),
    lab_instance_id     VARCHAR(200),
    lab_started_at      TIMESTAMPTZ  NOT NULL,
    submitted_at        TIMESTAMPTZ  NOT NULL,
    received_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status              VARCHAR(16)  NOT NULL DEFAULT 'queued'
                        CHECK (status IN ('queued', 'evaluating', 'complete', 'incomplete', 'error')),
    reasons             JSONB        NOT NULL DEFAULT '[]'::jsonb,
    check_results       JSONB        NOT NULL DEFAULT '[]'::jsonb,
    attempts            INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    locked_at           TIMESTAMPTZ,
    evaluated_at        TIMESTAMPTZ,
    rubric_version      INTEGER      NOT NULL DEFAULT 1,
    verification_status VARCHAR(16)  NOT NULL DEFAULT 'not_required'
                        CHECK (verification_status IN ('not_required', 'pending', 'verified', 'unverified')),
    verification_checked_at TIMESTAMPTZ,
    override_by         VARCHAR(200),
    override_note       TEXT,
    UNIQUE (integration_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS ix_submissions_queue ON submissions (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS ix_submissions_event ON submissions (event_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_submissions_participant ON submissions (participant_id, step_id);
CREATE INDEX IF NOT EXISTS ix_submissions_verification ON submissions (verification_status, verification_checked_at);

-- One row per participant per step: the leaderboard reads this, never the raw submissions.
CREATE TABLE IF NOT EXISTS step_progress (
    participant_id      VARCHAR(36)  NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
    step_id             VARCHAR(36)  NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
    event_id            VARCHAR(36)  NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status              VARCHAR(16)  NOT NULL CHECK (status IN ('complete', 'incomplete', 'error')),
    attempts            INTEGER      NOT NULL DEFAULT 0,
    completed_at        TIMESTAMPTZ,
    last_submission_id  VARCHAR(36),
    verification_status VARCHAR(16)  NOT NULL DEFAULT 'not_required',
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (participant_id, step_id)
);
CREATE INDEX IF NOT EXISTS ix_step_progress_event ON step_progress (event_id);

CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id                  VARCHAR(36) PRIMARY KEY,
    integration_id      VARCHAR(36)  NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    submission_id       VARCHAR(36)  NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
    url                 TEXT         NOT NULL,
    payload             JSONB        NOT NULL,
    status              VARCHAR(16)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'failed')),
    attempts            INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_error          TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    delivered_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_webhook_queue ON webhook_deliveries (status, next_attempt_at);

CREATE TABLE IF NOT EXISTS audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    actor               VARCHAR(320) NOT NULL,
    action              VARCHAR(80)  NOT NULL,
    target_type         VARCHAR(40),
    target_id           VARCHAR(80),
    details             JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_audit_created ON audit_log (created_at DESC);
