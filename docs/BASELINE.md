# SmartMovie verification baseline

This document separates the historical SmartMovie 2.0 baseline from the latest SmartMovie 3.0 verification evidence. A failure already present in the historical baseline is not attributed to a later architecture change without a fresh reproduction.

## Historical 2.0 baseline — 17 August 2026

| Surface | Baseline | Canonical command |
| --- | --- | --- |
| Catalog Worker | 19 tests passing locally | `npm test` from `backend/worker` |
| Swift shared core | 22 tests documented in CI | `swift test --package-path SmartMovieKit` |
| Apple app shells | Six build/analyze destinations plus an iOS launch smoke test | GitHub Actions `Swift`, `iOS`, and `Xcode - Build and Analyze` |
| Android native | Unit, lint, golden, phone emulator, TV emulator, mobile AAB, and Wear AAB checks | GitHub Actions `Android CI` and `Android release AAB` |
| Compose desktop/web | Desktop tests plus desktop, JavaScript, and Wasm compilation | GitHub Actions `Compose Multiplatform CI` |

### Local environment boundary

Run `./scripts/doctor.sh` before treating a local failure as a product regression. At capture time this machine selected Command Line Tools with a mismatched Swift SDK and exposed JDK 11 only; Swift and Gradle failures from that environment are not accepted as code baselines. CI remains the authoritative clean toolchain until Doctor passes locally.

After consolidation, every suite must additionally run catalog schema/fixture conformance and release-version validation. Baseline failures must be documented separately from regressions introduced by the change under review.

### Post-consolidation 2.0 verification

Local verification on 17 August 2026 produced the following evidence:

| Check | Result |
| --- | --- |
| SwiftLint | 31 files, zero violations in strict mode |
| SmartMovieKit | 25 tests passed, including 3 catalog contract conformance tests |
| iOS Simulator build | `SmartMovie` built successfully for an iPhone 16 Pro running iOS 18.6 |
| iOS launch smoke | The installed app launched as `LamNDT.SmartMovie`, remained alive for the three-second smoke window, and terminated normally |
| Catalog Worker | Type-check and 28 tests passed, including schema validation for all six routes and the normalized error envelope |

The Swift checks used the complete toolchain through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The machine-wide `xcode-select` value still points to Command Line Tools and the installed Node.js major is not 24, so `./scripts/doctor.sh` correctly remains red until those host settings are fixed. This is an environment exception, not a product-test failure.

## Latest 3.0 implementation verification — 26 August 2026

The current source was verified after the `/v2` catalog/account broker, durable account outboxes, External ID lookup, cross-platform Credit Detail navigation, and Account Recommendations Profile surfaces were added:

| Check | Result |
| --- | --- |
| SwiftLint | Strict mode passed with zero violations |
| SmartMovieKit | 57 tests passed, including `/v1` + `/v2` fixtures, fail-closed browser/TV account capability keys, cold-start callback deferral, stale completion invalidation, offline outbox isolation, capability-gated Advanced Discover and Profile provider regions with `/v1` fallback, stale pagination and locale reload guards, draft/apply isolation, External ID/Credit Detail behavior, Account Recommendations pagination/adult filtering, and restart-safe/race-safe custom-list account-outbox behavior |
| Catalog Worker | Type-check and 91 tests passed, including configured capability/fixture equality, malformed account-broker configuration and mis-scoped return-URI allowlist rejection, advanced Discover/provider configuration, type-specific query/date validation, External ID/Credit Detail schema and mapping, Account Recommendations, normalized paginated mixed-list mapping and PUT/PATCH compatibility, TMDb Changes pagination/14-day backlog recovery, invalid cursor and verified changing-page-count recovery, D1-safe chunking, monotonic entity-cache invalidation, D1-read cache bypass, repeatable D1 migrations, encryption, callback/CSRF/CORS controls, session lifecycle, and mutation replay |
| iOS, Catalyst, tvOS, macOS, watchOS | Unsigned source builds passed for every listed destination |
| iOS launch smoke | The simulator app launched and remained alive for the smoke window |
| Native macOS launch smoke | `SmartMovieNativeMac` remained alive for five seconds; the earlier exit-code 132 crash was not reproduced |
| visionOS | Source compile/link validation passed; full asset build remains unverified because the installed host lacks the required visionOS runtime/toolchain support |

This evidence proves the checked-in source behavior on the local host; it does not replace signed-device, CloudKit production, protected TMDb account, cross-OS KMP, or store-candidate validation. Android native and KMP evidence is maintained in the Android repository's `docs/TESTING.md`.

## Artwork regression verification — 28 August 2026

- SmartMovieKit: 71 tests passed, including four new render regressions for loaded-image fill/fit viewport sizing, unavailable-image sizing and nil-URL pixels.
- Strict SwiftLint: zero violations in 70 files, with the full Xcode `DEVELOPER_DIR` selected.
- Unsigned iOS, native macOS and tvOS preview builds passed. iPhone and Mac showed downloaded local preview artwork; this does not validate signed-device or live-TMDb behavior.
- Android/KMP local preview: three HTTP tests passed, including nested fixture images at every advertised size and complete PNG payloads. No native Android image-rendering claim is made by this suite.
- Release/version checks passed: train `3.0.0`, contract `2.0.0` and vendored checksum remained consistent.

