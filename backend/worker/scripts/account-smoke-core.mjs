const DEFAULT_ATTEMPTS = 6;
const DEFAULT_POLL_ATTEMPTS = 6;

export async function runAccountSmoke(options) {
  const configuration = normalizedOptions(options);
  const client = new AccountSmokeClient(configuration);
  const cleanup = [];
  let primaryFailure;
  let accountID;
  let operationCount = 0;
  let listID;
  let temporaryListLifecycleComplete = false;
  const originalListName = `SmartMovie CI ${configuration.runID}`;
  const verifiedListName = `${originalListName} verified`;

  try {
    const profile = await client.request("GET", "/v2/account/profile");
    accountID = positiveInteger(profile.id, "Account profile id");
    if (typeof profile.username !== "string" || profile.username.trim() === "") {
      throw new Error("Account profile username is missing.");
    }
    operationCount += 1;

    const movieStatePath = `/v2/account/state/movie/${configuration.movieID}`;
    const tvStatePath = `/v2/account/state/tv/${configuration.tvID}`;
    const episodeStatePath =
      `/v2/account/state/episode/${configuration.episodeSeriesID}/` +
      `${configuration.episodeSeasonNumber}/${configuration.episodeNumber}`;
    const movieState = await client.request("GET", movieStatePath);
    const tvState = await client.request("GET", tvStatePath);
    const episodeState = await client.request("GET", episodeStatePath);
    operationCount += 3;

    const libraryCases = [
      { collection: "favorites", mediaType: "movie", mediaID: configuration.movieID, statePath: movieStatePath, property: "favorite", original: libraryValueFromState(movieState, "favorite") },
      { collection: "watchlist", mediaType: "movie", mediaID: configuration.movieID, statePath: movieStatePath, property: "watchlist", original: libraryValueFromState(movieState, "watchlist") },
      { collection: "favorites", mediaType: "tv", mediaID: configuration.tvID, statePath: tvStatePath, property: "favorite", original: libraryValueFromState(tvState, "favorite") },
      { collection: "watchlist", mediaType: "tv", mediaID: configuration.tvID, statePath: tvStatePath, property: "watchlist", original: libraryValueFromState(tvState, "watchlist") },
    ];

    for (const item of libraryCases) {
      await assertLibraryMembership(client, item, item.original);
      cleanup.push(async () => {
        await mutateLibrary(client, item, item.original);
        await waitForState(client, item.statePath, (state) => libraryValueFromState(state, item.property) === item.original, configuration, `restore ${item.collection} ${item.mediaType}`);
        await waitForLibraryMembership(client, item, item.original, configuration, `restore ${item.collection} ${item.mediaType} membership`);
      });
      await mutateLibrary(client, item, !item.original);
      await waitForState(client, item.statePath, (state) => libraryValueFromState(state, item.property) !== item.original, configuration, `${item.collection} ${item.mediaType}`);
      await waitForLibraryMembership(client, item, !item.original, configuration, `${item.collection} ${item.mediaType} membership`);
      operationCount += 2;
    }

    const movieRating = ratingFromState(movieState);
    const tvRating = ratingFromState(tvState);
    const episodeRating = ratingFromState(episodeState);
    const ratingCases = [
      { path: `/v2/account/ratings/movie/${configuration.movieID}`, statePath: movieStatePath, original: movieRating, target: alternateRating(movieRating, 8.5) },
      { path: `/v2/account/ratings/tv/${configuration.tvID}`, statePath: tvStatePath, original: tvRating, target: alternateRating(tvRating, 8.0) },
      { path: `/v2/account/ratings/episode/${configuration.episodeSeriesID}/${configuration.episodeSeasonNumber}/${configuration.episodeNumber}`, statePath: episodeStatePath, original: episodeRating, target: alternateRating(episodeRating, 9.0) },
    ];

    for (const item of ratingCases) {
      cleanup.push(async () => {
        await mutateRating(client, item.path, item.original);
        await waitForState(client, item.statePath, (state) => ratingFromState(state) === item.original, configuration, `restore rating ${item.path}`);
      });
      await mutateRating(client, item.path, item.target);
      await waitForState(client, item.statePath, (state) => ratingFromState(state) === item.target, configuration, `rating ${item.path}`);
      operationCount += 1;
    }

    assertPage(await client.request("GET", "/v2/account/recommendations/movie?page=1&language=en-US"), "movie recommendations");
    assertPage(await client.request("GET", "/v2/account/recommendations/tv?page=1&language=en-US"), "TV recommendations");
    assertPage(await client.request("GET", "/v2/account/lists?page=1"), "custom lists");
    operationCount += 3;

    cleanup.push(async () => {
      if (temporaryListLifecycleComplete) return;
      await cleanupTemporaryLists(
        client,
        listID,
        new Set([originalListName, verifiedListName]),
        configuration,
      );
      listID = undefined;
    });
    const created = await client.mutation("POST", "/v2/account/lists", {
      name: originalListName,
      description: "Ephemeral protected staging smoke list",
      public: false,
      iso_3166_1: "US",
      iso_639_1: "en",
    }, 201);
    listID = positiveInteger(created.list_id, "Created list id");
    operationCount += 1;

    await client.mutation("PUT", `/v2/account/lists/${listID}`, {
      name: verifiedListName,
      description: "Ephemeral list updated by protected staging smoke",
      public: false,
    });
    await waitForList(client, listID, (list) => list.name === verifiedListName, configuration, "list metadata update");

    await client.mutation("POST", `/v2/account/lists/${listID}/items`, {
      items: [
        { media_type: "movie", media_id: configuration.movieID },
        { media_type: "tv", media_id: configuration.tvID },
      ],
    });
    await waitForList(client, listID, (list) => (
      hasListItem(list, "movie", configuration.movieID) && hasListItem(list, "tv", configuration.tvID)
    ), configuration, "mixed list additions");

    await client.mutation("PATCH", `/v2/account/lists/${listID}/items`, {
      items: [{ media_type: "movie", media_id: configuration.movieID, comment: "SmartMovie staging smoke" }],
    });
    await client.mutation("DELETE", `/v2/account/lists/${listID}/items`, {
      items: [{ media_type: "tv", media_id: configuration.tvID }],
    });
    await waitForList(client, listID, (list) => (
      hasListItem(list, "movie", configuration.movieID) && !hasListItem(list, "tv", configuration.tvID)
    ), configuration, "mixed list removal");
    operationCount += 5;

    await deleteTemporaryList(client, listID, configuration);
    listID = undefined;
    temporaryListLifecycleComplete = true;
    operationCount += 1;
  } catch (error) {
    primaryFailure = error;
  }

  client.beginCleanup();
  const cleanupFailures = [];
  for (const action of cleanup.reverse()) {
    try {
      await action();
    } catch (error) {
      cleanupFailures.push(error);
    }
  }
  cleanupFailures.push(...client.cleanupValidationFailures());

  if (primaryFailure && cleanupFailures.length > 0) {
    throw new AggregateError(
      [primaryFailure, ...cleanupFailures],
      `Account smoke failed: ${safeError(primaryFailure)} Cleanup reported additional failures.`,
    );
  }
  if (primaryFailure) throw primaryFailure;
  if (cleanupFailures.length > 0) throw new AggregateError(cleanupFailures, "Account smoke cleanup failed.");

  return {
    accountID,
    operationCount,
    workerVersion: client.workerVersion,
  };
}

