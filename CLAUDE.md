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
npm run test:emulator   # Rules + roles + policies + wallet — needs the Firestore emulator
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
- `lib/screens/` — client and driver screens
- `lib/screens/admin/` — admin-only screens (orders, drivers, zones + pricing, coupons, contracts, policies, analytics, e-invoice log, fleet radar, broadcast)
- `lib/utils/` — pure helpers shared by screens and tests (`day_capacity.dart`, `terrain_surcharge.dart`, `home_packages.dart`, `phone_format.dart`, …)
- `lib/services/` — all business logic and integrations (see below)
- `lib/providers/` — UserProvider, ConfigProvider, OrderProvider
- `lib/widgets/` — reusable UI components

`ZyiarahFirebaseService` (`lib/services/firebase_service.dart`) is a factory singleton — call it as `ZyiarahFirebaseService()`, **not** `.instance` (`_instance` is private; there is no `.instance` getter, so code written against one will not compile). Its scope is **auth and account provisioning**, not Firestore access: sign-up/sign-in (email and phone-as-email), password reset/update, OTP, `signOut`, `getUserRole`, `saveUserToRegistry`, worker-photo upload, and `createAccountViaAdmin` / `createDriverAccountViaAdmin`.

It is **not** a Firestore gateway, and describing it as one misleads: 15 of 139 files under `lib/` import it, while 72 call `FirebaseFirestore.instance` directly and 57 of 69 screens import `cloud_firestore` themselves. Screens query Firestore directly by design here — so a cross-cutting concern (caching, retry, logging, App Check) has no single chokepoint to land in, and adding one means touching those 72 files. Weigh that before assuming a central hook exists. Firestore offline persistence is enabled with unlimited cache.

### Key Services (`lib/services/`)

| Service | Responsibility |
|---|---|
| `firebase_service.dart` | Auth (email + phone-as-email, OTP, password reset) and admin account provisioning — **not** general Firestore CRUD |
| `order_service.dart` | Order lifecycle + dispatch Cloud Function calls |
| `notification_service.dart` + `zyiarah_messaging_service.dart` | FCM push + in-app notifications |
| `moyasar_service.dart` | Primary payment gateway (Moyasar: cards, STC Pay, Apple Pay) |
| `tamara_service.dart` | Installment payments (BNPL — Tamara only) |
| `zyiarah_wallet_service.dart` | Wallet (read-only client-side; writes via Cloud Functions) |
| `zatca_service.dart` | Saudi ZATCA tax compliance (QR) |
| `zyiarah_pdf_service.dart` | PDF invoices & contracts |
| `deep_link_service.dart` | Deep linking / app_links |
| `location_service.dart` + `geofence_service.dart` | Location tracking (100m driver geofence) |
| `audit_service.dart` | Admin audit trail |

Capacity is **not** a service: it lives in `lib/utils/day_capacity.dart` (`dayIsFull`) and `functions/capacity.js`. A `lib/services/zyiarah_capacity_service.dart` file exists but nothing imports it — dead code, listed here only so it is not mistaken for the live path. Four other files are dead the same way: `lib/models/order_model.dart` (`ZyiarahOrder` — the typed order model, unused; orders travel between screens as raw `Map<String, dynamic>`), `lib/screens/account_activation_screen.dart`, `lib/utils/app_error_handler.dart`, `lib/widgets/permission_sheet.dart`.

### Admin Web Panel (`admin_panel/`)

React 19 + TypeScript (Vite), Tailwind CSS, MapBox GL for map views. Connects to the same Firebase backend. Deployed to Firebase Hosting under the `admin` target.

### Firebase Backend (`functions/index.js`)

