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
| SmartMovieKit | 49 tests passed, including `/v1` + `/v2` fixtures, complete advanced Discover/provider behavior, stale pagination and locale reload guards, draft/apply isolation, External ID/Credit Detail behavior, Account Recommendations pagination/adult filtering, and restart-safe/race-safe custom-list account-outbox behavior |
| Catalog Worker | Type-check and 84 tests passed, including advanced Discover/provider configuration, type-specific query/date validation, External ID/Credit Detail schema and mapping, Account Recommendations, normalized paginated mixed-list mapping and PUT/PATCH compatibility, TMDb Changes pagination/14-day backlog recovery, invalid cursor and verified changing-page-count recovery, D1-safe chunking, monotonic entity-cache invalidation, D1-read cache bypass, repeatable D1 migrations, encryption, callback/CSRF/CORS controls, session lifecycle, and mutation replay |
| iOS, Catalyst, tvOS, macOS, watchOS | Unsigned source builds passed for every listed destination |
| iOS launch smoke | The simulator app launched and remained alive for the smoke window |
| Native macOS launch smoke | `SmartMovieNativeMac` remained alive for five seconds; the earlier exit-code 132 crash was not reproduced |
| visionOS | Source compile/link validation passed; full asset build remains unverified because the installed host lacks the required visionOS runtime/toolchain support |

This evidence proves the checked-in source behavior on the local host; it does not replace signed-device, CloudKit production, protected TMDb account, cross-OS KMP, or store-candidate validation. Android native and KMP evidence is maintained in the Android repository's `docs/TESTING.md`.
