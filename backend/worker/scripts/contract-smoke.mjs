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
const openapi = JSON.parse(await readFile(new URL("openapi.json", contractDirectory), "utf8"));
const schemaID = "https://smartmovie.app/contracts/catalog-v1";
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
ajv.addSchema({ ...openapi, $id: schemaID, $schema: "https://json-schema.org/draft/2020-12/schema" }, schemaID);

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

console.log(`Contract smoke passed for Worker ${observedWorkerVersion}, ${mediaType}, six routes, ${locales.length} locales, pagination, and normalized errors at ${baseURL}.`);

async function requestJSON(path, schemaName, expectedStatus = 200) {
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
    validate(response.ok ? schemaName : "ErrorEnvelope", payload, path);

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

function validate(schemaName, value, path) {
  let validator = validators.get(schemaName);
  if (!validator) {
    validator = ajv.getSchema(`${schemaID}#/components/schemas/${schemaName}`);
    if (!validator) throw new Error(`OpenAPI schema ${schemaName} is missing.`);
    validators.set(schemaName, validator);
  }
  if (!validator(value)) {
    throw new Error(`${path} violates ${schemaName}: ${ajv.errorsText(validator.errors, { separator: "\n" })}`);
  }
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
