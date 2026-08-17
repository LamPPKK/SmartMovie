import type { MediaType, TmdbPage, TmdbTitle } from "./contracts";
import { detail, pageResponse, summary } from "./transform";
import {
  RequestProblem,
  discoverParameters,
  language,
  mediaType,
  page,
  rejectUnknown,
  searchQuery,
  searchScope,
  titleID,
} from "./validation";

interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  TMDB_BEARER_TOKEN: string;
  TMDB_BASE_URL?: string;
  CATALOG_RATE_LIMITER?: RateLimitBinding;
  CF_VERSION_METADATA?: { id: string; tag?: string; timestamp?: string };
}

type Execution = Pick<ExecutionContext, "waitUntil">;
const TMDB_BASE_URL = "https://api.themoviedb.org/3";
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

export default {
  async fetch(request: Request, env: Env, context: Execution): Promise<Response> {
    const requestId = crypto.randomUUID();
    const workerVersion = env.CF_VERSION_METADATA?.id ?? "development";
    try {
      if (request.method !== "GET") {
        throw new RequestProblem(400, "unsupported_method", "Only GET requests are supported.");
      }
      const url = new URL(request.url);
      const match = route(url.pathname);
      if (!match) throw new RequestProblem(404, "not_found", "The requested catalog route does not exist.");

      await enforceRateLimit(request, env, match.id);
      const cached = await readCache(request, workerVersion);
      if (cached) return withWorkerVersion(withHeader(cached, "X-SmartMovie-Cache", "HIT"), workerVersion);

      const response = await match.handle(url, env, requestId);
      if (response.ok) {
        const cacheable = withHeader(response, "Cache-Control", `public, max-age=${match.ttl}`);
        context.waitUntil(writeCache(request, cacheable.clone(), workerVersion));
        return withWorkerVersion(withHeader(cacheable, "X-SmartMovie-Cache", "MISS"), workerVersion);
      }
      return withWorkerVersion(response, workerVersion);
    } catch (error) {
      return withWorkerVersion(errorResponse(error, requestId), workerVersion);
    }
  },
};

interface Route {
  id: string;
  ttl: number;
  handle(url: URL, env: Env, requestId: string): Promise<Response>;
}

export function route(pathname: string): Route | null {
  if (pathname === "/v1/home") return { id: "home", ttl: 900, handle: home };
  if (pathname === "/v1/search") return { id: "search", ttl: 300, handle: search };
  if (pathname === "/v1/configuration") return { id: "configuration", ttl: 86400, handle: configuration };

  let match = pathname.match(/^\/v1\/discover\/(movie|tv)$/);
  if (match) return { id: "discover", ttl: 900, handle: (url, env, id) => discover(url, env, id, mediaType(match![1])) };
  match = pathname.match(/^\/v1\/genres\/(movie|tv)$/);
  if (match) return { id: "genres", ttl: 86400, handle: (url, env, id) => genres(url, env, id, mediaType(match![1])) };
  match = pathname.match(/^\/v1\/titles\/(movie|tv)\/(\d+)$/);
  if (match) {
    return {
      id: "detail",
      ttl: 3600,
      handle: (url, env, id) => title(url, env, id, mediaType(match![1]), titleID(match![2])),
    };
  }
  return null;
}

async function home(url: URL, env: Env, requestId: string): Promise<Response> {
  rejectUnknown(url, new Set(["media_type", "language"]));
  const type = mediaType(url.searchParams.get("media_type") ?? "movie");
  const locale = language(url);
  const endpoints = type === "movie"
    ? [["trending", "/trending/movie/week"], ["popular", "/movie/popular"], ["top_rated", "/movie/top_rated"], ["now_playing", "/movie/now_playing"], ["upcoming", "/movie/upcoming"]]
    : [["trending", "/trending/tv/week"], ["popular", "/tv/popular"], ["top_rated", "/tv/top_rated"], ["airing_today", "/tv/airing_today"], ["on_the_air", "/tv/on_the_air"]];
  const pages = await Promise.all(endpoints.map(([, endpoint]) => tmdb<TmdbPage<TmdbTitle>>(env, endpoint, new URLSearchParams({ language: locale, page: "1" }), requestId)));
  const titles = homeLabels(locale, type);
  const sections = endpoints.map(([id], index) => ({
    id,
    title: titles[id],
    items: pageResponse(pages[index], type).results,
  }));
  return json({ media_type: type, hero: sections[0]?.items[0] ?? null, sections });
}

