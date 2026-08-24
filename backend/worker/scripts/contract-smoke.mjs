import { readFile } from "node:fs/promises";
import Ajv2020 from "ajv/dist/2020.js";

const baseURL = process.env.BASE_URL;
const clientID = process.env.CLIENT_ID;
const mediaType = process.env.MEDIA_TYPE ?? "movie";
const titleID = process.env.TITLE_ID ?? (mediaType === "tv" ? "1399" : "550");
const searchQuery = process.env.SEARCH_QUERY ?? (mediaType === "tv" ? "Shogun" : "Dune");
if (!baseURL || !clientID) {
  throw new Error("BASE_URL and CLIENT_ID are required.");
}
if (mediaType !== "movie" && mediaType !== "tv") {
  throw new Error("MEDIA_TYPE must be movie or tv.");
}

const contractDirectory = new URL("../contract/", import.meta.url);
const openapiV1 = JSON.parse(await readFile(new URL("openapi.json", contractDirectory), "utf8"));
const openapiV2 = JSON.parse(await readFile(new URL("v2/openapi.json", contractDirectory), "utf8"));
const schemaIDs = {
  v1: "https://smartmovie.app/contracts/catalog-v1",
  v2: "https://smartmovie.app/contracts/catalog-v2",
};
const ajv = new Ajv2020({ allErrors: true, strict: false });
ajv.addFormat("uuid", /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
ajv.addFormat("uri", (value) => {
  try {
    return Boolean(new URL(value));
  } catch {
    return false;
  }
});
ajv.addFormat("date", /^\d{4}-\d{2}-\d{2}$/);
ajv.addSchema({ ...openapiV1, $id: schemaIDs.v1, $schema: "https://json-schema.org/draft/2020-12/schema" }, schemaIDs.v1);
ajv.addSchema({ ...openapiV2, $id: schemaIDs.v2, $schema: "https://json-schema.org/draft/2020-12/schema" }, schemaIDs.v2);

const validators = new Map();
const locales = ["en-US", "vi-VN", "ja-JP", "ko-KR", "zh-CN", "zh-TW"];
let observedWorkerVersion;

await requestJSON("/v1/configuration", "ImageConfiguration");
for (const locale of locales) {
  await requestJSON(`/v1/home?media_type=${mediaType}&language=${locale}`, "HomeFeed");
  await requestJSON(`/v1/genres/${mediaType}?language=${locale}`, "GenreEnvelope");
  const firstPage = await requestJSON(
    `/v1/discover/${mediaType}?page=1&language=${locale}&sort_by=popularity.desc&vote_average_gte=0.0`,
    "TitlePage",
  );
  const secondPage = await requestJSON(
    `/v1/discover/${mediaType}?page=2&language=${locale}&sort_by=popularity.desc&vote_average_gte=0.0`,
    "TitlePage",
  );
  assertPagination(locale, firstPage, secondPage);
  await requestJSON(`/v1/search?query=${encodeURIComponent(searchQuery)}&scope=${mediaType}&page=1&language=${locale}`, "TitlePage");
  await requestJSON(`/v1/titles/${mediaType}/${titleID}?language=${locale}`, "TitleDetail");
}

await requestJSON("/v1/search?query=%20&scope=all&page=1&language=en-US", "ErrorEnvelope", 400);
await requestJSON("/v1/not-a-route", "ErrorEnvelope", 404);

await requestJSON("/v2/capabilities", "Capabilities", 200, "v2");
await requestJSON("/v2/configuration", "Configuration", 200, "v2");
for (const locale of locales) {
  await requestJSON(`/v2/home?media_type=${mediaType}&language=${locale}&include_adult=false`, "HomeFeed", 200, "v2");
  await requestJSON(`/v2/trending/all/day?page=1&language=${locale}&include_adult=false`, "EntityPage", 200, "v2");
  const firstPage = await requestJSON(
    `/v2/discover/${mediaType}?page=1&language=${locale}&sort_by=popularity.desc&vote_average_gte=0&include_adult=false`,
    "TitlePage", 200, "v2",
  );
  const secondPage = await requestJSON(
    `/v2/discover/${mediaType}?page=2&language=${locale}&sort_by=popularity.desc&vote_average_gte=0&include_adult=false`,
    "TitlePage", 200, "v2",
  );
  assertPagination(`v2 ${locale}`, firstPage, secondPage);
  await requestJSON(`/v2/search?query=${encodeURIComponent(searchQuery)}&scope=all&page=1&language=${locale}&include_adult=false`, "EntityPage", 200, "v2");
  await requestJSON(`/v2/titles/${mediaType}/${titleID}?language=${locale}&region=US&include_adult=false`, "TitleDetail", 200, "v2");
}
await requestJSON("/v2/entities/person/287?language=en-US", "PersonDetail", 200, "v2");
await requestJSON("/v2/entities/collection/10?language=en-US", "CollectionDetail", 200, "v2");
await requestJSON("/v2/tv/1399/seasons/1?language=en-US", "SeasonDetail", 200, "v2");
await requestJSON("/v2/tv/1399/seasons/1/episodes/1?language=en-US", "EpisodeDetail", 200, "v2");
await requestJSON("/v2/search?query=%20&scope=all&page=1&language=en-US", "ErrorEnvelope", 400, "v2");
await requestJSON("/v2/not-a-route", "ErrorEnvelope", 404, "v2");
await assertCancellation();

console.log(`Contract smoke passed for Worker ${observedWorkerVersion}, ${mediaType}, /v1 + /v2, ${locales.length} locales, deep entities, pagination, cancellation, and normalized errors at ${baseURL}.`);

async function requestJSON(path, schemaName, expectedStatus = 200, contract = "v1") {
  const maximumAttempts = 3;
  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    let response;
    try {
      response = await fetch(new URL(path, baseURL), {
        headers: { Accept: "application/json", "X-SmartMovie-Client": clientID },
        signal: AbortSignal.timeout(20_000),
      });
    } catch (error) {
      if (attempt < maximumAttempts) {
        await delay(attempt * 500);
        continue;
      }
      throw new Error(`${path} failed after ${maximumAttempts} attempts: ${error}`);
    }

    const body = await response.text();
    let payload;
    try {
      payload = JSON.parse(body);
    } catch (error) {
      if ((response.status === 429 || response.status >= 500) && attempt < maximumAttempts) {
        await delay(attempt * 500);
        continue;
      }
      throw new Error(`${path} returned non-JSON content: ${error}`);
    }
    validate(response.ok ? schemaName : "ErrorEnvelope", payload, path, contract);

    if (response.status === expectedStatus) {
      assertWorkerVersion(response, path);
      return payload;
    }
    if ((response.status === 429 || response.status >= 500) && attempt < maximumAttempts) {
      const retryAfter = Number(response.headers.get("Retry-After"));
      await delay(Number.isFinite(retryAfter) ? Math.min(retryAfter * 1_000, 5_000) : attempt * 500);
      continue;
    }
    throw new Error(`${path} returned HTTP ${response.status}; expected ${expectedStatus}.`);
  }
  throw new Error(`${path} exhausted its retry budget.`);
}

