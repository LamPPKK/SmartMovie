import type { MediaType, TmdbPage, TmdbTitle } from "./contracts";
import type {
  EntityKind,
  TmdbCollection,
  TmdbCompany,
  TmdbCredit,
  TmdbCreditDetail,
  TmdbEpisode,
  TmdbImage,
  TmdbKeyword,
  TmdbPerson,
  TmdbProvider,
  TmdbProviderResult,
  TmdbReview,
  TmdbSeason,
  TmdbTitleV2,
  TmdbVideoV2,
} from "./contracts-v2";
import { summary } from "./transform";

export function titleSummaryV2(item: TmdbTitle, fallbackType?: MediaType) {
  const value = summary(item, fallbackType);
  return value ? { entity_kind: value.media_type, ...value, adult: (item as TmdbTitle & { adult?: boolean }).adult ?? false } : null;
}

export function personSummary(item: TmdbPerson) {
  return {
    entity_kind: "person" as const,
    id: item.id,
    name: item.name ?? "",
    profile_path: item.profile_path ?? null,
    known_for_department: item.known_for_department ?? null,
    popularity: item.popularity ?? 0,
    known_for: (item.known_for ?? [])
      .map((value) => titleSummaryV2(value))
      .filter((value): value is NonNullable<typeof value> => value !== null),
  };
}

export function collectionSummary(item: TmdbCollection) {
  return {
    entity_kind: "collection" as const,
    id: item.id,
    name: item.name ?? "",
    overview: item.overview ?? "",
    poster_path: item.poster_path ?? null,
    backdrop_path: item.backdrop_path ?? null,
  };
}

export function companySummary(item: TmdbCompany, kind: "company" | "network" = "company") {
  return {
    entity_kind: kind,
    id: item.id,
    name: item.name ?? "",
    logo_path: item.logo_path ?? null,
    origin_country: item.origin_country ?? null,
  };
}

export function keywordSummary(item: TmdbKeyword) {
  return { entity_kind: "keyword" as const, id: item.id, name: item.name ?? "" };
}

export function searchEntity(item: Record<string, unknown>, fallbackKind?: EntityKind) {
  const kind = typeof item.media_type === "string" ? item.media_type : fallbackKind;
  switch (kind) {
    case "movie":
    case "tv":
      return titleSummaryV2(item as unknown as TmdbTitle, kind);
    case "person":
      return personSummary(item as unknown as TmdbPerson);
    case "collection":
      return collectionSummary(item as unknown as TmdbCollection);
    case "company":
      return companySummary(item as unknown as TmdbCompany);
    case "network":
      return companySummary(item as unknown as TmdbCompany, "network");
    case "keyword":
      return keywordSummary(item as unknown as TmdbKeyword);
    default:
      return null;
  }
}

export function entityPage(page: TmdbPage<Record<string, unknown>>, fallbackKind?: EntityKind) {
  return {
    page: Math.max(1, page.page),
    total_pages: Math.min(Math.max(0, page.total_pages), 500),
    results: page.results
      .map((item) => searchEntity(item, fallbackKind))
      .filter((item): item is NonNullable<typeof item> => item !== null),
  };
}

export function titlePageV2(source: TmdbPage<TmdbTitle>, type?: MediaType) {
  return {
    page: Math.max(1, source.page),
    total_pages: Math.min(Math.max(0, source.total_pages), 500),
    results: source.results
      .map((item) => titleSummaryV2(item, type))
      .filter((item): item is NonNullable<typeof item> => item !== null),
  };
}

export function titleDetailV2(item: TmdbTitleV2, type: MediaType) {
  const base = titleSummaryV2(item, type)!;
  const credits = item.aggregate_credits ?? item.credits;
  return {
    ...base,
    tagline: item.tagline ?? "",
    homepage: item.homepage ?? null,
    original_language: item.original_language ?? null,
    origin_countries: item.origin_country ?? item.production_countries?.map((country) => country.iso_3166_1) ?? [],
    adult: item.adult ?? false,
    popularity: item.popularity ?? 0,
    vote_count: item.vote_count ?? 0,
    runtime_minutes: type === "movie" ? item.runtime ?? null : item.episode_run_time?.[0] ?? null,
    number_of_seasons: type === "tv" ? item.number_of_seasons ?? null : null,
    status: item.status ?? null,
    budget: type === "movie" ? item.budget ?? null : null,
    revenue: type === "movie" ? item.revenue ?? null : null,
    genres: item.genres ?? [],
    creators: (item.created_by ?? []).map(credit),
    cast: (credits?.cast ?? []).slice(0, 60).map(credit),
    crew: (credits?.crew ?? []).slice(0, 100).map(credit),
    collection: item.belongs_to_collection ? collectionSummary(item.belongs_to_collection) : null,
    companies: (item.production_companies ?? []).map((value) => companySummary(value)),
    networks: (item.networks ?? []).map((value) => companySummary(value, "network")),
    seasons: (item.seasons ?? []).map(seasonSummary),
    alternative_titles: item.alternative_titles?.titles ?? item.alternative_titles?.results ?? [],
    external_ids: compactRecord(item.external_ids ?? { imdb_id: item.imdb_id }),
    images: normalizeImages(item.images),
    videos: (item.videos?.results ?? []).map(video),
    reviews: page(item.reviews, review),
    recommendations: titlePageV2(item.recommendations ?? emptyPage(), type),
    similar: titlePageV2(item.similar ?? emptyPage(), type).results,
    release_information: type === "movie" ? item.release_dates?.results ?? [] : item.content_ratings?.results ?? [],
    translations: item.translations?.translations ?? [],
    watch_providers: normalizeProviders(item["watch/providers"]?.results ?? {}),
  };
}

