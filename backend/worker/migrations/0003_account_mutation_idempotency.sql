CREATE TABLE IF NOT EXISTS account_mutations (
    account_id INTEGER NOT NULL,
    mutation_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    response_json TEXT,
    response_status INTEGER,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    PRIMARY KEY (account_id, mutation_id)
);

CREATE INDEX IF NOT EXISTS account_mutations_expiry_idx ON account_mutations (created_at);
