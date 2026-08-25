import type { MediaType, TmdbPage, TmdbTitle } from "./contracts";
import type {
  CapabilitiesV2,
  EntityKind,
  SearchScopeV2,
  TimeWindow,
  TmdbCollection,
  TmdbCompany,
  TmdbCreditDetail,
  TmdbEpisode,
  TmdbFindResponse,
  TmdbKeyword,
  TmdbPerson,
  TmdbSeason,
  TmdbTitleV2,
} from "./contracts-v2";
import {
  collectionDetail,
  companyDetail,
  creditDetail as normalizeCreditDetail,
  entityPage,
  episodeDetail,
  episodeSummary,
  keywordDetail,
  personDetail,
  relatedResource,
  searchEntity,
  seasonDetail,
  seasonSummary,
  titleDetailV2,
  titleSummaryV2,
} from "./transform-v2";
import { RequestProblem, language, page, rejectUnknown, titleID } from "./validation";

export interface WorkerEnvV2 {
  TMDB_BEARER_TOKEN: string;
  TMDB_BASE_URL?: string;
  TMDB_V4_BASE_URL?: string;
  RELEASE_TRAIN?: string;
}

export interface V2Route {
  id: string;
  ttl: number;
  methods: ReadonlySet<string>;
  isPrivate?: boolean;
  cacheRevisionKey?: string;
  handle(request: Request, url: URL, env: WorkerEnvV2, requestId: string): Promise<Response>;
}

const GET = new Set(["GET"]);
const TMDB_BASE_URL = "https://api.themoviedb.org/3";
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const entityKinds = new Set<EntityKind>([
  "movie", "tv", "person", "collection", "company", "network", "keyword", "season", "episode",
]);
const searchScopes = new Set<SearchScopeV2>(["all", "movie", "tv", "person", "collection", "company", "keyword"]);
const relatedResources = new Set([
  "credits", "images", "videos", "reviews", "recommendations", "similar", "translations",
  "release-information", "external-ids", "watch-providers",
]);

export function routeV2(pathname: string): V2Route | null {
  if (pathname === "/v2/capabilities") return getRoute("v2-capabilities", 60, capabilities);
  if (pathname === "/v2/home") return getRoute("v2-home", 900, home);
  if (pathname === "/v2/search") return getRoute("v2-search", 300, search);
  if (pathname === "/v2/configuration") return getRoute("v2-configuration", 86400, configuration);

  let match = pathname.match(/^\/v2\/discover\/(movie|tv)$/);
  if (match) return getRoute("v2-discover", 900, (request, url, env, id) => discover(request, url, env, id, match![1] as MediaType));

  match = pathname.match(/^\/v2\/trending\/(all|movie|tv|person)\/(day|week)$/);
  if (match) {
    return getRoute("v2-trending", 900, (request, url, env, id) => trending(
      request,
      url,
      env,
      id,
      match![1] as "all" | "movie" | "tv" | "person",
      match![2] as TimeWindow,
    ));
  }

  match = pathname.match(/^\/v2\/find\/([^/]+)$/);
  if (match) return getRoute("v2-find", 3600, (request, url, env, id) => findExternal(request, url, env, id, decodeURIComponent(match![1])));

  match = pathname.match(/^\/v2\/titles\/(movie|tv)\/(\d+)$/);
  if (match) {
    const type = match[1] as MediaType;
    const id = titleID(match[2]);
    return getRoute("v2-title", 3600, (request, url, env, requestId) => title(request, url, env, requestId, type, id), `${type}:${id}`);
  }

  match = pathname.match(/^\/v2\/titles\/(movie|tv)\/(\d+)\/([a-z-]+)$/);
  if (match && relatedResources.has(match[3])) {
    const type = match[1] as MediaType;
    const entityID = titleID(match[2]);
    const resource = match[3];
    return getRoute("v2-title-related", relatedTTL(match[3]), (request, url, env, requestId) => titleRelated(
      request,
      url,
      env,
      requestId,
      type,
      entityID,
      resource,
    ), `${type}:${entityID}`);
  }

  match = pathname.match(/^\/v2\/entities\/(movie|tv|person|collection|company|network|keyword)\/(\d+)$/);
  if (match) {
    const kind = entityKind(match[1]);
    const entityID = titleID(match[2]);
    const revisionKey = kind === "movie" || kind === "tv" || kind === "person" ? `${kind}:${entityID}` : undefined;
    return getRoute("v2-entity", 3600, (request, url, env, id) => entity(request, url, env, id, kind, entityID), revisionKey);
  }

  match = pathname.match(/^\/v2\/tv\/(\d+)\/seasons\/(\d+)$/);
  if (match) {
    const seriesID = titleID(match[1]);
    const seasonNumber = nonNegativeInteger(match[2], "season_number");
    return getRoute("v2-season", 3600, (request, url, env, id) => season(
      request,
      url,
      env,
      id,
      seriesID,
      seasonNumber,
    ), `tv:${seriesID}`);
  }

  match = pathname.match(/^\/v2\/tv\/(\d+)\/seasons\/(\d+)\/episodes\/(\d+)$/);
  if (match) {
    const seriesID = titleID(match[1]);
    const seasonNumber = nonNegativeInteger(match[2], "season_number");
    const episodeNumber = titleID(match[3]);
    return getRoute("v2-episode", 3600, (request, url, env, id) => episode(
      request,
      url,
      env,
      id,
      seriesID,
      seasonNumber,
      episodeNumber,
    ), `tv:${seriesID}`);
  }

  match = pathname.match(/^\/v2\/credits\/([^/]+)$/);
  if (match) return getRoute("v2-credit", 86400, (request, url, env, id) => creditDetail(request, url, env, id, decodeURIComponent(match![1])));

  return null;
}

