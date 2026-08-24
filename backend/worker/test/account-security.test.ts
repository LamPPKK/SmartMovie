import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { decryptSecret, encryptSecret, sha256 } from "../src/crypto";

const secret = "fixture-session-encryption-key-with-at-least-thirty-two-characters";
const context = { waitUntil: (promise: Promise<unknown>) => void promise };

afterEach(() => vi.unstubAllGlobals());

describe("v2 session broker security", () => {
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
