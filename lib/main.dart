import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';
import 'services/update_checker_service.dart';

/// Lets the notification tap handler below show a SnackBar (e.g.
/// "Downloading update...") without needing a BuildContext of its own —
/// notification taps can arrive while the app has no screen-level
/// context ready yet (cold start, background).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved look first so the very first screen already uses it.
  await ThemeController.instance.load();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _activateAppCheck();
  await NotificationService.instance.init(onNotificationTap: _handleNotificationTap);
  runApp(const MyApp());
}

/// The chat assistant (Firebase AI Logic) only accepts requests that carry
/// an App Check token, so App Check must start right after Firebase does.
///
/// Debug builds use the debug provider. Its token is printed in the run
/// logs the first time, and must be added in the Firebase console under
/// App Check > Apps > Manage debug tokens. Release builds use Play
/// Integrity on Android. Web and desktop are skipped here.
Future<void> _activateAppCheck() async {
  if (kIsWeb) return;
  final platform = defaultTargetPlatform;
  final isAndroid = platform == TargetPlatform.android;
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  if (!isAndroid && !isApple) return;

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    );
  } catch (e) {
    // Chat will be rejected without a token, but the rest of the app
    // should still open.
    debugPrint('App Check could not start: $e');
  }
}

/// Routes a tapped notification's payload to whatever it should do.
/// Only the update-available notification needs real handling here —
/// it kicks off the APK download/install. The other payloads
/// (password_changed, verify_email, wishlist) just open the app to
/// wherever AuthGate already routes a signed-in user; there's no
/// separate screen for them to jump to yet.
void _handleNotificationTap(String payload) {
  if (payload.startsWith(NotificationService.payloadUpdatePrefix)) {
    final apkUrl = payload.substring(
      NotificationService.payloadUpdatePrefix.length,
    );
    _downloadUpdate(apkUrl);
  }
}

// Tracks the last progress percent shown, so the snackbar updates in
// visible 5% steps instead of rebuilding on every single chunk that
// arrives (which would be many times a second on a fast connection).
int? _lastShownPercent;

// Shown alongside every "still downloading" snackbar — nothing in the
// download runs as a background service, so leaving the app (locking
// the screen, switching away, swiping it closed) can still interrupt
// an in-progress download. Left off the final done/error message,
// since the download is no longer at risk by then.
const _keepOpenReminder = 'Keep the app open until this finishes.';

Future<void> _downloadUpdate(String apkUrl) async {
  _lastShownPercent = null;
  _showUpdateSnackBar('Downloading update...\n$_keepOpenReminder');

  try {
    await UpdateCheckerService.instance.downloadAndInstall(
      apkUrl,
      onProgress: (progress) {
        if (progress == null) return; // Server didn't report a size.
        final percent = (progress * 100).clamp(0, 100).round();
        if (percent == _lastShownPercent) return;
        if (percent % 5 != 0 && percent != 100) return;
        _lastShownPercent = percent;
        final message = percent < 100
            ? 'Downloading update... $percent%\n$_keepOpenReminder'
            : 'Downloading update... $percent%';
        _showUpdateSnackBar(message);
      },
    );
  } catch (e) {
    _showUpdateSnackBar('Update download failed: $e', isError: true);
  }
}

void _showUpdateSnackBar(String message, {bool isError = false}) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: isError ? const Duration(seconds: 4) : const Duration(seconds: 3),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  /// Runs when the user picks a different look. Screens read their colors
  /// straight from AppTheme, which Flutter does not track, so besides
  /// giving MaterialApp the new theme we also ask every widget currently
  /// on screen to rebuild. Open screens and navigation stay as they are.
  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'VirtuWatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      // Colors come from AppTheme directly, so a fade between two themes
      // would only animate part of the screen. Switch instantly instead.
      themeAnimationDuration: Duration.zero,
      home: const AuthGate(),
    );
  }
}

class FirebaseTestPage extends StatelessWidget {
  const FirebaseTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VirtuWatch')),
      body: const Center(
        child: Text(
          'Firebase connected ✅',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}