async function capabilities(_request: Request, url: URL, env: WorkerEnvV2): Promise<Response> {
  rejectUnknown(url, new Set());
  const accountAvailable = Boolean((env as WorkerEnvV2 & {
    AUTH_DB?: D1Database;
    SESSION_ENCRYPTION_KEY?: string;
    AUTH_CALLBACK_ORIGIN?: string;
  }).AUTH_DB && (env as WorkerEnvV2 & { SESSION_ENCRYPTION_KEY?: string }).SESSION_ENCRYPTION_KEY
    && (env as WorkerEnvV2 & { AUTH_CALLBACK_ORIGIN?: string }).AUTH_CALLBACK_ORIGIN);
  const value: CapabilitiesV2 = {
    api_version: "v2",
    release_train: env.RELEASE_TRAIN ?? "3.0.0",
    catalog: {
      deep_title_detail: true,
      people: true,
      seasons_and_episodes: true,
      collections: true,
      trending: true,
      external_id_search: true,
      companies_networks_keywords: true,
      advanced_discover: true,
      watch_providers: true,
    },
    account: {
      browser_auth: accountAvailable,
      tv_qr_auth: accountAvailable,
      favorites: accountAvailable,
      watchlist: accountAvailable,
      ratings: accountAvailable,
      recommendations: accountAvailable,
      mixed_lists: accountAvailable,
    },
    supported_languages: ["en-US", "vi-VN", "ja-JP", "ko-KR", "zh-CN", "zh-TW"],
    supported_entity_kinds: [...entityKinds],
    adult_content: { supported: true, default_enabled: false, local_pin_required: true },
  };
  return json(value);
}

async function home(_request: Request, url: URL, env: WorkerEnvV2, requestId: string): Promise<Response> {
  rejectUnknown(url, new Set(["media_type", "language", "region", "include_adult"]));
  const type = mediaTypeQuery(url.searchParams.get("media_type") ?? "movie");
  const locale = language(url);
  const region = regionQuery(url);
  const adult = booleanQuery(url, "include_adult", false);
  const endpoints = type === "movie"
    ? [["trending", "/trending/movie/week"], ["popular", "/movie/popular"], ["top_rated", "/movie/top_rated"], ["now_playing", "/movie/now_playing"], ["upcoming", "/movie/upcoming"]]
    : [["trending", "/trending/tv/week"], ["popular", "/tv/popular"], ["top_rated", "/tv/top_rated"], ["airing_today", "/tv/airing_today"], ["on_the_air", "/tv/on_the_air"]];
  const parameters = new URLSearchParams({ language: locale, page: "1" });
  if (region) parameters.set("region", region);
  const pages = await Promise.all(endpoints.map(([, endpoint]) => tmdb<TmdbPage<Record<string, unknown>>>(env, endpoint, parameters, requestId)));
  const sections = endpoints.map(([id], index) => ({
    id,
    title: homeLabels(locale)[id],
    items: entityPage({
      ...pages[index],
      results: pages[index].results.filter((item) => adult || item.adult !== true),
    }, type).results,
  }));
  return json({ media_type: type, region, include_adult: adult, hero: sections[0]?.items[0] ?? null, sections });
}

