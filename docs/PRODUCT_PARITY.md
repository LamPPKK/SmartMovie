# SmartMovie 3.0 product parity contract

This document is the release authority for behavior shared by native Apple, native Android, TV, watch companions, and Compose Multiplatform desktop/web. Platform UI follows native conventions; parity means equivalent content, state transitions, privacy, localization, offline behavior, and error handling rather than pixel-identical layout.

## Required shared behavior

| ID | Capability | Required behavior |
| --- | --- | --- |
| PAR-HOME-001 | Home | Switch Movie/TV feeds, preserve Worker ordering, navigate titles, and retry failures. |
| PAR-EXPLORE-001 | Explore | Support catalog filters, region/adult partitioning, cancellation, pagination, retry, and `libraryKey` deduplication. |
| PAR-SEARCH-002 | Entity search | Decode and navigate Movie, TV, Person, Collection, Company, and Keyword discriminators; debounce, cancel stale requests, paginate, deduplicate, and retry. An explicit External ID mode supports every allowlisted source without per-keystroke requests. |
| PAR-DETAIL-002 | Deep title detail | Show normalized metadata, credits, media, reviews, related titles, release/content rating data, collection, seasons, and region-aware providers. |
| PAR-ENTITY-001 | Entity details | Navigate Person, Collection, Company, Network, Keyword, Season, and Episode without coercing them into title models; every title-bearing entity request carries the local adult gate and clients filter returned titles/credits again before display. |
| PAR-MEDIA-001 | Catalog media | Movie/TV, Season, and Episode details deduplicate non-blank image paths, expose only non-blank YouTube video keys, preserve upstream order, and show available air-date/runtime/production/vote/external-ID metadata with six-locale labels. |
| PAR-EDITORIAL-001 | Catalog reviews and recommendations | Title details show the full body of up to four non-blank reviews after stable ID deduplication, use a localized member fallback when the author is blank, preserve optional rating/date metadata, and expose same-media-type TMDb recommendations deduplicated by `libraryKey` while excluding the current title. Recommendations and similar titles remain separate shelves; both suppress adult titles unless the local adult gate is unlocked. |
| PAR-CREDIT-001 | Credit detail | Open cast/crew/guest-star credits from title, person, season, and episode surfaces; show role metadata; retain navigable person/title links; and suppress restricted title context while the adult gate is locked. |
| PAR-PROVIDER-001 | Availability | Use the selected/device region, distinguish stream/rent/buy, open only the TMDb URL, and display JustWatch attribution. |
| PAR-ADULT-001 | Adult content | Default off; require age confirmation and a local six-digit PIN; lock five minutes after five failures; partition Search, External ID, Title, Person, Collection, Company, Network, Keyword, Credit Detail and related-title responses at the Worker; filter again at every full client; exclude from companion/public surfaces. |
| PAR-AUTH-001 | TMDb authorization | Use TMDb browser approval, opaque SmartMovie sessions, allowlisted callbacks, and no password collection. TV uses QR/polling and requires `tv_qr_auth`; phone, desktop, and web require `browser_auth`, with Web using an `HttpOnly` cookie. Missing/false capabilities must fail closed, show a localized unavailable state, and prevent account requests. |
| PAR-LIBRARY-002 | Account library | Merge local and TMDb Favorites/Watchlist on first login; local pending mutations win; durable outbox retry is idempotent; logout offers keep-local or remove-account-data. |
| PAR-RATING-001 | Ratings | Rate/remove Movie, TV, and Episode values from 0.5 through 10; update optimistically; persist and retry the same mutation ID. |
| PAR-RECOMMENDATIONS-001 | Account recommendations | After TMDb sign-in, display separate Movie/TV recommendations with retry, pagination, title navigation, `libraryKey` deduplication, and the same local adult-PIN visibility rule as catalog search. |
| PAR-LISTS-001 | Custom lists | Support mixed Movie/TV list CRUD and item changes through the durable account outbox. |
| PAR-NETWORK-002 | Network | Send stable anonymous client identity, honor the normalized error envelope, retry 429/transient 5xx at most twice, honor `Retry-After`, and preserve cancellation. |
| PAR-LOCALE-001 | Localization | Ship English, Vietnamese, Japanese, Korean, Simplified Chinese, and Traditional Chinese; map exactly to the six Worker locales. |
| PAR-PRIVACY-002 | Privacy | Keep TMDb credentials and encrypted upstream tokens in the Worker; never log token/session/PIN/sensitive query values; ship no analytics or advertising. |
| PAR-COMPANION-002 | Watch/Wear | Mirror safe active-title/episode context and phone actions only; opening an episode returns to that exact series/season/episode, while trailer and library actions remain title-only; no independent login or adult content. |

## Intentional platform differences

- Apple uses SwiftUI, SwiftData/private CloudKit, WatchConnectivity, and dedicated tvOS, visionOS, Catalyst, and native macOS shells.
- Android uses Jetpack Compose, Room/backup, the Wear Data Layer, Android TV, ChromeOS, foldable, and Android XR Home Space experiences.
- KMP uses Java Preferences or browser `localStorage`; Web uses secure cookie-based auth rather than exposing the opaque native token to JavaScript.
- Watch/Wear are companions, not complete catalogs, and never authorize independently.
- CloudKit is Apple-ecosystem sync. It does not replace TMDb as the post-login account source of truth.

## Release blockers and exceptions

- Apple, Android, TV, watch companion, desktop JVM, JavaScript, and Wasm are release blockers for every 3.0 milestone.
- A capability is complete only when its behavior, errors, localization, accessibility input model, fixtures, and tests exist on every required client.
- Hotfixes may temporarily diverge at patch level only when recorded in `release/train.json`; the next release train must reconcile them.
- `/v1` remains available for 2.0 clients for at least 12 months after the 3.0 production release. `/v2` is additive-only.

The current release manifest has no recorded parity exceptions. This does **not** mean product parity is complete: unresolved coverage blockers are tracked in [TMDb coverage](TMDB_COVERAGE.md).
