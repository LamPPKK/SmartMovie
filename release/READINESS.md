# SmartMovie 2.0 release readiness

## Automated source gates

- Canonical OpenAPI and fixtures validate against all six Worker routes and normalized errors.
- Apple and Android release manifests pin product version `2.0.0` and catalog contract `1.0.0`.
- Android native and desktop/web clients consume the same vendored contract snapshot.
- Production Worker deployment checks Android `main` for the same OpenAPI checksum, fixture checksum, contract version, and release train.
- Staging and production serialize deployments, isolate Cache API entries by Worker version, validate live JSON from one version against the canonical schemas, and automatically roll back a successful deploy if smoke validation fails.
- Main and Wear release workflows verify their AABs use the same signing certificate.

## Release-owner actions

The following require external accounts, protected credentials, approved artwork, or store ownership and are intentionally not stored in source control:

- Create or activate DNS/TLS for `staging-catalog.smartmovie.app` and `catalog.smartmovie.app`. Both hostnames returned DNS resolution failures during the read-only check on 17 August 2026.
- Revoke any historical TMDb credential and set the replacement `TMDB_BEARER_TOKEN` in protected Cloudflare staging and production environments.
- Set `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and the least-privilege `ANDROID_CONTRACT_SYNC_TOKEN` repository secret.
- Configure Apple signing, App Store Connect records, and the production CloudKit schema.
- Supply approved TMDb attribution artwork, tvOS Top Shelf assets, final platform icons, privacy/support URLs, metadata, and screenshots.
- Set Android signing secrets, confirm Play App Signing, and upload the main and Wear AABs to the same listing.
- Provide notarization/signing identities before distributing desktop packages.
- Merge the canonical contract first, then merge the generated Android sync PR so `catalog-contract/manifest.json` records the real upstream commit instead of the local bootstrap marker.

Follow `docs/RELEASE_RUNBOOK.md` in order. Do not bypass the Android checksum gate or place production credentials in app builds to work around an external blocker.
