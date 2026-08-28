# TMDb coverage matrix

This matrix is the release authority for SmartMovie's TMDb surface. It classifies every TMDb API group used or deliberately omitted by the product. A route is not considered complete merely because the Worker can call it: `UI` requires a user-facing flow on Apple, native Android, and KMP; `backend-only` means the contract exists but no product surface exposes it; `excluded` is an intentional product boundary; `blocker` is required by the 3.0 plan but not yet complete on every client.

The canonical transport is OpenAPI 3.1 at `backend/worker/contract/v2/openapi.json`. Legacy `/v1` remains available for 2.0 clients.

## Catalog and discovery

| TMDb group | SmartMovie `/v2` surface | Classification | Evidence / remaining work |
| --- | --- | --- | --- |
| Configuration, genres | `/v2/configuration`, `/v2/home`, `/v2/discover/{mediaType}` | UI | Image configuration and genre-driven discovery are consumed by all catalog clients. |
| Home feeds | `/v2/home` | UI | Movie and TV shelves normalize trending, popular, top-rated, theatrical/on-air, and upcoming feeds. |
| Discover | `/v2/discover/{mediaType}` | UI | Apple, native Android, and KMP expose the same media type, genre, date range, original language/country, certification, runtime, minimum vote count, regional provider, monetization type, sort, rating, year, and local adult context. Adult access requires explicit age confirmation and a six-digit device PIN; five failed unlocks enforce a five-minute lockout. `/v2/configuration` supplies regional provider options and canonical fixtures verify every client decoder. |
| Trending | `/v2/trending/{kind}/{window}` | UI | Home consumes trending content; repository APIs also expose day/week and entity-kind selection. |
| Search | `/v2/search` | UI | Discriminated Movie, TV, Person, Collection, Company, and Keyword results navigate to native entity details. |
| Find by external ID | `/v2/find/{externalId}` | UI | Search offers an explicit External ID mode on Apple, native Android, and KMP with source selection for IMDb, TheTVDB, Wikidata, Facebook, Instagram, and X/Twitter; mixed results keep their entity discriminator, use normal detail navigation, carry `include_adult`, and are filtered again on-device. Season/Episode matches are withheld while the adult gate is locked because TMDb does not expose the parent title's adult flag in those result objects. |
| Movie and TV detail | `/v2/titles/{mediaType}/{id}` | UI | Apple, Apple TV, native Android/TV, and KMP expose tagline, creators/credits, collection, navigable companies/networks, seasons, external IDs, reviews, recommendations, similar titles, providers, and a typed release/localization section. Canonical fixtures contain non-empty editorial and media data matching TMDb's same-media-type recommendation route. Clients filter blank reviews, stably deduplicate review IDs, show the full body plus optional rating/date metadata, cap the review surface at four, deduplicate recommendations by `libraryKey`, exclude the current title, and keep recommendations separate from similar titles. Both related-title shelves suppress adult entries unless the local adult gate is unlocked. Image galleries expose deduplicated assets and every valid YouTube video while blank paths/keys, duplicate assets, and non-YouTube videos stay hidden. Regional certification/date selection, alternative-title ordering, translations, missing nullable values, and unknown fields share canonical conformance fixtures. |
| Related title resources | `/v2/titles/{mediaType}/{id}/{resource}` | UI through aggregate detail | Separate routes cover credits, images, videos, reviews, recommendations, similar, translations, release information, external IDs, and watch providers. Clients normally consume the normalized aggregate detail. |
| People | `/v2/entities/person/{id}` | UI | Biography, profile images, aliases, external IDs, and combined credits are navigable from cast/crew and Search. Known-for titles and cast/crew credits are partitioned by `include_adult` and filtered again by each client. |
| Collections | `/v2/entities/collection/{id}` | UI | Collection detail and member titles are navigable; restricted parts remain hidden until the local gate is unlocked. |
| Companies and networks | `/v2/entities/{company|network}/{id}` | UI | Search/detail navigation shows organization metadata and related titles, with Worker and client adult filtering. |
| Keywords | `/v2/entities/keyword/{id}` | UI | Keyword detail shows related titles, with Worker and client adult filtering. |
| TV seasons and episodes | `/v2/tv/{seriesId}/seasons/{seasonNumber}` and episode child route | UI | Apple, native Android, and KMP display Season/Episode artwork galleries, all valid YouTube videos, air date, episode count/runtime/production/vote metadata, external IDs, credits, and guest stars from non-empty canonical fixtures. Safe episode context mirrors to Apple Watch/Wear OS and opens the exact series/season/episode back on the paired phone without enabling title-only trailer or library mutations. |
| Credit detail | `/v2/credits/{creditId}` | UI | Cast, crew, season, episode, and guest-star credits open a localized detail screen on Apple, native Android, and KMP. The normalized response exposes stable person/title links and role metadata; an adult title returns the standard not-found envelope while locked, and clients defensively remove restricted title context. |
| Watch providers | title aggregate and related-resource route | UI | Region-aware stream/rent/buy offers open only the TMDb URL and show JustWatch attribution. |
| Changes | no public route | Backend-only | The hourly Worker cron polls paginated Movie/TV/Person change lists with durable D1 cursors. UTC-date entity revisions invalidate title/person/related/season/episode Cache API keys idempotently; TV revisions cover series-level season/episode edits. Each kind recovers independently after upstream failure, stale revision rows expire after 30 days, and no debug UI or public route exists. |
| Certifications, release dates, content ratings, alternative titles, translations, external IDs | normalized title detail | UI | These upstream groups are folded into stable typed title models and shown in the title detail flow on Apple, native Android/TV, and KMP. Certification and release date appear only for the effective device-or-override region, so data from another country is never mislabeled as local. |