async function discover(url: URL, env: Env, requestId: string, type: MediaType): Promise<Response> {
  const parameters = discoverParameters(url, type);
  return json(pageResponse(await tmdb<TmdbPage<TmdbTitle>>(env, `/discover/${type}`, parameters, requestId), type));
}

async function search(url: URL, env: Env, requestId: string): Promise<Response> {
  rejectUnknown(url, new Set(["query", "scope", "page", "language"]));
  const query = searchQuery(url);
  const scope = searchScope(url);
  const parameters = new URLSearchParams({ query, language: language(url), page: String(page(url)), include_adult: "false" });
  const endpoint = scope === "all" ? "/search/multi" : `/search/${scope}`;
  const result = await tmdb<TmdbPage<TmdbTitle>>(env, endpoint, parameters, requestId);
  return json(pageResponse({ ...result, results: result.results.filter((item) => scope !== "all" || item.media_type === "movie" || item.media_type === "tv") }, scope === "all" ? undefined : scope));
}

async function title(url: URL, env: Env, requestId: string, type: MediaType, id: number): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  const locale = language(url);
  const parameters = new URLSearchParams({ language: locale, append_to_response: "credits,videos,similar" });
  const primary = await tmdb<TmdbTitle>(env, `/${type}/${id}`, parameters, requestId);
  let fallback: TmdbTitle | undefined;
  if (locale !== "en-US" && needsFallback(primary, type)) {
    fallback = await tmdb<TmdbTitle>(env, `/${type}/${id}`, new URLSearchParams({ language: "en-US", append_to_response: "credits,videos,similar" }), requestId);
  }
  return json(detail(primary, fallback, type));
}

async function genres(url: URL, env: Env, requestId: string, type: MediaType): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  return json(await tmdb(env, `/genre/${type}/list`, new URLSearchParams({ language: language(url) }), requestId));
}

async function configuration(url: URL, env: Env, requestId: string): Promise<Response> {
  rejectUnknown(url, new Set());
  const response = await tmdb<{ images: { secure_base_url: string; poster_sizes: string[]; backdrop_sizes: string[]; profile_sizes: string[] } }>(env, "/configuration", new URLSearchParams(), requestId);
  return json({
    secure_base_url: response.images.secure_base_url,
    poster_sizes: response.images.poster_sizes,
    backdrop_sizes: response.images.backdrop_sizes,
    profile_sizes: response.images.profile_sizes,
  });
}

async function tmdb<T>(env: Env, path: string, parameters: URLSearchParams, requestId: string): Promise<T> {
  if (!env.TMDB_BEARER_TOKEN) throw new RequestProblem(500, "missing_secret", "The catalog service is not configured.");
  const url = new URL(`${env.TMDB_BASE_URL ?? TMDB_BASE_URL}${path}`);
  url.search = parameters.toString();
  let response: Response;
  try {
    response = await fetch(url, {
      headers: { Authorization: `Bearer ${env.TMDB_BEARER_TOKEN}`, Accept: "application/json" },
      cf: { cacheTtl: 0, cacheEverything: false },
    });
  } catch {
    throw new RequestProblem(502, "upstream_unavailable", "The movie catalog is temporarily unavailable.");
  }
  if (!response.ok) {
    if (response.status === 404) throw new RequestProblem(404, "title_not_found", "The requested title was not found.");
    if (response.status === 429) throw new RequestProblem(429, "upstream_rate_limited", "The movie catalog is busy. Please retry shortly.");
    throw new RequestProblem(502, "upstream_error", `The movie catalog returned status ${response.status}.`);
  }
  try {
    return await response.json<T>();
  } catch {
    throw new RequestProblem(502, "invalid_upstream_response", `The movie catalog returned an invalid response (${requestId.slice(0, 8)}).`);
  }
}

