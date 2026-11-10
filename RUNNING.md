# Running the VirtuWatch integration tests

The tests run the real app services against the Firebase Emulator Suite
(Auth + Firestore, using your real `firestore.rules`). Nothing touches your
live Firebase project.

## One-time setup

1. Install JDK 21 or newer (needed by the Firestore emulator):
       winget install EclipseAdoptium.Temurin.21.JDK
   Open a new terminal afterwards, then check with:  java -version
2. Install the Firebase CLI:
       npm install -g firebase-tools
3. Copy these files into your project (keep the paths):
       integration_test/                (all test files + support/emulator.dart)
       android/app/src/debug/AndroidManifest.xml
4. Add the `integration_test` package. In pubspec.yaml, under dev_dependencies:
       dev_dependencies:
         flutter_test:
           sdk: flutter
         integration_test:
           sdk: flutter
   then run:  flutter pub get
5. Add an "emulators" block to firebase.json, next to the existing
   "firestore" block (mind the commas):
       "firestore": {
         "rules": "firestore.rules"
       },
       "emulators": {
         "auth":      { "host": "127.0.0.1", "port": 9099 },
         "firestore": { "host": "127.0.0.1", "port": 8080 },
         "ui":        { "enabled": true, "port": 4000 },
         "singleProjectMode": true
       },
6. Apply the one-line test hook in lib/services/chat_service.dart (see
   chat_service.patch.diff): add this just under `get history`:
       @visibleForTesting
       String get systemPromptForTesting => _buildSystemPrompt();

## Every time you run the tests

Terminal 1 (leave it running):
    firebase emulators:start --only auth,firestore --project virtuwatch-711e4

Start your Android emulator, find its id with `flutter devices`, then in
terminal 2:
    flutter test integration_test/all_test.dart --reporter expanded -d emulator-5554

Run a single file instead, for example:
    flutter test integration_test/it07_engagement_test.dart --reporter expanded -d emulator-5554

The first run is slow because the app has to build. The emulator UI at
http://localhost:4000 shows the data the tests create (a good screenshot).

## Physical phone instead of an emulator

Pass your PC's LAN IP, and start the emulators with "host": "0.0.0.0":
    flutter test integration_test/all_test.dart -d <device> --dart-define=EMULATOR_HOST=192.168.1.20

## What is not automated

- IT-04 (hand tracking -> AR renderer): needs the camera and GPU. Keep the
  screenshots / logcat evidence.
- The Cloudinary upload itself, and the live Gemini reply. Their outputs are
  checked manually; everything after them is covered here.

## Known-issue tests (IT-10)

`it10_known_issues_test.dart` describes the correct behavior for two
suspected problems (a merchant deleting a watch customers saved, and a
customer creating a watch listing). They fail while the problem exists and
pass once it is fixed, so they are NOT part of all_test.dart. Run them alone:

    flutter test integration_test/it10_known_issues_test.dart --reporter expanded -d emulator-5554

The "CONTROL" tests in that file should pass either way.
