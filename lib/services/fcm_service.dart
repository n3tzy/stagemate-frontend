import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

typedef PostTapCallback = void Function(int postId);

class FcmService {
  static PostTapCallback? _onPostTap;
  static VoidCallback? _onNoticeTap;

  /// Call once from HomeScreen.initState() after login is confirmed.
  /// [onPostTap] switches the home screen to the Feed tab.
  /// [onNoticeTap] switches the home screen to the Announcements tab.
  static Future<void> init({
    required PostTapCallback onPostTap,
    VoidCallback? onNoticeTap,
  }) async {
    _onPostTap = onPostTap;
    _onNoticeTap = onNoticeTap;

    await FirebaseMessaging.instance.requestPermission();
    await _registerToken();

    // Show system banner even when app is in foreground
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground: message received while app is open
    FirebaseMessaging.onMessage.listen(_handleMessage);

    // Background: user taps notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // Terminated: app opened via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  static Future<void> _registerToken() async {
    // Always register the refresh listener regardless of initial token fetch result
    FirebaseMessaging.instance.onTokenRefresh.listen(ApiClient.updateFcmToken);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiClient.updateFcmToken(token);
    } catch (_) {
      // Fail silently — push is a nice-to-have
    }
  }

  static void _handleMessage(RemoteMessage message) {
    final postIdStr = message.data['post_id'];
    if (postIdStr != null) {
      final postId = int.tryParse(postIdStr);
      if (postId != null) _onPostTap?.call(postId);
      return;
    }

    // Announcement notification → switch to announcements tab
    final noticeIdStr = message.data['notice_id'];
    if (noticeIdStr != null) {
      _onNoticeTap?.call();
      return;
    }
  }
}
