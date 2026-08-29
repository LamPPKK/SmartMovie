import { afterEach, describe, expect, it, vi } from "vitest";
import accountFixture from "../contract/v2/fixtures/account.json";
import worker, { type Env } from "../src/index";
import { decryptSecret, encryptSecret, sha256 } from "../src/crypto";

const secret = "fixture-session-encryption-key-with-at-least-thirty-two-characters";
const context = { waitUntil: (promise: Promise<unknown>) => void promise };

afterEach(() => vi.unstubAllGlobals());

describe("v2 session broker security", () => {
  it.each(accountFixture.episode_states)("returns private canonical episode state for season $season_number", async (expected) => {
    const bearer = "fixture-episode-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer), account_object_id: "fixture-account", account_id: 42,
      access_token_encrypted: await encryptSecret("fixture-access", secret),
      v3_session_encrypted: await encryptSecret("fixture-v3", secret), csrf_hash: "unused",
      created_at: now() - 10, last_seen_at: now() - 10, expires_at: now() + 300, revoked_at: null,
    });
    const { series_id, season_number, episode_number, ...upstreamState } = expected;
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe(`/3/tv/${series_id}/season/${season_number}/episode/${episode_number}/account_states`);
      expect(url.searchParams.get("session_id")).toBe("fixture-v3");
      return Response.json(upstreamState);
    });
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(new Request(
      `https://catalog.example/v2/account/state/episode/${series_id}/${season_number}/${episode_number}`,
      { headers: { Authorization: `Bearer ${bearer}`, "X-SmartMovie-Client": "test" } },
    ), accountEnv(database), context);
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    await expect(response.json()).resolves.toEqual(expected);
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("keeps private cache and Worker-version metadata on account errors", async () => {
    const database = new SessionDatabase({
      token_hash: "unused",
      account_object_id: "unused",
      account_id: 42,
      access_token_encrypted: "unused",
      v3_session_encrypted: "unused",
      csrf_hash: "unused",
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const environment = accountEnv(database);
    environment.CATALOG_RATE_LIMITER = { limit: async () => ({ success: false }) };
    environment.CF_VERSION_METADATA = { id: "worker-private-error" };

    const response = await worker.fetch(new Request("https://catalog.example/v2/account/profile", {
      headers: { Origin: "https://smartmovie.app", "X-SmartMovie-Client": "test" },
    }), environment, context);

    expect(response.status).toBe(429);
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    expect(response.headers.get("X-SmartMovie-Worker-Version")).toBe("worker-private-error");
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("https://smartmovie.app");
    expect(response.headers.get("Access-Control-Allow-Credentials")).toBe("true");
    expect(response.headers.get("Vary")).toBe("Origin");
    await expect(response.json()).resolves.toMatchObject({ error: { code: "rate_limited", retry_after: 60 } });

    const rejectedOrigin = await worker.fetch(new Request("https://catalog.example/v2/account/profile", {
      headers: { Origin: "https://evil.example", "X-SmartMovie-Client": "test" },
    }), environment, context);
    expect(rejectedOrigin.status).toBe(429);
    expect(rejectedOrigin.headers.get("Cache-Control")).toBe("private, no-store");
    expect(rejectedOrigin.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect(rejectedOrigin.headers.get("Vary")).toBe("Origin");
  });

  it("encrypts TMDb tokens with randomized AES-GCM ciphertext", async () => {
    const first = await encryptSecret("tmdb-access-token", secret);
    const second = await encryptSecret("tmdb-access-token", secret);
    expect(first).not.toBe(second);
    await expect(decryptSecret(first, secret)).resolves.toBe("tmdb-access-token");
    await expect(decryptSecret(`${first}tampered`, secret)).rejects.toMatchObject({ code: "invalid_session" });
  });

  it("rotates a CSRF token without exposing the opaque session or TMDb tokens", async () => {
    const bearer = "opaque-smartmovie-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("old-csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const response = await worker.fetch(new Request("https://catalog.example/v2/auth/csrf", {
      headers: { Authorization: `Bearer ${bearer}`, "X-SmartMovie-Client": "test" },
    }), accountEnv(database), context);
    const value = await response.json() as { csrf_token: string };
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toContain("no-store");
    expect(value.csrf_token.length).toBeGreaterThanOrEqual(40);
    expect(database.session.csrf_hash).toBe(await sha256(value.csrf_token));
    expect(JSON.stringify(value)).not.toContain("tmdb-");
    expect(JSON.stringify(value)).not.toContain(bearer);
  });

  it("requires an allowed browser origin before rotating cookie-session CSRF", async () => {
    const cookie = "browser-cookie-session";
    const database = new SessionDatabase({
      token_hash: await sha256(cookie),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("old-csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const response = await worker.fetch(new Request("https://catalog.example/v2/auth/csrf", {
      headers: { Cookie: `smartmovie_session=${cookie}`, Origin: "https://evil.example", "X-SmartMovie-Client": "test" },
    }), accountEnv(database), context);
    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "origin_not_allowed" } });
  });

  it("expires stale sessions and removes them from D1", async () => {
    const bearer = "expired-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 500,
      last_seen_at: now() - 500,
      expires_at: now() - 1,
      revoked_at: null,
    });
    const response = await worker.fetch(new Request("https://catalog.example/v2/auth/csrf", {
      headers: { Authorization: `Bearer ${bearer}`, "X-SmartMovie-Client": "test" },
    }), accountEnv(database), context);
    expect(response.status).toBe(401);
    expect(database.deleted).toBe(true);
  });

  it("maps private v4 account recommendations with locale and pagination", async () => {
    const bearer = "opaque-recommendations-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe("/4/account/v4-account/tv/recommendations");
      expect(url.searchParams.get("language")).toBe("vi-VN");
      expect(url.searchParams.get("page")).toBe("2");
      expect(new Headers(init?.headers).get("Authorization")).toBe("Bearer tmdb-access");
      return Response.json({
        page: 2,
        total_pages: 3,
        results: [{
          id: 1399,
          name: "Game of Thrones",
          original_name: "Game of Thrones",
          overview: "Story",
          first_air_date: "2011-04-17",
          vote_average: 8.5,
          genre_ids: [18],
          adult: false,
        }],
      });
    });
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(new Request(
      "https://catalog.example/v2/account/recommendations/tv?language=vi-VN&page=2",
      { headers: { Authorization: `Bearer ${bearer}`, "X-SmartMovie-Client": "test" } },
    ), accountEnv(database), context);
    const value = await response.json() as { page: number; total_pages: number; results: Array<{ media_type: string }> };

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    expect(value).toMatchObject({ page: 2, total_pages: 3 });
    expect(value.results).toHaveLength(1);
    expect(value.results[0]?.media_type).toBe("tv");
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("normalizes a paginated mixed list into canonical Movie and TV summaries", async () => {
    const bearer = "opaque-list-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe("/4/list/7");
      expect(url.searchParams.get("language")).toBe("vi-VN");
      expect(url.searchParams.get("page")).toBe("2");
      expect(init?.method).toBe("GET");
      return Response.json({
        id: 7,
        name: "Mixed",
        description: "Movie and TV",
        public: false,
        page: 2,
        total_pages: 3,
        results: [
          { id: 10, media_type: "movie", title: "Movie", original_title: "Movie", overview: "", genre_ids: [] },
          { id: 11, media_type: "tv", name: "Series", original_name: "Series", overview: "", genre_ids: [] },
          { id: 12, media_type: "person", name: "Ignored" },
        ],
      });
    });
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(new Request(
      "https://catalog.example/v2/account/lists/7?language=vi-VN&page=2",
      { headers: { Authorization: `Bearer ${bearer}`, "X-SmartMovie-Client": "test" } },
    ), accountEnv(database), context);
    const value = await response.json() as {
      page: number;
      total_pages: number;
      results: Array<{ entity_kind: string; media_type: string; title: string }>;
    };

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    expect(value).toMatchObject({ page: 2, total_pages: 3 });
    expect(value.results.map((item) => [item.entity_kind, item.media_type, item.title])).toEqual([
      ["movie", "movie", "Movie"],
      ["tv", "tv", "Series"],
    ]);
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it.each(["PUT", "PATCH"])("maps %s list metadata updates to TMDb v4 PUT", async (method) => {
    const bearer = `opaque-list-update-${method.toLowerCase()}`;
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe("/4/list/7");
      expect(init?.method).toBe("PUT");
      expect(JSON.parse(String(init?.body))).toEqual({ name: "Weekend", description: "Ready", public: true });
      return Response.json({ success: true, status_code: 1, status_message: "Success." });
    });
    vi.stubGlobal("fetch", upstream);
    const mutationID = method === "PUT"
      ? "22222222-2222-4222-8222-222222222222"
      : "33333333-3333-4333-8333-333333333333";

    const response = await worker.fetch(new Request("https://catalog.example/v2/account/lists/7", {
      method,
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
        "X-SmartMovie-Client": "test",
      },
      body: JSON.stringify({ name: "Weekend", description: "Ready", public: true, mutation_id: mutationID }),
    }), accountEnv(database), context);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ mutation_id: mutationID, list_id: 7, success: true });
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("replays a canonical list identifier and rejects an invalid upstream identifier", async () => {
    const bearer = "opaque-list-create";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe("/4/list");
      expect(init?.method).toBe("POST");
      return Response.json({ id: 701, success: true, status_code: 1, status_message: "Success." });
    });
    vi.stubGlobal("fetch", upstream);
    const mutationID = "55555555-5555-4555-8555-555555555555";
    const makeRequest = () => new Request("https://catalog.example/v2/account/lists", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
        "X-SmartMovie-Client": "test",
      },
      body: JSON.stringify({
        name: "Weekend",
        description: "Ready",
        public: false,
        iso_3166_1: "US",
        iso_639_1: "en",
        mutation_id: mutationID,
      }),
    });

    const first = await worker.fetch(makeRequest(), accountEnv(database), context);
    const firstBody = await first.json();
    const replay = await worker.fetch(makeRequest(), accountEnv(database), context);
    const replayBody = await replay.json();

    expect(first.status).toBe(201);
    expect(replay.status).toBe(201);
    expect(firstBody).toEqual({
      mutation_id: mutationID,
      list_id: 701,
      success: true,
      status_code: 1,
      status_message: "Success.",
    });
    expect(replayBody).toEqual(firstBody);
    expect(upstream).toHaveBeenCalledTimes(1);

    const invalidBearer = "opaque-list-create-invalid-id";
    const invalidDatabase = new SessionDatabase({
      token_hash: await sha256(invalidBearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const invalidUpstream = vi.fn(async () => Response.json({ success: true, status_code: 1, status_message: "Success." }));
    vi.stubGlobal("fetch", invalidUpstream);
    const invalidMutationID = "66666666-6666-4666-8666-666666666666";

    const response = await worker.fetch(new Request("https://catalog.example/v2/account/lists", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${invalidBearer}`,
        "Content-Type": "application/json",
        "X-SmartMovie-Client": "test",
      },
      body: JSON.stringify({
        name: "Weekend",
        description: "Ready",
        public: false,
        iso_3166_1: "US",
        iso_639_1: "en",
        mutation_id: invalidMutationID,
      }),
    }), accountEnv(invalidDatabase), context);

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "invalid_upstream_response" } });
    expect(invalidDatabase.mutations.size).toBe(0);
    expect(invalidUpstream).toHaveBeenCalledTimes(1);
  });

  it("replays a PATCH list update as the same mutation after a client upgrades to PUT", async () => {
    const bearer = "opaque-list-upgrade";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async () => Response.json({ success: true, status_code: 1, status_message: "Success." }));
    vi.stubGlobal("fetch", upstream);
    const mutationID = "44444444-4444-4444-8444-444444444444";
    const makeRequest = (method: string) => new Request("https://catalog.example/v2/account/lists/7", {
      method,
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
        "X-SmartMovie-Client": "test",
      },
      body: JSON.stringify({ name: "Weekend", description: "Ready", public: true, mutation_id: mutationID }),
    });

    const legacy = await worker.fetch(makeRequest("PATCH"), accountEnv(database), context);
    const upgraded = await worker.fetch(makeRequest("PUT"), accountEnv(database), context);

    expect(legacy.status).toBe(200);
    expect(upgraded.status).toBe(200);
    expect(await upgraded.json()).toEqual(await legacy.json());
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("replays a completed account mutation without calling TMDb twice", async () => {
    const bearer = "opaque-retry-session";
    const database = new SessionDatabase({
      token_hash: await sha256(bearer),
      account_object_id: "v4-account",
      account_id: 42,
      access_token_encrypted: await encryptSecret("tmdb-access", secret),
      v3_session_encrypted: await encryptSecret("tmdb-v3", secret),
      csrf_hash: await sha256("csrf"),
      created_at: now() - 10,
      last_seen_at: now() - 10,
      expires_at: now() + 300,
      revoked_at: null,
    });
    const upstream = vi.fn(async () => Response.json({ success: true, status_code: 1, status_message: "Success." }));
    vi.stubGlobal("fetch", upstream);
    const mutationID = "11111111-1111-4111-8111-111111111111";
    const makeRequest = () => new Request("https://catalog.example/v2/account/ratings/movie/12", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
        "X-SmartMovie-Client": "test",
      },
      body: JSON.stringify({ value: 8.5, mutation_id: mutationID }),
    });

    const first = await worker.fetch(makeRequest(), accountEnv(database), context);
    const firstBody = await first.json();
    const replay = await worker.fetch(makeRequest(), accountEnv(database), context);
    const replayBody = await replay.json();

    expect(first.status).toBe(200);
    expect(replay.status).toBe(200);
    expect(replayBody).toEqual(firstBody);
    expect(replayBody).toMatchObject({ mutation_id: mutationID, media_type: "movie", media_id: 12, value: 8.5 });
    expect(upstream).toHaveBeenCalledTimes(1);
  });
});

interface SessionRow {
  token_hash: string;
  account_object_id: string;
  account_id: number;
  access_token_encrypted: string;
  v3_session_encrypted: string;
  csrf_hash: string;
  created_at: number;
  last_seen_at: number;
  expires_at: number;
  revoked_at: number | null;
}

class SessionDatabase {
  deleted = false;
  mutations = new Map<string, { kind: string; response_json: string | null; response_status: number | null; created_at: number; completed_at: number | null }>();
  constructor(public session: SessionRow) {}

  prepare(query: string) {
    let values: unknown[] = [];
    const statement = {
      bind: (...parameters: unknown[]) => { values = parameters; return statement; },
      first: async <Value>() => {
        if (query.startsWith("SELECT token_hash") && values[0] === this.session.token_hash) return this.session as Value;
        if (query.startsWith("SELECT kind, response_json")) return (this.mutations.get(`${values[0]}:${values[1]}`) ?? null) as Value | null;
        return null;
      },
      run: async () => {
        let changes = 1;
        if (query.startsWith("UPDATE sessions SET last_seen_at")) {
          this.session.last_seen_at = Number(values[0]);
          this.session.expires_at = Number(values[1]);
        } else if (query.startsWith("UPDATE sessions SET csrf_hash")) {
          this.session.csrf_hash = String(values[0]);
        } else if (query.startsWith("DELETE FROM sessions")) {
          this.deleted = true;
        } else if (query.startsWith("INSERT OR IGNORE INTO account_mutations")) {
          const key = `${values[0]}:${values[1]}`;
          if (this.mutations.has(key)) {
            changes = 0;
          } else {
            this.mutations.set(key, {
              kind: String(values[2]),
              response_json: null,
              response_status: null,
              created_at: Number(values[3]),
              completed_at: null,
            });
          }
        } else if (query.startsWith("UPDATE account_mutations SET response_json")) {
          const key = `${values[3]}:${values[4]}`;
          const mutation = this.mutations.get(key);
          if (mutation) {
            mutation.response_json = String(values[0]);
            mutation.response_status = Number(values[1]);
            mutation.completed_at = Number(values[2]);
          }
        } else if (query.startsWith("DELETE FROM account_mutations WHERE account_id")) {
          const key = `${values[0]}:${values[1]}`;
          const mutation = this.mutations.get(key);
          if (mutation?.completed_at === null) this.mutations.delete(key);
        } else if (query.startsWith("DELETE FROM account_mutations WHERE created_at")) {
          for (const [key, mutation] of this.mutations) if (mutation.created_at < Number(values[0])) this.mutations.delete(key);
        }
        return { success: true, meta: { changes } };
      },
    };
    return statement;
  }
}

function accountEnv(database: SessionDatabase): Env {
  return {
    TMDB_BEARER_TOKEN: "test-token",
    TMDB_BASE_URL: "https://tmdb.example/3",
    AUTH_DB: database as unknown as D1Database,
    SESSION_ENCRYPTION_KEY: secret,
    AUTH_CALLBACK_ORIGIN: "https://catalog.example",
    WEB_ORIGIN_ALLOWLIST: "https://smartmovie.app",
    RELEASE_TRAIN: "3.0.0",
  };
}

function now(): number { return Math.floor(Date.now() / 1000); }
