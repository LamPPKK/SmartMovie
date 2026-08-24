const baseURL = process.env.BASE_URL;
const clientID = process.env.CLIENT_ID;
const sessionToken = process.env.SMARTMOVIE_ACCOUNT_SESSION_TOKEN;
const titleID = Number(process.env.ACCOUNT_TEST_TITLE_ID ?? "550");
if (!baseURL || !clientID || !sessionToken) {
  throw new Error("BASE_URL, CLIENT_ID and SMARTMOVIE_ACCOUNT_SESSION_TOKEN are required.");
}

const runID = (process.env.GITHUB_RUN_ID ?? Date.now().toString()).replace(/[^0-9]/gu, "").slice(-12);
let listID;
let ratingCreated = false;

try {
  const profile = await api("GET", "/v2/account/profile");
  if (!Number.isSafeInteger(profile.id) || !profile.username) throw new Error("Account profile is incomplete.");

  const created = await api("POST", "/v2/account/lists", {
    name: `SmartMovie CI ${runID}`,
    description: "Ephemeral protected staging smoke list",
    public: false,
    iso_3166_1: "US",
    iso_639_1: "en",
    mutation_id: crypto.randomUUID(),
  }, 201);
  listID = Number(created.id ?? created.list_id);
  if (!Number.isSafeInteger(listID) || listID <= 0) throw new Error("TMDb did not return the created list id.");

  await api("POST", `/v2/account/lists/${listID}/items`, {
    items: [{ media_type: "movie", media_id: titleID }],
    mutation_id: crypto.randomUUID(),
  });
  const list = await api("GET", `/v2/account/lists/${listID}?language=en-US&page=1`);
  if (Number(list.id) !== listID) throw new Error("Created list could not be read back.");

  await api("PUT", `/v2/account/ratings/movie/${titleID}`, { value: 8.5, mutation_id: crypto.randomUUID() });
  ratingCreated = true;
  const state = await api("GET", `/v2/account/state/movie/${titleID}`);
  if (state.rated === false) throw new Error("Rating was not visible in account state.");
} finally {
  const failures = [];
  if (ratingCreated) await api("DELETE", `/v2/account/ratings/movie/${titleID}`).catch((error) => failures.push(error));
  if (listID) await api("DELETE", `/v2/account/lists/${listID}`).catch((error) => failures.push(error));
  if (failures.length) throw new AggregateError(failures, "Account smoke cleanup failed.");
}

console.log(`Protected TMDb account smoke passed and cleaned up list/rating at ${baseURL}.`);

async function api(method, path, body, expectedStatus = 200) {
  const response = await fetch(new URL(path, baseURL), {
    method,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${sessionToken}`,
      "X-SmartMovie-Client": clientID,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20_000),
  });
  const payload = await response.json().catch(() => ({}));
  if (response.status !== expectedStatus) {
    const code = payload?.error?.code ?? "unexpected_response";
    throw new Error(`${method} ${path} returned ${response.status} (${code}).`);
  }
  return payload;
}