The public TMDb example image was reachable, but both configured Worker domains failed DNS resolution from this machine. See [IMAGE_LOADING.md](IMAGE_LOADING.md); production image loading remains a release blocker, not a passing result hidden by demo artwork.

## Compact Detail layout verification — 29 August 2026

- SmartMovieKit: 78 tests passed, including seven new layout regressions for six action-label translation sets, a wide row, an extra action, long-label vertical growth, RTL alignment, minimum rendered button height and large metadata values.
- Strict SwiftLint: zero violations in 72 files. Unsigned iOS Simulator and tvOS Simulator builds passed.
- Detail action and metadata groups measure their full labels before choosing a row or leading-aligned column. Pill labels can wrap and have a minimum rendered height of 44 points. Existing action closures, trailer availability and signed-in rating conditions are unchanged.
- These render tests run on macOS. The fourth-action test uses a generic pill, not the signed-in rating menu; they do not prove account interactions, VoiceOver, D-pad navigation or every locale/device at every Dynamic Type size.
- Actual iPhone 16/iOS 18.6 preview captures confirmed full English action labels at normal size, unbroken rating/year/runtime at maximum Accessibility size, and the complete Watchlist label after scrolling. The simulator's original `large` text setting was restored. See [screenshots and remaining QA gaps](SCREENSHOTS.md).

The release train and contract stay at `3.0.0`/`2.0.0`. Production/account/store gates remain open; this layout fix is not a release-readiness declaration.

## CI timing and image recheck — 29 August 2026

- Apple commit `632be36` passed iOS and Xcode build/analyze CI, but [Swift run 33200358791](https://github.com/LamPPKK/Smart-Movie-iOS/actions/runs/33200358791) failed two assertions in the Search test after its fixed wait expired. All four artwork and seven Detail layout tests passed in that run.
- The Search test now waits for the old request to actually enter the repository, for the new result to arrive, and for cancellation of the old request. The stub records requests and cancellation; app debounce and production code are unchanged. The renamed test does not claim to cover a cancellation-ignoring stale success response.
- Independent verification in a fresh scratch build: `swift test --enable-code-coverage` passed 78/78 tests, including 12 feature-model, four artwork and seven Detail layout tests. The targeted cancellation test also passed ten repeated runs. Strict SwiftLint passed with zero violations in 72 files.
- Local verification used macOS 15.7.7, x86_64 and Swift 6.2.3. This is not the ARM64 GitHub runner; the new commit still requires its own CI result.
- Preview HTTP tests passed 3/3. TMDb's public image returned HTTP 200; both configured Worker domains still failed DNS outside the sandbox. Staging preflight reported three blockers and one warning; see [image-loading diagnostics](IMAGE_LOADING.md). No production image-delivery or signed-device claim is made.

## Half-step rating repair — 29 August 2026

- Apple Movie/TV and Episode menus previously offered only integer scores. The shared `AccountRatingOptions` component now exposes all 20 contract values from 0.5 through 10, with locale-aware choice labels and unchanged conditional removal.
- The range regression failed against the integer-only values before the repair. Independent final coverage verification passed 83/83 tests; strict SwiftLint passed with zero violations across 74 files. Unsigned iOS Simulator and tvOS Simulator builds passed.
- New coverage verifies six-locale labels, actual shared content rendered against literal expected labels with/without removal, all 63 Movie/TV/Episode value/removal payloads after disk reload, restart/retry of a failed 0.5 episode rating, and HTTP PUT/DELETE path/value/idempotency preservation through 503 retry.
- Render evidence is English macOS borderless content inside a VStack, not native popup-menu or signed-in gesture testing. Live TMDb and device/TV account QA remain open. Apple remote episode-rating hydration was found missing and is now explicitly recorded in [TMDb coverage](TMDB_COVERAGE.md).
- The previous commit `e4778c0` completed all three Apple Swift/iOS/Xcode CI workflows successfully. This rating commit requires its own CI run. Worker/Android/KMP sources and the `3.0.0` release train / `2.0.0` contract are unchanged; no production deployment was attempted.

## Episode account-state hydration — 29 August 2026

- Apple Episode Detail now fetches the authenticated `/v2/account/state/episode/{seriesId}/{seasonNumber}/{episodeNumber}` response. A pending local set/removal is checked both before and after the network suspension and remains authoritative until acknowledged.
- Generation and identity checks discard late success and error responses after an account or episode switch, cancellation, view disappearance, or optimistic local write. Returned series/season/episode identifiers must match the requested context.
- Independent verification passed 93/93 Swift tests with zero strict SwiftLint violations across 78 files. The eight model tests cover remote half-step/unrated state, retry, pending writes arriving in flight, acknowledged local writes, account/episode switches, reset, cancellation and mismatched identity. The authenticated HTTP and capability-gate tests cover exact routing, bearer authorization and fail-closed browser/TV rollout.
- Worker type-check plus 100 unit/contract tests and 9 smoke-runner tests passed. The two canonical episode-state fixtures are validated as private/no-store and decode on Swift, native Android and KMP; the 16-fixture checksum is `7ab968a4781b02010e2f213666ba587ce840f414de0eace72d1cf51f47faa96f`.
- Unsigned iOS Simulator and tvOS Simulator builds passed. These checks do not exercise SwiftUI gestures, integrated enqueue/flush dispatch, live Cloudflare/TMDb authentication or signed-in device/TV behavior; those release gates remain open.
