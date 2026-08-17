import Ajv2020, { type ValidateFunction } from "ajv/dist/2020.js";
import { afterEach, describe, expect, it, vi } from "vitest";
import configurationFixture from "../contract/fixtures/configuration.json";
import errorFixture from "../contract/fixtures/error.json";
import genresFixture from "../contract/fixtures/genres.json";
import homeFixture from "../contract/fixtures/home.json";
import detailFixture from "../contract/fixtures/title-detail.json";
import titlePageFixture from "../contract/fixtures/title-page.json";
import forwardCompatibleFixture from "../contract/fixtures/title-summary-forward-compatible.json";
import openapi from "../contract/openapi.json";
import worker, { type Env } from "../src/index";

type SchemaName =
  | "ErrorEnvelope"
  | "GenreEnvelope"
  | "HomeFeed"
  | "ImageConfiguration"
  | "TitleDetail"
  | "TitlePage"
  | "TitleSummary";

const schemaID = "https://smartmovie.app/contracts/catalog-v1";
const ajv = new Ajv2020({ allErrors: true, strict: false });
ajv.addFormat("uuid", /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
ajv.addFormat("uri", (value: string) => {
  try {
    return Boolean(new URL(value));
  } catch {
    return false;
  }
});
ajv.addFormat("date", /^\d{4}-\d{2}-\d{2}$/);
ajv.addSchema({ ...openapi, $id: schemaID, $schema: "https://json-schema.org/draft/2020-12/schema" }, schemaID);

const validators = new Map<SchemaName, ValidateFunction>();
const context = { waitUntil: (promise: Promise<unknown>) => void promise };

afterEach(() => vi.unstubAllGlobals());

describe("canonical catalog fixtures", () => {
  it.each([
    ["HomeFeed", homeFixture],
    ["TitlePage", titlePageFixture],
    ["GenreEnvelope", genresFixture],
    ["TitleDetail", detailFixture],
    ["ImageConfiguration", configurationFixture],
    ["ErrorEnvelope", errorFixture],
    ["TitleSummary", forwardCompatibleFixture],
  ] as const)("validates %s", (schema, fixture) => {
    expectContract(schema, fixture);
  });
});

describe("Worker responses conform to the canonical OpenAPI schemas", () => {
  it("validates every successful route", async () => {
    vi.stubGlobal("fetch", vi.fn(upstreamResponse));
    const routes: ReadonlyArray<readonly [string, SchemaName]> = [
      ["/v1/home?media_type=movie&language=en-US", "HomeFeed"],
      ["/v1/discover/movie?page=1&language=en-US&sort_by=popularity.desc&vote_average_gte=0", "TitlePage"],
      ["/v1/search?query=Example&scope=all&page=1&language=en-US", "TitlePage"],
      ["/v1/titles/movie/42?language=en-US", "TitleDetail"],
      ["/v1/genres/movie?language=en-US", "GenreEnvelope"],
      ["/v1/configuration", "ImageConfiguration"],
    ];

    for (const [path, schema] of routes) {
      const response = await worker.fetch(request(path), env(), context);
      expect(response.status, path).toBe(200);
      expectContract(schema, await response.json());
    }
  });

  it("validates normalized errors", async () => {
    const response = await worker.fetch(
      request("/v1/search?query=%20&scope=all&page=1&language=en-US"),
      env(),
      context,
    );

    expect(response.status).toBe(400);
    const payload = await response.json();
    expectContract("ErrorEnvelope", payload);
    expect(payload).toMatchObject({ error: { code: "invalid_query" } });
  });
});

function expectContract(schema: SchemaName, value: unknown): void {
  let validate = validators.get(schema);
  if (!validate) {
    validate = ajv.getSchema(`${schemaID}#/components/schemas/${schema}`);
    if (!validate) throw new Error(`OpenAPI schema ${schema} was not registered.`);
    validators.set(schema, validate);
  }
  const valid = validate(value);
  expect(valid, ajv.errorsText(validate.errors, { separator: "\n" })).toBe(true);
}

function request(path: string): Request {
  return new Request(`https://catalog.example${path}`, {
    headers: { "X-SmartMovie-Client": "00000000-0000-4000-8000-000000000001" },
  });
}

function env(): Env {
  return { TMDB_BEARER_TOKEN: "test-token", TMDB_BASE_URL: "https://tmdb.example" };
}

async function upstreamResponse(input: RequestInfo | URL): Promise<Response> {
  const url = new URL(input instanceof Request ? input.url : input.toString());
  if (url.pathname === "/configuration") {
    return Response.json({ images: configurationFixture });
  }
  if (url.pathname.startsWith("/genre/")) {
    return Response.json(genresFixture);
  }
  if (url.pathname === "/movie/42") {
    return Response.json({
      id: 42,
      title: "The Example",
      original_title: "The Example",
      overview: "A deterministic catalog fixture.",
      poster_path: "/poster.jpg",
      backdrop_path: "/backdrop.jpg",
      release_date: "2026-08-17",
      vote_average: 8.4,
      genres: [{ id: 12, name: "Adventure" }],
      runtime: 124,
      status: "Released",
      credits: { cast: [{ id: 7, name: "Example Actor", character: "Lead", profile_path: null, order: 0 }] },
      videos: { results: [{ id: "video-1", key: "example", name: "Official Trailer", site: "YouTube", type: "Trailer", official: true, iso_639_1: "en" }] },
      similar: { page: 1, total_pages: 0, results: [] },
    });
  }
  return Response.json({
    page: 1,
    total_pages: 1,
    results: [{
      id: 42,
      media_type: "movie",
      title: "The Example",
      original_title: "The Example",
      overview: "A deterministic catalog fixture.",
      poster_path: "/poster.jpg",
      backdrop_path: "/backdrop.jpg",
      release_date: "2026-08-17",
      vote_average: 8.4,
      genre_ids: [12, 18],
    }],
  });
}
