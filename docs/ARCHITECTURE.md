# SmartMovie 2.0 architecture

## Current behavior

Each app target contains only a SwiftUI lifecycle and platform shell. `SmartMovieKit` owns shared domain models, the Worker client, SwiftData library storage, observable feature state, design components, and localized UI for `en`, `vi`, `ja`, `ko`, `zh-Hans`, and `zh-Hant`.

The client never contacts the TMDb API for catalog JSON. It calls the Cloudflare Worker under `/v1`. Poster, backdrop, and profile images are loaded from the TMDb CDN using `/v1/configuration`; `URLCache` provides memory and disk caching. Favorite and Watchlist snapshots remain readable offline in SwiftData and sync through the user's private CloudKit database when available.

## Key interfaces

`CatalogRepository` exposes Home, Discover, Search, Detail, Genres, and image configuration. `LibraryRepository` exposes independent Favorite and Watchlist state, filtered/sorted queries, and duplicate reconciliation. Shared types use one `MediaType` discriminator so Movie and TV results can coexist safely.

The Worker accepts only:

- `GET /v1/home`
- `GET /v1/discover/{movie|tv}`
- `GET /v1/search`
- `GET /v1/titles/{movie|tv}/{id}`
- `GET /v1/genres/{movie|tv}`
- `GET /v1/configuration`

Errors use `{ "error": { "code", "message", "request_id", "retry_after" } }`. The client retries 429 and transient 5xx responses at most twice and honors `Retry-After`.

## Verification boundaries

Automated tests are split at the network boundary:

- `SmartMovieKitTests` uses repository fakes, an in-memory SwiftData container, a controlled clock, and a custom `URLProtocol` to verify domain models, observable feature state, Library behavior, request construction, decoding, cancellation, pagination, and retry policy without live services.
- Worker tests mock TMDb and the Cloudflare Cache API to verify the public `/v1` contract, route/query allowlists, language handling, error normalization, cache HIT/MISS behavior, rate-limit identity, localized detail fallback, and token isolation.
- Generic Xcode builds verify that the shared package compiles in iOS, tvOS, Mac Catalyst, and native macOS app shells.

Tests must not depend on a real TMDb token, Cloudflare account, iCloud account, wall-clock delay, or public network response. Cross-device CloudKit synchronization, accessibility, focus behavior, and App Store assets remain staging/device checks described in the release runbook.

## Invariants and limits

- TMDb Bearer tokens exist only as Worker environment secrets.
- Unknown routes, query fields, media types, languages, sort orders, and out-of-range values are rejected before any upstream request.
- Search results in `all` scope never include People.
- Cache TTLs are 5 minutes for Search, 15 minutes for Home/Discover, 1 hour for Detail, and 24 hours for Genres/Configuration.
- The Worker limiter permits 120 requests per minute per hashed IP and route, falling back to a random installation identifier when no edge IP is available. Raw identifiers are not logged.
- `LibraryItem` has no SwiftData unique constraint. `libraryKey` is `{mediaType}:{tmdbID}`; the newest snapshot wins while positive collection states and their timestamps are merged before duplicates are deleted.
- CloudKit schema changes after production deployment must be additive.

## Open release items

- Replace placeholder Worker hostnames in `SmartMovie/project.yml` with deployed staging and production domains.
- Add an approved, unmodified TMDb logo asset from the official logos page to About before App Review. The required notice is already present.
- Add the required tvOS App Icon & Top Shelf Image brand asset collection; simulator builds currently emit a notice because only the legacy iOS/macOS icon set is available.
- Resolve the launch-configuration notice emitted by the generic iOS build and the unassigned 1024-pixel icon warning emitted by Mac/Catalyst asset compilation.
- Supply the public privacy-policy URL, support URL, screenshots, signing team, and App Store Connect records.
