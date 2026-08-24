import type { MediaType, TmdbPage, TmdbTitle } from "./contracts";
import { decryptSecret, encryptSecret, randomToken, secureEqual, sha256 } from "./crypto";
import type { V2Route, WorkerEnvV2 } from "./v2";
import { tmdb } from "./v2";
import { titlePageV2, titleSummaryV2 } from "./transform-v2";
import { RequestProblem, language, page, rejectUnknown, titleID } from "./validation";

export interface WorkerAccountEnv extends WorkerEnvV2 {
  AUTH_DB?: D1Database;
  SESSION_ENCRYPTION_KEY?: string;
  AUTH_CALLBACK_ORIGIN?: string;
  AUTH_RETURN_URI_ALLOWLIST?: string;
  WEB_ORIGIN_ALLOWLIST?: string;
  SESSION_COOKIE_DOMAIN?: string;
}

interface AuthAttemptRow {
  id: string;
  state_hash: string;
  request_token_encrypted: string;
  return_uri: string;
  mode: "browser" | "tv" | "web";
  device_code_hash: string | null;
  status: "pending" | "approved" | "denied" | "completed" | "expired";
  created_at: number;
  expires_at: number;
  approved_at: number | null;
  completed_at: number | null;
}

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

interface SessionContext {
  row: SessionRow;
  v3Session: string;
  accessToken: string;
  cookieAuthenticated: boolean;
}

interface AccountMutationRow {
  kind: string;
  response_json: string | null;
  response_status: number | null;
  created_at: number;
}

interface AuthAttemptBody {
  return_uri?: string;
  mode?: "browser" | "tv" | "web";
}