Node.js v22 Cloud Functions — **62 exported functions in one 6,280-line `index.js`** (21 `onCall`, 17 `onDocumentUpdated`, 8 `onDocumentCreated`, 8 `onSchedule`, 4 `onDocumentWritten`, 3 `onRequest`, 1 `onTaskDispatched`). Only three logic modules are extracted — `pricing.js`, `capacity.js`, `notify_prefs.js` (the other root `.js` files are standalone diagnostics and eslint config) — so expect every backend change to touch `index.js` and to conflict there. Handling:
- FCM push notifications (Firestore triggers: orders, tickets, contracts, dispatch)
- Email via Resend (through the `notification_triggers` queue — anti-relay guarded)
- Payment webhooks & operations: Moyasar (primary; webhook + verify/refund/void/capture), Tamara — all HMAC-verified and idempotent; a Tabby webhook/refund pair is kept only for orders paid before Tabby was removed from the app (2026-09-30)
- Wallet operations (`payWithWallet`, `redeemQatratPoints`, `onOrderRewards`) — all wallet writes are server-side only
- Direct Dispatch engine (driver assignment, slot availability, surge pricing)
- Account deletion processing (Apple requirement)

All callable functions require authentication; sensitive ones also verify ownership or admin role (`_assertAdmin`). Secrets are managed via `defineSecret` / Secret Manager — never hardcode keys.

## CI/CD