class AccountSmokeClient {
  constructor(configuration) {
    this.configuration = configuration;
    this.workerVersion = undefined;
    this.cleanupMode = false;
    this.cleanupFailures = new Map();
  }

  beginCleanup() {
    this.cleanupMode = true;
  }

  cleanupValidationFailures() {
    return [...this.cleanupFailures.values()];
  }

  async mutation(method, path, body, expectedStatus = 200) {
    const mutationID = this.configuration.randomUUID();
    const payload = body === undefined ? undefined : { ...body, mutation_id: mutationID };
    const response = await this.request(method, path, payload, expectedStatus, mutationID);
    if (response.mutation_id !== mutationID) {
      throw new Error(`${method} ${path} did not acknowledge its idempotency key.`);
    }
    return response;
  }

  async request(method, path, body, expectedStatus = 200, mutationID) {
    const result = await this.requestWithStatus(method, path, body, [expectedStatus], mutationID);
    return result.payload;
  }

  async requestWithStatus(method, path, body, expectedStatuses = [200], mutationID) {
    const serializedBody = body === undefined ? undefined : JSON.stringify(body);
    let lastFailure;
    for (let attempt = 1; attempt <= this.configuration.maximumAttempts; attempt += 1) {
      let response;
      try {
        response = await this.configuration.fetchImpl(new URL(path, this.configuration.baseURL), {
          method,
          headers: {
            Accept: "application/json",
            ...(serializedBody === undefined ? {} : { "Content-Type": "application/json" }),
            Authorization: `Bearer ${this.configuration.sessionToken}`,
            "X-SmartMovie-Client": this.configuration.clientID,
            ...(mutationID === undefined ? {} : { "Idempotency-Key": mutationID }),
          },
          body: serializedBody,
          signal: AbortSignal.timeout(this.configuration.timeoutMilliseconds),
        });
      } catch (error) {
        lastFailure = new Error(`${method} ${path} failed before receiving a response: ${safeError(error)}`);
        if (attempt < this.configuration.maximumAttempts) {
          await this.configuration.sleep(attempt * 500);
          continue;
        }
        throw lastFailure;
      }

      try {
        assertPrivateResponse(response, method, path);
      } catch (error) {
        if (!this.cleanupMode) throw error;
        this.recordCleanupFailure(`cache:${method}:${path}`, error);
      }
      const version = response.headers.get("X-SmartMovie-Worker-Version");
      if (!version) {
        const error = new Error(`${method} ${path} did not expose Worker version metadata.`);
        if (!this.cleanupMode) throw error;
        this.recordCleanupFailure("worker-version-missing", error);
      }
      if (version && this.workerVersion && this.workerVersion !== version) {
        const error = new Error(`${method} ${path} switched Worker versions during protected smoke validation.`);
        if (!this.cleanupMode) throw error;
        this.recordCleanupFailure("worker-version-switch", error);
      }
      if (!this.workerVersion && version) this.workerVersion = version;

      let text;
      try {
        text = await response.text();
      } catch (error) {
        lastFailure = new Error(`${method} ${path} failed while reading the response: ${safeError(error)}`);
        if (attempt < this.configuration.maximumAttempts) {
          await this.configuration.sleep(attempt * 500);
          continue;
        }
        throw lastFailure;
      }
      let payload;
      try {
        payload = text === "" ? {} : JSON.parse(text);
      } catch {
        payload = {};
      }

      const retryableConflict = response.status === 409 && payload?.error?.code === "mutation_in_progress";
      if ((response.status === 429 || response.status >= 500 || retryableConflict) && attempt < this.configuration.maximumAttempts) {
        const retryHeader = response.headers.get("Retry-After");
        const envelopeDelay = payload?.error?.retry_after;
        const retryAfter = retryHeader !== null
          ? Number(retryHeader)
          : typeof envelopeDelay === "number" ? envelopeDelay : Number.NaN;
        await this.configuration.sleep(Number.isFinite(retryAfter) ? Math.min(retryAfter * 1_000, 5_000) : attempt * 500);
        continue;
      }
      if (!expectedStatuses.includes(response.status)) {
        const code = payload?.error?.code ?? "unexpected_response";
        throw new Error(`${method} ${path} returned ${response.status} (${code}); expected ${expectedStatuses.join(" or ")}.`);
      }
      return { payload, status: response.status };
    }
    throw lastFailure ?? new Error(`${method} ${path} exhausted its retry budget.`);
  }

