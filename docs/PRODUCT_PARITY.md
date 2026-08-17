# SmartMovie product parity contract

This document is the release authority for behavior shared by the native Apple and Android applications. Platform UI should follow native conventions; parity means equivalent inputs, state transitions, content, privacy, and failure behavior rather than pixel-identical layouts.

## Required shared behavior

| ID | Capability | Required behavior |
| --- | --- | --- |
| PAR-HOME-001 | Home | Switch between Movie and TV feeds; show the same Worker-provided hero and ordered sections; retry a failed load. |
| PAR-EXPLORE-001 | Explore | Support media type, genre, year, minimum rating, sort, grid/list presentation, pagination, cancellation, and `libraryKey` deduplication. |
| PAR-SEARCH-001 | Search | Support All/Movie/TV scopes, 350 ms debounce, cancellation of stale requests, pagination, deduplication, empty state, and retry. |
| PAR-DETAIL-001 | Detail | Show normalized title metadata, story, genres, runtime or seasons, cast, similar titles, and a language-aware YouTube trailer. |
| PAR-LIBRARY-001 | Library | Favorite and Watchlist are independent, persist offline, support Movie/TV filtering and common sort choices, and never remove the other collection when toggled. |
| PAR-NETWORK-001 | Network | Send an anonymous stable installation ID, retry 429 and transient 5xx responses at most twice, honor `Retry-After`, preserve cancellation, and map the common error envelope. |
| PAR-LOCALE-001 | Localization | Ship English, Vietnamese, Japanese, Korean, Simplified Chinese, and Traditional Chinese; map them to the six Worker locale tags. |
| PAR-PRIVACY-001 | Privacy | Keep the TMDb credential in Worker secrets only; do not add accounts, ads, analytics, IAP, search logging, or cross-platform user-data sync. |
| PAR-REMOTE-001 | Watch remote | Mirror only the active phone detail; reject stale title commands; support open, trailer, Favorite, and Watchlist actions. |

## Intentional platform differences

- Apple uses SwiftUI, SwiftData, private CloudKit, WatchConnectivity, and dedicated tvOS, visionOS, Catalyst, and native macOS shells.
- Android uses Jetpack Compose, Room, Google Auto Backup, the Wear Data Layer, Android TV, ChromeOS, foldable, and Android XR Home Space experiences.
- CloudKit sync is an Apple-ecosystem capability. Android library persistence and backup do not imply real-time cross-platform synchronization.
- Compose Multiplatform desktop and web clients must remain compatible with the catalog contract but do not block App Store or Play Store releases.

## Change and completion policy

1. Update this matrix before implementing a new shared behavior.
2. Update the canonical catalog contract first when the wire format changes.
3. Link the Apple and Android pull requests to the same release milestone and parity IDs.
4. A shared feature is complete only after both native implementations, localized states, conformance tests, and release checks pass.
5. A temporary platform-only hotfix must be recorded as a parity exception and reconciled in the next release train.

There are no open parity exceptions for the 2.0.0 release train.
