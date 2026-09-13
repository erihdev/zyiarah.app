# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zyiarah is a Flutter-based service booking platform (cleaning services) targeting iOS and Android. It includes a React/TypeScript admin web panel and a Firebase Cloud Functions backend. The app supports three user roles: **client**, **driver**, and **admin** (sub-types: super_admin, orders_manager, accountant_admin, marketing_admin).

- **Bundle ID**: com.zyiarah.zyiarah (iOS App Store ID: 6760955777)
- **Version**: see `pubspec.yaml` (`version:` line — build number auto-increments in CI)
- **Firebase Project**: zyiarah-app

## Commands

### Flutter App
```bash
flutter pub get              # Install dependencies
flutter analyze              # Lint (configured via analysis_options.yaml)
flutter test                 # Run unit tests
flutter build ipa --release  # iOS release build
flutter build apk --release  # Android release build
flutter build web            # Web build
cd ios && pod install         # Sync iOS CocoaPods after pubspec changes
```

### Admin Panel (`admin_panel/`)
```bash
npm run dev      # Dev server
npm run build    # Production build (tsc + vite)
npm run lint     # ESLint
npm test         # Vitest (role-gate tests)
```
`src/services/firebase.ts` is gitignored — create it locally (CI generates a placeholder) or the build fails.

### Firebase Functions (`functions/`)
```bash
npm run lint            # ESLint (flat config)
npm test                # Unit tests (pricing, notifications, email)
npm run test:emulator   # Rules + roles + wallet — needs the Firestore emulator
npm run serve           # Local emulator
npm run deploy          # Deploy functions
npm run logs            # Tail logs
```
Run the emulator suite from the repo root (that is where `firebase.json` lives), and note
`firebase-tools@15` requires **JDK 21+**:
```bash
npx firebase-tools@15 emulators:exec --only firestore --project demo-zyiarah-rules \
  'npm --prefix functions run test:emulator'
```

## Architecture

### Flutter App (`lib/`)

Entry point is `main.dart` (Firebase init + auth wrapper). Navigation is handled by `router.dart` using **GoRouter** with deep link support. State management uses **Provider** (`ChangeNotifierProvider`).

Key directories:
- `lib/models/` — data models (User, Order, Service)
- `lib/screens/` — client-facing screens
- `lib/admin/` — admin-only screens (drivers, orders, coupons, contracts, analytics)
- `lib/services/` — all business logic and integrations (see below)
- `lib/providers/` — UserProvider, ConfigProvider, OrderProvider
- `lib/widgets/` — reusable UI components

`ZyiarahFirebaseService` is a singleton (`lib/services/firebase_service.dart`) and the central access point for Firestore, Auth, and user management. Most screens go through this service. Firestore offline persistence is enabled with unlimited cache.

### Key Services (`lib/services/`)

| Service | Responsibility |
|---|---|
| `firebase_service.dart` | Auth, Firestore CRUD, user management |
| `order_service.dart` | Order lifecycle + dispatch Cloud Function calls |
| `notification_service.dart` + `zyiarah_messaging_service.dart` | FCM push + in-app notifications |
| `moyasar_service.dart` | Primary payment gateway (Moyasar: cards, STC Pay, Apple Pay) |
| `tamara_service.dart` + `tabby_service.dart` | Installment payments (BNPL) |
| `zyiarah_wallet_service.dart` | Wallet (read-only client-side; writes via Cloud Functions) |
| `zatca_service.dart` | Saudi ZATCA tax compliance (QR) |
| `zyiarah_pdf_service.dart` | PDF invoices & contracts |
| `deep_link_service.dart` | Deep linking / app_links |
| `location_service.dart` + `geofence_service.dart` | Location tracking (100m driver geofence) |
| `zyiarah_capacity_service.dart` | Booking capacity / slot availability |
| `audit_service.dart` | Admin audit trail |

### Admin Web Panel (`admin_panel/`)

React 19 + TypeScript (Vite), Tailwind CSS, MapBox GL for map views. Connects to the same Firebase backend. Deployed to Firebase Hosting under the `admin` target.

### Firebase Backend (`functions/index.js`)

Node.js v22 Cloud Functions (~37 functions) handling:
- FCM push notifications (Firestore triggers: orders, tickets, contracts, dispatch)
- Email via Resend (through the `notification_triggers` queue — anti-relay guarded)
- Payment webhooks & operations: Moyasar (primary; webhook + verify/refund/void/capture), Tamara, Tabby — all HMAC-verified and idempotent
- Wallet operations (`payWithWallet`, `redeemQatratPoints`, `onOrderRewards`) — all wallet writes are server-side only
- Direct Dispatch engine (driver assignment, slot availability, surge pricing)
- Account deletion processing (Apple requirement)