async function discover(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  type: MediaType,
): Promise<Response> {
  const parameters = discoverParametersV2(url, type);
  const result = await tmdb<TmdbPage<Record<string, unknown>>>(env, `/discover/${type}`, parameters, requestId);
  return json(entityPage(result, type));
}

async function trending(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  kind: "all" | "movie" | "tv" | "person",
  window: TimeWindow,
): Promise<Response> {
  rejectUnknown(url, new Set(["language", "page", "include_adult"]));
  const adult = booleanQuery(url, "include_adult", false);
  const parameters = new URLSearchParams({ language: language(url), page: String(page(url)) });
  const result = await tmdb<TmdbPage<Record<string, unknown>>>(env, `/trending/${kind}/${window}`, parameters, requestId);
  return json(entityPage({ ...result, results: result.results.filter((item) => adult || item.adult !== true) }));
}

async function search(_request: Request, url: URL, env: WorkerEnvV2, requestId: string): Promise<Response> {
  rejectUnknown(url, new Set(["query", "scope", "page", "language", "region", "include_adult"]));
  const query = requiredText(url, "query", 120);
  const scope = searchScope(url);
  const pageNumber = page(url);
  const parameters = new URLSearchParams({
    query,
    language: language(url),
    page: String(pageNumber),
    include_adult: String(booleanQuery(url, "include_adult", false)),
  });
  const region = regionQuery(url);
  if (region) parameters.set("region", region);

  if (scope === "all") {
    const [multi, collections] = await Promise.all([
      tmdb<TmdbPage<Record<string, unknown>>>(env, "/search/multi", parameters, requestId),
      tmdb<TmdbPage<Record<string, unknown>>>(env, "/search/collection", parameters, requestId),
    ]);
    const merged = [...multi.results, ...collections.results.map((item) => ({ ...item, media_type: "collection" }))];
    return json({
      page: pageNumber,
      total_pages: Math.min(Math.max(multi.total_pages, collections.total_pages), 500),
      results: merged
        .map((item) => searchEntity(item, item.media_type as EntityKind))
        .filter((item): item is NonNullable<typeof item> => item !== null),
    });
  }

  const result = await tmdb<TmdbPage<Record<string, unknown>>>(env, `/search/${scope}`, parameters, requestId);
  return json(entityPage(result, scope));
}

async function findExternal(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  externalID: string,
): Promise<Response> {
  rejectUnknown(url, new Set(["source", "language"]));
  if (!externalID || externalID.length > 160) throw new RequestProblem(400, "invalid_external_id", "External ID is required.");
  const source = url.searchParams.get("source") ?? "imdb_id";
  if (!new Set(["imdb_id", "tvdb_id", "wikidata_id", "facebook_id", "instagram_id", "twitter_id"]).has(source)) {
    throw new RequestProblem(400, "invalid_external_source", "The external ID source is not supported.");
  }
  const raw = await tmdb<TmdbFindResponse>(
    env,
    `/find/${encodeURIComponent(externalID)}`,
    new URLSearchParams({ external_source: source, language: language(url) }),
    requestId,
  );
  const results = [
    ...(raw.movie_results ?? []).map((item) => titleSummaryV2(item, "movie")),
    ...(raw.tv_results ?? []).map((item) => titleSummaryV2(item, "tv")),
    ...(raw.person_results ?? []).map((item) => searchEntity(item as unknown as Record<string, unknown>, "person")),
    ...(raw.tv_season_results ?? []).map(seasonSummary),
    ...(raw.tv_episode_results ?? []).map((item) => episodeSummary(Number((item as unknown as { show_id?: number }).show_id ?? 0), item)),
  ].filter((item): item is NonNullable<typeof item> => item !== null);
  return json({ source, external_id: externalID, results });
}

