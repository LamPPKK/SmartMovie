import assert from "node:assert/strict";
import test from "node:test";
import { runAccountSmoke } from "./account-smoke-core.mjs";

test("protected account smoke covers every account surface and restores state", async () => {
  const harness = createHarness();
  const result = await runSmoke(harness);

  assert.equal(result.operationCount, 25);
  assert.equal(result.workerVersion, "worker-test-version");
  assert.deepEqual(harness.state, harness.initialState);
  assert.equal(harness.lists.size, 0);
  assertRequested(harness, "GET", "/v2/account/favorites/movie");
  assertRequested(harness, "GET", "/v2/account/watchlist/tv");
  assertRequested(harness, "GET", "/v2/account/recommendations/movie");
  assertRequested(harness, "GET", "/v2/account/recommendations/tv");
  assertRequested(harness, "PUT", "/v2/account/ratings/tv/1399");
  assertRequested(harness, "PUT", "/v2/account/ratings/episode/1399/1/1");
  assertRequested(harness, "PATCH", "/v2/account/lists/101/items");
  assertRequested(harness, "DELETE", "/v2/account/lists/101/items");
  const deletion = harness.calls.findIndex((call) => call.method === "DELETE" && call.path === "/v2/account/lists/101");
  assert.ok(deletion >= 0);
  assert.ok(harness.calls.slice(deletion + 1).some((call) => call.method === "GET" && call.path === "/v2/account/lists/101"));
});

test("connection, 429, and 5xx mutation retries reuse the same idempotency key", async () => {
  for (const transientStatus of [429, 503]) {
    const harness = createHarness({ transientPath: "/v2/account/favorites/movie", transientStatus });
    await runSmoke(harness);

    const attempts = harness.calls.filter((call) => call.method === "PUT" && call.path === "/v2/account/favorites/movie");
    assert.ok(attempts.length >= 3, `expected retry, successful mutation, and cleanup after ${transientStatus}`);
    assert.equal(attempts[0].idempotencyKey, attempts[1].idempotencyKey);
    assert.equal(attempts[0].body.mutation_id, attempts[1].body.mutation_id);
    assert.notEqual(attempts[1].idempotencyKey, attempts.at(-1).idempotencyKey);
    assert.deepEqual(harness.state, harness.initialState);
  }

  const disconnected = createHarness({
    transientPath: "/v2/account/favorites/movie",
    throwTransient: true,
  });
  await runSmoke(disconnected);
  const attempts = disconnected.calls.filter((call) => call.method === "PUT" && call.path === "/v2/account/favorites/movie");
  assert.equal(attempts[0].idempotencyKey, attempts[1].idempotencyKey);
  assert.equal(attempts[0].body.mutation_id, attempts[1].body.mutation_id);
  assert.deepEqual(disconnected.state, disconnected.initialState);
});

test("mutation_in_progress retries reuse the same idempotency key, while other conflicts remain terminal", async () => {
  const inProgress = createHarness({
    transientPath: "/v2/account/favorites/movie",
    transientStatus: 409,
    transientCode: "mutation_in_progress",
  });
  await runSmoke(inProgress);
  const retries = inProgress.calls.filter((call) => call.method === "PUT" && call.path === "/v2/account/favorites/movie");
  assert.equal(retries[0].idempotencyKey, retries[1].idempotencyKey);
  assert.equal(retries[0].body.mutation_id, retries[1].body.mutation_id);

  const conflict = createHarness({
    transientPath: "/v2/account/favorites/movie",
    transientStatus: 409,
    transientCode: "idempotency_conflict",
  });
  await assert.rejects(runSmoke(conflict), /idempotency_conflict/);
  const terminal = conflict.calls.filter((call) => call.method === "PUT" && call.path === "/v2/account/favorites/movie");
  assert.notEqual(terminal[0].idempotencyKey, terminal[1].idempotencyKey);
  assert.deepEqual(conflict.state, conflict.initialState);
});

test("a lost list-create response body replays its stored list id without creating a duplicate", async () => {
  const harness = createHarness({ failFirstCreateBodyRead: true });

  await runSmoke(harness);

  const attempts = harness.calls.filter((call) => call.method === "POST" && call.path === "/v2/account/lists");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0].idempotencyKey, attempts[1].idempotencyKey);
  assert.equal(harness.listCreateApplications, 1);
  assert.equal(harness.lists.size, 0);
});

test("a mid-run failure still restores library, ratings, and the temporary list", async () => {
  const harness = createHarness({ failListUpdate: true });

  await assert.rejects(runSmoke(harness), /list_update_failed/);
  assert.deepEqual(harness.state, harness.initialState);
  assert.equal(harness.lists.size, 0);
  assertRequested(harness, "DELETE", "/v2/account/lists/101");
});

test("account responses must remain private and no-store", async () => {
  const harness = createHarness({ insecurePath: "/v2/account/profile" });

  await assert.rejects(runSmoke(harness), /Cache-Control: private, no-store/);
  assert.deepEqual(harness.state, harness.initialState);
});