const GET = new Set(["GET", "OPTIONS"]);
const POST = new Set(["POST", "OPTIONS"]);
const GET_POST = new Set(["GET", "POST", "PUT", "OPTIONS"]);
const GET_MUTATE = new Set(["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]);
const SESSION_MAX_AGE = 90 * 24 * 60 * 60;
const ATTEMPT_MAX_AGE = 15 * 60;
const DEFAULT_RETURN_URIS = [
  "smartmovie://auth/callback",
  "https://smartmovie.app/auth/callback",
  "http://localhost:8080/auth/callback",
];

export function routeAccountV2(pathname: string): V2Route | null {
  if (pathname === "/v2/auth/attempts") return privateRoute("v2-auth-attempt", POST, createAuthAttempt);
  if (pathname === "/v2/auth/callback") return privateRoute("v2-auth-callback", GET, authCallback);
  if (pathname === "/v2/auth/complete") return privateRoute("v2-auth-complete", POST, completeAuth);
  if (pathname === "/v2/auth/csrf") return privateRoute("v2-auth-csrf", GET, rotateCSRF);
  if (pathname === "/v2/auth/logout") return privateRoute("v2-auth-logout", POST, logout);
  if (pathname === "/v2/account/profile") return privateRoute("v2-account-profile", GET, accountProfile);
  if (pathname === "/v2/account/lists") return privateRoute("v2-account-lists", GET_POST, accountLists);

  let match = pathname.match(/^\/v2\/auth\/attempts\/([0-9a-f-]{36})$/i);
  if (match) return privateRoute("v2-auth-poll", GET, (request, url, env, id) => pollAuthAttempt(request, url, env, id, match![1]));

  match = pathname.match(/^\/v2\/account\/state\/(movie|tv)\/(\d+)$/);
  if (match) return privateRoute("v2-account-state", GET, (request, url, env, id) => accountState(request, url, env, id, match![1] as MediaType, titleID(match![2])));

  match = pathname.match(/^\/v2\/account\/state\/episode\/(\d+)\/(\d+)\/(\d+)$/);
  if (match) return privateRoute("v2-account-episode-state", GET, (request, url, env, id) => episodeState(
    request,
    url,
    env,
    id,
    titleID(match![1]),
    nonNegativeInteger(match![2], "season_number"),
    titleID(match![3]),
  ));

  match = pathname.match(/^\/v2\/account\/(favorites|watchlist)\/(movie|tv)$/);
  if (match) return privateRoute(`v2-account-${match[1]}`, GET_POST, (request, url, env, id) => library(
    request,
    url,
    env,
    id,
    match![1] as "favorites" | "watchlist",
    match![2] as MediaType,
  ));

  match = pathname.match(/^\/v2\/account\/ratings\/(movie|tv)\/(\d+)$/);
  if (match) return privateRoute("v2-account-rating", GET_MUTATE, (request, url, env, id) => rating(
    request,
    url,
    env,
    id,
    match![1] as MediaType,
    titleID(match![2]),
  ));

  match = pathname.match(/^\/v2\/account\/ratings\/episode\/(\d+)\/(\d+)\/(\d+)$/);
  if (match) return privateRoute("v2-account-episode-rating", GET_MUTATE, (request, url, env, id) => episodeRating(
    request,
    url,
    env,
    id,
    titleID(match![1]),
    nonNegativeInteger(match![2], "season_number"),
    titleID(match![3]),
  ));

  match = pathname.match(/^\/v2\/account\/recommendations\/(movie|tv)$/);
  if (match) return privateRoute("v2-account-recommendations", GET, (request, url, env, id) => recommendations(
    request,
    url,
    env,
    id,
    match![1] as MediaType,
  ));

  match = pathname.match(/^\/v2\/account\/lists\/(\d+)$/);
  if (match) return privateRoute("v2-account-list", GET_MUTATE, (request, url, env, id) => accountList(
    request,
    url,
    env,
    id,
    titleID(match![1]),
  ));

  match = pathname.match(/^\/v2\/account\/lists\/(\d+)\/items$/);
  if (match) return privateRoute("v2-account-list-items", GET_MUTATE, (request, url, env, id) => accountListItems(
    request,
    url,
    env,
    id,
    titleID(match![1]),
  ));

  return null;
}

export function accountCapabilitiesAvailable(env: WorkerAccountEnv): boolean {
  return Boolean(env.AUTH_DB && env.SESSION_ENCRYPTION_KEY && env.AUTH_CALLBACK_ORIGIN);
}

async function createAuthAttempt(request: Request, url: URL, env: WorkerAccountEnv, requestId: string): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const database = requireDatabase(env);
  const encryptionKey = requireEncryptionKey(env);
  const body = await jsonBody<AuthAttemptBody>(request);
  const mode = body.mode ?? "browser";
  if (!new Set(["browser", "tv", "web"]).has(mode)) throw new RequestProblem(400, "invalid_auth_mode", "Auth mode must be browser, tv, or web.");
  const returnURI = body.return_uri ?? (mode === "tv" ? "smartmovie://auth/callback" : undefined);
  if (!returnURI || !returnURIAllowed(returnURI, env)) throw new RequestProblem(400, "invalid_return_uri", "The auth return URI is not allowed.");

  const attemptID = crypto.randomUUID();
  const state = randomToken();
  const deviceCode = mode === "tv" ? numericCode() : null;
  const callbackOrigin = validatedCallbackOrigin(env);
  const callback = new URL("/v2/auth/callback", callbackOrigin);
  callback.searchParams.set("attempt_id", attemptID);
  callback.searchParams.set("state", state);
  const upstream = await tmdbV4Application<{ success: boolean; request_token: string; expires_at?: string }>(
    env,
    "/auth/request_token",
    { method: "POST", body: JSON.stringify({ redirect_to: callback.toString() }) },
    requestId,
  );
  if (!upstream.success || !upstream.request_token) throw new RequestProblem(502, "auth_attempt_failed", "TMDb did not create an authorization attempt.");
  const now = epochSeconds();
  const expiresAt = Math.min(now + ATTEMPT_MAX_AGE, parseTMDbExpiry(upstream.expires_at) ?? now + ATTEMPT_MAX_AGE);
  await database.prepare(
    "INSERT INTO auth_attempts (id, state_hash, request_token_encrypted, return_uri, mode, device_code_hash, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)",
  ).bind(
    attemptID,
    await sha256(state),
    await encryptSecret(upstream.request_token, encryptionKey),
    returnURI,
    mode,
    deviceCode ? await sha256(deviceCode) : null,
    now,
    expiresAt,
  ).run();
  await cleanupExpired(database, now);

  return privateJSON(request, env, {
    attempt_id: attemptID,
    status: "pending",
    authorization_url: `https://www.themoviedb.org/auth/access?request_token=${encodeURIComponent(upstream.request_token)}`,
    device_code: deviceCode,
    expires_at: new Date(expiresAt * 1000).toISOString(),
    polling_interval: mode === "tv" ? 5 : null,
  }, 201);
}

async function pollAuthAttempt(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  _requestId: string,
  attemptID: string,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set(["device_code"]));
  const database = requireDatabase(env);
  const row = await authAttempt(database, attemptID);
  const now = epochSeconds();
  if (row.expires_at <= now && row.status !== "completed") {
    await database.prepare("UPDATE auth_attempts SET status = 'expired' WHERE id = ?").bind(row.id).run();
    return privateJSON(request, env, { attempt_id: row.id, status: "expired", expires_at: new Date(row.expires_at * 1000).toISOString() });
  }
  if (row.mode === "tv") {
    const deviceCode = url.searchParams.get("device_code") ?? "";
    if (!row.device_code_hash || !secureEqual(await sha256(deviceCode), row.device_code_hash)) {
      throw new RequestProblem(401, "invalid_device_code", "The TV authorization code is invalid.");
    }
  }
  return privateJSON(request, env, {
    attempt_id: row.id,
    status: row.status,
    expires_at: new Date(row.expires_at * 1000).toISOString(),
  });
}

async function authCallback(request: Request, url: URL, env: WorkerAccountEnv): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set(["attempt_id", "state", "approved", "request_token", "denied"]));
  const database = requireDatabase(env);
  const attemptID = url.searchParams.get("attempt_id") ?? "";
  const state = url.searchParams.get("state") ?? "";
  const row = await authAttempt(database, attemptID);
  const now = epochSeconds();
  if (row.expires_at <= now || row.status !== "pending") throw new RequestProblem(410, "auth_attempt_expired", "This authorization attempt is no longer active.");
  if (!secureEqual(await sha256(state), row.state_hash)) throw new RequestProblem(400, "invalid_auth_state", "The authorization state is invalid.");
  const requestToken = await decryptSecret(row.request_token_encrypted, requireEncryptionKey(env));
  const callbackToken = url.searchParams.get("request_token");
  if (callbackToken && !secureEqual(callbackToken, requestToken)) throw new RequestProblem(400, "invalid_auth_token", "The authorization token does not match this attempt.");
  const approved = url.searchParams.get("approved") !== "false" && url.searchParams.get("denied") !== "true";
  await database.prepare("UPDATE auth_attempts SET status = ?, approved_at = ? WHERE id = ? AND status = 'pending'")
    .bind(approved ? "approved" : "denied", approved ? now : null, row.id)
    .run();
  if (row.mode === "tv") {
    return new Response(authResultHTML(approved), {
      status: approved ? 200 : 403,
      headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "private, no-store" },
    });
  }
  const destination = new URL(row.return_uri);
  destination.searchParams.set("auth_attempt", row.id);
  destination.searchParams.set("status", approved ? "approved" : "denied");
  return new Response(null, { status: 303, headers: { Location: destination.toString(), "Cache-Control": "private, no-store" } });
}