async function title(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  type: MediaType,
  id: number,
): Promise<Response> {
  rejectUnknown(url, new Set(["language", "region", "include_adult"]));
  const locale = language(url);
  const adult = booleanQuery(url, "include_adult", false);
  const append = type === "movie"
    ? "alternative_titles,credits,external_ids,images,videos,reviews,recommendations,similar,translations,release_dates,watch/providers"
    : "alternative_titles,aggregate_credits,external_ids,images,videos,reviews,recommendations,similar,translations,content_ratings,watch/providers";
  const parameters = new URLSearchParams({
    language: locale,
    append_to_response: append,
    include_image_language: `${locale.slice(0, 2)},en,null`,
    include_video_language: `${locale.slice(0, 2)},en,null`,
  });
  const item = await tmdb<TmdbTitleV2>(env, `/${type}/${id}`, parameters, requestId);
  if (item.adult === true && !adult) throw new RequestProblem(404, "entity_not_found", "The requested entity was not found.");
  return json(titleDetailV2(item, type));
}

async function titleRelated(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  type: MediaType,
  id: number,
  resource: string,
): Promise<Response> {
  const paged = new Set(["reviews", "recommendations", "similar"]);
  const allowed = new Set(["language", "region", ...(paged.has(resource) ? ["page"] : [])]);
  rejectUnknown(url, allowed);
  const suffix = resource === "release-information"
    ? type === "movie" ? "release_dates" : "content_ratings"
    : resource === "external-ids" ? "external_ids"
      : resource === "watch-providers" ? "watch/providers"
        : resource;
  const parameters = new URLSearchParams({ language: language(url) });
  if (paged.has(resource)) parameters.set("page", String(page(url)));
  const raw = await tmdb<Record<string, unknown>>(env, `/${type}/${id}/${suffix}`, parameters, requestId);
  return json(relatedResource(resource, raw, type));
}

async function entity(
  request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  kind: EntityKind,
  id: number,
): Promise<Response> {
  if (kind === "movie" || kind === "tv") return title(request, url, env, requestId, kind, id);
  rejectUnknown(url, new Set(["language", "page", "include_adult"]));
  const locale = language(url);
  if (kind === "person") {
    const raw = await tmdb<TmdbPerson>(env, `/person/${id}`, new URLSearchParams({
      language: locale,
      append_to_response: "combined_credits,external_ids,images,translations",
    }), requestId);
    return json(personDetail(raw));
  }
  if (kind === "collection") {
    const [raw, images] = await Promise.all([
      tmdb<TmdbCollection>(env, `/collection/${id}`, new URLSearchParams({ language: locale }), requestId),
      tmdb<TmdbCollection["images"]>(env, `/collection/${id}/images`, new URLSearchParams({ language: locale, include_image_language: `${locale.slice(0, 2)},en,null` }), requestId),
    ]);
    return json(collectionDetail({ ...raw, images }));
  }
  if (kind === "company" || kind === "network") {
    const raw = await tmdb<TmdbCompany>(env, `/${kind}/${id}`, new URLSearchParams(), requestId);
    const discoverType: MediaType = kind === "network" ? "tv" : "movie";
    const filter = kind === "network" ? "with_networks" : "with_companies";
    const titles = await tmdb<TmdbPage<TmdbTitle>>(env, `/discover/${discoverType}`, new URLSearchParams({
      language: locale,
      page: String(page(url)),
      [filter]: String(id),
      include_adult: String(booleanQuery(url, "include_adult", false)),
    }), requestId);
    titles.results = titles.results.map((item) => ({ ...item, media_type: discoverType }));
    return json(companyDetail(raw, kind, titles));
  }
  const raw = await tmdb<TmdbKeyword>(env, `/keyword/${id}`, new URLSearchParams(), requestId);
  const titles = await tmdb<TmdbPage<TmdbTitle>>(env, "/discover/movie", new URLSearchParams({
    language: locale,
    page: String(page(url)),
    with_keywords: String(id),
    include_adult: String(booleanQuery(url, "include_adult", false)),
  }), requestId);
  titles.results = titles.results.map((item) => ({ ...item, media_type: "movie" }));
  return json(keywordDetail(raw, titles));
}

async function season(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  seriesID: number,
  seasonNumber: number,
): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  const locale = language(url);
  const raw = await tmdb<TmdbSeason>(env, `/tv/${seriesID}/season/${seasonNumber}`, new URLSearchParams({
    language: locale,
    append_to_response: "aggregate_credits,external_ids,images,videos",
    include_image_language: `${locale.slice(0, 2)},en,null`,
    include_video_language: `${locale.slice(0, 2)},en,null`,
  }), requestId);
  return json(seasonDetail(seriesID, raw));
}