test("transient error responses must remain private and on one Worker version", async () => {
  const insecure = createHarness({
    transientPath: "/v2/account/favorites/movie",
    transientStatus: 503,
    insecureTransient: true,
  });
  await assert.rejects(runSmoke(insecure), /Cache-Control: private, no-store/);

  const switched = createHarness({
    transientPath: "/v2/account/favorites/movie",
    transientStatus: 503,
    transientWorkerVersion: "worker-old-version",
  });
  await assert.rejects(runSmoke(switched), /switched Worker versions/);

  const afterApply = createHarness({ switchWorkerAfterListUpdate: true });
  await assert.rejects(runSmoke(afterApply), /switched Worker versions/);
  assert.deepEqual(afterApply.state, afterApply.initialState);
  assert.equal(afterApply.lists.size, 0);
  assertRequested(afterApply, "DELETE", "/v2/account/lists/101");
});

test("missing rated state is rejected and any prior library mutations are restored", async () => {
  const harness = createHarness({ omitMovieRated: true });

  await assert.rejects(runSmoke(harness), /missing the rated value/);
  assert.deepEqual(harness.state, harness.initialState);

  const inconsistentLibrary = createHarness({ emptyLibraryCollections: true });
  await assert.rejects(runSmoke(inconsistentLibrary), /membership for movie:550 was false; expected true/);
  assert.deepEqual(inconsistentLibrary.state, inconsistentLibrary.initialState);
});

test("an untrusted create response still discovers and removes the temporary list", async () => {
  const harness = createHarness({ insecureCreateResponse: true });

  await assert.rejects(runSmoke(harness), /Cache-Control: private, no-store/);
  assert.equal(harness.lists.size, 0);
  assertRequested(harness, "DELETE", "/v2/account/lists/101");
});

async function runSmoke(harness) {
  let sequence = 0;
  return runAccountSmoke({
    baseURL: "https://staging-catalog.smartmovie.test",
    clientID: "00000000-0000-4000-8000-000000000001",
    sessionToken: "test-session-token",
    movieID: 550,
    tvID: 1399,
    episodeSeriesID: 1399,
    episodeSeasonNumber: 1,
    episodeNumber: 1,
    runID: "123456",
    fetchImpl: harness.fetch,
    randomUUID: () => `00000000-0000-4000-8000-${String(++sequence).padStart(12, "0")}`,
    sleep: async () => {},
    pollAttempts: 2,
  });
}

