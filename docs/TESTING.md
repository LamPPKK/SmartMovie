# SmartMovie testing guide

## Purpose

SmartMovie keeps unit and contract tests deterministic and independent of TMDb, Cloudflare, CloudKit, and App Store credentials. The automated suite verifies shared behavior; device and service integration remain explicit release checks.

## Test matrix

| Suite | Current count | Responsibilities |
| --- | ---: | --- |
| API client | 11 | Request path/query/header construction, External ID/Credit Detail mapping, snake-case decoding, stable person/title credit links, bounded 429/5xx retry, non-retriable errors, deterministic advanced Discover filters and regional provider configuration, stable installation ID |
| Feature models | 12 | Home refresh, Explore context/filter normalization and pagination/deduplication, Search debounce/cancellation/error state, explicit External ID lookup, trailer selection |
| SwiftData Library | 3 | Independent Favorite/Watchlist state, CloudKit-style duplicate reconciliation, filtering/sorting/offline snapshots |
| Domain and configuration | 7 | Detail fixture, six locale mappings, Movie/TV fallbacks, Worker acronym decoding, image URL normalization, fail-closed account capability keys, and deferred callback gating |
| `/v1` catalog conformance | 3 | Canonical success/error fixtures, additive fields, and omitted nullable fields across native Swift models |
| `/v2` contract conformance | 3 | Entity discriminators, account/auth/mutation fixtures, unknown fields, and missing nullable values |
| Account mutation outbox | 4 | Persistence, account isolation, stable idempotency keys, exact acknowledgement, backward-compatible item snapshots, and restart-safe retry |
| Account rollout gating | 3 | Pre-capability callback suppression, in-flight completion invalidation, and durable library outbox isolation while account capability is unavailable |
| Account recommendations | 2 | Movie/TV switching, pagination, `libraryKey` deduplication, and local adult-PIN filtering |
| Custom mixed lists | 7 | Paginated Movie/TV merging, `libraryKey` deduplication, cached/in-flight adult filtering, catalog search filtering, optimistic state, and pending add/remove overlay after reload |
| Watch remote | 2 | Remote presentation intent, dismissal, Library revision, and title/context state |
| Cloudflare Worker | 91 | `/v1` + `/v2` schema/fixture validation, configured capability/fixture equality, malformed broker configuration and mis-scoped return-URI allowlist rejection, advanced Movie/TV Discover forwarding and type-specific rejection, real calendar-date validation, normalized regional provider configuration, External ID and Credit Detail normalization, account-recommendation v4 mapping, normalized/paginated mixed lists, PUT/PATCH update compatibility, private `no-store`, cache/rate limits, TMDb Changes pagination/14-day backlog recovery, invalid cursor and verified changing-page-count recovery, UTC-date replay idempotency, D1-safe 100-item page chunking, monotonic entity revision invalidation, D1-read cache bypass, repeatable D1 migrations, Wrangler scheduled-bundle validation, encryption, callback/CSRF/CORS controls, sessions, and idempotent mutation replay |

Current verified baseline: 57 Swift tests plus 91 Worker tests. Historical evidence and the local toolchain boundary are recorded in [Baseline](BASELINE.md).

## Latest local verification

The 26 August 2026 implementation run passed all 57 SmartMovieKit tests and all 91 Worker tests plus Worker type-checking and strict SwiftLint. Account rollout coverage verifies canonical `browser_auth`/`tv_qr_auth` keys, configured Worker response/fixture equality, rejection of short encryption keys, malformed/insecure callback origins, and empty or mis-scoped return-URI allowlists, missing/false/true fail-closed behavior, cold-start callback deferral, stale async-completion invalidation, durable outbox isolation, and localized unavailable UI before any account request across Apple, native Android/TV, and KMP. Advanced Discover coverage verifies the same fail-closed capability model, `/v1` basic fallback routing, capability-gated Profile provider-region loading, complete type-safe Movie/TV query forwarding, calendar-date rejection, regional provider configuration, canonical fixture decoding, deterministic provider/monetization encoding, context-preserving draft/apply behavior, runtime-bound normalization, and stale request/provider clearing. Worker coverage also includes scheduled Movie/TV/Person change polling, bounded page cursors, 14-day backlog/UTC rollover, invalid cursor and verified changing-page-count recovery, partial upstream failure, replay-safe monotonic D1 revisions, D1-safe 100-item page chunking, change-aware Cache API misses, and cache bypass when a bound D1 revision read fails. The most recent full Apple platform run passed unsigned iOS, Catalyst, tvOS, native macOS, and watchOS source builds, plus iOS launch smoke. visionOS remains subject to the host limitation below.

