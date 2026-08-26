import type { TmdbPage, TmdbTitle } from "./contracts";

export type EntityKind =
  | "movie"
  | "tv"
  | "person"
  | "collection"
  | "company"
  | "network"
  | "keyword"
  | "season"
  | "episode";

export type SearchScopeV2 = "all" | Exclude<EntityKind, "network" | "season" | "episode">;
export type TimeWindow = "day" | "week";

export interface TmdbPerson {
  id: number;
  name?: string;
  biography?: string;
  birthday?: string | null;
  deathday?: string | null;
  place_of_birth?: string | null;
  homepage?: string | null;
  profile_path?: string | null;
  known_for_department?: string;
  popularity?: number;
  also_known_as?: string[];
  known_for?: TmdbTitle[];
  images?: { profiles?: TmdbImage[] };
  combined_credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
  external_ids?: Record<string, string | null | undefined>;
}

export interface TmdbCollection {
  id: number;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  parts?: TmdbTitle[];
  images?: { backdrops?: TmdbImage[]; posters?: TmdbImage[] };
}

export interface TmdbCompany {
  id: number;
  name?: string;
  description?: string;
  headquarters?: string;
  homepage?: string;
  logo_path?: string | null;
  origin_country?: string;
  parent_company?: TmdbCompany | null;
}

export interface TmdbKeyword {
  id: number;
  name?: string;
}

export interface TmdbCredit {
  id: number;
  name: string;
  credit_id?: string;
  media_type?: string;
  title?: string;
  original_title?: string;
  original_name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  profile_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  genre_ids?: number[];
  character?: string;
  job?: string;
  department?: string;
  known_for_department?: string;
  order?: number;
  episode_count?: number;
}

export interface TmdbCreditDetail {
  id?: string;
  credit_type?: string;
  department?: string;
  job?: string;
  character?: string;
  media_type?: string;
  media?: TmdbTitle;
  person?: TmdbPerson;
  [key: string]: unknown;
}

export interface TmdbImage {
  file_path: string;
  aspect_ratio?: number;
  height?: number;
  width?: number;
  iso_639_1?: string | null;
  vote_average?: number;
}

export interface TmdbReview {
  id: string;
  author?: string;
  content?: string;
  created_at?: string;
  updated_at?: string;
  url?: string;
  author_details?: {
    name?: string;
    username?: string;
    avatar_path?: string | null;
    rating?: number | null;
  };
}

export interface TmdbSeason {
  id: number;
  season_number: number;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  air_date?: string | null;
  vote_average?: number;
  episode_count?: number;
  episodes?: TmdbEpisode[];
  credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
  aggregate_credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
  guest_stars?: TmdbCredit[];
  images?: { posters?: TmdbImage[] };
  videos?: { results?: TmdbVideoV2[] };
  external_ids?: Record<string, string | null | undefined>;
}

export interface TmdbEpisode {
  id: number;
  episode_number: number;
  season_number: number;
  name?: string;
  overview?: string;
  still_path?: string | null;
  air_date?: string | null;
  runtime?: number | null;
  vote_average?: number;
  vote_count?: number;
  production_code?: string;
  crew?: TmdbCredit[];
  guest_stars?: TmdbCredit[];
  credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[]; guest_stars?: TmdbCredit[] };
  images?: { stills?: TmdbImage[] };
  videos?: { results?: TmdbVideoV2[] };
  external_ids?: Record<string, string | null | undefined>;
}

export interface TmdbVideoV2 {
  id: string;
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  iso_639_1?: string;
  iso_3166_1?: string;
  published_at?: string;
  size?: number;
}

export interface TmdbFindResponse {
  movie_results?: TmdbTitle[];
  tv_results?: TmdbTitle[];
  person_results?: TmdbPerson[];
  tv_episode_results?: TmdbEpisode[];
  tv_season_results?: TmdbSeason[];
}

export interface TmdbProviderResult {
  link?: string;
  flatrate?: TmdbProvider[];
  rent?: TmdbProvider[];
  buy?: TmdbProvider[];
  ads?: TmdbProvider[];
  free?: TmdbProvider[];
}

export interface TmdbProvider {
  provider_id: number;
  provider_name?: string;
  logo_path?: string | null;
  display_priority?: number;
}

export interface TmdbTitleV2 extends TmdbTitle {
  adult?: boolean;
  tagline?: string;
  homepage?: string | null;
  original_language?: string;
  origin_country?: string[];
  production_countries?: Array<{ iso_3166_1: string; name: string }>;
  production_companies?: TmdbCompany[];
  networks?: TmdbCompany[];
  created_by?: TmdbCredit[];
  seasons?: TmdbSeason[];
  belongs_to_collection?: TmdbCollection | null;
  popularity?: number;
  vote_count?: number;
  budget?: number;
  revenue?: number;
  imdb_id?: string | null;
  credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
  aggregate_credits?: { cast?: TmdbCredit[]; crew?: TmdbCredit[] };
  alternative_titles?: {
    titles?: Array<{ iso_3166_1?: string; title?: string; type?: string }>;
    results?: Array<{ iso_3166_1?: string; title?: string; type?: string }>;
  };
  external_ids?: Record<string, string | null | undefined>;
  images?: { backdrops?: TmdbImage[]; posters?: TmdbImage[]; logos?: TmdbImage[] };
  reviews?: TmdbPage<TmdbReview>;
  recommendations?: TmdbPage<TmdbTitle>;
  release_dates?: { results?: unknown[] };
  content_ratings?: { results?: unknown[] };
  translations?: { translations?: unknown[] };
  "watch/providers"?: { results?: Record<string, TmdbProviderResult> };
}

export interface CapabilitiesV2 {
  api_version: "v2";
  release_train: string;
  catalog: Record<string, boolean>;
  account: Record<string, boolean>;
  supported_languages: string[];
  supported_entity_kinds: EntityKind[];
  adult_content: { supported: boolean; default_enabled: false; local_pin_required: true };
}
