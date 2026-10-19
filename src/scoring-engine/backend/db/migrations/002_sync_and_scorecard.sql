-- 002: organiser-initiated Microsoft 365 sync (no partner call required) and evidence timestamps.

ALTER TABLE events ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS roster_group_id VARCHAR(100);

-- vendor: a partner's Complete click. sync: found by an organiser-initiated sync.
ALTER TABLE submissions ADD COLUMN IF NOT EXISTS source VARCHAR(16) NOT NULL DEFAULT 'vendor';
-- When the participant actually did the work (latest matching evidence), used to rank synced completions.
ALTER TABLE submissions ADD COLUMN IF NOT EXISTS evidence_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS ix_participants_event_upn ON participants (event_id, lower(upn));

CREATE TABLE IF NOT EXISTS sync_runs (
    id                   VARCHAR(36) PRIMARY KEY,
    event_id             VARCHAR(36)  NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status               VARCHAR(24)  NOT NULL DEFAULT 'queued'
                         CHECK (status IN ('queued', 'running', 'completed', 'completed_with_errors', 'failed')),
    triggered_by         VARCHAR(320) NOT NULL,
    watermark_from       TIMESTAMPTZ,              -- previous sync point (NULL on the first run)
    watermark_to         TIMESTAMPTZ,              -- evidence up to this instant has been scanned
    participants_total   INTEGER      NOT NULL DEFAULT 0,
    participants_scanned INTEGER      NOT NULL DEFAULT 0,
    participants_added   INTEGER      NOT NULL DEFAULT 0,
    steps_checked        INTEGER      NOT NULL DEFAULT 0,
    steps_skipped        INTEGER      NOT NULL DEFAULT 0,
    new_completions      INTEGER      NOT NULL DEFAULT 0,
    errors               INTEGER      NOT NULL DEFAULT 0,
    error_detail         TEXT,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    started_at           TIMESTAMPTZ,
    finished_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_sync_runs_event ON sync_runs (event_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_sync_runs_queue ON sync_runs (status, created_at);
