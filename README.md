# SmartMovie 2.0

SmartMovie is a cinematic Movie and TV Series catalog for iPhone, iPad, Apple TV, Mac Catalyst, and native macOS. The UI is SwiftUI, library data is stored with SwiftData and CloudKit, and TMDb credentials stay behind a Cloudflare Worker.

## Products

- `SmartMovie` — iOS, iPadOS, tvOS, and Mac Catalyst; bundle ID `LamNDT.SmartMovie`.
- `SmartMovie for Mac` — native macOS; bundle ID `LamNDT.SmartMovie.NativeMac`.

Both products share `SmartMovieKit`, Worker APIs, and the private CloudKit container `iCloud.LamNDT.SmartMovie`.

## Repository layout

- `SmartMovie/` — Xcode project, app shells, entitlements, and assets.
- `SmartMovieKit/` — local Swift package containing Domain, Data, shared design system, features, localization, and unit tests.
- `backend/worker/` — TypeScript Cloudflare Worker and contract tests.
- `docs/` — architecture, privacy, and release operations.

## Local development

Requirements: Xcode with iOS, tvOS, and macOS SDKs; XcodeGen; Node.js and npm.

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
cd SmartMovie
xcodegen generate
open SmartMovie.xcodeproj
```

The Debug configuration points at `https://staging-catalog.smartmovie.app/`. Change `CATALOG_BASE_URL` in `SmartMovie/project.yml` for a different staging Worker, then regenerate the project.

Run core and Worker checks:

```sh
cd SmartMovieKit
swift test

cd ../backend/worker
npm install
npm run check
npm test
```

The current baseline is 20 Swift unit tests and 19 Worker contract tests. The shared Swift core has 74.20% line coverage when UI, generated accessors, and test sources are excluded. All four Apple targets build successfully without code signing: iOS, tvOS, Mac Catalyst, and native macOS.

See [Testing](docs/TESTING.md) for the test matrix, coverage command, and platform build commands. Worker secrets are never stored in the repository. See [Release runbook](docs/RELEASE_RUNBOOK.md) for staging, CloudKit, and production steps.

## Release status

The source implementation and automated checks are complete. Before App Store submission, the release owner must still:

- deploy the staging and production Workers and replace the placeholder catalog hostnames;
- configure the shared CloudKit container and signing for both products;
- add approved TMDb attribution artwork;
- complete the tvOS App Icon and Top Shelf Image brand assets;
- provide App Store metadata, screenshots, privacy-policy URL, and support contact.

## Attribution

This product uses the TMDB API but is not endorsed or certified by TMDB. Movie metadata and artwork are supplied by [The Movie Database](https://www.themoviedb.org/).
