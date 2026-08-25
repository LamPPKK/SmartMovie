CREATE TABLE IF NOT EXISTS catalog_change_cursors (
    kind TEXT PRIMARY KEY CHECK (kind IN ('movie', 'tv', 'person')),
    window_date TEXT NOT NULL,
    next_page INTEGER NOT NULL CHECK (next_page >= 1),
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS catalog_entity_revisions (
    entity_key TEXT PRIMARY KEY,
    revision TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS catalog_entity_revisions_updated_idx
    ON catalog_entity_revisions (updated_at);