async function enforceRateLimit(request: Request, env: Env, routeID: string): Promise<void> {
  if (!env.CATALOG_RATE_LIMITER) return;
  const client = request.headers.get("X-SmartMovie-Client") ?? "anonymous";
  const identity = request.headers.get("CF-Connecting-IP") ?? client;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(identity));
  const key = `${routeID}:${Array.from(new Uint8Array(digest)).slice(0, 12).map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
  if (!(await env.CATALOG_RATE_LIMITER.limit({ key })).success) {
    throw new RequestProblem(429, "rate_limited", "Too many requests. Please retry shortly.");
  }
}

async function readCache(request: Request, workerVersion: string): Promise<Response | undefined> {
  if (typeof caches === "undefined") return undefined;
  return (await caches.default.match(versionedCacheRequest(request, workerVersion))) ?? undefined;
}

async function writeCache(request: Request, response: Response, workerVersion: string): Promise<void> {
  if (typeof caches === "undefined") return;
  await caches.default.put(versionedCacheRequest(request, workerVersion), response);
}

function versionedCacheRequest(request: Request, workerVersion: string): Request {
  const url = new URL(request.url);
  url.searchParams.set("__smartmovie_worker_version", workerVersion);
  return new Request(url, { method: "GET" });
}

function withHeader(response: Response, name: string, value: string): Response {
  const copy = new Response(response.body, response);
  copy.headers.set(name, value);
  return copy;
}

function withWorkerVersion(response: Response, workerVersion: string): Response {
  return withHeader(response, "X-SmartMovie-Worker-Version", workerVersion);
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function errorResponse(error: unknown, requestId: string): Response {
  const problem = error instanceof RequestProblem ? error : new RequestProblem(500, "internal_error", "An unexpected catalog error occurred.");
  const retryAfter = problem.status === 429 ? 60 : undefined;
  const response = json({ error: { code: problem.code, message: problem.message, request_id: requestId, retry_after: retryAfter } }, problem.status);
  response.headers.set("Cache-Control", "no-store");
  if (retryAfter) response.headers.set("Retry-After", String(retryAfter));
  return response;
}

function needsFallback(value: TmdbTitle, type: MediaType): boolean {
  return !(value.overview && (type === "movie" ? value.title : value.name))
    || (value.videos?.results?.length ?? 0) === 0;
}

function homeLabels(locale: string, type: MediaType): Record<string, string> {
  const languageCode = locale === "zh-CN" ? "zh-Hans" : locale === "zh-TW" ? "zh-Hant" : locale.slice(0, 2);
  const labels: Record<string, Record<string, string>> = {
    en: { trending: "Trending", popular: "Popular", top_rated: "Top Rated", now_playing: "Now Playing", upcoming: "Upcoming", airing_today: "Airing Today", on_the_air: "On the Air" },
    vi: { trending: "Xu hướng", popular: "Phổ biến", top_rated: "Đánh giá cao", now_playing: "Đang chiếu", upcoming: "Sắp chiếu", airing_today: "Phát sóng hôm nay", on_the_air: "Đang phát sóng" },
    ja: { trending: "トレンド", popular: "人気", top_rated: "高評価", now_playing: "上映中", upcoming: "近日公開", airing_today: "本日放送", on_the_air: "放送中" },
    ko: { trending: "트렌딩", popular: "인기", top_rated: "높은 평점", now_playing: "현재 상영", upcoming: "개봉 예정", airing_today: "오늘 방영", on_the_air: "방영 중" },
    "zh-Hans": { trending: "热门趋势", popular: "热门", top_rated: "高分", now_playing: "正在上映", upcoming: "即将上映", airing_today: "今日播出", on_the_air: "播出中" },
    "zh-Hant": { trending: "熱門趨勢", popular: "熱門", top_rated: "高分", now_playing: "正在上映", upcoming: "即將上映", airing_today: "今日播出", on_the_air: "播出中" },
  };
  void type;
  return labels[languageCode] ?? labels.en;
}

export { detail, pageResponse, summary } from "./transform";
export { RequestProblem, discoverParameters } from "./validation";