async function completeAuth(request: Request, url: URL, env: WorkerAccountEnv, requestId: string): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const database = requireDatabase(env);
  const encryptionKey = requireEncryptionKey(env);
  const body = await jsonBody<{ attempt_id?: string; device_code?: string }>(request);
  const row = await authAttempt(database, body.attempt_id ?? "");
  const now = epochSeconds();
  if (row.expires_at <= now) throw new RequestProblem(410, "auth_attempt_expired", "This authorization attempt has expired.");
  if (row.status !== "approved") throw new RequestProblem(409, "auth_not_approved", "TMDb authorization has not been approved.");
  if (row.mode === "tv") {
    if (!body.device_code || !row.device_code_hash || !secureEqual(await sha256(body.device_code), row.device_code_hash)) {
      throw new RequestProblem(401, "invalid_device_code", "The TV authorization code is invalid.");
    }
  }
  const requestToken = await decryptSecret(row.request_token_encrypted, encryptionKey);
  const access = await tmdbV4Application<{ success: boolean; access_token: string; account_id: string }>(env, "/auth/access_token", {
    method: "POST",
    body: JSON.stringify({ request_token: requestToken }),
  }, requestId);
  if (!access.success || !access.access_token || !access.account_id) throw new RequestProblem(502, "auth_exchange_failed", "TMDb did not complete authorization.");
  const converted = await tmdb<{ success: boolean; session_id: string }>(
    env,
    "/authentication/session/convert/4",
    new URLSearchParams(),
    requestId,
    { method: "POST", body: JSON.stringify({ access_token: access.access_token }) },
  );
  const profile = await tmdb<Record<string, unknown>>(env, "/account", new URLSearchParams({ session_id: converted.session_id }), requestId);
  const accountID = Number(profile.id);
  if (!Number.isSafeInteger(accountID) || accountID <= 0) throw new RequestProblem(502, "invalid_account_profile", "TMDb returned an invalid account profile.");

  const sessionToken = randomToken();
  const csrfToken = randomToken();
  const expiresAt = now + SESSION_MAX_AGE;
  await database.prepare(
    "INSERT INTO sessions (token_hash, account_object_id, account_id, access_token_encrypted, v3_session_encrypted, csrf_hash, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).bind(
    await sha256(sessionToken),
    access.account_id,
    accountID,
    await encryptSecret(access.access_token, encryptionKey),
    await encryptSecret(converted.session_id, encryptionKey),
    await sha256(csrfToken),
    now,
    now,
    expiresAt,
  ).run();
  await database.prepare("UPDATE auth_attempts SET status = 'completed', completed_at = ? WHERE id = ? AND status = 'approved'")
    .bind(now, row.id)
    .run();

  const response = privateJSON(request, env, {
    session_token: row.mode === "web" ? null : sessionToken,
    csrf_token: csrfToken,
    expires_at: new Date(expiresAt * 1000).toISOString(),
    profile: normalizeProfile(profile),
  });
  if (row.mode === "web") response.headers.append("Set-Cookie", sessionCookie(sessionToken, env, SESSION_MAX_AGE));
  return response;
}

async function logout(request: Request, url: URL, env: WorkerAccountEnv, requestId: string): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const session = await authorize(request, env, true);
  const results = await Promise.allSettled([
    tmdb(env, "/authentication/session", new URLSearchParams(), requestId, {
      method: "DELETE",
      body: JSON.stringify({ session_id: session.v3Session }),
    }),
    tmdbV4User(env, session.accessToken, "/auth/access_token", {
      method: "DELETE",
      body: JSON.stringify({ access_token: session.accessToken }),
    }, requestId),
  ]);
  await requireDatabase(env).prepare("DELETE FROM sessions WHERE token_hash = ?").bind(session.row.token_hash).run();
  const response = privateJSON(request, env, { success: true, upstream_revoked: results.every((result) => result.status === "fulfilled") });
  response.headers.append("Set-Cookie", sessionCookie("", env, 0));
  return response;
}

async function rotateCSRF(request: Request, url: URL, env: WorkerAccountEnv): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const session = await authorize(request, env);
  if (session.cookieAuthenticated) validateOrigin(request, env);
  const token = randomToken();
  await requireDatabase(env).prepare("UPDATE sessions SET csrf_hash = ? WHERE token_hash = ?")
    .bind(await sha256(token), session.row.token_hash)
    .run();
  return privateJSON(request, env, { csrf_token: token });
}

async function accountProfile(request: Request, url: URL, env: WorkerAccountEnv, requestId: string): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set(["language"]));
  const session = await authorize(request, env);
  const profile = await tmdb<Record<string, unknown>>(env, "/account", new URLSearchParams({ session_id: session.v3Session }), requestId);
  return privateJSON(request, env, normalizeProfile(profile));
}

async function accountState(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  type: MediaType,
  id: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const session = await authorize(request, env);
  const value = await tmdb<Record<string, unknown>>(env, `/${type}/${id}/account_states`, new URLSearchParams({ session_id: session.v3Session }), requestId);
  return privateJSON(request, env, { media_type: type, media_id: id, ...value });
}

async function episodeState(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  seriesID: number,
  seasonNumber: number,
  episodeNumber: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set());
  const session = await authorize(request, env);
  const value = await tmdb<Record<string, unknown>>(
    env,
    `/tv/${seriesID}/season/${seasonNumber}/episode/${episodeNumber}/account_states`,
    new URLSearchParams({ session_id: session.v3Session }),
    requestId,
  );
  return privateJSON(request, env, { series_id: seriesID, season_number: seasonNumber, episode_number: episodeNumber, ...value });
}

