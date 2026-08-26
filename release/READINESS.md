# SmartMovie 3.0 release readiness

## Automated source gates

- Canonical `/v1` and `/v2` OpenAPI/fixtures validate public success and normalized error responses.
- Apple and Android manifests pin product `3.0.0`, contract `2.0.0`, and OpenAPI SHA-256 `36df27d7f9e20dc7fdd544f3bdc7e3d231f71f17a10eecec92a17bc0de62cc2e`.
- Native Android and KMP consume the same versioned snapshot; production promotion verifies Android `main` before deploy.
- Worker tests cover v3/v4 mapping, cache partitions, rate limiting, D1 migrations, encryption, callback/CSRF/CORS controls, session expiry/revoke, durable mutation idempotency, and rollback paths.
- Swift, native Android, and KMP test canonical discriminator/nullable/unknown-field fixtures and local-first storage/outbox behavior.
- Native Android CI validates unit/lint/goldens plus phone/TV launch; main and Wear release workflows verify shared signing identity.
- KMP desktop tests/compile, JS, Wasm, and portable desktop packages are release blockers.
- Apple source gates cover Swift tests, strict SwiftLint, iOS/Catalyst/tvOS/macOS/watchOS/visionOS builds, analyze, and launch smoke where runtimes are installed.

## Product coverage status

[TMDb coverage](../docs/TMDB_COVERAGE.md) currently has no **Blocker** rows. Mixed-list editing/items, account recommendations, and Worker TMDb-change-feed cache invalidation have cross-platform or backend test coverage. Account authorization is fail-closed on every full client: Apple/Android TV require `tv_qr_auth`, while phone, desktop, and web require `browser_auth`; missing or false flags disable the action before any account request.

## Release-owner actions

The following require external accounts, protected credentials, approved artwork, or store ownership and are intentionally not committed:

- Create/verify DNS and TLS for `staging-catalog.smartmovie.app`, `catalog.smartmovie.app`, and browser callback origins.
- Create staging/production D1 databases, bind each as `AUTH_DB`, and apply all migrations.
- Rotate and set `TMDB_BEARER_TOKEN`, `SESSION_ENCRYPTION_KEY`, Cloudflare deployment credentials, callback origins, cookie domain, CORS origin allowlists, and return-URI allowlists.
- Configure `ANDROID_CONTRACT_SYNC_TOKEN` with least privilege and merge the checksummed Android snapshot PR.
- Configure Apple signing, App Store Connect records, production CloudKit schema, universal/app links, privacy/support URLs, approved TMDb artwork, Top Shelf/icons, screenshots, age rating, and metadata.
- Configure Android/Play signing secrets, verify main + Wear AAB identity/version/signature, complete Play privacy/age/attribution metadata, and run Internal Testing.
- Provide desktop code signing/notarization identities and publish the Web origin with correct `application/wasm`, cookie, CORS, and CSRF behavior.
- Provision a dedicated protected TMDb staging account. Tests must create/clean lists and ratings per run and never use a personal account.

## Promotion rule

Worker staging → contract/account smoke → every client CI/package → TestFlight, Play Internal, desktop/web candidates → device QA → Worker production → coordinated store/release publication.

Do not bypass contract checksum, capability, privacy, or signing gates. If Worker smoke fails, roll back the Worker deployment. If a client-only defect appears, stop staged rollout or return to the last store build while keeping the compatible Worker online.
