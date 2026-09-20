import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications. Every notification
/// VirtuWatch shows — update available, password changed, verify your
/// email, saved watches waiting — goes through this one service, so
/// there's a single place owning the plugin instance, the notification
/// channels, and what happens when someone taps a notification.
///
/// All of VirtuWatch's notifications are local: nothing here is pushed
/// from a server. Each one is triggered by something the app itself
/// just noticed (a version check, a password change, a stale
/// verification status), not by a remote event, so there's no need for
/// Firebase Cloud Messaging or a backend component.
///
/// Tap routing works via a plain string "payload" set per notification
/// (see the `payload*` prefixes/constants below). main.dart registers a
/// callback via [init] that decides what to do with each payload —
/// currently only the update payload does anything beyond opening the
/// app, since it needs to trigger the APK download.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _updateChannel = AndroidNotificationDetails(
    'update_channel',
    'App Updates',
    channelDescription:
        'Lets you know when a new VirtuWatch build is available.',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _accountChannel = AndroidNotificationDetails(
    'account_channel',
    'Account',
    channelDescription: 'Password changes and account-related confirmations.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _engagementChannel = AndroidNotificationDetails(
    'engagement_channel',
    'Reminders',
    channelDescription:
        'Email verification and saved-watches reminders.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Prefix for the update-available payload; the rest of the string is
  /// the release's APK download URL, so the tap handler knows exactly
  /// what to download without a second lookup.
  static const payloadUpdatePrefix = 'update:';
  static const payloadPasswordChanged = 'password_changed';
  static const payloadVerifyEmail = 'verify_email';
  static const payloadWishlist = 'wishlist';

  final _plugin = FlutterLocalNotificationsPlugin();
  void Function(String payload)? _onTap;

  Future<void> init({void Function(String payload)? onNotificationTap}) async {
    _onTap = onNotificationTap;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _onTap?.call(payload);
      },
    );

    if (Platform.isAndroid) {
      // Android 13+ requires runtime permission to show notifications
      // at all; earlier versions grant it automatically, and this call
      // is a no-op there.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required AndroidNotificationDetails android,
    String? payload,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> showUpdateAvailable({
    required String versionLabel,
    required String apkUrl,
  }) {
    return _show(
      id: 1001,
      title: 'Update available',
      body: 'VirtuWatch $versionLabel is ready to download. Tap to update.',
      android: _updateChannel,
      payload: '$payloadUpdatePrefix$apkUrl',
    );
  }

  Future<void> showPasswordChanged() {
    return _show(
      id: 1002,
      title: 'Password updated',
      body: "Your VirtuWatch password was just changed. If this wasn't "
          'you, reset it right away.',
      android: _accountChannel,
      payload: payloadPasswordChanged,
    );
  }

  Future<void> showVerifyEmailReminder() {
    return _show(
      id: 1003,
      title: 'Verify your email',
      body: 'Confirm your email address to keep your VirtuWatch account '
          'secure.',
      android: _engagementChannel,
      payload: payloadVerifyEmail,
    );
  }

  Future<void> showWishlistReminder(int count) {
    return _show(
      id: 1004,
      title: 'Your saved watches are waiting',
      body: count == 1
          ? 'You have 1 watch saved. Come take another look.'
          : 'You have $count watches saved. Come take another look.',
      android: _engagementChannel,
      payload: payloadWishlist,
    );
  }
}