## Account and lists

| TMDb group | SmartMovie `/v2` surface | Classification | Evidence / remaining work |
| --- | --- | --- | --- |
| v4 browser authorization and v3 session exchange | `/v2/auth/*` | UI | Clients open TMDb in the system browser; TV uses QR/polling; Web uses secure cookies. SmartMovie never receives a TMDb password. Full clients fail closed against canonical `/v2/capabilities`: Apple/Android TV require `tv_qr_auth`, while phone, desktop, and web require `browser_auth`; missing or false flags suppress auth/profile requests and present a localized unavailable state. Production still requires D1 bindings, encryption secrets, callback DNS, and allowlists. |
| Account profile/state | `/v2/account/profile`, `/v2/account/state/*` | UI | Profile is the fifth primary destination; title/episode state hydrates rating and library UI. |
| Favorites and Watchlist | `/v2/account/{favorites|watchlist}/{mediaType}` | UI | Local-first merge and durable outbox preserve offline mutations. Pending local state wins until acknowledged. Protected staging toggles and restores Favorite and Watchlist for both Movie and TV. |
| Movie/TV/Episode ratings | `/v2/account/ratings/*` | UI | Apple, native Android, and KMP support 0.5–10 ratings, removal, optimistic state, persistence, and idempotent retry. Protected staging sets, verifies, and restores all three rating kinds. |
| Account recommendations | `/v2/account/recommendations/{mediaType}` | UI | Profile displays separate Movie/TV recommendations on Apple, native Android/TV, and KMP, with retry, pagination, title navigation, `libraryKey` deduplication, and local adult-PIN filtering. The canonical fixture and Worker test cover v4 mapping and private `no-store` delivery. |
| Custom mixed lists | `/v2/account/lists*` | UI | Apple, native Android/TV, and KMP can load every list-summary page, create/open/delete mixed lists, edit metadata, page through contents, search Movie/TV titles, and add/remove items through the durable outbox. Canonical list detail responses normalize discriminators and pagination; canonical mutation responses preserve `list_id` across idempotent creation replay. Clients deduplicate by `libraryKey`, reject stale list/search responses, preserve pending add/remove snapshots across restarts, enforce the local adult-PIN filter on cached state, and keep pending offline list creation visibly read-only until TMDb assigns an ID. Protected staging verifies create/update/add, acknowledges the comment mutation, verifies removal and deletion, and discovers/deletes uniquely named temporary lists after failure. |
| Guest sessions | none | Excluded | SmartMovie uses browser-approved account sessions only. |
| Raw username/password login | none | Excluded | Credentials must only be entered on TMDb-controlled pages. |

## Product boundaries

| TMDb group or behavior | Classification | Reason |
| --- | --- | --- |
| Full movie or episode playback | Excluded | SmartMovie is a catalog; it only opens trailers and availability links. |
| SmartMovie-owned accounts | Excluded | Identity and user content remain at TMDb; the Worker brokers opaque sessions only. |
| Server-side storage of favorites, watchlist, ratings, or list contents | Excluded | User content lives at TMDb and in local client caches/outboxes. |
| Analytics, advertising, in-app purchases | Excluded | Outside the product and privacy model. |
| Adult content on Watch/Wear, notifications, public screenshots, or store metadata | Excluded | Adult content is local opt-in with a six-digit device PIN and is deliberately withheld from public/companion surfaces. |
| TMDb app credential in a client | Excluded / security violation | The credential belongs only in protected Worker secrets. |

## Completion rule

SmartMovie 3.0 is not product-complete while any row is marked **Blocker**. Every completed UI row must have Worker schema/fixture coverage plus Swift, native Android, and KMP decoding or behavior tests; backend-only rows require deployment configuration and focused Worker behavior tests without inventing a client surface. Production account capability must remain disabled until the deployed Worker has its D1 binding, session-encryption key, callback origin, and return-URI allowlist. The canonical capability fixture must match the live configured Worker response so rollout gates cannot drift from deployed keys.
