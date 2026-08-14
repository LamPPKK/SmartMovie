import type { MediaType } from "./contracts";

export class RequestProblem extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const languages = new Set(["en-US", "vi-VN", "ja-JP", "ko-KR", "zh-CN", "zh-TW"]);
const scopes = new Set(["all", "movie", "tv"]);
const sorts = new Set(["popularity.desc", "vote_average.desc", "primary_release_date.desc"]);

export function mediaType(value: string): MediaType {
  if (value !== "movie" && value !== "tv") {
    throw new RequestProblem(404, "not_found", "The requested catalog route does not exist.");
  }
  return value;
}

export function language(url: URL): string {
  const value = url.searchParams.get("language") ?? "en-US";
  if (!languages.has(value)) {
    throw new RequestProblem(400, "invalid_language", "The requested language is not supported.");
  }
  return value;
}

export function page(url: URL): number {
  return boundedInteger(url.searchParams.get("page") ?? "1", "page", 1, 500);
}

export function titleID(value: string): number {
  return boundedInteger(value, "id", 1, Number.MAX_SAFE_INTEGER);
}

export function searchScope(url: URL): "all" | MediaType {
  const value = url.searchParams.get("scope") ?? "all";
  if (!scopes.has(value)) {
    throw new RequestProblem(400, "invalid_scope", "Search scope must be all, movie, or tv.");
  }
  return value as "all" | MediaType;
}

export function searchQuery(url: URL): string {
  const value = (url.searchParams.get("query") ?? "").trim();
  if (value.length < 1 || value.length > 120) {
    throw new RequestProblem(400, "invalid_query", "Search query must contain between 1 and 120 characters.");
  }
  return value;
}

export function discoverParameters(url: URL, type: MediaType): URLSearchParams {
  const allowed = new Set(["language", "page", "genre_ids", "year", "vote_average_gte", "sort_by"]);
  rejectUnknown(url, allowed);

  const parameters = new URLSearchParams({
    language: language(url),
    page: String(page(url)),
    include_adult: "false",
    include_video: "false",
  });

  const genres = url.searchParams.get("genre_ids");
  if (genres) {
    if (!/^\d+(,\d+)*$/.test(genres)) {
      throw new RequestProblem(400, "invalid_genres", "Genre IDs must be comma-separated integers.");
    }
    parameters.set("with_genres", genres);
  }

  const year = url.searchParams.get("year");
  if (year) {
    const parsed = boundedInteger(year, "year", 1870, 2100);
    parameters.set(type === "movie" ? "primary_release_year" : "first_air_date_year", String(parsed));
  }

  const rating = url.searchParams.get("vote_average_gte");
  if (rating) {
    const parsed = Number(rating);
    if (!Number.isFinite(parsed) || parsed < 0 || parsed > 10) {
      throw new RequestProblem(400, "invalid_rating", "Minimum rating must be between 0 and 10.");
    }
    parameters.set("vote_average.gte", parsed.toFixed(1));
    if (parsed > 0) parameters.set("vote_count.gte", "20");
  }

  const sort = url.searchParams.get("sort_by") ?? "popularity.desc";
  if (!sorts.has(sort)) {
    throw new RequestProblem(400, "invalid_sort", "The requested sort order is not supported.");
  }
  parameters.set("sort_by", type === "tv" && sort === "primary_release_date.desc" ? "first_air_date.desc" : sort);
  return parameters;
}

export function rejectUnknown(url: URL, allowed: ReadonlySet<string>): void {
  for (const key of url.searchParams.keys()) {
    if (!allowed.has(key)) {
      throw new RequestProblem(400, "unsupported_parameter", `Query parameter '${key}' is not supported.`);
    }
  }
}

function boundedInteger(value: string, name: string, minimum: number, maximum: number): number {
  if (!/^\d+$/.test(value)) {
    throw new RequestProblem(400, `invalid_${name}`, `${name} must be an integer.`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new RequestProblem(400, `invalid_${name}`, `${name} is outside the supported range.`);
  }
  return parsed;
}
