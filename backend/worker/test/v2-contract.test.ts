import Ajv2020, { type ValidateFunction } from "ajv/dist/2020.js";
import { afterEach, describe, expect, it, vi } from "vitest";
import accountFixture from "../contract/v2/fixtures/account.json";
import accountRecommendationsFixture from "../contract/v2/fixtures/account-recommendations.json";
import attemptFixture from "../contract/v2/fixtures/auth-attempt.json";
import capabilitiesFixture from "../contract/v2/fixtures/capabilities.json";
import collectionFixture from "../contract/v2/fixtures/collection.json";
import configurationFixture from "../contract/v2/fixtures/configuration.json";
import creditFixture from "../contract/v2/fixtures/credit-detail.json";
import csrfFixture from "../contract/v2/fixtures/csrf.json";
import entitiesFixture from "../contract/v2/fixtures/entities.json";
import episodeFixture from "../contract/v2/fixtures/episode.json";
import errorFixture from "../contract/v2/fixtures/error.json";
import findFixture from "../contract/v2/fixtures/find.json";
import mutationFixture from "../contract/v2/fixtures/mutation.json";
import personFixture from "../contract/v2/fixtures/person.json";
import seasonFixture from "../contract/v2/fixtures/season.json";
import titleFixture from "../contract/v2/fixtures/title-detail.json";
import openapi from "../contract/v2/openapi.json";
import worker, { type Env } from "../src/index";

type SchemaName =
  | "AccountProfile"
  | "AccountState"
  | "AuthAttempt"
  | "Capabilities"
  | "CollectionDetail"
  | "Configuration"
  | "CreditDetail"
  | "CSRFToken"
  | "EntityPage"
  | "EpisodeDetail"
  | "ErrorEnvelope"
  | "FindResult"
  | "MutationResult"
  | "PersonDetail"
  | "SeasonDetail"
  | "TitleDetail"
  | "TitlePage"
  | "UserList";

