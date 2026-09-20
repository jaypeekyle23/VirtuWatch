import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'services/notification_service.dart';
import 'services/update_checker_service.dart';

/// Lets the notification tap handler below show a SnackBar (e.g.
/// "Downloading update...") without needing a BuildContext of its own —
/// notification taps can arrive while the app has no screen-level
/// context ready yet (cold start, background).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.init(onNotificationTap: _handleNotificationTap);
  runApp(const MyApp());
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

Future<void> _downloadUpdate(String apkUrl) async {
  scaffoldMessengerKey.currentState?.showSnackBar(
    const SnackBar(content: Text('Downloading update...')),
  );
  try {
    await UpdateCheckerService.instance.downloadAndInstall(apkUrl);
  } catch (e) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('Update download failed: $e')),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'VirtuWatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
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