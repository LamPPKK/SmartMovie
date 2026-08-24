CREATE TABLE IF NOT EXISTS auth_attempts (
    id TEXT PRIMARY KEY,
    state_hash TEXT NOT NULL,
    request_token_encrypted TEXT NOT NULL,
    return_uri TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('browser', 'tv', 'web')),
    device_code_hash TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'denied', 'completed', 'expired')),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    approved_at INTEGER,
    completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS auth_attempts_expiry_idx ON auth_attempts (expires_at);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    account_object_id TEXT NOT NULL,
    account_id INTEGER NOT NULL,
    access_token_encrypted TEXT NOT NULL,
    v3_session_encrypted TEXT NOT NULL,
    csrf_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER
);

CREATE INDEX IF NOT EXISTS sessions_account_idx ON sessions (account_object_id);
CREATE INDEX IF NOT EXISTS sessions_expiry_idx ON sessions (expires_at);
