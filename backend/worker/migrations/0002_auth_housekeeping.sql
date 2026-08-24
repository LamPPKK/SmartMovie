CREATE TABLE IF NOT EXISTS auth_housekeeping (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    last_cleanup_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO auth_housekeeping (singleton, last_cleanup_at) VALUES (1, 0);
