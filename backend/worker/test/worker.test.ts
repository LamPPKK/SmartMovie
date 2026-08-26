import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { detail, discoverParameters, pageResponse } from "../src/index";
import type { Env } from "../src/index";
import { episodeDetail, seasonDetail } from "../src/transform-v2";

const context = { waitUntil: (promise: Promise<unknown>) => void promise };

afterEach(() => vi.unstubAllGlobals());

describe("request validation", () => {
  it("rejects unsupported methods and unknown routes without calling TMDb", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);

    const unsupportedMethod = await worker.fetch(
      new Request("https://catalog.example/v1/home", { method: "POST" }),
      env(),
      context,
    );
    const unknownRoute = await worker.fetch(
      new Request("https://catalog.example/v1/proxy"),
      env(),
      context,
    );

    expect(unsupportedMethod.status).toBe(400);
    await expect(unsupportedMethod.json()).resolves.toMatchObject({ error: { code: "unsupported_method" } });
    expect(unknownRoute.status).toBe(404);
    await expect(unknownRoute.json()).resolves.toMatchObject({ error: { code: "not_found" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects unknown query parameters before calling TMDb", async () => {
    const response = await worker.fetch(new Request("https://catalog.example/v1/discover/movie?redirect=https://evil.example"), env(), context);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "unsupported_parameter" } });
  });

  it("maps TV release sorting and year to TMDb fields", () => {
    const url = new URL("https://catalog.example/v1/discover/tv?year=2026&sort_by=primary_release_date.desc&vote_average_gte=7");
    const result = discoverParameters(url, "tv");
    expect(result.get("first_air_date_year")).toBe("2026");
    expect(result.get("sort_by")).toBe("first_air_date.desc");
    expect(result.get("vote_count.gte")).toBe("20");
  });

  it("rejects unsupported languages before calling TMDb", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(
      new Request("https://catalog.example/v1/search?query=film&language=fr-FR"),
      env(),
      context,
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "invalid_language" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([
    ["genre_ids=18,action", "invalid_genres"],
    ["year=1800", "invalid_year"],
    ["vote_average_gte=10.1", "invalid_rating"],
    ["sort_by=revenue.desc", "invalid_sort"],
    ["page=501", "invalid_page"],
  ])("rejects invalid discover query %s", (query, expectedCode) => {
    expect(() => discoverParameters(new URL(`https://catalog.example/v1/discover/movie?${query}`), "movie"))
      .toThrowError(expect.objectContaining({ code: expectedCode }));
  });
});