  recordCleanupFailure(key, error) {
    if (!this.cleanupFailures.has(key)) {
      this.cleanupFailures.set(key, error instanceof Error ? error : new Error(String(error)));
    }
  }
}

function normalizedOptions(options) {
  if (!options?.baseURL || !options?.clientID || !options?.sessionToken) {
    throw new Error("baseURL, clientID and sessionToken are required.");
  }
  return {
    ...options,
    baseURL: new URL(options.baseURL),
    movieID: positiveInteger(options.movieID ?? 550, "Movie id"),
    tvID: positiveInteger(options.tvID ?? 1399, "TV id"),
    episodeSeriesID: positiveInteger(options.episodeSeriesID ?? 1399, "Episode series id"),
    episodeSeasonNumber: nonNegativeInteger(options.episodeSeasonNumber ?? 1, "Episode season number"),
    episodeNumber: positiveInteger(options.episodeNumber ?? 1, "Episode number"),
    runID: String(options.runID ?? Date.now()).replace(/[^0-9]/gu, "").slice(-12) || "local",
    fetchImpl: options.fetchImpl ?? fetch,
    randomUUID: options.randomUUID ?? (() => crypto.randomUUID()),
    sleep: options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))),
    maximumAttempts: positiveInteger(options.maximumAttempts ?? DEFAULT_ATTEMPTS, "Maximum attempts"),
    pollAttempts: positiveInteger(options.pollAttempts ?? DEFAULT_POLL_ATTEMPTS, "Poll attempts"),
    timeoutMilliseconds: positiveInteger(options.timeoutMilliseconds ?? 20_000, "Timeout milliseconds"),
  };
}

