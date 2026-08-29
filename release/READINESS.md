# SmartMovie 3.0 release readiness

## Automated source gates

- Canonical `/v1` and `/v2` OpenAPI/fixtures validate public success and normalized error responses.
- Apple and Android manifests pin product `3.0.0`, contract `2.0.0`, and OpenAPI SHA-256 `8bf63751f286daa30263a74aa98b633ccb78e9d2777e21a5023719fd1c3b6257`.
- Native Android and KMP consume the same versioned snapshot; production promotion verifies Android `main` before deploy.
- Worker tests cover v3/v4 mapping, cache partitions, rate limiting, D1 migrations, encryption, callback/CSRF/CORS controls, session expiry/revoke, durable mutation idempotency, and rollback paths. The protected staging runner snapshots and restores the full Movie/TV library matrix and Movie/TV/Episode ratings, validates recommendations, completes the mixed-list lifecycle, retries safely, and cleans up after failure.
- Swift, native Android, and KMP test canonical discriminator/nullable/unknown-field fixtures and local-first storage/outbox behavior.
- Native Android CI validates unit/lint/goldens plus phone/TV launch; main and Wear release workflows verify shared signing identity.
- KMP desktop tests/compile, JS, Wasm, and portable desktop packages are release blockers.
- Apple source gates cover Swift tests, strict SwiftLint, iOS/Catalyst/tvOS/macOS/watchOS/visionOS builds, analyze, and launch smoke where runtimes are installed. Committed release artwork now supplies opaque iOS/Mac icons, a separate Watch icon set, layered tvOS icons/Top Shelf images, a two-layer visionOS icon stack, and the named iOS launch color. Build-log inspection turns relevant asset warnings into CI failures; visionOS validation runs on Apple silicon.
- `./scripts/release-preflight.sh staging` and `production` are read-only owner gates for the matching promotion stage; `all` is the final combined audit. They check the source manifest, required GitHub secret names without reading their values, matching DNS/TLS, and optional local Wrangler authentication. Production additionally requires reviewer/branch protection plus exact Android `main` contract, fixture, release-manifest, and canonical-source provenance parity. The scoped post-deploy form such as `./scripts/release-preflight.sh staging --live` requires the exact capability contract and a Cloudflare UUID Worker version header; its public GET can exercise normal rate-limit/cache behavior.

## Product coverage status

[TMDb coverage](../docs/TMDB_COVERAGE.md) records Apple Episode account-state as implemented with model, HTTP, canonical fixture, pending-local precedence, and capability-gate coverage; live signed-in device/TV QA remains open. Mixed-list editing/items, account recommendations, and Worker TMDb-change-feed cache invalidation have cross-platform or backend test coverage. Account authorization is fail-closed on every full client: Apple/Android TV require `tv_qr_auth`, while phone, desktop, and web require `browser_auth`; missing or false flags disable the action before any account request.

## Release-owner actions

The following require external accounts, protected credentials, approved artwork, or store ownership and are intentionally not committed:

- Create/verify DNS and TLS for `staging-catalog.smartmovie.app`, `catalog.smartmovie.app`, and browser callback origins.
- Create staging/production D1 databases, bind each as `AUTH_DB`, and apply all migrations.
- Rotate and set `TMDB_BEARER_TOKEN`, `SESSION_ENCRYPTION_KEY`, Cloudflare deployment credentials, callback origins, cookie domain, CORS origin allowlists, and return-URI allowlists.
- Configure `ANDROID_CONTRACT_SYNC_TOKEN` with least privilege and merge the checksummed Android snapshot PR.
- Review and approve the committed Apple artwork, configure signing, App Store Connect records, production CloudKit schema, universal/app links, privacy/support URLs, approved TMDb attribution artwork, screenshots, age rating, and metadata.
- Configure Android/Play signing secrets, verify main + Wear AAB identity/version/signature, complete Play privacy/age/attribution metadata, and run Internal Testing.
- Provide desktop code signing/notarization identities and publish the Web origin with correct `application/wasm`, cookie, CORS, and CSRF behavior.
- Provision a dedicated protected TMDb staging account and persistent non-personal broker session. The automated runner restores library/ratings and deletes lists per run; browser/TV approval and logout/revoke use separate disposable sessions during manual QA.

## Promotion rule

Worker staging → contract/account smoke → every client CI/package → TestFlight, Play Internal, desktop/web candidates → device QA → Worker production → coordinated store/release publication.

Do not bypass contract checksum, capability, privacy, or signing gates. If Worker smoke fails, roll back the Worker deployment. If a client-only defect appears, stop staged rollout or return to the last store build while keeping the compatible Worker online.
