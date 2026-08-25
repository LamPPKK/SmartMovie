import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const migrationsDirectory = join(scriptDirectory, "..", "migrations");
const migrationFiles = readdirSync(migrationsDirectory)
  .filter((file) => file.endsWith(".sql"))
  .sort();

if (migrationFiles.length === 0) {
  throw new Error("No D1 migrations found.");
}

const database = new DatabaseSync(":memory:");

try {
  // Applying the full sequence twice catches non-idempotent local migrations
  // before a staging or production deployment attempts them.
  for (let pass = 0; pass < 2; pass += 1) {
    for (const file of migrationFiles) {
      database.exec(readFileSync(join(migrationsDirectory, file), "utf8"));
    }
  }

  const integrity = database.prepare("PRAGMA integrity_check").get();
  if (integrity?.integrity_check !== "ok") {
    throw new Error(`SQLite integrity check failed: ${JSON.stringify(integrity)}`);
  }

  const expectedTables = [
    "account_mutations",
    "auth_attempts",
    "auth_housekeeping",
    "catalog_change_cursors",
    "catalog_entity_revisions",
    "sessions",
  ];
  const tables = new Set(
    database
      .prepare("SELECT name FROM sqlite_schema WHERE type = 'table'")
      .all()
      .map((row) => row.name),
  );
  const missingTables = expectedTables.filter((table) => !tables.has(table));

  if (missingTables.length > 0) {
    throw new Error(`Missing migrated tables: ${missingTables.join(", ")}`);
  }

  console.log(
    `Validated ${migrationFiles.length} D1 migrations twice; SQLite integrity and required tables are valid.`,
  );
} finally {
  database.close();
}
