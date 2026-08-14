# SmartMovie testing guide

## Purpose

SmartMovie keeps unit and contract tests deterministic and independent of TMDb, Cloudflare, CloudKit, and App Store credentials. The automated suite verifies shared behavior; device and service integration remain explicit release checks.

## Test matrix

| Suite | Current count | Responsibilities |
| --- | ---: | --- |
| API client | 6 | Request path/query/header construction, snake-case decoding, bounded 429/5xx retry, non-retriable errors, Discover filters, stable installation ID |
| Feature models | 6 | Home refresh, Explore pagination/deduplication, Search debounce/cancellation/error state, trailer selection |
| SwiftData Library | 3 | Independent Favorite/Watchlist state, CloudKit-style duplicate reconciliation, filtering/sorting/offline snapshots |
| Domain and configuration | 5 | Detail fixture, six locale mappings, Movie/TV fallbacks, Worker acronym decoding, image URL normalization |
| Cloudflare Worker | 19 | Route and query validation, cache behavior, rate limiting, TMDb error mapping, Home/Detail contracts, fallback language, token isolation |

Baseline: 20 Swift tests plus 19 Worker tests, all passing on 15 August 2026.

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
- `Xcode - Build and Analyze` builds and analyzes iOS, tvOS, Mac Catalyst, and native macOS independently.
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

The current core baseline is 74.20% line coverage. This number is diagnostic rather than a release gate: new behavior must be covered at its decision boundaries, while declarative SwiftUI rendering is verified through platform builds and UI/device checks.

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
```

All four unsigned builds currently succeed. Asset warnings for tvOS Top Shelf/App Icon, the Mac/Catalyst icon set, and the iOS launch configuration must be resolved before release.

## Adding tests

- Test observable feature state through public actions and outputs; do not couple tests to SwiftUI layout internals.
- Control asynchronous work with actors, cancellation, injected sleep functions, or explicit test clocks. Avoid arbitrary long sleeps.
- Verify both successful responses and normalized failures at the client/Worker contract boundary.
- Keep fixtures free of real tokens, search history, personal identifiers, and production CloudKit data.
- Add a regression test before or with every bug fix so the original failure cannot silently return.

## Manual release checks

Automated tests do not replace end-to-end verification on signed devices. Follow [Release runbook](RELEASE_RUNBOOK.md) for staging Worker checks, CloudKit synchronization, keyboard and Remote focus, accessibility, localization, App Store assets, and production promotion.
