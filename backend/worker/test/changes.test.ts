import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { route, type Env } from "../src/index";
import { syncCatalogChanges } from "../src/changes";
import { routeV2 } from "../src/v2";

afterEach(() => vi.unstubAllGlobals());

describe("TMDb change synchronization", () => {
  it("advances independent paginated cursors and stores UTC-date revisions", async () => {
    const database = new ChangeDatabase();
    const requested: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      requested.push(`${url.pathname}?${url.searchParams}`);
      expect(request.headers.get("Authorization")).toBe("Bearer test-token");
      const kind = url.pathname.split("/").at(-2);
      const currentPage = Number(url.searchParams.get("page"));
      if (kind === "movie") {
        return Response.json({
          page: currentPage,
          total_pages: 3,
          results: currentPage === 1 ? [{ id: 10 }, { id: 10 }, { id: -1 }] : [{ id: 11 }],
        });
      }
      if (kind === "tv") return Response.json({ page: 1, total_pages: 1, results: [{ id: 20 }] });
      return Response.json({ page: 1, total_pages: 1, results: [{ id: 30 }] });
    }));

    const scheduledTime = Date.parse("2026-08-25T07:17:00.000Z");
    const report = await syncCatalogChanges(changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "2" }), scheduledTime);

    expect(report).toEqual({
      scheduledDate: "2026-08-25",
      kinds: [
        { kind: "movie", pages: 2, entities: 2, windowDate: "2026-08-25", nextPage: 3 },
        { kind: "tv", pages: 1, entities: 1, windowDate: "2026-08-25", nextPage: 1 },
        { kind: "person", pages: 1, entities: 1, windowDate: "2026-08-25", nextPage: 1 },
      ],
    });
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 3 });
    expect(database.revisions.get("movie:10")?.revision).toBe("2026-08-25");
    expect(database.revisions.get("movie:11")?.revision).toBe("2026-08-25");
    expect(database.revisions.get("tv:20")?.revision).toBe("2026-08-25");
    expect(database.revisions.get("person:30")?.revision).toBe("2026-08-25");
    expect(requested).toEqual(expect.arrayContaining([
      "/3/movie/changes?start_date=2026-08-25&end_date=2026-08-25&page=1",
      "/3/movie/changes?start_date=2026-08-25&end_date=2026-08-25&page=2",
      "/3/tv/changes?start_date=2026-08-25&end_date=2026-08-25&page=1",
      "/3/person/changes?start_date=2026-08-25&end_date=2026-08-25&page=1",
    ]));
  });

  it("finishes an older UTC-date cursor before advancing and keeps replay idempotent", async () => {
    const database = new ChangeDatabase();
    database.cursors.set("movie", { window_date: "2026-08-24", next_page: 19, updated_at: 0 });
    database.revisions.set("movie:10", {
      revision: "2026-08-25",
      updated_at: Date.parse("2026-08-25T00:00:00Z") / 1_000,
    });
    const pages: Array<{ kind: string; page: string | null }> = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      pages.push({ kind: url.pathname.split("/").at(-2) ?? "", page: url.searchParams.get("page") });
      const requestedPage = Number(url.searchParams.get("page"));
      return Response.json({ page: requestedPage, total_pages: requestedPage, results: [{ id: 10 }] });
    }));

    await syncCatalogChanges(changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }), Date.parse("2026-08-25T00:17:00Z"));

    expect(pages.find((item) => item.kind === "movie")?.page).toBe("19");
    expect(database.revisionWrites.get("movie:10")).toBeUndefined();
    expect(database.revisions.get("movie:10")?.revision).toBe("2026-08-25");
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 1 });
  });

  it("clamps a stale cursor to TMDb's supported 14-day lookback window", async () => {
    const database = new ChangeDatabase();
    database.cursors.set("movie", { window_date: "2026-01-01", next_page: 400, updated_at: 0 });
    let movieStartDate: string | null = null;
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      if (url.pathname.endsWith("/movie/changes")) movieStartDate = url.searchParams.get("start_date");
      return Response.json({ page: 1, total_pages: 1, results: [] });
    }));

    await syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }),
      Date.parse("2026-08-25T00:17:00Z"),
    );

    expect(movieStartDate).toBe("2026-08-12");
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-13", next_page: 1 });
  });

  it("recovers an ISO-shaped but invalid cursor date instead of failing the kind", async () => {
    const database = new ChangeDatabase();
    database.cursors.set("movie", { window_date: "2026-13-01", next_page: 7, updated_at: 0 });
    let movieStartDate: string | null = null;
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      if (url.pathname.endsWith("/movie/changes")) movieStartDate = url.searchParams.get("start_date");
      return Response.json({ page: 1, total_pages: 1, results: [] });
    }));

    await expect(syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }),
      Date.parse("2026-08-25T00:17:00Z"),
    )).resolves.toBeDefined();

    expect(movieStartDate).toBe("2026-08-25");
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 1 });
  });

  it("recovers when the current change page count shrinks and later grows", async () => {
    const database = new ChangeDatabase();
    database.cursors.set("movie", { window_date: "2026-08-25", next_page: 3, updated_at: 0 });
    let phase: "shrink" | "grow" = "shrink";
    const moviePages: number[] = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      const kind = url.pathname.split("/").at(-2);
      const requestedPage = Number(url.searchParams.get("page"));
      if (kind !== "movie") return Response.json({ page: 1, total_pages: 1, results: [] });
      moviePages.push(requestedPage);
      if (phase === "shrink" && requestedPage === 3) return new Response("page out of range", { status: 422 });
      if (phase === "shrink") return Response.json({ page: requestedPage, total_pages: 2, results: [] });
      return Response.json({ page: requestedPage, total_pages: 4, results: [] });
    }));

    await syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "2" }),
      Date.parse("2026-08-25T01:17:00Z"),
    );
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 1 });

    phase = "grow";
    await syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "2" }),
      Date.parse("2026-08-25T02:17:00Z"),
    );

    expect(moviePages).toEqual([3, 1, 2, 1, 2]);
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 3 });
  });

  it("does not treat a page failure as shrinkage while page one still includes that page", async () => {
    const database = new ChangeDatabase();
    database.cursors.set("movie", { window_date: "2026-08-25", next_page: 3, updated_at: 0 });
    const moviePages: number[] = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      const kind = url.pathname.split("/").at(-2);
      const requestedPage = Number(url.searchParams.get("page"));
      if (kind !== "movie") return Response.json({ page: 1, total_pages: 1, results: [] });
      moviePages.push(requestedPage);
      if (requestedPage === 3) return new Response("temporary page failure", { status: 503 });
      return Response.json({ page: 1, total_pages: 4, results: [] });
    }));

    await expect(syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }),
      Date.parse("2026-08-25T02:17:00Z"),
    )).rejects.toThrow("TMDb change sync failed for movie.");

    expect(moviePages).toEqual([3, 1]);
    expect(database.cursors.get("movie")).toMatchObject({ window_date: "2026-08-25", next_page: 3 });
    expect(database.cursors.get("tv")).toMatchObject({ window_date: "2026-08-25", next_page: 1 });
    expect(database.cursors.get("person")).toMatchObject({ window_date: "2026-08-25", next_page: 1 });
  });

  it("continues TV and Person invalidation when one TMDb change list fails", async () => {
    const database = new ChangeDatabase();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const kind = new URL(String(input)).pathname.split("/").at(-2);
      if (kind === "movie") return new Response("upstream unavailable", { status: 503 });
      return Response.json({ page: 1, total_pages: 1, results: [{ id: kind === "tv" ? 20 : 30 }] });
    }));

    await expect(syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }),
      Date.parse("2026-08-25T01:17:00Z"),
    )).rejects.toThrow("TMDb change sync failed for movie.");
    expect(database.revisions.get("tv:20")?.revision).toBe("2026-08-25");
    expect(database.revisions.get("person:30")?.revision).toBe("2026-08-25");
    expect(database.cursors.has("movie")).toBe(false);
  });

  it("chunks a full 100-item TMDb page below D1's 100-parameter query limit", async () => {
    const database = new ChangeDatabase();
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const kind = new URL(String(input)).pathname.split("/").at(-2);
      return Response.json({
        page: 1,
        total_pages: 1,
        results: kind === "movie" ? Array.from({ length: 100 }, (_, index) => ({ id: index + 1 })) : [],
      });
    }));

    await syncCatalogChanges(
      changeEnv(database, { CATALOG_CHANGE_PAGES_PER_RUN: "1" }),
      Date.parse("2026-08-25T01:17:00Z"),
    );

    expect([...database.revisions.keys()].filter((key) => key.startsWith("movie:"))).toHaveLength(100);
    expect(database.maximumBoundValues).toBe(99);
  });

  it("registers the scheduled promise with the Worker execution context", async () => {
    const database = new ChangeDatabase();
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ page: 1, total_pages: 1, results: [] })));
    let pending: Promise<unknown> | undefined;

    worker.scheduled(
      { scheduledTime: Date.parse("2026-08-25T02:17:00Z") },
      changeEnv(database),
      { waitUntil: (promise) => { pending = promise; } },
    );

    expect(pending).toBeDefined();
    await expect(pending).resolves.toMatchObject({ scheduledDate: "2026-08-25" });
  });
});