async function library(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  collection: "favorites" | "watchlist",
  type: MediaType,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  const session = await authorize(request, env, request.method !== "GET");
  if (request.method === "GET") {
    rejectUnknown(url, new Set(["language", "page", "sort_by"]));
    const sort = url.searchParams.get("sort_by") ?? "created_at.desc";
    if (!new Set(["created_at.asc", "created_at.desc"]).has(sort)) throw new RequestProblem(400, "invalid_sort", "The account sort order is not supported.");
    const segment = collection === "favorites" ? "favorite" : "watchlist";
    const media = type === "movie" ? "movies" : "tv";
    const result = await tmdb<TmdbPage<TmdbTitle>>(
      env,
      `/account/${session.row.account_id}/${segment}/${media}`,
      new URLSearchParams({ session_id: session.v3Session, language: language(url), page: String(page(url)), sort_by: sort }),
      requestId,
    );
    return privateJSON(request, env, titlePageV2(result, type));
  }
  rejectUnknown(url, new Set());
  const body = await jsonBody<{ media_id?: number; enabled?: boolean; mutation_id?: string }>(request);
  const mediaID = positiveBodyInteger(body.media_id, "media_id");
  if (typeof body.enabled !== "boolean") throw new RequestProblem(400, "invalid_enabled", "enabled must be a boolean.");
  const endpoint = collection === "favorites" ? "favorite" : "watchlist";
  const property = collection === "favorites" ? "favorite" : "watchlist";
  return idempotentMutation(request, env, session, body.mutation_id, `library:${collection}:${type}:${mediaID}`, async (id) => {
    const result = await tmdb<Record<string, unknown>>(
      env,
      `/account/${session.row.account_id}/${endpoint}`,
      new URLSearchParams({ session_id: session.v3Session }),
      requestId,
      { method: "POST", body: JSON.stringify({ media_type: type, media_id: mediaID, [property]: body.enabled }) },
    );
    return { mutation_id: id, media_type: type, media_id: mediaID, enabled: body.enabled, ...result };
  });
}

async function rating(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  type: MediaType,
  id: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  const session = await authorize(request, env, request.method !== "GET");
  rejectUnknown(url, new Set());
  if (request.method === "GET") {
    const value = await tmdb<Record<string, unknown>>(env, `/${type}/${id}/account_states`, new URLSearchParams({ session_id: session.v3Session }), requestId);
    return privateJSON(request, env, { media_type: type, media_id: id, rated: value.rated ?? false });
  }
  const body = request.method === "DELETE" ? {} : await jsonBody<{ value?: number; mutation_id?: string }>(request);
  return idempotentMutation(request, env, session, body.mutation_id, `rating:${type}:${id}`, async (mutation) => {
    const result = await tmdb<Record<string, unknown>>(
      env,
      `/${type}/${id}/rating`,
      new URLSearchParams({ session_id: session.v3Session }),
      requestId,
      request.method === "DELETE"
        ? { method: "DELETE" }
        : { method: "POST", body: JSON.stringify({ value: ratingValue(body.value) }) },
    );
    return { mutation_id: mutation, media_type: type, media_id: id, value: request.method === "DELETE" ? null : body.value, ...result };
  });
}

async function episodeRating(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  seriesID: number,
  seasonNumber: number,
  episodeNumber: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  const session = await authorize(request, env, request.method !== "GET");
  rejectUnknown(url, new Set());
  const path = `/tv/${seriesID}/season/${seasonNumber}/episode/${episodeNumber}`;
  if (request.method === "GET") {
    const value = await tmdb<Record<string, unknown>>(env, `${path}/account_states`, new URLSearchParams({ session_id: session.v3Session }), requestId);
    return privateJSON(request, env, { series_id: seriesID, season_number: seasonNumber, episode_number: episodeNumber, rated: value.rated ?? false });
  }
  const body = request.method === "DELETE" ? {} : await jsonBody<{ value?: number; mutation_id?: string }>(request);
  return idempotentMutation(request, env, session, body.mutation_id, `episode-rating:${seriesID}:${seasonNumber}:${episodeNumber}`, async (mutation) => {
    const result = await tmdb<Record<string, unknown>>(
      env,
      `${path}/rating`,
      new URLSearchParams({ session_id: session.v3Session }),
      requestId,
      request.method === "DELETE"
        ? { method: "DELETE" }
        : { method: "POST", body: JSON.stringify({ value: ratingValue(body.value) }) },
    );
    return {
      mutation_id: mutation,
      series_id: seriesID,
      season_number: seasonNumber,
      episode_number: episodeNumber,
      value: request.method === "DELETE" ? null : body.value,
      ...result,
    };
  });
}

async function recommendations(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  type: MediaType,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  rejectUnknown(url, new Set(["language", "page"]));
  const session = await authorize(request, env);
  const value = await tmdbV4User<TmdbPage<TmdbTitle>>(
    env,
    session.accessToken,
    `/account/${encodeURIComponent(session.row.account_object_id)}/${type}/recommendations?language=${encodeURIComponent(language(url))}&page=${page(url)}`,
    { method: "GET" },
    requestId,
  );
  return privateJSON(request, env, titlePageV2(value, type));
}

