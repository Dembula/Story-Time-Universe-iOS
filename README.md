# Story Time Universe (iOS)

Native SwiftUI viewer app for [Story Time](https://story-time.online).

## Viewer flow

1. **Sign in / Sign up** natively (NextAuth credentials viewer).
2. **Subscribe with Apple** (StoreKit 2 In-App Purchase) — plans are never sold via web/PayFast inside the app (App Store Guideline 3.1.1).
3. Every launch after auth opens **Choose your profile** (profile is not auto-restored).
4. Select a profile (PIN supported) → Home / Search / My List / Account.
5. **Play** uses `/api/content/:id/playback-bundle` (HLS) and locks to **landscape**.
6. **Change plan / Reactivate / PPV unlock** use the App Store paywall.

## In-App Purchase product IDs

Create matching products in App Store Connect (subscription group + consumable):

| Product ID | Type | Plan |
|------------|------|------|
| `com.storytime.universe.sub.base.monthly` | Auto-renewable | BASE_1 |
| `com.storytime.universe.sub.standard.monthly` | Auto-renewable | STANDARD_3 |
| `com.storytime.universe.sub.family.monthly` | Auto-renewable | FAMILY_5 |
| `com.storytime.universe.sub.base.yearly` | Auto-renewable | BASE_1 |
| `com.storytime.universe.sub.standard.yearly` | Auto-renewable | STANDARD_3 |
| `com.storytime.universe.sub.family.yearly` | Auto-renewable | FAMILY_5 |
| `com.storytime.universe.ppv.unlock` | Consumable | Title unlock |

Local StoreKit testing file: `Configuration/Products.storekit`  
(Scheme → Run → Options → StoreKit Configuration).

### Backend required for production unlock

After a successful Apple purchase the app POSTs to (first 2xx wins):

- `POST /api/viewer/apple/activate` — body includes `productId`, `transactionId`, `originalTransactionId`, `signedTransactionInfo` (JWS), `environment`, `plan` / `planCode`, `platform: ios`
- `POST /api/viewer/apple/ppv` — same + `contentId`, `kind: ppv`

The web API must verify the JWS (App Store Server API), mark the viewer subscription/PPV access active, then `GET /api/viewer/subscription` returns that entitlement. Without this, Apple can charge but streaming may stay locked.

## API surface used

| Area | Endpoints |
|------|-----------|
| Auth | `GET /api/auth/csrf`, `POST /api/auth/callback/credentials-viewer`, `POST /api/auth/signup`, `GET /api/auth/session`, `POST /api/auth/signout` |
| Profiles | `GET/POST /api/viewer/profiles`, `POST /api/viewer/profiles/active` |
| Catalogue | `GET /api/content`, `GET /api/content/:id`, `GET /api/browse/search` |
| Playback | `GET /api/content/:id/playback-bundle`, `GET/PUT /api/watch/progress`, `POST /api/watch`, `GET /api/watch/continue-watching` |
| My List | `GET/POST /api/watchlist` |
| Subscription status | `GET /api/viewer/subscription` |
| Apple IAP activate | `POST /api/viewer/apple/activate`, `POST /api/viewer/apple/ppv` (and alias paths the client tries) |
| PPV ownership check | `POST /api/viewer/ppv` (iOS never opens returned web checkout URLs) |

## Open in Xcode

Open `Story Time Universe IOS.xcodeproj`, select an iPhone simulator or device, and Run.

Demo viewer (production seed, if enabled): `viewer@storytime.com` — see production `DEMO_ACCOUNTS.md`.
