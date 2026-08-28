# Image loading: diagnosis and verification

Checked on 2026-08-28. Scope: missing thumbnails/artwork in development captures
and the shared Apple image component. This is not a production-readiness sign-off.

## Confirmed findings

| Path | Evidence | Action/status |
| --- | --- | --- |
| Local preview | Earlier `/v1` preview returned null image paths and empty image configuration. Nested `/v2` fixture paths also referenced nonexistent files. | Android `multiplatform/tools/preview_server.py` now serves explicit local demo artwork/configuration and remaps nested fixture paths without editing the canonical fixtures. |
| Apple layout after success | A 1920×1080 loaded backdrop expanded a 343-point hero to about 693 points; fit-mode artwork shrank a 320-point viewport to 45 points. | `RemoteArtwork` now lets the caller's viewport own layout. Four render regression tests cover fill, fit, failure and nil URL. |
| Apple missing URL | No request could complete, but the empty phase displayed loading indefinitely. | Nil URLs render the same unavailable-artwork state as failure. |
| TMDb public image CDN | A public image from TMDb's official image-basics example returned HTTP 200, `image/jpeg`, 103,520 bytes. | The CDN was reachable from this machine; this does not verify every title image. |
| Staging and production Worker origins | Requests to `staging-catalog.smartmovie.app` and `catalog.smartmovie.app` failed DNS resolution (`curl` exit 6). | Unresolved infrastructure blocker. No DNS, secret, token or deployment was changed. |

TMDb images are constructed from configuration base URL + supported size + image
file path, per [TMDb image documentation](https://developer.themoviedb.org/docs/image-basics).
The Worker supplies configuration/paths; the clients load image bytes from the CDN.
The local preview's `/artwork/` URL serves only generated abstract illustrations.
Those are not production fallbacks or actual posters/portraits for the demo titles.

## Repeatable checks

From the Apple repository:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SmartMovieKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict --no-cache
```

From the Android repository's `multiplatform` directory:

```sh
python3 -B -m unittest discover -s tools -p 'test_*.py' -v
python3 -B tools/preview_server.py
```

Open `http://127.0.0.1:8099/?preview=1` after building the Wasm distribution.
For an unsigned local Apple build, pass `CATALOG_BASE_URL=http://127.0.0.1:8099/`
to `xcodebuild`. Never submit a candidate configured against localhost.

Verification: 71 Swift tests passed (including four artwork tests), strict SwiftLint
reported zero violations in 70 files, and three local preview HTTP tests passed.
Preview tests verify complete PNG responses for all advertised sizes, nested
artwork paths, missing-image 404 and account 401; they do not prove production
image delivery. Native Android/TV/Wear image rendering is not revalidated by these tests.

## Production completion checklist

- [ ] Release owner resolves staging/production Worker DNS and TLS.
- [ ] Worker has its server-side TMDb credential and returns usable image configuration.
- [ ] Capture a non-null image path from a real catalog response and request the exact client URL; expect image content, not HTML/JSON.
- [ ] Verify visible poster/backdrop/profile/gallery/provider images on Apple, native Android and KMP; test loading, missing, failed and offline states.
- [ ] Recapture store/gallery images with provenance; do not label preview captures as live TMDb results.

Do not put TMDb credentials into clients, query strings, screenshots, fixtures or
diagnostic logs to work around the infrastructure blocker.