async function mutateLibrary(client, item, enabled) {
  await client.mutation("PUT", `/v2/account/${item.collection}/${item.mediaType}`, {
    media_id: item.mediaID,
    enabled,
  });
}

async function assertLibraryMembership(client, item, expected) {
  const found = await libraryMembership(client, item);
  if (found !== expected) {
    throw new Error(
      `${item.collection} ${item.mediaType} membership for ${item.mediaType}:${item.mediaID} ` +
      `was ${found}; expected ${expected}.`,
    );
  }
}

async function waitForLibraryMembership(client, item, expected, configuration, description) {
  await waitFor(
    async () => libraryMembership(client, item),
    (found) => found === expected,
    configuration,
    description,
  );
}

async function libraryMembership(client, item) {
  let currentPage = 1;
  let totalPages = 1;
  let found = false;
  do {
    const value = await client.request(
      "GET",
      `/v2/account/${item.collection}/${item.mediaType}` +
        `?page=${currentPage}&language=en-US&sort_by=created_at.desc`,
    );
    assertPage(value, `${item.collection} ${item.mediaType}`);
    totalPages = Math.min(Math.max(value.total_pages, 1), 500);
    found ||= value.results.some((title) => (
      title?.media_type === item.mediaType && Number(title?.id) === item.mediaID
    ));
    currentPage += 1;
  } while (!found && currentPage <= totalPages);
  return found;
}

async function mutateRating(client, path, value) {
  if (value === null) await client.mutation("DELETE", path);
  else await client.mutation("PUT", path, { value });
}

async function waitForState(client, path, predicate, configuration, description) {
  await waitFor(async () => client.request("GET", path), predicate, configuration, description);
}

async function waitForList(client, id, predicate, configuration, description) {
  await waitFor(
    async () => {
      const list = await client.request("GET", `/v2/account/lists/${id}?language=en-US&page=1`);
      assertList(list, id);
      return list;
    },
    predicate,
    configuration,
    description,
  );
}

async function deleteTemporaryList(client, id, configuration) {
  const current = await listWithStatus(client, id);
  if (current === null) return;
  await client.mutation("DELETE", `/v2/account/lists/${id}`);
  await waitForListDeletion(client, id, configuration);
}

async function cleanupTemporaryLists(client, knownID, names, configuration) {
  const pendingIDs = new Set();
  if (knownID !== undefined) pendingIDs.add(positiveInteger(knownID, "Temporary list id"));
  let discoveredAny = pendingIDs.size > 0;

  for (let attempt = 1; attempt <= configuration.pollAttempts; attempt += 1) {
    for (const id of await temporaryListIDs(client, names)) pendingIDs.add(id);
    if (pendingIDs.size > 0) discoveredAny = true;

    for (const id of [...pendingIDs]) {
      await deleteTemporaryList(client, id, configuration);
      pendingIDs.delete(id);
    }

    const remaining = await temporaryListIDs(client, names);
    if (remaining.length === 0 && discoveredAny) return;
    for (const id of remaining) pendingIDs.add(id);
    if (attempt < configuration.pollAttempts) await configuration.sleep(attempt * 500);
  }

  if (pendingIDs.size > 0) {
    throw new Error(`Temporary TMDb lists were not removed: ${[...pendingIDs].join(", ")}.`);
  }
}