async function episode(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  seriesID: number,
  seasonNumber: number,
  episodeNumber: number,
): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  const locale = language(url);
  const raw = await tmdb<TmdbEpisode>(env, `/tv/${seriesID}/season/${seasonNumber}/episode/${episodeNumber}`, new URLSearchParams({
    language: locale,
    append_to_response: "credits,external_ids,images,videos",
    include_image_language: `${locale.slice(0, 2)},en,null`,
    include_video_language: `${locale.slice(0, 2)},en,null`,
  }), requestId);
  return json(episodeDetail(seriesID, raw));
}

async function creditDetail(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
  creditID: string,
): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(creditID)) throw new RequestProblem(400, "invalid_credit_id", "Credit ID is invalid.");
  const raw = await tmdb<TmdbCreditDetail>(
    env,
    `/credit/${creditID}`,
    new URLSearchParams({ language: language(url) }),
    requestId,
  );
  return json(normalizeCreditDetail(creditID, raw));
}

async function configuration(
  _request: Request,
  url: URL,
  env: WorkerEnvV2,
  requestId: string,
): Promise<Response> {
  rejectUnknown(url, new Set(["language"]));
  const locale = language(url);
  const [configurationValue, countries, languages, regions] = await Promise.all([
    tmdb<{ images: Record<string, unknown>; change_keys?: string[] }>(env, "/configuration", new URLSearchParams(), requestId),
    tmdb<unknown[]>(env, "/configuration/countries", new URLSearchParams({ language: locale }), requestId),
    tmdb<unknown[]>(env, "/configuration/languages", new URLSearchParams(), requestId),
    tmdb<{ results?: unknown[] }>(env, "/watch/providers/regions", new URLSearchParams({ language: locale }), requestId),
  ]);
  return json({
    images: configurationValue.images,
    change_keys: configurationValue.change_keys ?? [],
    countries,
    languages,
    watch_provider_regions: regions.results ?? [],
    attribution: {
      tmdb: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
      watch_providers: "JustWatch",
    },
  });
}

export async function tmdb<T>(
  env: WorkerEnvV2,
  path: string,
  parameters: URLSearchParams,
  requestId: string,
  init: RequestInit = {},
): Promise<T> {
  if (!env.TMDB_BEARER_TOKEN) throw new RequestProblem(500, "missing_secret", "The catalog service is not configured.");
  const url = new URL(`${env.TMDB_BASE_URL ?? TMDB_BASE_URL}${path}`);
  url.search = parameters.toString();
  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      headers: {
        Authorization: `Bearer ${env.TMDB_BEARER_TOKEN}`,
        Accept: "application/json",
        ...(init.body ? { "Content-Type": "application/json" } : {}),
        ...init.headers,
      },
      cf: { cacheTtl: 0, cacheEverything: false },
    });
  } catch {
    throw new RequestProblem(502, "upstream_unavailable", "The movie catalog is temporarily unavailable.");
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) throw new RequestProblem(401, "account_authorization_failed", "TMDb authorization is no longer valid.");
    if (response.status === 404) throw new RequestProblem(404, "entity_not_found", "The requested entity was not found.");
    if (response.status === 429) throw new RequestProblem(429, "upstream_rate_limited", "The movie catalog is busy. Please retry shortly.");
    throw new RequestProblem(502, "upstream_error", `The movie catalog returned status ${response.status}.`);
  }
  if (response.status === 204) return undefined as T;
  try {
    return await response.json<T>();
  } catch {
    throw new RequestProblem(502, "invalid_upstream_response", `The movie catalog returned an invalid response (${requestId.slice(0, 8)}).`);
  }
}

