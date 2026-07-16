# Story Time Universe (iOS)

Native SwiftUI viewer app for [Story Time](https://story-time.online).

## Viewer flow

1. **Sign in** with a viewer account (`credentials-viewer` via NextAuth).
2. Every launch after auth opens **Choose your profile** (profile is not auto-restored).
3. Select a profile (PIN supported) → Home / Search / My List / Account.
4. **Play** uses `/api/content/:id/playback-bundle` (HLS) and locks to **landscape**.
5. **Renew / Pay / Change plan** open Safari to the web app — no in-app payments.

## API surface used

| Area | Endpoints |
|------|-----------|
| Auth | `GET /api/auth/csrf`, `POST /api/auth/callback/credentials-viewer`, `GET /api/auth/session`, `POST /api/auth/signout` |
| Profiles | `GET/POST /api/viewer/profiles`, `POST /api/viewer/profiles/active` |
| Catalogue | `GET /api/content`, `GET /api/content/:id`, `GET /api/browse/search` |
| Playback | `GET /api/content/:id/playback-bundle`, `GET/PUT /api/watch/progress`, `POST /api/watch`, `GET /api/watch/continue-watching` |
| My List | `GET/POST /api/watchlist` |
| Subscription status | `GET /api/viewer/subscription` (read-only; checkout stays on web) |

## Open in Xcode

Open `Story Time Universe IOS.xcodeproj`, select an iPhone simulator or device, and Run.

Demo viewer (production seed, if enabled): `viewer@storytime.com` — see production `DEMO_ACCOUNTS.md`.
