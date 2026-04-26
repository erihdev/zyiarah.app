# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zyiarah is a Flutter-based service booking platform (cleaning services) targeting iOS and Android. It includes a React/TypeScript admin web panel and a Firebase Cloud Functions backend. The app supports three user roles: **client**, **driver**, and **admin** (sub-types: super_admin, orders_manager, accountant_admin, marketing_admin).

- **Bundle ID**: com.zyiarah.zyiarah (iOS App Store ID: 6760955777)
- **Version**: 1.2.0+25
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
```

### Firebase Functions (`functions/`)
```bash
npm run serve    # Local emulator
npm run deploy   # Deploy functions
npm run logs     # Tail logs
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
| `order_service.dart` | Order lifecycle management |
| `notification_service.dart` | Firebase Cloud Messaging |
| `edfapay_service.dart` | Primary payment gateway (EDFAPAY) |
| `tamara_service.dart` | Installment payments |
| `zatca_service.dart` | Saudi ZATCA tax compliance |
| `invoice_pdf_service.dart` | PDF invoice generation |
| `zyiarah_contract_pdf_service.dart` | Digital contract PDF generation |
| `deep_link_service.dart` | Deep linking / app_links |
| `location_service.dart` + `geofence_service.dart` | Location tracking |
| `audit_service.dart` | Admin audit trail |
| `n8n_automation_service.dart` | N8N workflow automation |

### Admin Web Panel (`admin_panel/`)

React 19 + TypeScript (Vite), Tailwind CSS, MapBox GL for map views. Connects to the same Firebase backend. Deployed to Firebase Hosting under the `admin` target.

### Firebase Backend (`functions/index.js`)

Node.js v22 Cloud Functions handling:
- Support ticket push notifications
- Email via Resend
- Firestore document triggers
- A/B testing optimization engine

## CI/CD

Codemagic (`codemagic.yaml`) handles iOS App Store releases:
1. Sets up signing from `appstore_credentials` group (App Store Connect API key)
2. Runs `flutter pub get` + `pod install`
3. Builds IPA with `flutter build ipa --release`
4. Publishes directly to the App Store (not TestFlight)

The `AuthKey_RJMPC4734X.p8` file at root is the App Store Connect API key — do not commit or expose it.

Android signing uses `android/key.properties` (gitignored). Distribution can be triggered locally via `distribute_android.bat`.

## Environment & Config

- `.env` — Mapbox token and Firebase config (loaded via `flutter_dotenv`)
- `.env.automation` — Additional automation env vars
- `firebase.json` — Firebase project config (Firestore, hosting, functions)
- `firestore.rules` — Database security rules
- `android/key.properties` — Android keystore signing credentials

## Important Patterns

- **Singleton service**: Always access Firebase/Firestore via `ZyiarahFirebaseService.instance`
- **Role checks**: User role is stored in Firestore and accessed via `UserProvider`; always verify role before rendering admin-only UI
- **Arabic support**: Use `arabic_reshaper` + `bidi` for any Arabic text rendering — do not use plain `Text()` for Arabic strings
- **PDF generation**: Use existing service classes in `lib/services/`; they depend on the `pdf` and `printing` packages
- **Payments**: EDFAPAY is primary; Tamara handles installments; both are integrated with ZATCA for tax receipts