async function accountLists(request: Request, url: URL, env: WorkerAccountEnv, requestId: string): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  const session = await authorize(request, env, request.method !== "GET");
  if (request.method === "GET") {
    rejectUnknown(url, new Set(["page"]));
    const value = await tmdbV4User<Record<string, unknown>>(
      env,
      session.accessToken,
      `/account/${encodeURIComponent(session.row.account_object_id)}/lists?page=${page(url)}`,
      { method: "GET" },
      requestId,
    );
    return privateJSON(request, env, normalizeUserListPage(value));
  }
  rejectUnknown(url, new Set());
  const body = await jsonBody<Record<string, unknown>>(request);
  const payload = listMetadata(body, true);
  return idempotentMutation(request, env, session, typeof body.mutation_id === "string" ? body.mutation_id : undefined, "list:create", async (mutation) => {
    const value = await tmdbV4User<Record<string, unknown>>(env, session.accessToken, "/list", { method: "POST", body: JSON.stringify(payload) }, requestId);
    return { mutation_id: mutation, ...value };
  }, 201);
}

async function accountList(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  listID: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  const session = await authorize(request, env, request.method !== "GET");
  if (request.method === "GET") {
    rejectUnknown(url, new Set(["language", "page"]));
    const value = await tmdbV4User<Record<string, unknown>>(
      env,
      session.accessToken,
      `/list/${listID}?language=${encodeURIComponent(language(url))}&page=${page(url)}`,
      { method: "GET" },
      requestId,
    );
    return privateJSON(request, env, normalizeUserList(value, true));
  }
  rejectUnknown(url, new Set());
  const body = request.method === "DELETE" ? {} : await jsonBody<Record<string, unknown>>(request);
  const method = request.method === "DELETE" ? "DELETE" : "PUT";
  return idempotentMutation(request, env, session, typeof body.mutation_id === "string" ? body.mutation_id : undefined, `list:${method.toLowerCase()}:${listID}`, async (mutation) => {
    const value = await tmdbV4User<Record<string, unknown>>(
      env,
      session.accessToken,
      `/list/${listID}`,
      method === "DELETE"
        ? { method: "DELETE" }
        : { method: "PUT", body: JSON.stringify(listMetadata(body, false)) },
      requestId,
    );
    return { mutation_id: mutation, list_id: listID, ...value };
  });
}

async function accountListItems(
  request: Request,
  url: URL,
  env: WorkerAccountEnv,
  requestId: string,
  listID: number,
): Promise<Response> {
  if (request.method === "OPTIONS") return preflight(request, env);
  if (request.method === "GET") throw new RequestProblem(400, "unsupported_method", "List items are returned by the list detail route.");
  rejectUnknown(url, new Set());
  const session = await authorize(request, env, true);
  const body = await jsonBody<{ items?: unknown[]; mutation_id?: string }>(request);
  const items = listItems(body.items, request.method === "PATCH");
  const method = request.method === "PATCH" ? "PUT" : request.method;
  return idempotentMutation(request, env, session, body.mutation_id, `list-items:${method.toLowerCase()}:${listID}`, async (mutation) => {
    const value = await tmdbV4User<Record<string, unknown>>(
      env,
      session.accessToken,
      `/list/${listID}/items`,
      { method, body: JSON.stringify({ items }) },
      requestId,
    );
    return { mutation_id: mutation, list_id: listID, ...value };
  });
}

async function idempotentMutation(
  request: Request,
  env: WorkerAccountEnv,
  session: SessionContext,
  bodyMutationID: string | undefined,
  kind: string,
  operation: (mutationID: string) => Promise<Record<string, unknown>>,
  responseStatus = 200,
): Promise<Response> {
  const database = requireDatabase(env);
  const id = mutationID(bodyMutationID ?? request.headers.get("Idempotency-Key") ?? undefined);
  const now = epochSeconds();
  let row = await storedMutation(database, session.row.account_id, id);

  if (row && row.kind !== kind) {
    throw new RequestProblem(409, "idempotency_conflict", "This mutation ID was already used for a different operation.");
  }
  if (row?.response_json && row.response_status) {
    return privateJSON(request, env, JSON.parse(row.response_json) as unknown, row.response_status);
  }
  if (row && row.created_at > now - 15 * 60) {
    throw new RequestProblem(409, "mutation_in_progress", "This mutation is already being processed. Retry shortly.");
  }
  if (row) {
    await database.prepare("DELETE FROM account_mutations WHERE account_id = ? AND mutation_id = ? AND completed_at IS NULL")
      .bind(session.row.account_id, id)
      .run();
  }

  const inserted = await database.prepare(
    "INSERT OR IGNORE INTO account_mutations (account_id, mutation_id, kind, created_at) VALUES (?, ?, ?, ?)",
  ).bind(session.row.account_id, id, kind, now).run();
  if ((inserted.meta.changes ?? 0) === 0) {
    row = await storedMutation(database, session.row.account_id, id);
    if (row?.kind !== kind) {
      throw new RequestProblem(409, "idempotency_conflict", "This mutation ID was already used for a different operation.");
    }
    if (row?.response_json && row.response_status) {
      return privateJSON(request, env, JSON.parse(row.response_json) as unknown, row.response_status);
    }
    throw new RequestProblem(409, "mutation_in_progress", "This mutation is already being processed. Retry shortly.");
  }

  try {
    const result = await operation(id);
    const acknowledgement = mutationAcknowledgement(result);
    await database.prepare(
      "UPDATE account_mutations SET response_json = ?, response_status = ?, completed_at = ? WHERE account_id = ? AND mutation_id = ?",
    ).bind(JSON.stringify(acknowledgement), responseStatus, now, session.row.account_id, id).run();
    await database.prepare("DELETE FROM account_mutations WHERE created_at < ?").bind(now - 7 * 24 * 60 * 60).run();
    return privateJSON(request, env, result, responseStatus);
  } catch (error) {
    await database.prepare("DELETE FROM account_mutations WHERE account_id = ? AND mutation_id = ? AND completed_at IS NULL")
      .bind(session.row.account_id, id)
      .run();
    throw error;
  }
}

