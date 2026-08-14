import type { MediaType, TmdbPage, TmdbTitle, TmdbVideo } from "./contracts";

export function summary(item: TmdbTitle, fallbackType?: MediaType) {
  const type = item.media_type === "tv" || item.media_type === "movie" ? item.media_type : fallbackType;
  if (!type) return null;
  return {
    id: item.id,
    media_type: type,
    title: item.title ?? item.name ?? "",
    original_title: item.original_title ?? item.original_name ?? item.title ?? item.name ?? "",
    overview: item.overview ?? "",
    poster_path: item.poster_path ?? null,
    backdrop_path: item.backdrop_path ?? null,
    release_date: item.release_date ?? item.first_air_date ?? null,
    vote_average: item.vote_average ?? 0,
    genre_ids: item.genre_ids ?? item.genres?.map((genre) => genre.id) ?? [],
  };
}

export function pageResponse(page: TmdbPage<TmdbTitle>, fallbackType?: MediaType) {
  return {
    page: page.page,
    total_pages: Math.min(page.total_pages, 500),
    results: page.results
      .map((item) => summary(item, fallbackType))
      .filter((item): item is NonNullable<typeof item> => item !== null),
  };
}

export function detail(primary: TmdbTitle, fallback: TmdbTitle | undefined, type: MediaType) {
  const merged: TmdbTitle = {
    ...fallback,
    ...primary,
    title: primary.title || fallback?.title,
    name: primary.name || fallback?.name,
    original_title: primary.original_title || fallback?.original_title,
    original_name: primary.original_name || fallback?.original_name,
    overview: primary.overview || fallback?.overview,
    poster_path: primary.poster_path ?? fallback?.poster_path,
    backdrop_path: primary.backdrop_path ?? fallback?.backdrop_path,
    release_date: primary.release_date || fallback?.release_date,
    first_air_date: primary.first_air_date || fallback?.first_air_date,
  };
  const normalized = summary(merged, type)!;
  const videos = mergeVideos(primary.videos?.results ?? [], fallback?.videos?.results ?? []);
  return {
    ...normalized,
    genres: primary.genres ?? fallback?.genres ?? [],
    runtime_minutes: type === "movie" ? primary.runtime ?? fallback?.runtime ?? null : primary.episode_run_time?.[0] ?? fallback?.episode_run_time?.[0] ?? null,
    number_of_seasons: type === "tv" ? primary.number_of_seasons ?? fallback?.number_of_seasons ?? null : null,
    status: primary.status ?? fallback?.status ?? null,
    cast: (primary.credits?.cast ?? fallback?.credits?.cast ?? [])
      .slice()
      .sort((a, b) => (a.order ?? 999) - (b.order ?? 999))
      .slice(0, 30)
      .map((member) => ({
        id: member.id,
        name: member.name,
        character: member.character ?? null,
        profile_path: member.profile_path ?? null,
      })),
    videos: videos.map((video) => ({
      id: video.id,
      key: video.key,
      name: video.name,
      site: video.site,
      type: video.type,
      official: video.official ?? false,
      language: video.iso_639_1 ?? null,
    })),
    similar: pageResponse(primary.similar ?? fallback?.similar ?? { page: 1, total_pages: 0, results: [] }, type).results,
  };
}

function mergeVideos(primary: TmdbVideo[], fallback: TmdbVideo[]): TmdbVideo[] {
  const seen = new Set<string>();
  return [...primary, ...fallback].filter((video) => {
    if (video.site !== "YouTube" || seen.has(video.id)) return false;
    seen.add(video.id);
    return true;
  });
}