describe("change-aware entity caching", () => {
  it("shares revision keys across title resources and TV season/episode routes", () => {
    expect(route("/v1/titles/movie/42")?.cacheRevisionKey).toBe("movie:42");
    expect(routeV2("/v2/titles/movie/42")?.cacheRevisionKey).toBe("movie:42");
    expect(routeV2("/v2/titles/movie/42/recommendations")?.cacheRevisionKey).toBe("movie:42");
    expect(routeV2("/v2/entities/person/7")?.cacheRevisionKey).toBe("person:7");
    expect(routeV2("/v2/tv/1399/seasons/1")?.cacheRevisionKey).toBe("tv:1399");
    expect(routeV2("/v2/tv/1399/seasons/1/episodes/2")?.cacheRevisionKey).toBe("tv:1399");
    expect(routeV2("/v2/entities/collection/10")?.cacheRevisionKey).toBeUndefined();
    expect(routeV2("/v2/changes")).toBeNull();
  });

  it("misses the Cache API after a scheduled entity revision changes", async () => {
    const database = new ChangeDatabase();
    database.revisions.set("movie:42", { revision: "2026-08-24", updated_at: 1 });
    const entries = new Map<string, Response>();
    vi.stubGlobal("caches", {
      default: {
        match: async (request: Request) => entries.get(request.url)?.clone(),
        put: async (request: Request, response: Response) => { entries.set(request.url, response.clone()); },
      },
    });
    const upstream = vi.fn(async () => Response.json({
      id: 42,
      title: "Changed movie",
      original_title: "Changed movie",
      overview: "",
      genres: [],
    }));
    vi.stubGlobal("fetch", upstream);
    const pending: Promise<unknown>[] = [];
    const context = { waitUntil: (promise: Promise<unknown>) => { pending.push(promise); } };
    const request = new Request("https://catalog.example/v2/titles/movie/42?language=en-US");
    const environment = changeEnv(database, { CF_VERSION_METADATA: { id: "worker-1" } });

    const first = await worker.fetch(request, environment, context);
    await Promise.all(pending.splice(0));
    const hit = await worker.fetch(request, environment, context);
    for (const reserved of ["__smartmovie_worker_version", "__smartmovie_catalog_revision"]) {
      const injection = await worker.fetch(
        new Request(`${request.url}&${reserved}=attacker-controlled`),
        environment,
        context,
      );
      expect(injection.status).toBe(400);
      await expect(injection.json()).resolves.toMatchObject({ error: { code: "unsupported_parameter" } });
    }
    database.revisions.set("movie:42", { revision: "2026-08-25", updated_at: 2 });
    const invalidated = await worker.fetch(request, environment, context);
    await Promise.all(pending.splice(0));

    expect(first.headers.get("X-SmartMovie-Cache")).toBe("MISS");
    expect(hit.headers.get("X-SmartMovie-Cache")).toBe("HIT");
    expect(invalidated.headers.get("X-SmartMovie-Cache")).toBe("MISS");
    expect(upstream).toHaveBeenCalledTimes(2);
    expect([...entries.keys()]).toEqual(expect.arrayContaining([
      expect.stringContaining("__smartmovie_catalog_revision=2026-08-24"),
      expect.stringContaining("__smartmovie_catalog_revision=2026-08-25"),
    ]));
  });

  it("bypasses an old revision-zero cache entry when the D1 revision read fails", async () => {
    const database = new ChangeDatabase();
    const entries = new Map<string, Response>();
    let cacheMatches = 0;
    let cachePuts = 0;
    vi.stubGlobal("caches", {
      default: {
        match: async (request: Request) => {
          cacheMatches += 1;
          return entries.get(request.url)?.clone();
        },
        put: async (request: Request, response: Response) => {
          cachePuts += 1;
          entries.set(request.url, response.clone());
        },
      },
    });
    const upstream = vi.fn(async () => Response.json({
      id: 42,
      title: "Fresh movie",
      original_title: "Fresh movie",
      overview: "",
      genres: [],
    }));
    vi.stubGlobal("fetch", upstream);
    const pending: Promise<unknown>[] = [];
    const context = { waitUntil: (promise: Promise<unknown>) => { pending.push(promise); } };
    const request = new Request("https://catalog.example/v2/titles/movie/42?language=en-US");
    const environment = changeEnv(database, { CF_VERSION_METADATA: { id: "worker-1" } });

    const initial = await worker.fetch(request, environment, context);
    await Promise.all(pending.splice(0));
    expect(initial.headers.get("X-SmartMovie-Cache")).toBe("MISS");
    expect([...entries.keys()]).toEqual([expect.stringContaining("__smartmovie_catalog_revision=0")]);

    database.revisions.set("movie:42", { revision: "2026-08-25", updated_at: 2 });
    database.failRevisionReads = true;
    const degraded = await worker.fetch(request, environment, context);
    const repeated = await worker.fetch(request, environment, context);
    const unbound = await worker.fetch(
      request,
      changeEnv(database, { AUTH_DB: undefined, CF_VERSION_METADATA: { id: "worker-1" } }),
      context,
    );

    expect(degraded.headers.get("X-SmartMovie-Cache")).toBe("BYPASS");
    expect(repeated.headers.get("X-SmartMovie-Cache")).toBe("BYPASS");
    expect(unbound.headers.get("X-SmartMovie-Cache")).toBe("BYPASS");
    expect(upstream).toHaveBeenCalledTimes(4);
    expect(pending).toHaveLength(0);
    expect(entries).toHaveLength(1);
    expect(cacheMatches).toBe(1);
    expect(cachePuts).toBe(1);
  });
});

