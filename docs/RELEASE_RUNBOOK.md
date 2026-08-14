# SmartMovie release runbook

## Prerequisites

- Xcode with iOS, tvOS, and macOS platform SDKs, plus access to the Apple Developer team.
- XcodeGen 2.46 or newer, Node.js, npm, and a Cloudflare account authenticated by Wrangler.
- Editable App IDs for `LamNDT.SmartMovie` and `LamNDT.SmartMovie.NativeMac`.
- Private CloudKit container `iCloud.LamNDT.SmartMovie` assigned to both App IDs.
- A newly issued TMDb API Read Access Token. Revoke the historical key that was committed before SmartMovie 2.0.

Select the full Xcode toolchain once on each build machine (this requires an administrator password):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcode-select --print-path
```

Verification: the printed path is `/Applications/Xcode.app/Contents/Developer` and `xcodebuild -showsdks` includes iOS, tvOS, and macOS SDKs.

## 1. Verify the source tree

```sh
cd SmartMovie
xcodegen generate

cd ../SmartMovieKit
swift test

cd ../backend/worker
npm ci
npm run check
npm test
```

Verification: Swift tests, Worker type-check, and Worker contract tests all complete with zero failures. Search the repository for `api_key=` and confirm no credential is present.

Current automated baseline: 20 Swift tests and 19 Worker tests. See [Testing](TESTING.md) for coverage and unsigned multi-platform build commands. Treat a changed test count as expected only when the test suite changed intentionally; zero failures is always required.

## 2. Deploy Worker staging

```sh
cd backend/worker
npx wrangler login
npx wrangler secret put TMDB_BEARER_TOKEN --env staging
npm run deploy:staging
```

Set the actual staging hostname in `SmartMovie/project.yml` under Debug `CATALOG_BASE_URL`, then run `xcodegen generate` again.

Verification: request `/v1/configuration`, `/v1/home?media_type=movie&language=en-US`, and a deliberately invalid query. Valid routes must return JSON and the invalid request must return status 400 with a request ID. Responses and Cloudflare logs must not contain the Bearer token or search text.

Rollback/escalation: deploy the previous known-good Worker version from Cloudflare deployment history. If upstream 401/403 persists, rotate the TMDb secret; do not place it in source or an app build setting.

## 3. Configure and test CloudKit development

Enable iCloud/CloudKit for both bundle IDs and select `iCloud.LamNDT.SmartMovie`. Build signed Development versions, add a Favorite and Watchlist item, and allow the SwiftData schema to initialize in the Development environment.

Verification: the same signed-in iCloud user sees both collection states on a second device or product. Removing Favorite must not remove Watchlist. Duplicates for a single `libraryKey` must reconcile to one visible item.

Rollback/escalation: do not reset a production CloudKit schema. Development data may be reset in CloudKit Console before production deployment. Schema fixes must be additive once production is live.

## 4. Build all products

```sh
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovie -destination 'generic/platform=iOS' build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovie -destination 'platform=macOS,variant=Mac Catalyst' build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieTV -destination 'generic/platform=tvOS' build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieNativeMac -destination 'generic/platform=macOS' build
```

Verification: all four commands succeed with signing enabled. Exercise Home → Search/Explore → Detail → Favorite/Watchlist in every target; verify keyboard shortcuts on Mac/iPad and Remote focus/search on Apple TV. Check all six languages, large Dynamic Type, VoiceOver, Increase Contrast, and Reduce Motion.

Before archiving, asset compilation must no longer report a missing tvOS App Icon/Top Shelf collection, an unassigned Mac/Catalyst icon, or a missing iOS launch configuration. These warnings do not block the current unsigned development builds, but they are release blockers.

## 5. Promote production

Deploy the CloudKit Development schema to Production in CloudKit Console. Then set the production Worker secret and deploy:

```sh
cd backend/worker
npx wrangler secret put TMDB_BEARER_TOKEN --env production
npm run deploy:production
```

Verification: run the staging end-to-end flow against production without using a debug credential. Confirm cache HIT/MISS behavior, 429 `Retry-After`, image loading, offline Library snapshots, and cross-device CloudKit sync.

Rollback/escalation: roll the Worker back independently if catalog traffic fails. App releases should be phased in App Store Connect; pause the phased release if crash, sync, or localization validation fails.

## 6. App Store submission

Use one App Store record/universal purchase for iOS, tvOS, and Catalyst with `LamNDT.SmartMovie`. Use a separate record named `SmartMovie for Mac` for `LamNDT.SmartMovie.NativeMac`. Add the approved TMDb logo and required notice, public [privacy policy](PRIVACY.md), support URL, export-compliance answers, and platform-specific screenshots before submitting.