All callable functions require authentication; sensitive ones also verify ownership or admin role (`_assertAdmin`). Secrets are managed via `defineSecret` / Secret Manager — never hardcode keys.

## CI/CD

Codemagic (`codemagic.yaml`) handles iOS releases — triggered on every push to `main` through the GitHub→Codemagic webhook created on 2026-09-13 (before that date every build was started by hand; see the webhook note below):
1. Sets up signing from the "Zyiarah Key" integration + `appstore_credentials` group (App Store Connect API key)
2. Injects payment/Mapbox keys from the `payment_keys` group into `.env` at build time
3. Runs `flutter pub get` + `pod install`, builds IPA with auto-incremented build number
4. Publishes to **TestFlight** (public App Store release is manual)

Any `AuthKey_*.p8` file at root is an App Store Connect API key — gitignored; never commit or expose it. Add `[skip ci]` to commit messages that shouldn't trigger a build (docs, rules-only changes) — note this skips **both** Codemagic builds (iOS and Android) **and all five GitHub Actions CI jobs**, because Actions honours the same marker natively. A PR whose head commit carries it shows *zero* checks, not green ones. So don't put it on a PR commit you still want guarded: leave the PR commits clean and put the marker in the **squash-merge message** instead — that skips the release build while the PR's own checks still ran.

The match is purely textual and has no notion of quoting or intent: a commit message that merely *mentions* the bracketed marker — documenting it, or quoting it in a subject line — is skipped exactly like one that means it. (This paragraph exists because the commit that first documented the behaviour was silenced by the marker in its own title.) To write about it in a commit message, drop the brackets: bare `skip ci` matches nothing. The full set Actions recognises is `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]` — all bracketed, all case-insensitive.

The Android workflow (`android-release`) mirrors iOS: it declares the same push-to-`main` trigger, builds a signed AAB, and publishes to the Google Play **internal testing** track (public release stays manual). It publishes through the `google_play` variable group in Codemagic (`GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`) — already configured and verified: build #30 (2026-08-31) completed its Publishing step and uploaded to the internal track. Android signing uses `android/key.properties` (gitignored) in local builds and the `android_credentials` group in CI.

**Automatic triggering depends on the GitHub→Codemagic webhook, which exists only since 2026-09-13.** Both workflows declare `triggering` (iOS since 2026-07-25, Android since 2026-09-13), but Codemagic learns about a push only through that webhook, and until 2026-09-13 21:25 (+03) none existed: Codemagic's *Recent deliveries* read "No deliveries yet", five clean pushes after the last recorded build (#30 / #208 on `4f33ce9`, 2026-08-31) produced zero builds, and build #30 reads `Started by: erihdev@gmail.com`. It was created from Codemagic → app settings → Webhooks (*Update webhook*); GitHub's ping was accepted (202, "Your builds will be started on branch and tag push"). The first push after it is the merge of this very paragraph — its builds in the Builds list, with no manual starter, are the proof. If builds ever stop appearing again, check *Recent deliveries* there first; until they resume, start builds by hand in the dashboard.

Two other Android paths exist and do **not** reach Google Play: `.github/workflows/android_release.yml` builds an AAB on `v*` tags without publishing, and `distribute_android.bat` builds an APK for Firebase App Distribution (testers only).

## Environment & Config

- `.env` — Mapbox token + publishable payment keys (Moyasar pk, Tabby public, Samsung Pay service ID), loaded via `flutter_dotenv` and bundled as an app asset — publishable keys only, never secrets
- `.env.automation` — Additional automation env vars
- `firebase.json` — Firebase project config (Firestore, hosting, functions)
- `firestore.rules` — Database security rules
- `android/key.properties` — Android keystore signing credentials

## Important Patterns

- **Singleton service**: Always access Firebase/Firestore via `ZyiarahFirebaseService.instance`
- **Role checks**: User role is stored in Firestore and accessed via `UserProvider`; always verify role before rendering admin-only UI
- **Arabic support**: Use `arabic_reshaper` + `bidi` for any Arabic text rendering — do not use plain `Text()` for Arabic strings
- **PDF generation**: Use existing service classes in `lib/services/`; they depend on the `pdf` and `printing` packages
- **Payments**: Moyasar is primary (cards, STC Pay, Apple Pay); Tamara and Tabby handle installments; wallet and COD are also supported — all integrated with ZATCA for tax receipts
- **Wallet integrity**: never write to `wallets/*` from the client — Firestore rules block it; all balance changes go through Cloud Functions