const schemaID = "https://smartmovie.app/contracts/catalog-v2";
const ajv = new Ajv2020({ allErrors: true, strict: false });
ajv.addFormat("uuid", /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
ajv.addFormat("uri", (value: string) => {
  try { return Boolean(new URL(value)); } catch { return false; }
});
ajv.addFormat("date", /^\d{4}-\d{2}-\d{2}$/);
ajv.addFormat("date-time", (value: string) => Number.isFinite(Date.parse(value)));
ajv.addSchema({ ...openapi, $id: schemaID, $schema: "https://json-schema.org/draft/2020-12/schema" }, schemaID);

const validators = new Map<SchemaName, ValidateFunction>();
const context = { waitUntil: (promise: Promise<unknown>) => void promise };

afterEach(() => vi.unstubAllGlobals());

describe("canonical v2 fixtures", () => {
  it.each([
    ["Capabilities", capabilitiesFixture],
    ["EntityPage", entitiesFixture],
    ["FindResult", findFixture],
    ["TitleDetail", titleFixture],
    ["PersonDetail", personFixture],
    ["CollectionDetail", collectionFixture],
    ["Configuration", configurationFixture],
    ["CreditDetail", creditFixture],
    ["CSRFToken", csrfFixture],
    ["SeasonDetail", seasonFixture],
    ["EpisodeDetail", episodeFixture],
    ["AccountProfile", accountFixture.profile],
    ["AccountState", accountFixture.state],
    ["TitlePage", accountRecommendationsFixture],
    ["UserList", accountFixture.list],
    ["AuthAttempt", attemptFixture],
    ["MutationResult", mutationFixture],
    ["ErrorEnvelope", errorFixture],
  ] as const)("validates %s", (schema, fixture) => expectContract(schema, fixture));
});

describe("v2 Worker contract", () => {
  it("advertises catalog features but disables account features until D1 is bound", async () => {
    const response = await worker.fetch(request("/v2/capabilities"), env(), context);
    expect(response.status).toBe(200);
    const value = await response.json() as { account: Record<string, boolean> };
    expectContract("Capabilities", value);
    expect(Object.values(value.account).every((enabled) => !enabled)).toBe(true);
  });

  it("advertises every canonical account feature when the session broker is configured", async () => {
    const response = await worker.fetch(request("/v2/capabilities"), env({
      AUTH_DB: {} as D1Database,
      SESSION_ENCRYPTION_KEY: "fixture-session-encryption-key-with-at-least-thirty-two-characters",
      AUTH_CALLBACK_ORIGIN: "https://catalog.example",
    }), context);
    expect(response.status).toBe(200);
    const value = await response.json() as {
      account: Record<string, boolean>;
      catalog: Record<string, boolean>;
    };
    expectContract("Capabilities", value);
    expect(value.account).toEqual(capabilitiesFixture.account);
    expect(value.catalog).toEqual(capabilitiesFixture.catalog);
  });

  it.each([
    ["short encryption key", {
      AUTH_DB: {} as D1Database,
      SESSION_ENCRYPTION_KEY: "too-short",
      AUTH_CALLBACK_ORIGIN: "https://catalog.example",
    }],
    ["malformed callback origin", {
      AUTH_DB: {} as D1Database,
      SESSION_ENCRYPTION_KEY: "fixture-session-encryption-key-with-at-least-thirty-two-characters",
      AUTH_CALLBACK_ORIGIN: "not a URL",
    }],
    ["insecure callback origin", {
      AUTH_DB: {} as D1Database,
      SESSION_ENCRYPTION_KEY: "fixture-session-encryption-key-with-at-least-thirty-two-characters",
      AUTH_CALLBACK_ORIGIN: "http://catalog.example",
    }],
  ])("disables every account feature for %s", async (_name, configuration) => {
    const response = await worker.fetch(request("/v2/capabilities"), env(configuration), context);
    expect(response.status).toBe(200);
    const value = await response.json() as { account: Record<string, boolean> };
    expect(Object.values(value.account).every((enabled) => !enabled)).toBe(true);
  });

  it.each([
    ["empty allowlist", "", false, false],
    ["web-only allowlist", "https://smartmovie.app/auth/callback", false, false],
    ["native-only allowlist", "smartmovie://auth/callback", false, true],
  ])(
    "scopes account authentication for %s",
    async (_name, allowlist, expectedBrowser, expectedTV) => {
      const response = await worker.fetch(request("/v2/capabilities"), env({
        AUTH_DB: {} as D1Database,
        SESSION_ENCRYPTION_KEY: "fixture-session-encryption-key-with-at-least-thirty-two-characters",
        AUTH_CALLBACK_ORIGIN: "https://catalog.example",
        AUTH_RETURN_URI_ALLOWLIST: allowlist,
      }), context);
      expect(response.status).toBe(200);
      const value = await response.json() as { account: Record<string, boolean> };
      expect(value.account.browser_auth).toBe(expectedBrowser);
      expect(value.account.tv_qr_auth).toBe(expectedTV);
    },
  );

  it("normalizes mixed search with a stable discriminator", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      if (url.pathname.endsWith("/search/collection")) {
        return Response.json({ page: 1, total_pages: 1, results: [{ id: 2, name: "Saga", overview: "" }] });
      }
      return Response.json({ page: 1, total_pages: 1, results: [
        { id: 1, media_type: "person", name: "Actor", known_for: [] },
        { id: 10, media_type: "movie", title: "Movie", original_title: "Movie", overview: "", genre_ids: [] },
      ] });
    }));
    const response = await worker.fetch(request("/v2/search?query=example&scope=all&language=en-US"), env(), context);
    const value = await response.json() as { results: Array<{ entity_kind: string }> };
    expect(response.status).toBe(200);
    expectContract("EntityPage", value);
    expect(value.results.map((item) => item.entity_kind)).toEqual(["person", "movie", "collection"]);
  });

  it("finds mixed entities by an external ID and forwards the selected source", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toMatch(/\/find\/tt0000010$/);
      expect(url.searchParams.get("external_source")).toBe("imdb_id");
      expect(url.searchParams.get("language")).toBe("vi-VN");
      return Response.json({
        movie_results: [{ id: 10, title: "Example Movie", original_title: "Example Movie", overview: "", genre_ids: [18] }],
        person_results: [{ id: 12, name: "Example Person", known_for_department: "Acting", known_for: [] }],
        tv_season_results: [{ id: 13, season_number: 1, name: "Restricted Series Season", overview: "", episode_count: 8 }],
        tv_episode_results: [{ id: 14, show_id: 15, season_number: 1, episode_number: 1, name: "Restricted Episode", overview: "" }],
      });
    }));

    const response = await worker.fetch(request("/v2/find/tt0000010?source=imdb_id&language=vi-VN"), env(), context);
    const value = await response.json() as { source: string; external_id: string; results: Array<{ entity_kind: string }> };

    expect(response.status).toBe(200);
    expectContract("FindResult", value);
    expect(value.source).toBe("imdb_id");
    expect(value.external_id).toBe("tt0000010");
    expect(value.results.map((item) => item.entity_kind)).toEqual(["movie", "person"]);

    const unlocked = await worker.fetch(
      request("/v2/find/tt0000010?source=imdb_id&language=vi-VN&include_adult=true"),
      env(),
      context,
    );
    const unlockedValue = await unlocked.json() as { results: Array<{ entity_kind: string }> };
    expect(unlockedValue.results.map((item) => item.entity_kind)).toEqual(["movie", "person", "season", "episode"]);
  });

  it("adds stable person and title summaries to TMDb credit details", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toMatch(/\/credit\/52fe425bc3a36847f80181c1$/);
      expect(url.searchParams.get("language")).toBe("ja-JP");
      return Response.json({
        id: "52fe425bc3a36847f80181c1",
        credit_type: "cast",
        department: "Acting",
        job: "Actor",
        character: "Neo",
        media_type: "movie",
        person: { id: 6384, name: "Keanu Reeves", profile_path: "/profile.jpg", known_for_department: "Acting" },
        media: {
          id: 603,
          title: "The Matrix",
          original_title: "The Matrix",
          overview: "Story",
          poster_path: "/poster.jpg",
          release_date: "1999-03-30",
          vote_average: 8.2,
          genre_ids: [28, 878],
        },
      });
    }));

    const response = await worker.fetch(
      request("/v2/credits/52fe425bc3a36847f80181c1?language=ja-JP"),
      env(),
      context,
    );
    const value = await response.json() as {
      credit_id: string;
      person_summary: { entity_kind: string; id: number };
      title_summary: { entity_kind: string; id: number };
    };

    expect(response.status).toBe(200);
    expectContract("CreditDetail", value);
    expect(value.credit_id).toBe("52fe425bc3a36847f80181c1");
    expect(value.person_summary).toMatchObject({ entity_kind: "person", id: 6384 });
    expect(value.title_summary).toMatchObject({ entity_kind: "movie", id: 603 });
  });

  it("partitions person and collection titles by the adult gate", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      const safe = { id: 10, media_type: "movie", title: "Safe", original_title: "Safe", overview: "", genre_ids: [], adult: false };
      const restricted = { id: 11, media_type: "movie", title: "Restricted", original_title: "Restricted", overview: "", genre_ids: [], adult: true };
      if (url.pathname.endsWith("/person/12")) {
        return Response.json({
          id: 12,
          name: "Example Person",
          known_for: [safe, restricted],
          combined_credits: {
            cast: [
              { ...safe, media_type: "movie", credit_id: "safe-credit", name: "Safe" },
              { ...restricted, media_type: "movie", credit_id: "adult-credit", name: "Restricted" },
            ],
            crew: [],
          },
        });
      }
      if (url.pathname.endsWith("/collection/13/images")) return Response.json({});
      if (url.pathname.endsWith("/collection/13")) {
        return Response.json({ id: 13, name: "Collection", parts: [safe, restricted] });
      }
      throw new Error(`Unexpected TMDb route ${url.pathname}`);
    }));

    const safePerson = await worker.fetch(request("/v2/entities/person/12?language=en-US"), env(), context);
    const safePersonValue = await safePerson.json() as {
      known_for: Array<{ id: number }>;
      credits: { cast: Array<{ id: number; adult: boolean }> };
    };
    expect(safePersonValue.known_for.map((item) => item.id)).toEqual([10]);
    expect(safePersonValue.credits.cast).toEqual([expect.objectContaining({ id: 10, adult: false })]);

    const adultPerson = await worker.fetch(request("/v2/entities/person/12?language=en-US&include_adult=true"), env(), context);
    const adultPersonValue = await adultPerson.json() as {
      known_for: Array<{ id: number }>;
      credits: { cast: Array<{ id: number; adult: boolean }> };
    };
    expect(adultPersonValue.known_for.map((item) => item.id)).toEqual([10, 11]);
    expect(adultPersonValue.credits.cast.map((item) => item.adult)).toEqual([false, true]);

    const safeCollection = await worker.fetch(request("/v2/entities/collection/13?language=en-US"), env(), context);
    expect((await safeCollection.json() as { parts: Array<{ id: number }> }).parts.map((item) => item.id)).toEqual([10]);
    const adultCollection = await worker.fetch(
      request("/v2/entities/collection/13?language=en-US&include_adult=true"),
      env(),
      context,
    );
    expect((await adultCollection.json() as { parts: Array<{ id: number }> }).parts.map((item) => item.id)).toEqual([10, 11]);
  });

  it("defensively filters organization and keyword discovery responses", async () => {
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      if (url.pathname.endsWith("/company/14")) return Response.json({ id: 14, name: "Studio" });
      if (url.pathname.endsWith("/keyword/16")) return Response.json({ id: 16, name: "example" });
      if (url.pathname.endsWith("/discover/movie")) {
        return Response.json({ page: 1, total_pages: 1, results: [
          { id: 10, title: "Safe", original_title: "Safe", overview: "", genre_ids: [], adult: false },
          { id: 11, title: "Restricted", original_title: "Restricted", overview: "", genre_ids: [], adult: true },
        ] });
      }
      throw new Error(`Unexpected TMDb route ${url.pathname}`);
    });
    vi.stubGlobal("fetch", upstream);

    const company = await worker.fetch(request("/v2/entities/company/14?language=en-US"), env(), context);
    expect((await company.json() as { titles: { results: Array<{ id: number }> } }).titles.results.map((item) => item.id)).toEqual([10]);
    const keyword = await worker.fetch(request("/v2/entities/keyword/16?language=en-US"), env(), context);
    expect((await keyword.json() as { titles: { results: Array<{ id: number }> } }).titles.results.map((item) => item.id)).toEqual([10]);
    const unlocked = await worker.fetch(
      request("/v2/entities/company/14?language=en-US&include_adult=true"),
      env(),
      context,
    );
    expect((await unlocked.json() as { titles: { results: Array<{ id: number }> } }).titles.results.map((item) => item.id)).toEqual([10, 11]);
    expect(upstream).toHaveBeenCalled();
  });

  it("hides an adult credit detail unless the request is explicitly unlocked", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      id: "adult-credit",
      credit_type: "cast",
      media_type: "movie",
      person: { id: 12, name: "Example Person" },
      media: {
        id: 99,
        title: "Restricted",
        original_title: "Restricted",
        overview: "",
        genre_ids: [],
        adult: true,
      },
    })));

    const hidden = await worker.fetch(request("/v2/credits/adult-credit?language=en-US"), env(), context);
    expect(hidden.status).toBe(404);
    await expect(hidden.json()).resolves.toMatchObject({ error: { code: "entity_not_found" } });

    const visible = await worker.fetch(
      request("/v2/credits/adult-credit?language=en-US&include_adult=true"),
      env(),
      context,
    );
    expect(visible.status).toBe(200);
    expect((await visible.json() as { title_summary: { adult: boolean } }).title_summary.adult).toBe(true);
  });

  it("returns a deep title that conforms to the v2 schema", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      id: 10,
      title: "Movie",
      original_title: "Movie",
      overview: "Story",
      adult: false,
      genres: [{ id: 18, name: "Drama" }],
      credits: { cast: [], crew: [] },
      videos: { results: [] },
      reviews: { page: 1, total_pages: 0, results: [] },
      recommendations: { page: 1, total_pages: 0, results: [] },
      similar: { page: 1, total_pages: 0, results: [] },
      images: {},
      alternative_titles: { titles: [{ iso_3166_1: "VN", title: "Phim Mẫu", type: "Localized title" }] },
      release_dates: {
        results: [{
          iso_3166_1: "US",
          release_dates: [{ certification: "PG-13", release_date: "2026-08-25T00:00:00.000Z", type: 3 }],
        }],
      },
      translations: {
        translations: [{
          iso_639_1: "vi",
          iso_3166_1: "VN",
          name: "Tiếng Việt",
          english_name: "Vietnamese",
          data: { title: "Phim Mẫu" },
        }],
      },
      "watch/providers": { results: {} },
    })));
    const response = await worker.fetch(request("/v2/titles/movie/10?language=en-US"), env(), context);
    const value = await response.json() as {
      alternative_titles: Array<{ title: string }>;
      release_information: Array<{ release_dates: Array<{ certification: string }> }>;
      translations: Array<{ data: { title: string } }>;
    };
    expect(response.status).toBe(200);
    expectContract("TitleDetail", value);
    expect(value.alternative_titles[0]?.title).toBe("Phim Mẫu");
    expect(value.release_information[0]?.release_dates[0]?.certification).toBe("PG-13");
    expect(value.translations[0]?.data.title).toBe("Phim Mẫu");
  });

  it("maps TV alternative titles from the TMDb results envelope", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      id: 20,
      name: "Series",
      original_name: "Series",
      overview: "Story",
      adult: false,
      genres: [],
      aggregate_credits: { cast: [], crew: [] },
      videos: { results: [] },
      reviews: { page: 1, total_pages: 0, results: [] },
      recommendations: { page: 1, total_pages: 0, results: [] },
      similar: { page: 1, total_pages: 0, results: [] },
      images: {},
      alternative_titles: { results: [{ iso_3166_1: "VN", title: "Loạt phim mẫu", type: "Localized title" }] },
      content_ratings: { results: [] },
      translations: { translations: [] },
      "watch/providers": { results: {} },
    })));
    const response = await worker.fetch(request("/v2/titles/tv/20?language=vi-VN"), env(), context);
    const value = await response.json() as { alternative_titles: Array<{ title: string }> };
    expect(response.status).toBe(200);
    expectContract("TitleDetail", value);
    expect(value.alternative_titles).toEqual([
      { iso_3166_1: "VN", title: "Loạt phim mẫu", type: "Localized title" },
    ]);
  });

  it("keeps account errors private and returns the v2 error envelope", async () => {
    const response = await worker.fetch(new Request("https://catalog.example/v2/account/profile", {
      headers: { Authorization: "Bearer opaque-not-tmdb" },
    }), env(), context);
    const value = await response.json();
    expect(response.status).toBe(503);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expectContract("ErrorEnvelope", value);
    expect(value).toMatchObject({ error: { code: "account_unavailable", retry_after: null } });
  });

  it("validates advanced discovery before contacting TMDb", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request("/v2/discover/movie?watch_providers=8%7C9&language=en-US"), env(), context);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "missing_watch_region" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("requires a watch region for monetization-only discovery", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request("/v2/discover/tv?watch_monetization_types=free%7Cads"), env(), context);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "missing_watch_region" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects impossible calendar dates before contacting TMDb", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request("/v2/discover/movie?release_date_gte=2026-99-99"), env(), context);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "invalid_release_date_gte" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([
    ["movie", "networks=213", "invalid_networks"],
    ["movie", "air_date_gte=2026-01-01", "invalid_air_date_gte"],
    ["tv", "region=VN", "invalid_region"],
    ["tv", "certification_country=US", "invalid_certification_country"],
    ["tv", "sort_by=revenue.desc", "invalid_sort"],
  ])("rejects %s discovery filters unsupported by TMDb (%s)", async (type, query, code) => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    const response = await worker.fetch(request(`/v2/discover/${type}?${query}`), env(), context);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("forwards the complete advanced discovery filter set", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      expect(url.pathname).toBe("/3/discover/tv");
      expect(Object.fromEntries(url.searchParams)).toMatchObject({
        language: "vi-VN",
        page: "2",
        include_adult: "true",
        sort_by: "first_air_date.desc",
        with_genres: "18,10765",
        "first_air_date.gte": "2024-01-01",
        "first_air_date.lte": "2026-08-26",
        "air_date.gte": "2026-01-01",
        "air_date.lte": "2026-12-31",
        with_original_language: "ko",
        with_origin_country: "KR",
        watch_region: "VN",
        "with_runtime.gte": "25",
        "with_runtime.lte": "90",
        "vote_average.gte": "7.5",
        "vote_count.gte": "100",
        with_watch_providers: "8|337",
        with_watch_monetization_types: "flatrate|buy",
      });
      return Response.json({ page: 2, total_pages: 2, results: [] });
    }));
    const query = new URLSearchParams({
      language: "vi-VN", page: "2", include_adult: "true", sort_by: "primary_release_date.desc",
      genres: "18,10765", release_date_gte: "2024-01-01", release_date_lte: "2026-08-26",
      air_date_gte: "2026-01-01", air_date_lte: "2026-12-31", original_language: "ko",
      origin_country: "KR", watch_region: "VN", runtime_gte: "25", runtime_lte: "90",
      vote_average_gte: "7.5", vote_count_gte: "100", watch_providers: "8|337",
      watch_monetization_types: "flatrate|buy",
    });
    const response = await worker.fetch(request(`/v2/discover/tv?${query}`), env(), context);
    expect(response.status).toBe(200);
    expectContract("EntityPage", await response.json());
  });

  it("returns normalized region-aware provider options in configuration", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      if (url.pathname === "/3/configuration") return Response.json({ images: {}, change_keys: ["title"] });
      if (url.pathname === "/3/configuration/countries") return Response.json(configurationFixture.countries);
      if (url.pathname === "/3/configuration/languages") return Response.json(configurationFixture.languages);
      if (url.pathname === "/3/watch/providers/regions") {
        return Response.json({ results: configurationFixture.watch_provider_regions });
      }
      expect(url.searchParams.get("watch_region")).toBe("US");
      if (url.pathname === "/3/watch/providers/movie") {
        return Response.json({ results: [
          { provider_id: 9, provider_name: "Provider B", logo_path: null, display_priority: 2 },
          { provider_id: 8, provider_name: "Provider A", logo_path: "/a.jpg", display_priority: 1 },
          { provider_id: 8, provider_name: "Duplicate", display_priority: 99 },
          { provider_id: -1, provider_name: "Invalid" },
        ] });
      }
      return Response.json({ results: [{ provider_id: 337, provider_name: "Provider TV", display_priority: 0 }] });
    }));

    const response = await worker.fetch(request("/v2/configuration?language=en-US&region=US"), env(), context);
    const value = await response.json() as {
      watch_providers: { movie: unknown[]; tv: unknown[] };
    };
    expect(response.status).toBe(200);
    expectContract("Configuration", value);
    expect(value.watch_providers.movie).toEqual([
      { id: 9, name: "Provider B", logo_path: null, display_priority: 2 },
      { id: 8, name: "Duplicate", logo_path: null, display_priority: 99 },
    ]);
    expect(value.watch_providers.tv).toEqual([
      { id: 337, name: "Provider TV", logo_path: null, display_priority: 0 },
    ]);
  });
});

function expectContract(schema: SchemaName, value: unknown): void {
  let validate = validators.get(schema);
  if (!validate) {
    validate = ajv.getSchema(`${schemaID}#/components/schemas/${schema}`);
    if (!validate) throw new Error(`OpenAPI schema ${schema} was not registered.`);
    validators.set(schema, validate);
  }
  expect(validate(value), ajv.errorsText(validate.errors, { separator: "\n" })).toBe(true);
}

function request(path: string): Request {
  return new Request(`https://catalog.example${path}`, { headers: { "X-SmartMovie-Client": "fixture-client" } });
}

function env(overrides: Partial<Env> = {}): Env {
  return {
    TMDB_BEARER_TOKEN: "test-token",
    TMDB_BASE_URL: "https://tmdb.example/3",
    RELEASE_TRAIN: "3.0.0",
    ...overrides,
  };
}