The native `SmartMovieNativeMac` executable also remained alive for a five-second smoke window, so the earlier exit-code 132 launch crash was not reproduced. Signed-device CloudKit validation is still required before release. visionOS source compile/link validation passed, but a full asset build remains unverified on this host because the required visionOS runtime/toolchain support is unavailable.

## Run unit and contract tests

Select the full Xcode toolchain first if the active developer directory points to Command Line Tools:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Run the Swift package tests:

```sh
cd SmartMovieKit
swift test
```

Run Worker type-checking and contract tests:

```sh
cd backend/worker
npm ci
npm run check
npm test
```

Verify the release train, contract version, and checksum from the repository root:

```sh
./scripts/verify-release.sh
```

No test command requires a TMDb Bearer token. Tests must use the existing URL protocol stub, repository fakes, in-memory SwiftData configuration, mocked Worker globals, or fixture data as appropriate.

## Enforce Swift style

Install SwiftLint and run it from the repository root:

```sh
brew install swiftlint
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swiftlint lint --strict --no-cache
```

`.swiftlint.yml` is the canonical rule configuration. CI treats every SwiftLint warning as a failure; do not introduce a baseline or inline suppression when a small code change can satisfy the rule.

## GitHub Actions

- `Swift` runs strict SwiftLint and the SmartMovieKit unit tests with code coverage.
- `Xcode - Build and Analyze` builds and analyzes iOS, tvOS, watchOS, visionOS, Mac Catalyst, and native macOS independently.
- `iOS` selects an available iPhone Simulator dynamically, builds the app, installs it, and performs a launch smoke test. SmartMovieKit unit tests remain in the `Swift` workflow because the package-generated Xcode scheme has no test action.

All workflows run for pushes and pull requests targeting `main` or `develop`, support manual dispatch, use read-only repository permissions, cancel stale runs on the same ref, and upload Xcode result bundles only when a job fails.

## Measure Swift core coverage

```sh
cd SmartMovieKit
SMARTMOVIE_COVERAGE=/tmp/SmartMovieKitCoverage
swift test --enable-code-coverage --scratch-path "$SMARTMOVIE_COVERAGE"

SMARTMOVIE_TEST_BINARY="$(find "$SMARTMOVIE_COVERAGE" -type f -path '*SmartMovieKitPackageTests.xctest/Contents/MacOS/SmartMovieKitPackageTests' -print -quit)"
SMARTMOVIE_PROFDATA="$(find "$SMARTMOVIE_COVERAGE" -name default.profdata -print -quit)"
xcrun llvm-cov report "$SMARTMOVIE_TEST_BINARY" \
  -instr-profile="$SMARTMOVIE_PROFDATA" \
  -ignore-filename-regex='Tests|/UI/|resource_bundle_accessor'
```

The last recorded 2.0 core baseline was 74.20% line coverage. Recalculate it for the 3.0 release candidate before publishing a new baseline. Coverage is diagnostic rather than a release gate: new behavior must be covered at its decision boundaries, while declarative SwiftUI rendering is verified through platform builds and UI/device checks.

## Build every Apple target

Run from the repository root after regenerating the Xcode project when `SmartMovie/project.yml` changes:

```sh
cd SmartMovie
xcodegen generate
cd ..

xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovie \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovie \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieNativeMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieWatch \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieVision \
  -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
```

All six destinations are enforced in CI. visionOS build and Simulator validation require an Apple-silicon host with the visionOS runtime installed. Asset warnings for tvOS Top Shelf/App Icon, watchOS/visionOS production icons, the Mac/Catalyst icon set, and the iOS launch configuration must be resolved before release.

## Adding tests

- Test observable feature state through public actions and outputs; do not couple tests to SwiftUI layout internals.
- Control asynchronous work with actors, cancellation, injected sleep functions, or explicit test clocks. Avoid arbitrary long sleeps.
- Verify both successful responses and normalized failures at the client/Worker contract boundary.
- Keep fixtures free of real tokens, search history, personal identifiers, and production CloudKit data.
- Add a regression test before or with every bug fix so the original failure cannot silently return.

## Manual release checks

Automated tests do not replace end-to-end verification on signed devices. Follow [Release runbook](RELEASE_RUNBOOK.md) for staging Worker checks, CloudKit synchronization, WatchConnectivity delivery, spatial windows, keyboard and Remote focus, accessibility, localization, App Store assets, and production promotion.
