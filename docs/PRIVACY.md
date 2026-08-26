# SmartMovie privacy policy

Last updated: 25 August 2026

SmartMovie is an advertising-free movie and television catalog. It does not create a separate SmartMovie identity, sell personal information, run third-party analytics, or collect payment information. Users may optionally connect an existing TMDb account through TMDb's browser approval page.

## Data processed

- **Catalog requests:** Home, Explore, Search, entity, and detail requests go to the SmartMovie Cloudflare Worker, which forwards only allowlisted values to TMDb. Public responses may be cached by locale, region, and adult flag. Application code does not log search text.
- **Rate limiting:** Cloudflare rate limiting and a privacy-preserving network identity protect the service. A random installation identifier is used as a fallback. Application code does not persist raw network identifiers in logs.
- **TMDb authorization:** SmartMovie opens a TMDb-controlled browser page and never receives the user's TMDb password. The Worker temporarily stores authorization attempts in Cloudflare D1. Return URIs are allowlisted and attempts expire.
- **Session broker:** Native clients receive an opaque SmartMovie session token; Web uses a `Secure`, `HttpOnly`, `SameSite` cookie plus CSRF protection. D1 stores only the SmartMovie token hash and encrypted TMDb access/session tokens. Sessions expire after 90 days without activity and are revoked on logout.
- **Account content:** The Worker does not store Favorites, Watchlist, ratings, recommendations, or custom-list contents. Those values remain at TMDb and in local client databases/caches.
- **Catalog change refresh:** The Worker stores non-personal TMDb Movie/TV/Person entity IDs, UTC-date cache revisions, and pagination cursors in D1 so changed catalog entries stop using an older cache key. It does not expose this operational data through an app route.
- **Offline library and outbox:** Apple apps use SwiftData/private CloudKit where configured; Android uses Room/local backup; desktop and web use their platform key-value store. Pending mutations include entity/list identifiers and requested state but never credentials.
- **Adult-content PIN:** The six-digit PIN and lockout state stay on the individual device. The PIN is not sent to the Worker, TMDb, CloudKit, or another SmartMovie client.
- **Artwork and trailers:** Images load from TMDb's CDN. Opening a trailer sends its YouTube identifier to YouTube or the system browser.
- **Availability:** Provider data comes from JustWatch through TMDb. SmartMovie opens only the availability URL supplied by TMDb.
- **Watch/Wear companions:** Safe active-title or exact-episode context and remote commands travel between paired devices. Adult titles and independent account sessions are excluded.

## Service providers

SmartMovie uses Cloudflare for API delivery, caching, rate limiting, D1, and encrypted session brokering; TMDb for catalog and optional account services; JustWatch through TMDb for provider availability; YouTube for trailers; and platform storage providers such as Apple iCloud/private CloudKit or Google backup when enabled by the user.

Each provider receives the technical network information required to deliver its service and operates under its own privacy terms.

## Retention and control

- Public catalog cache durations range from five minutes to 24 hours by route.
- Authorization attempts are short-lived and cleaned after expiry.
- SmartMovie broker sessions expire after 90 days without activity. Logout revokes upstream authorization where supported and removes the D1 session record.
- Mutation-idempotency records are operational replay protection and contain normalized response metadata, not credentials or user list contents.
- Catalog entity revisions older than 30 days are removed; change cursors retain only kind, UTC date, next page, and update time.
- Users can remove local library items, ratings, and lists in the app. At logout they choose whether to keep the library as local data or remove account-linked data from that device.
- Deleting the app removes local data subject to the platform's backup/synchronization controls. TMDb account data must also be managed at TMDb.

## Children and sensitive data

Adult content is disabled by default and requires local confirmation plus a six-digit PIN. This application-level control is not a replacement for operating-system parental controls, especially on Web. Adult content is excluded from Watch/Wear, public screenshots, notifications, and store preview metadata.

Search and list text should not be used to submit personal, confidential, or sensitive information.

## Contact and publication status

Before store submission, the release owner must replace this paragraph with a public support email or website and publish the same policy at the privacy URL used by App Store Connect and Google Play.

This product uses the TMDB API but is not endorsed or certified by TMDB. Availability data is supplied by JustWatch through TMDb.
