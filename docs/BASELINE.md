# SmartMovie 2.0 verification baseline

Baseline captured on 17 August 2026 before contract consolidation and removal of the duplicate Compose iOS client.

## Automated suites

| Surface | Baseline | Canonical command |
| --- | --- | --- |
| Catalog Worker | 19 tests passing locally | `npm test` from `backend/worker` |
| Swift shared core | 22 tests documented in CI | `swift test --package-path SmartMovieKit` |
| Apple app shells | Six build/analyze destinations plus an iOS launch smoke test | GitHub Actions `Swift`, `iOS`, and `Xcode - Build and Analyze` |
| Android native | Unit, lint, golden, phone emulator, TV emulator, mobile AAB, and Wear AAB checks | GitHub Actions `Android CI` and `Android release AAB` |
| Compose desktop/web | Desktop tests plus desktop, JavaScript, and Wasm compilation | GitHub Actions `Compose Multiplatform CI` |

## Local environment boundary

Run `./scripts/doctor.sh` before treating a local failure as a product regression. At capture time this machine selected Command Line Tools with a mismatched Swift SDK and exposed JDK 11 only; Swift and Gradle failures from that environment are not accepted as code baselines. CI remains the authoritative clean toolchain until Doctor passes locally.

After consolidation, every suite must additionally run catalog schema/fixture conformance and release-version validation. Baseline failures must be documented separately from regressions introduced by the change under review.

## Post-consolidation verification

Local verification on 17 August 2026 produced the following evidence:

| Check | Result |
| --- | --- |
| SwiftLint | 31 files, zero violations in strict mode |
| SmartMovieKit | 25 tests passed, including 3 catalog contract conformance tests |
| iOS Simulator build | `SmartMovie` built successfully for an iPhone 16 Pro running iOS 18.6 |
| iOS launch smoke | The installed app launched as `LamNDT.SmartMovie`, remained alive for the three-second smoke window, and terminated normally |
| Catalog Worker | Type-check and 28 tests passed, including schema validation for all six routes and the normalized error envelope |

The Swift checks used the complete toolchain through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The machine-wide `xcode-select` value still points to Command Line Tools and the installed Node.js major is not 24, so `./scripts/doctor.sh` correctly remains red until those host settings are fixed. This is an environment exception, not a product-test failure.

The Android verification evidence for the same release train is maintained in the Android repository's `docs/TESTING.md`.
