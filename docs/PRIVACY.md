# SmartMovie privacy policy

Last updated: 15 August 2026

SmartMovie is a free, advertising-free catalog app. It does not create a SmartMovie account and does not sell personal information.

## Data processed

- Catalog requests: Home, Explore, Search, and Detail requests are sent to the SmartMovie Cloudflare service, which forwards allowed fields to TMDb. Search text is needed to return results and may exist in Cloudflare's response cache for up to five minutes. Application logging is disabled and the Worker code does not log search text.
- Rate limiting: the Worker hashes network address information and uses the result only to enforce request limits. The app's random installation identifier is used as a fallback when edge network information is unavailable. Raw identifiers are not written by application code to logs.
- Library: Favorite and Watchlist metadata is stored locally with SwiftData. If the user enables iCloud, Apple stores and synchronizes it in the user's private CloudKit database.
- Artwork: poster, backdrop, and cast images load from TMDb's image CDN. TMDb and its infrastructure providers receive the network information required to serve those files.
- Trailers: opening a trailer sends the selected YouTube video identifier to YouTube or the system browser.

## Service providers

SmartMovie uses Apple iCloud/CloudKit for optional synchronization, Cloudflare for API proxying/caching/rate limiting, TMDb for movie and television metadata/artwork, and YouTube for trailers. Each provider may process technical network data under its own privacy terms.

## Retention and control

Catalog response cache durations range from five minutes to 24 hours depending on route. SmartMovie does not maintain a user profile on its Worker. Users can remove Favorite and Watchlist entries in the app. Local data is removed when the app and its data are deleted; synchronized data may remain in the user's iCloud account until removed there.

## Children and sensitive data

SmartMovie is not designed to collect sensitive personal information. Search text should not be used to submit personal or confidential information.

## Contact and changes

Before publication, the App Store listing must replace this paragraph with the developer's support email or website. Material changes will update the date and the public policy URL.

This product uses the TMDB API but is not endorsed or certified by TMDB.
