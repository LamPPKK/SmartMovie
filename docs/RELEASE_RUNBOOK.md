# SmartMovie release runbook

## Prerequisites

- Xcode on Apple silicon with iOS, tvOS, watchOS, visionOS, and macOS platform SDKs, plus access to the Apple Developer team.
- XcodeGen 2.46 or newer, Node.js 24, npm, and a Cloudflare account authenticated by Wrangler.
- Editable App IDs for `LamNDT.SmartMovie`, `LamNDT.SmartMovie.watchkitapp`, and `LamNDT.SmartMovie.NativeMac`.
- Private CloudKit container `iCloud.LamNDT.SmartMovie` assigned to the universal and native Mac catalog App IDs.
- A newly issued TMDb API Read Access Token. Revoke the historical key that was committed before SmartMovie 2.0.
- Repository secret `ANDROID_CONTRACT_SYNC_TOKEN`, limited to Contents and Pull requests on `LamPPKK/Android.Smart.Movie`, so canonical contract changes can open snapshot PRs.

Select the full Xcode toolchain once on each build machine (this requires an administrator password):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcode-select --print-path
```

Verification: the printed path is `/Applications/Xcode.app/Contents/Developer` and `xcodebuild -showsdks` includes iOS, tvOS, watchOS, visionOS, and macOS SDKs.

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

Current automated baseline: 25 Swift tests and 28 Worker tests. Run `./scripts/verify-release.sh` and see [Testing](TESTING.md) for coverage and unsigned multi-platform build commands. Treat a changed test count as expected only when the test suite changed intentionally; zero failures is always required.

When the contract or release train changes on `main`, confirm the `Sync catalog contract to Android` workflow opens a pull request and that Android native plus desktop conformance CI passes before merging it. Production promotion remains blocked until the Android snapshot is on `main`.

## 2. Deploy Worker staging

The preferred path is the `Catalog Worker` GitHub Actions workflow. Run it manually with production deployment disabled. The workflow installs the rotated secret, deploys the `staging` Wrangler environment, and schema-validates configuration, Home, Genres, paginated Discover, Search, Detail, and normalized errors in `en-US`, `vi-VN`, `ja-JP`, `ko-KR`, `zh-CN`, and `zh-TW`. The smoke runner retries transient 429/5xx responses and requires every response to come from one Worker version. Client pagination deduplication and cancellation remain deterministic native/KMP test responsibilities.

The staging environment owns the Cloudflare custom domain `staging-catalog.smartmovie.app`. Confirm its DNS record and TLS certificate are active before running the workflow. The equivalent manual commands are:

```sh
cd backend/worker
npx wrangler login
npx wrangler secret put TMDB_BEARER_TOKEN --env staging
npm run deploy:staging
```

Set the actual staging hostname in `SmartMovie/project.yml` under Debug `CATALOG_BASE_URL`, then run `xcodegen generate` again.

Verification: request `/v1/configuration`, `/v1/home?media_type=movie&language=en-US`, and a deliberately invalid query. Valid routes must return JSON and the invalid request must return status 400 with a request ID. Responses and Cloudflare logs must not contain the Bearer token or search text.

Rollback/escalation: the protected workflow automatically runs `wrangler rollback` if post-deploy smoke validation fails. If upstream 401/403 persists, rotate the TMDb secret; do not place it in source or an app build setting.

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
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieWatch -destination 'generic/platform=watchOS' build
xcodebuild -project SmartMovie/SmartMovie.xcodeproj -scheme SmartMovieVision -destination 'generic/platform=visionOS' build
```

Verification: all six commands succeed with signing enabled. Exercise Home → Search/Explore → Detail → Favorite/Watchlist in every full catalog target; verify keyboard shortcuts on Mac/iPad, Remote focus/search on Apple TV, resizable and secondary detail windows on Vision Pro, and Watch remote commands while the iPhone app is reachable. Check all six languages, large Dynamic Type, VoiceOver, Increase Contrast, and Reduce Motion.

Before archiving, asset compilation must no longer report missing tvOS, watchOS, or visionOS production artwork, an unassigned Mac/Catalyst icon, or a missing iOS launch configuration. These warnings do not block the current unsigned development builds, but they are release blockers.

## 5. Promote production

Deploy the CloudKit Development schema to Production in CloudKit Console. Then rerun the protected `Catalog Worker` workflow with `deploy_production` enabled. The production job depends on successful staging deployment and smoke tests, requires Android `main` to match the OpenAPI checksum, fixture checksum, contract version, and release train, and uses the protected `production` environment for manual approval.

The production environment owns the Cloudflare custom domain `catalog.smartmovie.app`. The equivalent manual commands are:

```sh
cd backend/worker
npx wrangler secret put TMDB_BEARER_TOKEN --env production
npm run deploy:production
```

Verification: run the staging end-to-end flow against production without using a debug credential. Confirm cache HIT/MISS behavior, 429 `Retry-After`, image loading, offline Library snapshots, and cross-device CloudKit sync.

Rollback/escalation: roll the Worker back independently if catalog traffic fails. App releases should be phased in App Store Connect; pause the phased release if crash, sync, or localization validation fails.

## 6. App Store submission

Use one App Store record/universal purchase for iOS, tvOS, visionOS, Catalyst, and the embedded watchOS companion with `LamNDT.SmartMovie`. Use a separate record named `SmartMovie for Mac` for `LamNDT.SmartMovie.NativeMac`. Add the approved TMDb logo and required notice, public [privacy policy](PRIVACY.md), support URL, export-compliance answers, and platform-specific screenshots before submitting.