function discoverParametersV2(url: URL, type: MediaType): URLSearchParams {
  const allowed = new Set([
    "language", "page", "sort_by", "include_adult", "region", "genres", "companies", "networks", "keywords",
    "release_date_gte", "release_date_lte", "air_date_gte", "air_date_lte", "original_language", "origin_country",
    "certification_country", "certification_gte", "certification_lte", "runtime_gte", "runtime_lte", "vote_average_gte",
    "vote_count_gte", "watch_region", "watch_providers", "watch_monetization_types", "year",
  ]);
  rejectUnknown(url, allowed);
  const parameters = new URLSearchParams({
    language: language(url),
    page: String(page(url)),
    include_adult: String(booleanQuery(url, "include_adult", false)),
    include_video: "false",
    sort_by: discoverSort(url, type),
  });
  copyCSV(url, parameters, "genres", "with_genres");
  copyCSV(url, parameters, "companies", "with_companies");
  copyCSV(url, parameters, "keywords", "with_keywords");
  if (type === "tv") copyCSV(url, parameters, "networks", "with_networks");
  copyDate(url, parameters, "release_date_gte", type === "movie" ? "primary_release_date.gte" : "first_air_date.gte");
  copyDate(url, parameters, "release_date_lte", type === "movie" ? "primary_release_date.lte" : "first_air_date.lte");
  copyDate(url, parameters, "air_date_gte", "air_date.gte");
  copyDate(url, parameters, "air_date_lte", "air_date.lte");
  copyPattern(url, parameters, "original_language", "with_original_language", /^[a-z]{2,3}$/i);
  copyPattern(url, parameters, "origin_country", "with_origin_country", /^[A-Z]{2}$/);
  copyPattern(url, parameters, "region", "region", /^[A-Z]{2}$/);
  copyPattern(url, parameters, "watch_region", "watch_region", /^[A-Z]{2}$/);
  copyPattern(url, parameters, "certification_country", "certification_country", /^[A-Z]{2}$/);
  copyText(url, parameters, "certification_gte", "certification.gte", 20);
  copyText(url, parameters, "certification_lte", "certification.lte", 20);
  copyInteger(url, parameters, "runtime_gte", "with_runtime.gte", 0, 1000);
  copyInteger(url, parameters, "runtime_lte", "with_runtime.lte", 0, 1000);
  copyNumber(url, parameters, "vote_average_gte", "vote_average.gte", 0, 10);
  copyInteger(url, parameters, "vote_count_gte", "vote_count.gte", 0, 1_000_000_000);
  copyInteger(url, parameters, "year", type === "movie" ? "primary_release_year" : "first_air_date_year", 1870, 2100);
  copyCSV(url, parameters, "watch_providers", "with_watch_providers", "|");
  copyPattern(url, parameters, "watch_monetization_types", "with_watch_monetization_types", /^(flatrate|free|ads|rent|buy)(\|(flatrate|free|ads|rent|buy))*$/);
  if (parameters.has("with_watch_providers") && !parameters.has("watch_region")) {
    throw new RequestProblem(400, "missing_watch_region", "watch_region is required with watch_providers.");
  }
  return parameters;
}

function getRoute(
  id: string,
  ttl: number,
  handle: V2Route["handle"],
  cacheRevisionKey?: string,
): V2Route {
  return { id, ttl, methods: GET, cacheRevisionKey, handle };
}

function mediaTypeQuery(value: string): MediaType {
  if (value !== "movie" && value !== "tv") throw new RequestProblem(400, "invalid_media_type", "Media type must be movie or tv.");
  return value;
}

function entityKind(value: string): EntityKind {
  if (!entityKinds.has(value as EntityKind)) throw new RequestProblem(404, "not_found", "The requested entity route does not exist.");
  return value as EntityKind;
}

function searchScope(url: URL): SearchScopeV2 {
  const value = url.searchParams.get("scope") ?? "all";
  if (!searchScopes.has(value as SearchScopeV2)) throw new RequestProblem(400, "invalid_scope", "The requested search scope is not supported.");
  return value as SearchScopeV2;
}

function regionQuery(url: URL): string | null {
  const value = url.searchParams.get("region");
  if (value !== null && !/^[A-Z]{2}$/.test(value)) throw new RequestProblem(400, "invalid_region", "Region must be an ISO 3166-1 alpha-2 code.");
  return value;
}

function booleanQuery(url: URL, name: string, fallback: boolean): boolean {
  const value = url.searchParams.get(name);
  if (value === null) return fallback;
  if (value !== "true" && value !== "false") throw new RequestProblem(400, `invalid_${name}`, `${name} must be true or false.`);
  return value === "true";
}

function requiredText(url: URL, name: string, maximum: number): string {
  const value = (url.searchParams.get(name) ?? "").trim();
  if (!value || value.length > maximum) throw new RequestProblem(400, `invalid_${name}`, `${name} is required and must be at most ${maximum} characters.`);
  return value;
}

