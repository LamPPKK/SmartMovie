# SmartMovie 3.0 architecture

## Repository and client boundaries

`SmartMovie` owns the native SwiftUI products, `SmartMovieKit`, Cloudflare Worker, D1 migrations, and canonical `/v1` + `/v2` contracts. `Android.Smart.Movie` owns native Android/Wear and Compose Multiplatform desktop/web, consuming a checksummed contract snapshot.

Every full client keeps native domain and UI models. Shared behavior comes from OpenAPI/fixtures, parity requirements, normalized errors, and the release train—not generated UI code. Watch/Wear remain safe companions and never authorize independently.

## Catalog path

Clients call only the SmartMovie Worker for catalog JSON. The Worker calls TMDb v3 using its server-side Bearer credential, rejects unknown inputs, maps upstream shapes to stable discriminated entities, and validates public success/error responses. Poster, backdrop, profile, and provider images use URLs built from normalized configuration.

- `/v1` keeps the six SmartMovie 2.0 route families alive.
- `/v2` adds capabilities, deep Movie/TV data, entity search/detail, trending, external-ID lookup, credits, seasons/episodes, providers, and account routes.
- Public cache keys partition by route inputs including locale, region, and adult flag, plus Worker deployment version metadata.
- Private auth/account responses use `private, no-store` and are never inserted into the catalog cache.
- `/v2` is additive-only. A discriminator, type, or semantic break requires `/v3`.

The exact route inventory lives in `backend/worker/contract/v2/openapi.json`; product classification and missing surfaces live in [TMDb coverage](TMDB_COVERAGE.md).

## Account session broker

SmartMovie never accepts a TMDb username or password. It creates a short-lived authorization attempt, opens a TMDb approval page, verifies callback state, exchanges the approved v4 token, and creates a v3 session only where the upstream account API requires one.

Cloudflare D1 contains:

- `auth_attempts`: hashes/state, encrypted request token, allowlisted return URI, mode, status, and expiry;
- `sessions`: SmartMovie token hash, account identity, encrypted TMDb access/v3 session tokens, CSRF hash, activity/expiry, and revocation;
- `account_mutations`: account-scoped mutation IDs and normalized acknowledgements for durable idempotency.

Native clients store only the opaque SmartMovie token in Keychain/Keystore/OS credential storage. Web uses a `Secure`, `HttpOnly`, `SameSite` cookie and CSRF header. Sessions expire after 90 inactive days. Logout revokes upstream state where possible and removes the D1 session. Tokens, PINs, and sensitive callback/query values must never be logged.

The Worker does **not** store Favorite, Watchlist, rating, recommendation, or custom-list content.

## Local-first user data

Favorite and Watchlist remain independently readable offline. Apple uses SwiftData/private CloudKit, Android uses Room/local backup, and KMP uses Java Preferences or browser `localStorage`.

On first TMDb login, each client merges local and remote library sets and sends local-only enabled values upstream. Later mutations update UI immediately and enter a durable outbox. Pending local state wins over refresh until the Worker returns the same mutation ID. Rating and custom-list mutations use state-setting operations so retries are safe.

Adult opt-in and its six-digit PIN are local per device. Five failures lock the control for five minutes. Adult entities never enter companion state or public previews.

## Key interfaces

- `CatalogRepository` retains Home, Genres, Discover, Search, Detail, and Configuration compatibility.
- `CatalogRepositoryV2` adds capabilities, trending, discriminated entity search, deep title detail, Person, Collection, Company/Network, Keyword, Season, and Episode.
- `AccountRepository` covers auth, profile/state, library, ratings, recommendations, and mixed-list CRUD/items.
- `LibraryRepository` and account mutation outboxes own offline/merge/idempotency rules independently of UI.
- `libraryKey` remains `{mediaType}:{tmdbID}`. Episode ratings use series/season/episode identity.

## Verification boundaries

- Swift tests use repository fakes, in-memory SwiftData, deterministic clocks, and custom URL loading to verify decoding, state, storage, outboxes, retries, cancellation, and account behavior without live credentials.
- Worker tests mock TMDb, Cache API, D1, and cryptography to validate `/v1` and `/v2` schemas, upstream mapping, cache partitions, rate limiting, migrations, encryption, callback state, CSRF/CORS, session lifecycle, idempotency, and rollback behavior.
- Android native and KMP decode the same canonical fixtures and separately test Room/key-value persistence, optimistic state, retry, migration, navigation, and platform UI.
- Protected staging tests own the only dedicated TMDb test account. They must clean ratings/lists after each run and never use a personal account.

Tests must not require a live personal TMDb token, production Cloudflare account, iCloud account, or public response unless they are explicitly protected staging smoke tests.

## Release invariants and open external configuration

- All app binaries remain free of TMDb application credentials and SmartMovie session material.
- Production account capabilities remain false until the deployed environment has `AUTH_DB`, `SESSION_ENCRYPTION_KEY`, callback origin, and return-URI allowlist.
- Apple, Android, TV, watch companions, desktop JVM, JavaScript, and Wasm are release blockers for 3.0.
- CloudKit and client database migrations must be additive and preserve existing libraries.
- Worker production promotion requires the Android `main` contract version and checksums to match canonical values.

External release owners still need to configure/verify D1 bindings and migrations, rotate secrets, activate DNS/TLS, finish signing and store records, deploy CloudKit production schema, provide privacy/support URLs and final assets, and run protected account/device QA.
