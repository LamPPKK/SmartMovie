import type { WorkerAccountEnv } from "./account";
import { tmdb } from "./v2";

export type CatalogChangeKind = "movie" | "tv" | "person";

interface ChangeCursorRow {
  window_date: string;
  next_page: number;
}

interface TmdbChangePage {
  page: number;
  total_pages: number;
  total_results?: number;
  results: Array<{ id?: number }>;
}

export interface CatalogChangeReport {
  scheduledDate: string;
  kinds: Array<{
    kind: CatalogChangeKind;
    pages: number;
    entities: number;
    windowDate: string;
    nextPage: number;
  }>;
}

const CHANGE_KINDS: readonly CatalogChangeKind[] = ["movie", "tv", "person"];
const DEFAULT_PAGES_PER_RUN = 3;
const MAX_PAGES_PER_RUN = 20;
const D1_ENTITY_CHUNK_SIZE = 33;
const TMDB_MAX_LOOKBACK_DAYS = 14;
const REVISION_RETENTION_SECONDS = 30 * 24 * 60 * 60;

/**
 * Polls TMDb's date-scoped change lists and advances a durable per-kind cursor.
 * Revisions use the UTC date so replaying a page is idempotent and can never
 * churn an entity's cache key more than once per day.
 */
export async function syncCatalogChanges(
  env: WorkerAccountEnv,
  scheduledTime: number,
): Promise<CatalogChangeReport> {
  const database = requireChangeDatabase(env);
  const epochSeconds = Math.floor(scheduledTime / 1_000);
  const scheduledDate = new Date(scheduledTime).toISOString().slice(0, 10);
  const pagesPerRun = configuredPagesPerRun(env.CATALOG_CHANGE_PAGES_PER_RUN);
  const reports: CatalogChangeReport["kinds"] = [];
  const failedKinds: CatalogChangeKind[] = [];
  let firstFailure: unknown;

  // Keep each cursor independent: one transient TMDb failure must not prevent
  // the other entity kinds from invalidating their cache entries.
  for (const kind of CHANGE_KINDS) {
    try {
      reports.push(await syncKind(database, env, kind, scheduledDate, epochSeconds, pagesPerRun));
    } catch (error) {
      failedKinds.push(kind);
      firstFailure ??= error;
    }
  }

  try {
    await database.prepare(
      "DELETE FROM catalog_entity_revisions WHERE entity_key IN ("
      + "SELECT entity_key FROM catalog_entity_revisions WHERE updated_at < ? ORDER BY updated_at LIMIT 1000)",
    )
      .bind(epochSeconds - REVISION_RETENTION_SECONDS)
      .run();
  } catch (error) {
    firstFailure ??= error;
  }

  if (firstFailure !== undefined) {
    const scope = failedKinds.length > 0 ? failedKinds.join(", ") : "revision housekeeping";
    throw new Error(`TMDb change sync failed for ${scope}.`, { cause: firstFailure });
  }
  return { scheduledDate, kinds: reports };
}

/** Returns null when D1 is bound but unavailable so callers can bypass cache. */
export async function catalogCacheRevision(env: WorkerAccountEnv, entityKey?: string): Promise<string | null> {
  if (!entityKey) return "0";
  if (!env.AUTH_DB) return null;
  try {
    const row = await env.AUTH_DB.prepare(
      "SELECT revision FROM catalog_entity_revisions WHERE entity_key = ?",
    ).bind(entityKey).first<{ revision: string }>();
    return row?.revision ?? "0";
  } catch {
    // A rolling deploy can briefly run before migration 0004 reaches every
    // environment. Preserve availability without reusing a previously valid
    // revision-0 entry; the scheduled event still fails until migration lands.
    return null;
  }
}

async function syncKind(
  database: D1Database,
  env: WorkerAccountEnv,
  kind: CatalogChangeKind,
  scheduledDate: string,
  epochSeconds: number,
  pagesPerRun: number,
): Promise<CatalogChangeReport["kinds"][number]> {
  const cursor = await database.prepare(
    "SELECT window_date, next_page FROM catalog_change_cursors WHERE kind = ?",
  ).bind(kind).first<ChangeCursorRow>();
  const start = resumeCursor(cursor, scheduledDate);
  let windowDate = start.windowDate;
  let nextPage = start.nextPage;
  let pages = 0;
  let entities = 0;

  while (pages < pagesPerRun) {
    const result = await changePage(env, kind, windowDate, nextPage);
    const pageNumber = positivePage(result.page);
    const totalPages = boundedTotalPages(result.total_pages);
    const ids = uniquePositiveIDs(result.results);
    const completedWindow = pageNumber >= totalPages;
    const followingWindow = completedWindow && windowDate < scheduledDate
      ? nextUTCDate(windowDate)
      : windowDate;
    const followingPage = completedWindow ? 1 : pageNumber + 1;

    const statements: D1PreparedStatement[] = [];
    statements.push(...revisionUpserts(database, kind, ids, windowDate, epochSeconds));
    statements.push(database.prepare(
      "INSERT INTO catalog_change_cursors (kind, window_date, next_page, updated_at) VALUES (?, ?, ?, ?) "
      + "ON CONFLICT(kind) DO UPDATE SET window_date = excluded.window_date, next_page = excluded.next_page, updated_at = excluded.updated_at",
    ).bind(kind, followingWindow, followingPage, epochSeconds));
    await database.batch(statements);

    pages += 1;
    entities += ids.length;
    const wrappedCurrentDate = completedWindow && followingWindow === windowDate;
    windowDate = followingWindow;
    nextPage = followingPage;
    if (wrappedCurrentDate) break;
  }

  return { kind, pages, entities, windowDate, nextPage };
}