interface CursorRecord {
  window_date: string;
  next_page: number;
  updated_at: number;
}

interface RevisionRecord {
  revision: string;
  updated_at: number;
}

class ChangeStatement {
  values: unknown[] = [];

  constructor(readonly database: ChangeDatabase, readonly query: string) {}

  bind(...values: unknown[]): ChangeStatement {
    this.values = values;
    this.database.maximumBoundValues = Math.max(this.database.maximumBoundValues, values.length);
    return this;
  }

  async first<Value>(): Promise<Value | null> {
    if (this.query.startsWith("SELECT window_date")) {
      return (this.database.cursors.get(String(this.values[0])) ?? null) as Value | null;
    }
    if (this.query.startsWith("SELECT revision")) {
      if (this.database.failRevisionReads) throw new Error("D1 temporarily unavailable");
      return (this.database.revisions.get(String(this.values[0])) ?? null) as Value | null;
    }
    return null;
  }

  async run(): Promise<D1Result> {
    if (this.query.startsWith("DELETE FROM catalog_entity_revisions")) {
      const cutoff = Number(this.values[0]);
      for (const [key, value] of this.database.revisions) {
        if (value.updated_at < cutoff) this.database.revisions.delete(key);
      }
    } else if (this.query.startsWith("INSERT INTO catalog_entity_revisions")) {
      for (let index = 0; index < this.values.length; index += 3) {
        const key = String(this.values[index]);
        const revision = String(this.values[index + 1]);
        const updatedAt = Number(this.values[index + 2]);
        if ((this.database.revisions.get(key)?.revision ?? "") < revision) {
          this.database.revisions.set(key, { revision, updated_at: updatedAt });
          this.database.revisionWrites.set(key, (this.database.revisionWrites.get(key) ?? 0) + 1);
        }
      }
    } else if (this.query.startsWith("INSERT INTO catalog_change_cursors")) {
      this.database.cursors.set(String(this.values[0]), {
        window_date: String(this.values[1]),
        next_page: Number(this.values[2]),
        updated_at: Number(this.values[3]),
      });
    }
    return { success: true, meta: { changes: 1 } } as D1Result;
  }
}

class ChangeDatabase {
  cursors = new Map<string, CursorRecord>();
  revisions = new Map<string, RevisionRecord>();
  revisionWrites = new Map<string, number>();
  maximumBoundValues = 0;
  failRevisionReads = false;

  prepare(query: string): D1PreparedStatement {
    return new ChangeStatement(this, query) as unknown as D1PreparedStatement;
  }

  async batch(statements: D1PreparedStatement[]): Promise<D1Result[]> {
    const results: D1Result[] = [];
    for (const statement of statements) {
      results.push(await (statement as unknown as ChangeStatement).run());
    }
    return results;
  }
}

function changeEnv(database: ChangeDatabase, overrides: Partial<Env> = {}): Env {
  return {
    TMDB_BEARER_TOKEN: "test-token",
    TMDB_BASE_URL: "https://tmdb.example/3",
    AUTH_DB: database as unknown as D1Database,
    ...overrides,
  };
}