describe("catalog contract", () => {
  it("serves identical requests from a version-isolated Cache API", async () => {
    const entries = new Map<string, Response>();
    vi.stubGlobal("caches", {
      default: {
        match: async (request: Request) => entries.get(request.url)?.clone(),
        put: async (request: Request, response: Response) => { entries.set(request.url, response.clone()); },
      },
    });
    const upstream = vi.fn(async () => Response.json({ images: {
      secure_base_url: "https://image.tmdb.org/t/p/",
      poster_sizes: ["w500"],
      backdrop_sizes: ["w1280"],
      profile_sizes: ["w185"],
    } }));
    vi.stubGlobal("fetch", upstream);
    const pending: Promise<unknown>[] = [];
    const cacheContext = { waitUntil: (promise: Promise<unknown>) => { pending.push(promise); } };
    const request = new Request("https://catalog.example/v1/configuration");
    const firstVersion = env({ CF_VERSION_METADATA: { id: "version-1" } });

    const miss = await worker.fetch(request, firstVersion, cacheContext);
    await Promise.all(pending);
    const hit = await worker.fetch(request, firstVersion, cacheContext);
    const nextVersion = await worker.fetch(
      request,
      env({ CF_VERSION_METADATA: { id: "version-2" } }),
      cacheContext,
    );
    await Promise.all(pending);

    expect(miss.headers.get("X-SmartMovie-Cache")).toBe("MISS");
    expect(hit.headers.get("X-SmartMovie-Cache")).toBe("HIT");
    expect(hit.headers.get("X-SmartMovie-Worker-Version")).toBe("version-1");
    expect(nextVersion.headers.get("X-SmartMovie-Cache")).toBe("MISS");
    expect(nextVersion.headers.get("X-SmartMovie-Worker-Version")).toBe("version-2");
    expect(upstream).toHaveBeenCalledTimes(2);
  });

  it("removes people from All search and never exposes the token", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      expect(request.headers.get("Authorization")).toBe("Bearer super-secret");
      return Response.json({
        page: 1,
        total_pages: 1,
        results: [
          { id: 1, media_type: "person", name: "Actor" },
          { id: 2, media_type: "movie", title: "Film", original_title: "Film", overview: "", genre_ids: [] },
        ],
      });
    }));
    const response = await worker.fetch(new Request("https://catalog.example/v1/search?query=film&scope=all&language=en-US"), env(), context);
    expect(response.status).toBe(200);
    const body = JSON.stringify(await response.json());
    expect(body).not.toContain("super-secret");
    expect(JSON.parse(body).results).toHaveLength(1);
    expect(JSON.parse(body).results[0].media_type).toBe("movie");
  });

  it("normalizes upstream failures", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("token=super-secret", { status: 503 })));
    const response = await worker.fetch(new Request("https://catalog.example/v1/genres/movie?language=en-US"), env(), context);
    expect(response.status).toBe(502);
    const body = JSON.stringify(await response.json());
    expect(body).not.toContain("super-secret");
    expect(JSON.parse(body).error.code).toBe("upstream_error");
  });

  it("returns a safe configuration error when the Worker secret is absent", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(
      new Request("https://catalog.example/v1/configuration"),
      env({ TMDB_BEARER_TOKEN: "" }),
      context,
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "missing_secret" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("returns retry metadata when the limiter rejects a request", async () => {
    const response = await worker.fetch(
      new Request("https://catalog.example/v1/configuration", { headers: { "CF-Connecting-IP": "203.0.113.8" } }),
      env({ CATALOG_RATE_LIMITER: { limit: async () => ({ success: false }) } }),
      context,
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
  });

  it("rate-limits by a hashed IP identity instead of the mutable client header", async () => {
    const keys: string[] = [];
    const limiter = {
      limit: async ({ key }: { key: string }) => {
        keys.push(key);
        return { success: false };
      },
    };

    for (const client of ["client-a", "client-b"]) {
      await worker.fetch(
        new Request("https://catalog.example/v1/configuration", {
          headers: { "CF-Connecting-IP": "203.0.113.9", "X-SmartMovie-Client": client },
        }),
        env({ CATALOG_RATE_LIMITER: limiter }),
        context,
      );
    }

    expect(keys).toHaveLength(2);
    expect(keys[0]).toBe(keys[1]);
    expect(keys[0]).toMatch(/^configuration:[a-f0-9]{24}$/);
    expect(keys[0]).not.toContain("203.0.113.9");
  });

  it("builds all five localized Home shelves in one response", async () => {
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      const id = url.pathname.split("/").join("").length;
      return Response.json({
        page: 1,
        total_pages: 1,
        results: [{ id, title: url.pathname, original_title: url.pathname, overview: "", genre_ids: [] }],
      });
    });
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(
      new Request("https://catalog.example/v1/home?media_type=movie&language=vi-VN"),
      env(),
      context,
    );
    const body = await response.json() as {
      media_type: string;
      hero: { title: string };
      sections: Array<{ id: string; title: string; items: unknown[] }>;
    };

    expect(response.status).toBe(200);
    expect(upstream).toHaveBeenCalledTimes(5);
    expect(body.media_type).toBe("movie");
    expect(body.hero.title).toContain("trending/movie/week");
    expect(body.sections.map((section) => section.id)).toEqual([
      "trending", "popular", "top_rated", "now_playing", "upcoming",
    ]);
    expect(body.sections.map((section) => section.title)).toEqual([
      "Xu hướng", "Phổ biến", "Đánh giá cao", "Đang chiếu", "Sắp chiếu",
    ]);
    expect(body.sections.every((section) => section.items.length === 1)).toBe(true);
  });

  it("fills missing localized detail fields from en-US while preserving localized metadata", async () => {
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const locale = new URL(String(input)).searchParams.get("language");
      if (locale === "vi-VN") {
        return Response.json({
          id: 42,
          title: "Phim Việt hóa",
          original_title: "Original",
          overview: "",
          genres: [{ id: 18, name: "Chính kịch" }],
          videos: { results: [] },
          credits: { cast: [] },
        });
      }
      return Response.json({
        id: 42,
        title: "English title",
        original_title: "Original",
        overview: "English fallback overview",
        videos: { results: [{ id: "trailer", key: "abc", name: "Trailer", site: "YouTube", type: "Trailer", official: true, iso_639_1: "en" }] },
      });
    });
    vi.stubGlobal("fetch", upstream);

    const response = await worker.fetch(
      new Request("https://catalog.example/v1/titles/movie/42?language=vi-VN"),
      env(),
      context,
    );
    const body = await response.json() as { title: string; overview: string; videos: Array<{ id: string }> };

    expect(upstream).toHaveBeenCalledTimes(2);
    expect(body.title).toBe("Phim Việt hóa");
    expect(body.overview).toBe("English fallback overview");
    expect(body.videos).toEqual([expect.objectContaining({ id: "trailer" })]);
  });

  it("normalizes pages into the shared Swift contract", () => {
    expect(pageResponse({ page: 1, total_pages: 900, results: [{ id: 3, name: "Series" }] }, "tv")).toEqual({
      page: 1,
      total_pages: 500,
      results: [{
        id: 3,
        media_type: "tv",
        title: "Series",
        original_title: "Series",
        overview: "",
        poster_path: null,
        backdrop_path: null,
        release_date: null,
        vote_average: 0,
        genre_ids: [],
      }],
    });
  });

  it("normalizes TV detail runtime, ordered cast, YouTube videos, and similar titles", () => {
    const result = detail({
      id: 7,
      name: "Series",
      original_name: "Series",
      overview: "Story",
      episode_run_time: [52, 55],
      number_of_seasons: 3,
      credits: { cast: [
        { id: 1, name: "Second", order: 2 },
        { id: 2, name: "First", order: 1 },
      ] },
      videos: { results: [
        { id: "youtube", key: "yt", name: "Trailer", site: "YouTube", type: "Trailer" },
        { id: "vimeo", key: "vm", name: "Trailer", site: "Vimeo", type: "Trailer" },
      ] },
      similar: { page: 1, total_pages: 1, results: [{ id: 8, name: "Similar" }] },
    }, undefined, "tv");

    expect(result.runtime_minutes).toBe(52);
    expect(result.number_of_seasons).toBe(3);
    expect(result.cast.map((member) => member.name)).toEqual(["First", "Second"]);
    expect(result.videos.map((video) => video.id)).toEqual(["youtube"]);
    expect(result.similar[0]).toMatchObject({ id: 8, media_type: "tv", title: "Similar" });
  });

  it("preserves numeric and string season and episode external IDs as strings", () => {
    const season = seasonDetail(7, {
      id: 11,
      season_number: 1,
      external_ids: { tvdb_id: 12345, freebase_id: " season-one ", tvrage_id: null },
    });
    const episode = episodeDetail(7, {
      id: 12,
      season_number: 1,
      episode_number: 2,
      external_ids: { tvdb_id: 67890, imdb_id: "ttepisode102", empty_id: " " },
    });

    expect(season.external_ids).toEqual({ tvdb_id: "12345", freebase_id: "season-one" });
    expect(episode.external_ids).toEqual({ tvdb_id: "67890", imdb_id: "ttepisode102" });
  });
});

function env(overrides: Partial<Env> = {}): Env {
  return { TMDB_BEARER_TOKEN: "super-secret", TMDB_BASE_URL: "https://tmdb.invalid/3", ...overrides };
}