function createHarness(options = {}) {
  const initialState = {
    movie: { favorite: true, watchlist: false, rated: { value: 7 } },
    tv: { favorite: false, watchlist: true, rated: false },
    episode: { rated: { value: 6.5 } },
  };
  const state = structuredClone(initialState);
  const calls = [];
  const lists = new Map();
  const createAcknowledgements = new Map();
  let transientUsed = false;
  let createBodyFailureUsed = false;
  let insecureCreateUsed = false;
  let listCreateApplications = 0;
  let workerVersion = "worker-test-version";

  const fetch = async (input, init = {}) => {
    const url = new URL(input);
    const method = init.method ?? "GET";
    const headers = new Headers(init.headers);
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    const call = {
      method,
      path: url.pathname,
      query: url.search,
      body,
      idempotencyKey: headers.get("Idempotency-Key"),
    };
    calls.push(call);
    assert.equal(headers.get("Authorization"), "Bearer test-session-token");

    if (!transientUsed && options.transientPath === url.pathname && method === (options.transientMethod ?? "PUT")) {
      transientUsed = true;
      if (options.throwTransient) throw new Error("connection interrupted");
      return json(
        { error: { code: options.transientCode ?? "temporary_failure", retry_after: 0 } },
        options.transientStatus ?? 503,
        { "Retry-After": "0" },
        !options.insecureTransient,
        options.transientWorkerVersion ?? workerVersion,
      );
    }
    if (options.failListUpdate && method === "PUT" && /^\/v2\/account\/lists\/\d+$/u.test(url.pathname)) {
      return json({ error: { code: "list_update_failed" } }, 400);
    }

    const insecure = options.insecurePath === url.pathname;
    const mutationID = body?.mutation_id ?? headers.get("Idempotency-Key");
    const response = (payload, status = 200) => json(payload, status, {}, !insecure, workerVersion);

    if (method === "GET" && url.pathname === "/v2/account/profile") {
      return response({ id: 42, username: "smartmovie-ci" });
    }
    if (method === "GET" && url.pathname === "/v2/account/state/movie/550") {
      const value = { media_type: "movie", media_id: 550, ...structuredClone(state.movie) };
      if (options.omitMovieRated) delete value.rated;
      return response(value);
    }
    if (method === "GET" && url.pathname === "/v2/account/state/tv/1399") {
      return response({ media_type: "tv", media_id: 1399, ...structuredClone(state.tv) });
    }
    if (method === "GET" && url.pathname === "/v2/account/state/episode/1399/1/1") {
      return response({ series_id: 1399, season_number: 1, episode_number: 1, ...structuredClone(state.episode) });
    }

    const library = url.pathname.match(/^\/v2\/account\/(favorites|watchlist)\/(movie|tv)$/u);
    if (library && method === "GET") {
      const target = library[2] === "movie" ? state.movie : state.tv;
      const property = library[1] === "favorites" ? "favorite" : "watchlist";
      const id = library[2] === "movie" ? 550 : 1399;
      const results = target[property] && !options.emptyLibraryCollections
        ? [{ id, media_type: library[2] }]
        : [];
      return response({ page: 1, total_pages: 1, results });
    }
    if (library && method === "PUT") {
      const target = library[2] === "movie" ? state.movie : state.tv;
      target[library[1] === "favorites" ? "favorite" : "watchlist"] = body.enabled;
      return response({ mutation_id: mutationID, media_type: library[2], media_id: body.media_id, enabled: body.enabled });
    }

    const rating = url.pathname.match(/^\/v2\/account\/ratings\/(movie|tv)\/(550|1399)$/u);
    if (rating && (method === "PUT" || method === "DELETE")) {
      const target = rating[1] === "movie" ? state.movie : state.tv;
      target.rated = method === "DELETE" ? false : { value: body.value };
      return response({ mutation_id: mutationID, media_type: rating[1], media_id: Number(rating[2]) });
    }
    if (url.pathname === "/v2/account/ratings/episode/1399/1/1" && (method === "PUT" || method === "DELETE")) {
      state.episode.rated = method === "DELETE" ? false : { value: body.value };
      return response({ mutation_id: mutationID, series_id: 1399, season_number: 1, episode_number: 1 });
    }

    if (method === "GET" && /^\/v2\/account\/recommendations\/(movie|tv)$/u.test(url.pathname)) {
      return response({ page: 1, total_pages: 1, results: [] });
    }
    if (url.pathname === "/v2/account/lists" && method === "GET") {
      return response({ page: 1, total_pages: 1, results: [...lists.values()].map(listSummary) });
    }
    if (url.pathname === "/v2/account/lists" && method === "POST") {
      const replay = createAcknowledgements.get(mutationID);
      if (replay) return response(replay, 201);

      listCreateApplications += 1;
      lists.set(101, { id: 101, name: body.name, description: body.description, public: body.public, results: [] });
      const acknowledgement = { list_id: 101, mutation_id: mutationID };
      createAcknowledgements.set(mutationID, acknowledgement);
      if (options.failFirstCreateBodyRead && !createBodyFailureUsed) {
        createBodyFailureUsed = true;
        const lost = response(acknowledgement, 201);
        lost.text = async () => { throw new Error("response stream interrupted"); };
        return lost;
      }
      if (options.insecureCreateResponse && !insecureCreateUsed) {
        insecureCreateUsed = true;
        return json(acknowledgement, 201, {}, false);
      }
      return response(acknowledgement, 201);
    }

    const listItems = url.pathname.match(/^\/v2\/account\/lists\/(\d+)\/items$/u);
    if (listItems && ["POST", "PATCH", "DELETE"].includes(method)) {
      const list = requiredList(lists, Number(listItems[1]));
      for (const item of body.items) {
        const index = list.results.findIndex((current) => current.media_type === item.media_type && current.id === item.media_id);
        if (method === "DELETE") {
          if (index >= 0) list.results.splice(index, 1);
        } else if (index < 0) {
          list.results.push({ id: item.media_id, media_type: item.media_type, title: `${item.media_type} ${item.media_id}` });
        }
      }
      return response({ mutation_id: mutationID, list_id: list.id });
    }

    const listDetail = url.pathname.match(/^\/v2\/account\/lists\/(\d+)$/u);
    if (listDetail) {
      const id = Number(listDetail[1]);
      if (method === "GET") {
        const list = lists.get(id);
        if (!list) return response({ error: { code: "entity_not_found", retry_after: null } }, 404);
        return response({ ...structuredClone(list), page: 1, total_pages: 1 });
      }
      if (method === "PUT") {
        const list = requiredList(lists, id);
        list.name = body.name;
        list.description = body.description;
        list.public = body.public;
        if (options.switchWorkerAfterListUpdate) workerVersion = "worker-next-version";
        return response({ mutation_id: mutationID, list_id: id });
      }
      if (method === "DELETE") {
        lists.delete(id);
        return response({ mutation_id: mutationID, list_id: id });
      }
    }

    return json({ error: { code: "unexpected_test_route", method, path: url.pathname } }, 500);
  };

  return {
    fetch,
    calls,
    lists,
    state,
    initialState: structuredClone(initialState),
    get listCreateApplications() { return listCreateApplications; },
  };
}

function json(payload, status, extraHeaders = {}, secure = true, workerVersion = "worker-test-version") {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "X-SmartMovie-Worker-Version": workerVersion,
      ...(secure ? { "Cache-Control": "private, no-store" } : {}),
      ...extraHeaders,
    },
  });
}

function requiredList(lists, id) {
  const list = lists.get(id);
  assert.ok(list, `list ${id} must exist`);
  return list;
}

function listSummary(list) {
  const { results: _results, ...summary } = list;
  return summary;
}

function assertRequested(harness, method, path) {
  assert.ok(harness.calls.some((call) => call.method === method && call.path === path), `${method} ${path} was not requested`);
}
