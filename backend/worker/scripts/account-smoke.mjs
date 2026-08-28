import { runAccountSmoke } from "./account-smoke-core.mjs";

const baseURL = process.env.BASE_URL;
const clientID = process.env.CLIENT_ID;
const sessionToken = process.env.SMARTMOVIE_ACCOUNT_SESSION_TOKEN;
if (!baseURL || !clientID || !sessionToken) {
  throw new Error("BASE_URL, CLIENT_ID and SMARTMOVIE_ACCOUNT_SESSION_TOKEN are required.");
}

const result = await runAccountSmoke({
  baseURL,
  clientID,
  sessionToken,
  movieID: environmentInteger("ACCOUNT_TEST_MOVIE_ID", process.env.ACCOUNT_TEST_TITLE_ID ?? "550"),
  tvID: environmentInteger("ACCOUNT_TEST_TV_ID", "1399"),
  episodeSeriesID: environmentInteger("ACCOUNT_TEST_EPISODE_SERIES_ID", "1399"),
  episodeSeasonNumber: environmentInteger("ACCOUNT_TEST_EPISODE_SEASON_NUMBER", "1", true),
  episodeNumber: environmentInteger("ACCOUNT_TEST_EPISODE_NUMBER", "1"),
  runID: (process.env.GITHUB_RUN_ID ?? Date.now().toString()).replace(/[^0-9]/gu, "").slice(-12),
});

console.log(
  `Protected TMDb account smoke passed ${result.operationCount} checks and restored ` +
  `library, ratings, and temporary list state for account ${result.accountID} on Worker ${result.workerVersion}.`,
);

function environmentInteger(name, fallback, allowZero = false) {
  const raw = process.env[name] ?? fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || (allowZero ? value < 0 : value <= 0)) {
    throw new Error(`${name} must be ${allowZero ? "a non-negative" : "a positive"} integer.`);
  }
  return value;
}
