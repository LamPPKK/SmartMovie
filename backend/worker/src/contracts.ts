export type MediaType = "movie" | "tv";

export interface TmdbPage<T> {
  page: number;
  total_pages: number;
  results: T[];
}

export interface TmdbTitle {
  id: number;
  adult?: boolean;
  media_type?: string;
  title?: string;
  name?: string;
  original_title?: string;
  original_name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  genre_ids?: number[];
  genres?: Array<{ id: number; name: string }>;
  runtime?: number | null;
  episode_run_time?: number[];
  number_of_seasons?: number | null;
  status?: string;
  credits?: { cast?: TmdbCast[] };
  videos?: { results?: TmdbVideo[] };
  similar?: TmdbPage<TmdbTitle>;
}

export interface TmdbCast {
  id: number;
  name: string;
  character?: string;
  profile_path?: string | null;
  order?: number;
}

export interface TmdbVideo {
  id: string;
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  iso_639_1?: string;
}