async function storedMutation(database: D1Database, accountID: number, mutationIDValue: string): Promise<AccountMutationRow | null> {
  return database.prepare(
    "SELECT kind, response_json, response_status, created_at FROM account_mutations WHERE account_id = ? AND mutation_id = ?",
  ).bind(accountID, mutationIDValue).first<AccountMutationRow>();
}

function mutationAcknowledgement(result: Record<string, unknown>): Record<string, unknown> {
  const allowed = new Set(["mutation_id", "success", "status_code", "status_message", "list_id", "media_type", "media_id", "series_id", "season_number", "episode_number", "enabled", "value"]);
  return Object.fromEntries(Object.entries(result).filter(([key]) => allowed.has(key)));
}

async function authorize(request: Request, env: WorkerAccountEnv, requireCSRF = false): Promise<SessionContext> {
  const database = requireDatabase(env);
  const authorization = request.headers.get("Authorization");
  const bearer = authorization?.startsWith("Bearer ") ? authorization.slice(7).trim() : null;
  const cookie = cookieValue(request.headers.get("Cookie"), "smartmovie_session");
  const token = bearer || cookie;
  if (!token) throw new RequestProblem(401, "authentication_required", "A SmartMovie session is required.");
  const tokenHash = await sha256(token);
  const row = await database.prepare(
    "SELECT token_hash, account_object_id, account_id, access_token_encrypted, v3_session_encrypted, csrf_hash, created_at, last_seen_at, expires_at, revoked_at FROM sessions WHERE token_hash = ?",
  ).bind(tokenHash).first<SessionRow>();
  const now = epochSeconds();
  if (!row || row.revoked_at !== null || row.expires_at <= now) {
    if (row) await database.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(tokenHash).run();
    throw new RequestProblem(401, "invalid_session", "The SmartMovie session has expired or was revoked.");
  }
  if (cookie && requireCSRF) {
    const csrf = request.headers.get("X-CSRF-Token") ?? "";
    if (!csrf || !secureEqual(await sha256(csrf), row.csrf_hash)) throw new RequestProblem(403, "csrf_failed", "The CSRF token is missing or invalid.");
    validateOrigin(request, env);
  }
  await database.prepare("UPDATE sessions SET last_seen_at = ?, expires_at = ? WHERE token_hash = ?")
    .bind(now, now + SESSION_MAX_AGE, tokenHash)
    .run();
  const encryptionKey = requireEncryptionKey(env);
  return {
    row,
    v3Session: await decryptSecret(row.v3_session_encrypted, encryptionKey),
    accessToken: await decryptSecret(row.access_token_encrypted, encryptionKey),
    cookieAuthenticated: Boolean(cookie),
  };
}

async function tmdbV4Application<T>(env: WorkerAccountEnv, path: string, init: RequestInit, requestId: string): Promise<T> {
  return tmdbV4<T>(env, env.TMDB_BEARER_TOKEN, path, init, requestId);
}

async function tmdbV4User<T>(env: WorkerAccountEnv, accessToken: string, path: string, init: RequestInit, requestId: string): Promise<T> {
  return tmdbV4<T>(env, accessToken, path, init, requestId);
}

async function tmdbV4<T>(env: WorkerAccountEnv, bearer: string, path: string, init: RequestInit, requestId: string): Promise<T> {
  if (!bearer) throw new RequestProblem(500, "missing_secret", "The catalog service is not configured.");
  const url = new URL(`${env.TMDB_V4_BASE_URL ?? "https://api.themoviedb.org/4"}${path}`);
  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      headers: { Authorization: `Bearer ${bearer}`, Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}), ...init.headers },
      cf: { cacheTtl: 0, cacheEverything: false },
    });
  } catch {
    throw new RequestProblem(502, "upstream_unavailable", "TMDb account services are temporarily unavailable.");
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) throw new RequestProblem(401, "account_authorization_failed", "TMDb authorization is no longer valid.");
    if (response.status === 404) throw new RequestProblem(404, "entity_not_found", "The requested account resource was not found.");
    if (response.status === 429) throw new RequestProblem(429, "upstream_rate_limited", "TMDb account services are busy. Please retry shortly.");
    throw new RequestProblem(502, "upstream_error", `TMDb account services returned status ${response.status}.`);
  }
  if (response.status === 204) return {} as T;
  try {
    return await response.json<T>();
  } catch {
    throw new RequestProblem(502, "invalid_upstream_response", `TMDb account services returned an invalid response (${requestId.slice(0, 8)}).`);
  }
}

function privateRoute(id: string, methods: ReadonlySet<string>, handle: V2Route["handle"]): V2Route {
  return { id, ttl: 0, methods, isPrivate: true, handle };
}

function requireDatabase(env: WorkerAccountEnv): D1Database {
  if (!env.AUTH_DB) throw new RequestProblem(503, "account_unavailable", "SmartMovie account services are not configured.");
  return env.AUTH_DB;
}

function requireEncryptionKey(env: WorkerAccountEnv): string {
  if (!env.SESSION_ENCRYPTION_KEY || env.SESSION_ENCRYPTION_KEY.length < 32) {
    throw new RequestProblem(503, "account_unavailable", "SmartMovie account services are not configured.");
  }
  return env.SESSION_ENCRYPTION_KEY;
}

