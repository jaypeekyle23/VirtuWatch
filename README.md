# VirtuWatch

AI-assisted virtual watch try-on and fit-recommendation app, built for Shoe Rock Philippines. Customers can try watches on in AR, get a wrist measurement without a camera, and receive AI-scored recommendations based on fit, color, and style — with a Gemini-backed chat assistant to help them decide.

## Features

### Customer
- **AR try-on** — live, markerless AR watch try-on using on-device hand-landmark tracking (no ARCore/ARKit dependency, so it works without an ARCore-certified device).
- **Wrist measurement, no camera** — a direct on-screen comparison: rest your wrist above/below the phone, line it up against a fixed reference line, and adjust a second line (via tap/hold step buttons or an optional drag slider) until it matches your wrist's edge. Requires a one-time per-device screen calibration against a real card or a ₱20 coin, since phones can't be trusted to self-report their screen density accurately. Manual entry is always available as a fallback.
- **Outfit color scanning** — scans an outfit photo to extract dominant colors for style-matched recommendations.
- **AI-scored recommendations** ("For You") — watches ranked by a weighted blend of Fit (50%, wrist width vs. lug-to-lug), Color (30%, outfit vs. watch color), and Style (20%, category match). Missing signals are excluded and remaining weights rebalanced rather than penalizing an incomplete profile. Budget range is tracked separately as a hard affordability label, not part of the score.
- **Chat assistant** — a Gemini-backed assistant, scoped to either a single watch or the customer's recommendation list, grounded with the same fit/score data shown in the UI so it can't contradict what's on screen.
- Saved/wishlist watches, style preferences, profile management.

### Merchant
- Add/edit watch listings (with images via Cloudinary), catalog management, sales analytics, profile.

### Admin
- Account management, catalog moderation, dashboard.

## Tech Stack

- **Flutter** (mobile targets; also builds for web/desktop)
- **Firebase** — Authentication and Firestore (data is read/written as raw `Map<String, dynamic>`; there's no separate model layer)
- **Google Gemini** — powers the in-app chat assistant
- **MediaPipe (`hand_landmarker`)** — on-device hand tracking for AR try-on
- **Cloudinary** — merchant-uploaded watch image hosting

## Getting Started

### Prerequisites
- Flutter SDK (Dart `^3.11.0` per `pubspec.yaml`)
- A Firebase project with Authentication and Firestore enabled, and `google-services.json` placed under `android/app/`
- A Gemini API key

### Setup
1. Clone the repo and run `flutter pub get`.
2. Copy `env.example` to `.env` and fill in `GEMINI_API_KEY`.
3. Run with the env file loaded, e.g.:
   ```
   flutter run --dart-define-from-file=.env
   ```

### Building a release APK
```
flutter build apk --release --dart-define-from-file=.env
```
`--dart-define-from-file=.env` is required — without it, the chat assistant builds fine but silently has no API key at runtime.

> **Note:** the release build type in `android/app/build.gradle` is currently signed with the debug keystore (the default Flutter template setup, never replaced with a real release signing config). Fine for local installs and demos; a proper signing config is needed before any wider distribution.

## Project Structure

```
lib/
  screens/
    customer/   # catalog, AR try-on, wrist measurement, outfit scan, recommendations, profile
    merchant/   # listings, analytics, profile
    admin/      # account management, catalog moderation, dashboard
  services/     # business logic — recommendation scoring, AR anchoring, chat, auth, etc.
  widgets/      # shared UI (e.g. EdgeMatchGuide, OffsetStepperControl — used by both the
                # wrist measurement and screen calibration screens)
  constants/    # app_knowledge.dart (grounds the chat assistant), watch_colors.dart
  theme/        # app-wide styling
```

## Known Limitations

- No automated test coverage beyond the default Flutter scaffold test.
- AR/hand-tracking package versions are unpinned — the underlying MediaPipe bindings can change API between versions.
- Release APKs are debug-signed (see build note above).