async function changePage(
  env: WorkerAccountEnv,
  kind: CatalogChangeKind,
  windowDate: string,
  requestedPage: number,
): Promise<TmdbChangePage> {
  try {
    return await requestChangePage(env, kind, windowDate, requestedPage);
  } catch (error) {
    // TMDb does not guarantee how a page beyond a newly shrunken total is
    // represented. Page-one replay is idempotent and prevents a stale cursor
    // from retrying the same out-of-range page forever.
    if (requestedPage === 1) throw error;
    const fallback = await requestChangePage(env, kind, windowDate, 1);
    const fallbackTotalPages = fallback.total_pages;
    if (!Number.isSafeInteger(fallbackTotalPages)
      || fallbackTotalPages < 1
      || fallbackTotalPages >= requestedPage) {
      throw error;
    }
    return fallback;
  }
}

function requestChangePage(
  env: WorkerAccountEnv,
  kind: CatalogChangeKind,
  windowDate: string,
  requestedPage: number,
): Promise<TmdbChangePage> {
  return tmdb<TmdbChangePage>(
    env,
    `/${kind}/changes`,
    new URLSearchParams({
      start_date: windowDate,
      end_date: windowDate,
      page: String(requestedPage),
    }),
    `changes-${kind}-${requestedPage}`,
  );
}

function revisionUpserts(
  database: D1Database,
  kind: CatalogChangeKind,
  ids: number[],
  revision: string,
  epochSeconds: number,
): D1PreparedStatement[] {
  const statements: D1PreparedStatement[] = [];
  for (let offset = 0; offset < ids.length; offset += D1_ENTITY_CHUNK_SIZE) {
    const chunk = ids.slice(offset, offset + D1_ENTITY_CHUNK_SIZE);
    const placeholders = chunk.map(() => "(?, ?, ?)").join(", ");
    const values: Array<string | number> = [];
    for (const id of chunk) values.push(`${kind}:${id}`, revision, epochSeconds);
    statements.push(database.prepare(
      `INSERT INTO catalog_entity_revisions (entity_key, revision, updated_at) VALUES ${placeholders} `
      + "ON CONFLICT(entity_key) DO UPDATE SET revision = excluded.revision, updated_at = excluded.updated_at "
      + "WHERE catalog_entity_revisions.revision < excluded.revision",
    ).bind(...values));
  }
  return statements;
}

function uniquePositiveIDs(results: TmdbChangePage["results"]): number[] {
  return [...new Set(results.map((item) => item.id).filter(
    (id): id is number => Number.isSafeInteger(id) && (id ?? 0) > 0,
  ))];
}

function positivePage(value: number): number {
  return Number.isSafeInteger(value) && value >= 1 ? value : 1;
}

function boundedTotalPages(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1) return 1;
  return value;
}

function resumeCursor(cursor: ChangeCursorRow | null, scheduledDate: string): { windowDate: string; nextPage: number } {
  // A new deployment starts today because every pre-existing entity cache has
  // a maximum 24-hour TTL; spending the first runs on older dates cannot evict
  // a still-live pre-deployment entry. Existing cursors retain up to 14 days.
  if (!cursor || !validUTCDate(cursor.window_date)) return { windowDate: scheduledDate, nextPage: 1 };
  const earliestDate = offsetUTCDate(scheduledDate, -(TMDB_MAX_LOOKBACK_DAYS - 1));
  if (cursor.window_date > scheduledDate) return { windowDate: scheduledDate, nextPage: 1 };
  if (cursor.window_date < earliestDate) return { windowDate: earliestDate, nextPage: 1 };
  return { windowDate: cursor.window_date, nextPage: positivePage(cursor.next_page) };
}

function validUTCDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const timestamp = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isFinite(timestamp) && new Date(timestamp).toISOString().slice(0, 10) === value;
}

function nextUTCDate(value: string): string {
  return offsetUTCDate(value, 1);
}

function offsetUTCDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function configuredPagesPerRun(value?: string): number {
  if (value === undefined || value === "") return DEFAULT_PAGES_PER_RUN;
  if (!/^\d+$/.test(value)) return DEFAULT_PAGES_PER_RUN;
  return Math.min(Math.max(Number(value), 1), MAX_PAGES_PER_RUN);
}

function requireChangeDatabase(env: WorkerAccountEnv): D1Database {
  if (!env.AUTH_DB) throw new Error("AUTH_DB is required for TMDb change synchronization.");
  return env.AUTH_DB;
}