async function authAttempt(database: D1Database, id: string): Promise<AuthAttemptRow> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RequestProblem(404, "auth_attempt_not_found", "The authorization attempt was not found.");
  const row = await database.prepare(
    "SELECT id, state_hash, request_token_encrypted, return_uri, mode, device_code_hash, status, created_at, expires_at, approved_at, completed_at FROM auth_attempts WHERE id = ?",
  ).bind(id).first<AuthAttemptRow>();
  if (!row) throw new RequestProblem(404, "auth_attempt_not_found", "The authorization attempt was not found.");
  return row;
}

async function cleanupExpired(database: D1Database, now: number): Promise<void> {
  await database.batch([
    database.prepare("UPDATE auth_attempts SET status = 'expired' WHERE expires_at <= ? AND status IN ('pending', 'approved')").bind(now),
    database.prepare("DELETE FROM auth_attempts WHERE expires_at < ?").bind(now - 86_400),
    database.prepare("DELETE FROM sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL").bind(now),
    database.prepare("UPDATE auth_housekeeping SET last_cleanup_at = ? WHERE singleton = 1").bind(now),
  ]);
}

async function jsonBody<T>(request: Request): Promise<T> {
  const contentLength = Number(request.headers.get("Content-Length") ?? "0");
  if (contentLength > 65_536) throw new RequestProblem(413, "request_too_large", "The request body is too large.");
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) {
    throw new RequestProblem(400, "invalid_content_type", "A JSON request body is required.");
  }
  try {
    return await request.json<T>();
  } catch {
    throw new RequestProblem(400, "invalid_json", "The request body is not valid JSON.");
  }
}

function privateJSON(request: Request, env: WorkerAccountEnv, value: unknown, status = 200): Response {
  const headers = new Headers({ "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", Vary: "Origin" });
  const origin = request.headers.get("Origin");
  if (origin && originAllowed(origin, env)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Credentials", "true");
  }
  return new Response(JSON.stringify(value), { status, headers });
}

function preflight(request: Request, env: WorkerAccountEnv): Response {
  validateOrigin(request, env);
  const origin = request.headers.get("Origin")!;
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Credentials": "true",
      "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type, Idempotency-Key, X-CSRF-Token, X-SmartMovie-Client",
      "Access-Control-Max-Age": "600",
      Vary: "Origin",
      "Cache-Control": "private, no-store",
    },
  });
}

function validateOrigin(request: Request, env: WorkerAccountEnv): void {
  const origin = request.headers.get("Origin");
  if (!origin || !originAllowed(origin, env)) throw new RequestProblem(403, "origin_not_allowed", "The browser origin is not allowed.");
}

function originAllowed(origin: string, env: WorkerAccountEnv): boolean {
  const allowed = (env.WEB_ORIGIN_ALLOWLIST ?? "https://smartmovie.app,http://localhost:8080")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return allowed.includes(origin);
}

function returnURIAllowed(value: string, env: WorkerAccountEnv): boolean {
  let candidate: URL;
  try {
    candidate = new URL(value);
  } catch {
    return false;
  }
  if (candidate.username || candidate.password || candidate.hash) return false;
  const allowed = (env.AUTH_RETURN_URI_ALLOWLIST?.split(",") ?? DEFAULT_RETURN_URIS).map((item) => item.trim()).filter(Boolean);
  return allowed.some((item) => {
    try {
      const expected = new URL(item);
      return expected.protocol === candidate.protocol && expected.host === candidate.host && expected.pathname === candidate.pathname;
    } catch {
      return false;
    }
  });
}

function validatedCallbackOrigin(env: WorkerAccountEnv): string {
  const value = env.AUTH_CALLBACK_ORIGIN;
  if (!value) throw new RequestProblem(503, "account_unavailable", "The auth callback domain is not configured.");
  const url = new URL(value);
  if (url.protocol !== "https:" && url.hostname !== "localhost") throw new RequestProblem(500, "invalid_callback_origin", "The auth callback domain must use HTTPS.");
  return url.origin;
}

function sessionCookie(token: string, env: WorkerAccountEnv, maxAge: number): string {
  const domain = env.SESSION_COOKIE_DOMAIN ? `; Domain=${env.SESSION_COOKIE_DOMAIN}` : "";
  return `smartmovie_session=${encodeURIComponent(token)}; Path=/v2; Max-Age=${maxAge}; Secure; HttpOnly; SameSite=Lax${domain}`;
}

function cookieValue(header: string | null, name: string): string | null {
  if (!header) return null;
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return decodeURIComponent(rest.join("="));
  }
  return null;
}

function listMetadata(body: Record<string, unknown>, creating: boolean): Record<string, unknown> {
  const name = typeof body.name === "string" ? body.name.trim() : "";
  if ((creating || body.name !== undefined) && (!name || name.length > 100)) throw new RequestProblem(400, "invalid_list_name", "List name must contain between 1 and 100 characters.");
  const description = typeof body.description === "string" ? body.description : "";
  if (description.length > 1000) throw new RequestProblem(400, "invalid_list_description", "List description is too long.");
  const result: Record<string, unknown> = {};
  if (creating || body.name !== undefined) result.name = name;
  if (creating || body.description !== undefined) result.description = description;
  if (creating) {
    result.iso_3166_1 = countryCode(body.iso_3166_1);
    result.iso_639_1 = languageCode(body.iso_639_1);
  }
  if (body.public !== undefined && typeof body.public !== "boolean") throw new RequestProblem(400, "invalid_list_visibility", "public must be a boolean.");
  if (body.public !== undefined || creating) result.public = body.public ?? false;
  if (!creating && body.sort_by !== undefined) {
    if (typeof body.sort_by !== "string" || !/^[a-z_]+\.(asc|desc)$/.test(body.sort_by)) throw new RequestProblem(400, "invalid_sort", "List sort order is invalid.");
    result.sort_by = body.sort_by;
  }
  return result;
}