export function personDetail(item: TmdbPerson) {
  return {
    ...personSummary(item),
    biography: item.biography ?? "",
    birthday: item.birthday ?? null,
    deathday: item.deathday ?? null,
    place_of_birth: item.place_of_birth ?? null,
    homepage: item.homepage ?? null,
    also_known_as: item.also_known_as ?? [],
    images: (item.images?.profiles ?? []).map((value) => image(value, "profile")),
    credits: {
      cast: (item.combined_credits?.cast ?? []).map(credit),
      crew: (item.combined_credits?.crew ?? []).map(credit),
    },
    external_ids: compactRecord(item.external_ids ?? {}),
  };
}

export function collectionDetail(item: TmdbCollection) {
  return {
    ...collectionSummary(item),
    parts: (item.parts ?? [])
      .map((value) => titleSummaryV2(value, "movie"))
      .filter((value): value is NonNullable<typeof value> => value !== null),
    images: normalizeImages(item.images),
  };
}

export function companyDetail(item: TmdbCompany, kind: "company" | "network", titles: TmdbPage<TmdbTitle>) {
  return {
    ...companySummary(item, kind),
    description: item.description ?? "",
    headquarters: item.headquarters ?? null,
    homepage: item.homepage ?? null,
    parent_company: item.parent_company ? companySummary(item.parent_company) : null,
    titles: titlePageV2(titles),
  };
}

export function keywordDetail(item: TmdbKeyword, titles: TmdbPage<TmdbTitle>) {
  return { ...keywordSummary(item), titles: titlePageV2(titles) };
}

export function seasonDetail(seriesID: number, item: TmdbSeason) {
  return {
    ...seasonSummary(item),
    series_id: seriesID,
    episodes: (item.episodes ?? []).map((value) => episodeSummary(seriesID, value)),
    credits: {
      cast: (item.aggregate_credits?.cast ?? item.credits?.cast ?? []).map(credit),
      crew: (item.aggregate_credits?.crew ?? item.credits?.crew ?? []).map(credit),
    },
    images: (item.images?.posters ?? []).map((value) => image(value, "poster")),
    videos: (item.videos?.results ?? []).map(video),
    external_ids: compactRecord(item.external_ids ?? {}),
  };
}

export function episodeDetail(seriesID: number, item: TmdbEpisode) {
  return {
    ...episodeSummary(seriesID, item),
    production_code: item.production_code ?? null,
    vote_count: item.vote_count ?? 0,
    crew: (item.credits?.crew ?? item.crew ?? []).map(credit),
    guest_stars: (item.credits?.guest_stars ?? item.guest_stars ?? []).map(credit),
    images: (item.images?.stills ?? []).map((value) => image(value, "still")),
    videos: (item.videos?.results ?? []).map(video),
    external_ids: compactRecord(item.external_ids ?? {}),
  };
}

export function credit(value: TmdbCredit) {
  const type = value.media_type === "movie" || value.media_type === "tv" ? value.media_type : null;
  return {
    credit_id: value.credit_id ?? null,
    id: value.id ?? null,
    media_type: type,
    title: value.title ?? value.name ?? null,
    character: value.character ?? null,
    job: value.job ?? null,
    department: value.department ?? value.known_for_department ?? null,
    profile_path: value.profile_path ?? null,
    poster_path: value.poster_path ?? null,
    order: value.order ?? null,
    episode_count: value.episode_count ?? null,
  };
}

export function creditDetail(creditID: string, value: TmdbCreditDetail) {
  const mediaType = value.media_type === "movie" || value.media_type === "tv" ? value.media_type : undefined;
  const person = value.person && Number.isInteger(value.person.id) ? personSummary(value.person) : null;
  const title = value.media && mediaType ? titleSummaryV2(value.media, mediaType) : null;
  return {
    ...value,
    credit_id: creditID,
    credit_type: typeof value.credit_type === "string" ? value.credit_type : null,
    department: typeof value.department === "string" ? value.department : null,
    job: typeof value.job === "string" ? value.job : null,
    character: typeof value.character === "string" ? value.character : null,
    person_summary: person,
    title_summary: title,
  };
}