async function temporaryListIDs(client, names) {
  const ids = new Set();
  let currentPage = 1;
  let totalPages = 1;
  do {
    const value = await client.request("GET", `/v2/account/lists?page=${currentPage}`);
    assertPage(value, "custom lists cleanup");
    totalPages = Math.min(Math.max(value.total_pages, 1), 500);
    for (const list of value.results) {
      if (names.has(list?.name)) ids.add(positiveInteger(list?.id, "Temporary list summary id"));
    }
    currentPage += 1;
  } while (currentPage <= totalPages);
  return [...ids];
}

async function waitForListDeletion(client, id, configuration) {
  for (let attempt = 1; attempt <= configuration.pollAttempts; attempt += 1) {
    if (await listWithStatus(client, id) === null) return;
    if (attempt < configuration.pollAttempts) await configuration.sleep(attempt * 500);
  }
  throw new Error(`TMDb account state did not converge for deletion of list ${id}.`);
}

async function listWithStatus(client, id) {
  const result = await client.requestWithStatus(
    "GET",
    `/v2/account/lists/${id}?language=en-US&page=1`,
    undefined,
    [200, 404],
  );
  if (result.status === 404) {
    if (result.payload?.error?.code !== "entity_not_found") {
      throw new Error(`List ${id} returned an unexpected 404 response.`);
    }
    return null;
  }
  assertList(result.payload, id);
  return result.payload;
}

async function waitFor(load, predicate, configuration, description) {
  for (let attempt = 1; attempt <= configuration.pollAttempts; attempt += 1) {
    const value = await load();
    if (predicate(value)) return value;
    if (attempt < configuration.pollAttempts) await configuration.sleep(attempt * 500);
  }
  throw new Error(`TMDb account state did not converge for ${description}.`);
}

function assertPage(value, label) {
  if (!Number.isSafeInteger(value?.page) || !Number.isSafeInteger(value?.total_pages) || !Array.isArray(value?.results)) {
    throw new Error(`${label} did not return a normalized paginated response.`);
  }
}

function assertList(value, id) {
  if (Number(value?.id) !== id || typeof value?.name !== "string" || !Array.isArray(value?.results)) {
    throw new Error(`List ${id} did not return a normalized mixed-list response.`);
  }
}

function hasListItem(list, mediaType, mediaID) {
  return list.results.some((item) => item?.media_type === mediaType && Number(item.id) === mediaID);
}

function libraryValueFromState(state, property) {
  if (typeof state?.[property] !== "boolean") {
    throw new Error(`TMDb account state is missing the ${property} flag.`);
  }
  return state[property];
}

function ratingFromState(state) {
  if (!state || !Object.prototype.hasOwnProperty.call(state, "rated")) {
    throw new Error("TMDb account state is missing the rated value.");
  }
  if (state.rated === false || state.rated === null) return null;
  const value = Number(typeof state.rated === "number" ? state.rated : state.rated?.value);
  if (!Number.isFinite(value)) throw new Error("TMDb returned an invalid account rating state.");
  return value;
}

function alternateRating(original, preferred) {
  return [preferred, 7.5, 8.5, 9.5].find((candidate) => candidate !== original) ?? 10;
}

function assertPrivateResponse(response, method, path) {
  const cacheControl = response.headers.get("Cache-Control")?.toLowerCase() ?? "";
  if (!cacheControl.includes("private") || !cacheControl.includes("no-store")) {
    throw new Error(`${method} ${path} did not return Cache-Control: private, no-store.`);
  }
}

function positiveInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${label} must be a positive integer.`);
  return parsed;
}

function nonNegativeInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`${label} must be a non-negative integer.`);
  return parsed;
}

function safeError(error) {
  return error instanceof Error ? error.message : String(error);
}