function validate(schemaName, value, path, contract) {
  const key = `${contract}:${schemaName}`;
  let validator = validators.get(key);
  if (!validator) {
    validator = ajv.getSchema(`${schemaIDs[contract]}#/components/schemas/${schemaName}`);
    if (!validator) throw new Error(`OpenAPI schema ${schemaName} is missing.`);
    validators.set(key, validator);
  }
  if (!validator(value)) {
    throw new Error(`${path} violates ${schemaName}: ${ajv.errorsText(validator.errors, { separator: "\n" })}`);
  }
}

async function assertCancellation() {
  const controller = new AbortController();
  const pending = fetch(new URL("/v2/trending/all/day?page=1&language=en-US", baseURL), {
    headers: { Accept: "application/json", "X-SmartMovie-Client": clientID },
    signal: controller.signal,
  });
  controller.abort();
  await pending.then(
    () => { throw new Error("The staging fetch ignored cancellation."); },
    (error) => {
      if (error?.name !== "AbortError") throw error;
    },
  );
}

function assertPagination(locale, firstPage, secondPage) {
  if (firstPage.page !== 1 || secondPage.page !== 2) {
    throw new Error(`Discover pagination returned unexpected page numbers for ${locale}.`);
  }
}

function assertWorkerVersion(response, path) {
  const workerVersion = response.headers.get("X-SmartMovie-Worker-Version");
  if (!workerVersion) {
    throw new Error(`${path} did not expose the Worker version metadata header.`);
  }
  if (observedWorkerVersion && observedWorkerVersion !== workerVersion) {
    throw new Error(`${path} switched Worker versions during smoke validation.`);
  }
  observedWorkerVersion = workerVersion;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