Codemagic (`codemagic.yaml`) handles iOS releases — triggered on every push to `main` through the GitHub→Codemagic webhook created on 2026-09-13 (before that date every build was started by hand; see the webhook note below):
1. Sets up signing from the "Zyiarah Key" integration + `appstore_credentials` group (App Store Connect API key)
2. Injects payment/Mapbox keys from the `payment_keys` group into `.env` at build time
3. Runs `flutter pub get` + `pod install`, builds IPA with auto-incremented build number
4. Publishes to **TestFlight**, then submits the build to **App Store review** automatically
   (`submit_to_app_store: true` since 2026-09-21 — owner decision; before that the public
   release was a manual click). Revert by setting it back to `false`. **The submission needs
   "What's New"**: from 2026-09-21 to 2026-09-30 every automatic submission stalled silently
   at `PREPARE_FOR_SUBMISSION` because the `ar-SA` field was empty (1.2.46 stayed live while
   every merge reached TestFlight only; 1.2.47 and 1.2.48 were submitted by hand). The 09-28
   attempt — exporting `APP_STORE_CONNECT_WHATS_NEW` through `$CM_ENV` — never worked:
   Codemagic runs `submit_to_app_store` in **post-processing**, after the build machine is
   released, so CM_ENV variables never reach it, and a failed submission there does not fail
   the build (#238 was green with 1.2.48 unsubmitted). Since 2026-09-30 the
   `Write release_notes.json` step generates `release_notes.json` (Codemagic's documented
   channel for "What's New", locale `ar-SA`, gitignored) at the repo root from
   `.github/whatsnew/whatsnew-ar`, with `cancel_previous_submissions: true` and
   `release_type: AFTER_APPROVAL`. **Edit that file with every version bump**;
   `test/ios_auto_submit_guard_test.dart` pins the wiring. `cancel_previous_submissions`
   also cancels a submission that is `WAITING_FOR_REVIEW` or `IN_REVIEW`, so a push to
   `main` while Apple is reviewing restarts the review with the new build — hold merges
   until the review completes (or squash-merge with the skip-ci marker). To check
   the real state from the terminal (the dashboard only shows the upload), query App Store
   Connect's `appStoreVersions` / `reviewSubmissions` with the API key — a `READY_FOR_REVIEW`
   submission with no `submittedDate` means "created, never submitted".

Any `AuthKey_*.p8` file at root is an App Store Connect API key — gitignored; never commit or expose it. Add `[skip ci]` to commit messages that shouldn't trigger a build (docs, rules-only changes) — note this skips **both** Codemagic builds (iOS and Android) **and all five GitHub Actions CI jobs**, because Actions honours the same marker natively. A PR whose head commit carries it shows *zero* checks, not green ones. So don't put it on a PR commit you still want guarded: leave the PR commits clean and put the marker in the **squash-merge message** instead — that skips the release build while the PR's own checks still ran.

The match is purely textual and has no notion of quoting or intent: a commit message that merely *mentions* the bracketed marker — documenting it, or quoting it in a subject line — is skipped exactly like one that means it. (This paragraph exists because the commit that first documented the behaviour was silenced by the marker in its own title.) To write about it in a commit message, drop the brackets: bare `skip ci` matches nothing. The full set Actions recognises is `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]` — all bracketed, all case-insensitive.

The Android workflow (`android-release`) mirrors iOS: it declares the same push-to-`main` trigger, builds a signed AAB **and** a tester APK with the same `versionCode`, and publishes to **two** places. (1) Google Play **closed testing** track (`track: alpha` since 2026-09-28 — owner decision). Play requires a personal account to have **12 testers opted in to closed testing for 14 consecutive days** before granting production access, and only installs *from Play* via the opt-in link count; `track: production` (set 2026-09-21) predated that grant, and publishing to an ungranted track fails at the Publishing step. Once access is granted, set `track` back to `production` **and** update `test/app_distribution_guard_test.dart`, which pins `alpha` deliberately. (2) **Firebase App Distribution** — the APK goes to the App Distribution group `testers` (`publishing.firebase`, `artifact_type: 'apk'`; AAB would need the Firebase↔Play link, which isn't set up). This is a second tester channel for people without Play or for quick feedback — it does **not** count toward the 12-tester rule. Both publish through the `google_play` variable group in Codemagic (`GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`): the same `play-publisher` service account, granted `Firebase App Distribution Admin` on `zyiarah-app` on 2026-09-28. The Play credential was verified by build #30 (2026-08-31). Android signing uses `android/key.properties` (gitignored) in local builds and the `android_credentials` group in CI. **The first production release will need one manual promotion:** the API uploads the bundle fine but `tracks.update` returns `Precondition check failed` until the app has shipped to production once — hit on build #53 and documented under "فشل خطوة النشر" in `production_deployment_guide.md`, which also records that a `500` from Apple's ContentDelivery during an iOS publish means the upload already succeeded (check TestFlight before re-running, and never blame the build-number logic).

**Automatic triggering depends on the GitHub→Codemagic webhook, which exists only since 2026-09-13.** Both workflows declare `triggering` (iOS since 2026-07-25, Android since 2026-09-13), but Codemagic learns about a push only through that webhook, and until 2026-09-13 21:25 (+03) none existed: Codemagic's *Recent deliveries* read "No deliveries yet", five clean pushes after the last recorded build (#30 / #208 on `4f33ce9`, 2026-08-31) produced zero builds, and build #30 reads `Started by: erihdev@gmail.com`. It was created from Codemagic → app settings → Webhooks (*Update webhook*); GitHub's ping was accepted (202, "Your builds will be started on branch and tag push"). The first push after it is the merge of this very paragraph — its builds in the Builds list, with no manual starter, are the proof. If builds ever stop appearing again, check *Recent deliveries* there first; until they resume, start builds by hand in the dashboard.

Two other Android paths exist and do **not** reach Google Play: `.github/workflows/android_release.yml` builds an AAB on `v*` tags without publishing, and `distribute_android.bat` builds an APK locally and uploads it to the same App Distribution group `testers` (fixed 2026-09-28 — it had silently targeted the retired `com.zyiarah.app` Firebase app, read a `testers.txt` that never existed, and passed `--clean`, which `flutter build` doesn't accept; `test/app_distribution_guard_test.dart` keeps its App ID and group in lockstep with `codemagic.yaml`).

## Environment & Config

- `.env` — Mapbox token + publishable payment keys (Moyasar pk, Samsung Pay service ID), loaded via `flutter_dotenv` and bundled as an app asset — publishable keys only, never secrets
- `.env.automation` — Additional automation env vars
- `firebase.json` — Firebase project config (Firestore, hosting, functions)
- `firestore.rules` — Database security rules
- `android/key.properties` — Android keystore signing credentials

## Important Patterns

- **Auth service**: reach auth and account provisioning through `ZyiarahFirebaseService()` — the factory call, never `.instance` (it does not exist). Firestore reads/writes are made directly from screens via `FirebaseFirestore.instance`; there is no service layer in front of them (see the note under *Flutter App* above)
- **Role checks**: User role is stored in Firestore and accessed via `UserProvider`; always verify role before rendering admin-only UI
- **Arabic support**: plain `Text()` is **correct** for Arabic in the UI — Flutter shapes and bidi-orders Arabic natively, and there are ~528 such literals across `lib/`. Do **not** pass UI strings through `arabic_reshaper`: pre-shaping text Flutter will shape again garbles it. `arabic_reshaper` is needed in exactly one place — `zyiarah_pdf_service.dart`, because the `pdf` package draws glyphs without shaping them; that file wraps it in a single static helper `_ar()`, so every Arabic string in a PDF goes through that one call. `bidi` is declared in `pubspec.yaml` but imported nowhere in our code (the `pdf` package pulls it in itself)
- **PDF generation**: Use existing service classes in `lib/services/`; they depend on the `pdf` and `printing` packages
- **Payments**: Moyasar is primary (cards, STC Pay, Apple Pay); Tamara handles installments — Tabby was removed at the root on 2026-09-30 (owner uses Tamara only; `test/no_tabby_test.dart` guards it, and legacy Tabby orders stay displayable and refundable); wallet is supported. Cash on delivery was removed at the root by owner decision — `test/no_cod_test.dart` guards it; never reintroduce it. All paid orders get a ZATCA invoice
- **Pricing is server-verified**: the client shows prices, but `functions/pricing.js` recomputes the base from the zone document (per-service rates, optional `terrain_surcharge_percent`) on every Moyasar/wallet payment and flags underpayment. `PriceBreakdown` (`lib/utils/terrain_surcharge.dart`) is the single client formula: base + terrain + surge − discount = net, + 15% VAT = total; fixed-price contracts skip all three
- **Capacity**: drivers have no zones; capacity is one global daily cap plus the active-driver count, optionally tightened by a zone's `max_orders_per_day`. Every consumer of `getHourlyAvailability` decides day fullness through `dayIsFull` (`lib/utils/day_capacity.dart`). Home cleaning is day-only (no arrival slot for the client)
- **Firestore queries**: do not add composite indexes casually — range/orderBy on one field and filter locally (see `firestore.indexes.json` for what exists)
- **Notifications**: operational pushes go through `notification_triggers`; admin broadcasts (`notifications_log`) are marketing unless `operational: true`, and skip users with `notification_prefs.marketing == false`
- **Testability**: models and helpers are pure; screens accept injectable streams/loaders/callbacks (`items`, `loader`, `clock`, `tileLayer`, …) so widget tests run without Firebase. Source-guard tests (`File(...).readAsStringSync()`) pin owner decisions — read the guard before changing what it protects
- **Wallet integrity**: never write to `wallets/*` from the client — Firestore rules block it; all balance changes go through Cloud Functions
- **App Check — sending, not enforcing (yet)**: `main.dart` activates App Check (Play Integrity on Android; App Attest with DeviceCheck fallback on Apple, skipped on web for lack of a reCAPTCHA site key), so clients now *send* attestation tokens. **Nothing verifies them**: there is no `enforceAppCheck` in `functions/index.js` and no enforcement in the Firebase Console — and turning either on today is a **service outage, not a hardening**, because the public release 1.2.46 does not carry the package at all, so every request from every current user would be rejected. The gate is: a version carrying App Check has rolled out and the Console's App Check metrics show verified requests near 100%. Two caveats to settle **before** enforcing: `ios/Runner/AppDelegate.swift` calls `FirebaseApp.configure()`, which makes iOS silently fall back to DeviceCheck instead of App Attest ([flutterfire#18613](https://github.com/firebase/flutterfire/issues/18613)); and the React admin panel has no App Check, so enforcing on Firestore breaks it too. `test/app_check_guard_test.dart` pins both halves — that tokens are sent, and that enforcement is still off; if it fails because someone enabled enforcement, the question is whether the rollout gate was met, not how to silence the test. Procedure in `production_deployment_guide.md`
