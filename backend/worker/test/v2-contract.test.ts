import Ajv2020, { type ValidateFunction } from "ajv/dist/2020.js";
import { afterEach, describe, expect, it, vi } from "vitest";
import accountFixture from "../contract/v2/fixtures/account.json";
import attemptFixture from "../contract/v2/fixtures/auth-attempt.json";
import capabilitiesFixture from "../contract/v2/fixtures/capabilities.json";
import collectionFixture from "../contract/v2/fixtures/collection.json";
import csrfFixture from "../contract/v2/fixtures/csrf.json";
import entitiesFixture from "../contract/v2/fixtures/entities.json";
import episodeFixture from "../contract/v2/fixtures/episode.json";
import errorFixture from "../contract/v2/fixtures/error.json";
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
  | "CSRFToken"
  | "EntityPage"
  | "EpisodeDetail"
  | "ErrorEnvelope"
  | "MutationResult"
  | "PersonDetail"
  | "SeasonDetail"
  | "TitleDetail"
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
    ["TitleDetail", titleFixture],
    ["PersonDetail", personFixture],
    ["CollectionDetail", collectionFixture],
    ["CSRFToken", csrfFixture],
    ["SeasonDetail", seasonFixture],
    ["EpisodeDetail", episodeFixture],
    ["AccountProfile", accountFixture.profile],
    ["AccountState", accountFixture.state],
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
      release_dates: { results: [] },
      translations: { translations: [] },
      "watch/providers": { results: {} },
    })));
    const response = await worker.fetch(request("/v2/titles/movie/10?language=en-US"), env(), context);
    const value = await response.json();
    expect(response.status).toBe(200);
    expectContract("TitleDetail", value);
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

function env(): Env {
  return { TMDB_BEARER_TOKEN: "test-token", TMDB_BASE_URL: "https://tmdb.example/3", RELEASE_TRAIN: "3.0.0" };
}