function nonNegativeInteger(value: string, name: string): number {
  if (!/^\d+$/.test(value)) throw new RequestProblem(400, `invalid_${name}`, `${name} must be a non-negative integer.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new RequestProblem(400, `invalid_${name}`, `${name} is outside the supported range.`);
  return parsed;
}

function discoverSort(url: URL, type: MediaType): string {
  const value = url.searchParams.get("sort_by") ?? "popularity.desc";
  const allowed = new Set([
    "popularity.asc", "popularity.desc", "vote_average.asc", "vote_average.desc", "vote_count.asc", "vote_count.desc",
    "primary_release_date.asc", "primary_release_date.desc", "revenue.asc", "revenue.desc",
  ]);
  if (!allowed.has(value)) throw new RequestProblem(400, "invalid_sort", "The requested sort order is not supported.");
  if (type === "tv" && value.startsWith("primary_release_date")) return value.replace("primary_release_date", "first_air_date");
  return value;
}

function copyCSV(url: URL, target: URLSearchParams, source: string, destination: string, separator = ","): void {
  const value = url.searchParams.get(source);
  if (value === null) return;
  const pattern = separator === "|" ? /^\d+(\|\d+)*$/ : /^\d+(,\d+)*$/;
  if (!pattern.test(value)) throw new RequestProblem(400, `invalid_${source}`, `${source} must contain numeric IDs separated by '${separator}'.`);
  target.set(destination, value);
}

function copyDate(url: URL, target: URLSearchParams, source: string, destination: string): void {
  copyPattern(url, target, source, destination, /^\d{4}-\d{2}-\d{2}$/);
}

function copyPattern(url: URL, target: URLSearchParams, source: string, destination: string, pattern: RegExp): void {
  const value = url.searchParams.get(source);
  if (value === null) return;
  if (!pattern.test(value)) throw new RequestProblem(400, `invalid_${source}`, `${source} has an invalid format.`);
  target.set(destination, value);
}

function copyText(url: URL, target: URLSearchParams, source: string, destination: string, maximum: number): void {
  const value = url.searchParams.get(source);
  if (value === null) return;
  if (!value || value.length > maximum) throw new RequestProblem(400, `invalid_${source}`, `${source} is invalid.`);
  target.set(destination, value);
}

function copyInteger(url: URL, target: URLSearchParams, source: string, destination: string, minimum: number, maximum: number): void {
  const value = url.searchParams.get(source);
  if (value === null) return;
  if (!/^\d+$/.test(value)) throw new RequestProblem(400, `invalid_${source}`, `${source} must be an integer.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) throw new RequestProblem(400, `invalid_${source}`, `${source} is outside the supported range.`);
  target.set(destination, String(parsed));
}

function copyNumber(url: URL, target: URLSearchParams, source: string, destination: string, minimum: number, maximum: number): void {
  const value = url.searchParams.get(source);
  if (value === null) return;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum) throw new RequestProblem(400, `invalid_${source}`, `${source} is outside the supported range.`);
  target.set(destination, String(parsed));
}

function relatedTTL(resource: string): number {
  if (resource === "watch-providers" || resource === "release-information") return 21600;
  if (resource === "reviews") return 900;
  return 3600;
}

function homeLabels(locale: string): Record<string, string> {
  const key = locale === "zh-CN" ? "zh-Hans" : locale === "zh-TW" ? "zh-Hant" : locale.slice(0, 2);
  const labels: Record<string, Record<string, string>> = {
    en: { trending: "Trending", popular: "Popular", top_rated: "Top Rated", now_playing: "Now Playing", upcoming: "Upcoming", airing_today: "Airing Today", on_the_air: "On the Air" },
    vi: { trending: "Xu hướng", popular: "Phổ biến", top_rated: "Đánh giá cao", now_playing: "Đang chiếu", upcoming: "Sắp chiếu", airing_today: "Phát sóng hôm nay", on_the_air: "Đang phát sóng" },
    ja: { trending: "トレンド", popular: "人気", top_rated: "高評価", now_playing: "上映中", upcoming: "近日公開", airing_today: "本日放送", on_the_air: "放送中" },
    ko: { trending: "트렌딩", popular: "인기", top_rated: "높은 평점", now_playing: "현재 상영", upcoming: "개봉 예정", airing_today: "오늘 방영", on_the_air: "방영 중" },
    "zh-Hans": { trending: "热门趋势", popular: "热门", top_rated: "高分", now_playing: "正在上映", upcoming: "即将上映", airing_today: "今日播出", on_the_air: "播出中" },
    "zh-Hant": { trending: "熱門趨勢", popular: "熱門", top_rated: "高分", now_playing: "正在上映", upcoming: "即將上映", airing_today: "今日播出", on_the_air: "播出中" },
  };
  return labels[key] ?? labels.en;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}