function listItems(value: unknown[] | undefined, allowComment: boolean): Array<Record<string, unknown>> {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) throw new RequestProblem(400, "invalid_list_items", "List mutation requires between 1 and 100 items.");
  return value.map((raw) => {
    if (!raw || typeof raw !== "object") throw new RequestProblem(400, "invalid_list_item", "Each list item must be an object.");
    const item = raw as Record<string, unknown>;
    if (item.media_type !== "movie" && item.media_type !== "tv") throw new RequestProblem(400, "invalid_media_type", "List item media_type must be movie or tv.");
    const result: Record<string, unknown> = { media_type: item.media_type, media_id: positiveBodyInteger(item.media_id, "media_id") };
    if (allowComment && item.comment !== undefined) {
      if (typeof item.comment !== "string" || item.comment.length > 500) throw new RequestProblem(400, "invalid_comment", "List item comment is too long.");
      result.comment = item.comment;
    }
    return result;
  });
}

function normalizeUserListPage(value: Record<string, unknown>) {
  const results = Array.isArray(value.results) ? value.results : [];
  return {
    page: normalizedPage(value.page, 1),
    total_pages: normalizedPage(value.total_pages, 0),
    results: results
      .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
      .map((item) => normalizeUserList(item, false)),
  };
}

function normalizeUserList(value: Record<string, unknown>, includePagination: boolean) {
  const rawResults = Array.isArray(value.results) ? value.results : [];
  const results = rawResults
    .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
    .map((item) => {
      const mediaType = item.media_type === "movie" || item.media_type === "tv" ? item.media_type : undefined;
      return titleSummaryV2(item as unknown as TmdbTitle, mediaType);
    })
    .filter((item): item is NonNullable<typeof item> => item !== null);
  const normalized = {
    id: Number(value.id),
    name: typeof value.name === "string" ? value.name : "",
    description: typeof value.description === "string" ? value.description : "",
    public: value.public === true,
    results,
  };
  return includePagination
    ? {
        ...normalized,
        page: normalizedPage(value.page, 1),
        total_pages: normalizedPage(value.total_pages, 0),
      }
    : normalized;
}

function normalizedPage(value: unknown, fallback: number): number {
  const candidate = typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
  return Math.min(500, Math.max(fallback === 0 ? 0 : 1, candidate));
}

function normalizeProfile(value: Record<string, unknown>) {
  const avatar = value.avatar && typeof value.avatar === "object" ? value.avatar as Record<string, unknown> : {};
  const tmdbAvatar = avatar.tmdb && typeof avatar.tmdb === "object" ? avatar.tmdb as Record<string, unknown> : {};
  const gravatar = avatar.gravatar && typeof avatar.gravatar === "object" ? avatar.gravatar as Record<string, unknown> : {};
  return {
    id: Number(value.id),
    username: typeof value.username === "string" ? value.username : "",
    name: typeof value.name === "string" ? value.name : "",
    language: typeof value.iso_639_1 === "string" ? value.iso_639_1 : null,
    country: typeof value.iso_3166_1 === "string" ? value.iso_3166_1 : null,
    include_adult: value.include_adult === true,
    avatar_path: typeof tmdbAvatar.avatar_path === "string" ? tmdbAvatar.avatar_path : null,
    gravatar_hash: typeof gravatar.hash === "string" ? gravatar.hash : null,
  };
}

function ratingValue(value: number | undefined): number {
  if (typeof value !== "number" || value < 0.5 || value > 10 || Math.round(value * 2) !== value * 2) {
    throw new RequestProblem(400, "invalid_rating", "Rating must be between 0.5 and 10 in 0.5 increments.");
  }
  return value;
}

function positiveBodyInteger(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) throw new RequestProblem(400, `invalid_${name}`, `${name} must be a positive integer.`);
  return value;
}

function nonNegativeInteger(value: string, name: string): number {
  if (!/^\d+$/.test(value)) throw new RequestProblem(400, `invalid_${name}`, `${name} must be a non-negative integer.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new RequestProblem(400, `invalid_${name}`, `${name} is outside the supported range.`);
  return parsed;
}

function mutationID(value: unknown): string {
  if (value === undefined) return crypto.randomUUID();
  if (typeof value !== "string" || !/^[0-9a-f-]{36}$/i.test(value)) throw new RequestProblem(400, "invalid_mutation_id", "mutation_id must be a UUID.");
  return value;
}

function countryCode(value: unknown): string {
  const code = typeof value === "string" ? value : "US";
  if (!/^[A-Z]{2}$/.test(code)) throw new RequestProblem(400, "invalid_country", "Country must be an ISO 3166-1 alpha-2 code.");
  return code;
}

function languageCode(value: unknown): string {
  const code = typeof value === "string" ? value : "en";
  if (!/^[a-z]{2,3}$/.test(code)) throw new RequestProblem(400, "invalid_language", "List language must be an ISO 639-1 code.");
  return code;
}

function numericCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
}

function parseTMDbExpiry(value: string | undefined): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? Math.floor(timestamp / 1000) : null;
}

function epochSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

function authResultHTML(approved: boolean): string {
  const title = approved ? "SmartMovie connected" : "Authorization denied";
  const message = approved ? "You can return to your TV and finish signing in." : "No account access was granted. You can close this window.";
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${title}</title><body style="font:18px system-ui;background:#101010;color:#fff;padding:48px"><main style="max-width:560px;margin:auto"><h1>${title}</h1><p>${message}</p></main></body></html>`;
}