export function seasonSummary(item: TmdbSeason) {
  return {
    entity_kind: "season" as const,
    id: item.id,
    season_number: item.season_number,
    name: item.name ?? `Season ${item.season_number}`,
    overview: item.overview ?? "",
    poster_path: item.poster_path ?? null,
    air_date: item.air_date ?? null,
    vote_average: item.vote_average ?? 0,
    episode_count: item.episode_count ?? item.episodes?.length ?? 0,
  };
}

export function episodeSummary(seriesID: number, item: TmdbEpisode) {
  return {
    entity_kind: "episode" as const,
    id: item.id,
    series_id: seriesID,
    season_number: item.season_number,
    episode_number: item.episode_number,
    name: item.name ?? `Episode ${item.episode_number}`,
    overview: item.overview ?? "",
    still_path: item.still_path ?? null,
    air_date: item.air_date ?? null,
    runtime_minutes: item.runtime ?? null,
    vote_average: item.vote_average ?? 0,
  };
}

export function normalizeProviders(results: Record<string, TmdbProviderResult>) {
  return Object.entries(results).map(([region, value]) => ({
    region,
    tmdb_url: value.link ?? null,
    attribution: "JustWatch",
    stream: (value.flatrate ?? []).map(provider),
    rent: (value.rent ?? []).map(provider),
    buy: (value.buy ?? []).map(provider),
    ads: (value.ads ?? []).map(provider),
    free: (value.free ?? []).map(provider),
  }));
}

export function relatedResource(
  resource: string,
  raw: Record<string, unknown>,
  type: MediaType,
) {
  switch (resource) {
    case "credits": {
      const value = raw as { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
      return { cast: (value.cast ?? []).map(credit), crew: (value.crew ?? []).map(credit) };
    }
    case "images":
      return normalizeImages(raw as { backdrops?: TmdbImage[]; posters?: TmdbImage[]; logos?: TmdbImage[] });
    case "videos":
      return { results: ((raw.results as TmdbVideoV2[] | undefined) ?? []).map(video) };
    case "reviews":
      return page(raw as unknown as TmdbPage<TmdbReview>, review);
    case "recommendations":
    case "similar":
      return titlePageV2(raw as unknown as TmdbPage<TmdbTitle>, type);
    case "external-ids":
      return { external_ids: compactRecord(raw as Record<string, string | null | undefined>) };
    case "watch-providers":
      return {
        attribution: "JustWatch",
        regions: normalizeProviders((raw.results as Record<string, TmdbProviderResult> | undefined) ?? {}),
      };
    case "translations":
      return { translations: (raw.translations as unknown[] | undefined) ?? [] };
    case "release-information":
      return { results: (raw.results as unknown[] | undefined) ?? [] };
    default:
      return raw;
  }
}

function provider(value: TmdbProvider) {
  return {
    provider_id: value.provider_id,
    provider_name: value.provider_name ?? "",
    logo_path: value.logo_path ?? null,
    display_priority: value.display_priority ?? 0,
  };
}

function normalizeImages(value: { backdrops?: TmdbImage[]; posters?: TmdbImage[]; logos?: TmdbImage[] } | undefined) {
  return {
    backdrops: (value?.backdrops ?? []).map((item) => image(item, "backdrop")),
    posters: (value?.posters ?? []).map((item) => image(item, "poster")),
    logos: (value?.logos ?? []).map((item) => image(item, "logo")),
  };
}

function image(value: TmdbImage, kind: string) {
  return {
    kind,
    file_path: value.file_path,
    aspect_ratio: value.aspect_ratio ?? 0,
    height: value.height ?? 0,
    width: value.width ?? 0,
    language: value.iso_639_1 ?? null,
    vote_average: value.vote_average ?? 0,
  };
}

function video(value: TmdbVideoV2) {
  return {
    id: value.id,
    key: value.key ?? "",
    name: value.name ?? "",
    site: value.site ?? "",
    type: value.type ?? "",
    official: value.official ?? false,
    language: value.iso_639_1 ?? null,
    country: value.iso_3166_1 ?? null,
    published_at: value.published_at ?? null,
    size: value.size ?? null,
  };
}

function review(value: TmdbReview) {
  return {
    id: value.id,
    author: value.author ?? value.author_details?.username ?? "",
    content: value.content ?? "",
    created_at: value.created_at ?? null,
    updated_at: value.updated_at ?? null,
    url: value.url ?? null,
    avatar_path: value.author_details?.avatar_path ?? null,
    rating: value.author_details?.rating ?? null,
  };
}

function page<T, U>(source: TmdbPage<T> | undefined, transform: (value: T) => U) {
  return {
    page: source?.page ?? 1,
    total_pages: Math.min(source?.total_pages ?? 0, 500),
    results: (source?.results ?? []).map(transform),
  };
}

function emptyPage(): TmdbPage<TmdbTitle> {
  return { page: 1, total_pages: 0, results: [] };
}

function compactRecord(value: Record<string, string | null | undefined>) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => typeof item === "string" && item.length > 0));
}
