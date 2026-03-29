import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import '../api/api_client.dart';

typedef PostTapCallback = void Function(int postId);

// Android 알림 채널 (앱 포그라운드 배너용)
const _androidChannel = AndroidNotificationChannel(
  'stagemate_push',
  'StageMate 알림',
  description: '공지사항, 댓글 등 주요 알림',
  importance: Importance.high,
);

const _androidDetails = AndroidNotificationDetails(
  'stagemate_push',
  'StageMate 알림',
  channelDescription: '공지사항, 댓글 등 주요 알림',
  importance: Importance.high,
  priority: Priority.high,
  icon: '@mipmap/launcher_icon',
);

final _plugin = FlutterLocalNotificationsPlugin();

class FcmService {
  static PostTapCallback? _onPostTap;
  static VoidCallback? _onNoticeTap;

  static Future<void> init({
    required PostTapCallback onPostTap,
    VoidCallback? onNoticeTap,
  }) async {
    _onPostTap = onPostTap;
    _onNoticeTap = onNoticeTap;

    // 로컬 알림 초기화 (다운로드 완료 탭 + 포그라운드 FCM 배너)
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Android 알림 채널 생성 (앱 포그라운드일 때 배너 표시에 필요)
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    await FirebaseMessaging.instance.requestPermission();
    await _registerToken();

    // iOS 포그라운드 배너 (Android는 로컬 알림으로 별도 처리)
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 포그라운드: 로컬 배너 직접 띄우기 (Android)
    FirebaseMessaging.onMessage.listen(_showForegroundBanner);

    // 백그라운드에서 알림 탭: 화면 이동
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);

    // 앱 종료 상태에서 알림 탭: 화면 이동
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _navigateFromMessage(initial);
  }

  /// 포그라운드에서 FCM 수신 → 로컬 알림 배너 표시
  static Future<void> _showForegroundBanner(RemoteMessage message) async {
    final title = message.notification?.title ?? 'StageMate';
    final body = message.notification?.body ?? '';

    // 탭 시 이동 대상을 payload에 인코딩
    String? payload;
    final postId = message.data['post_id'];
    final noticeId = message.data['notice_id'];
    if (postId != null) {
      payload = 'post:$postId';
    } else if (noticeId != null) {
      payload = 'notice:$noticeId';
    }

    await _plugin.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(android: _androidDetails),
      payload: payload,
    );
  }

  /// 알림 탭 → 해당 화면으로 이동
  static void _navigateFromMessage(RemoteMessage message) {
    final postId = message.data['post_id'];
    final noticeId = message.data['notice_id'];
    if (postId != null) {
      final id = int.tryParse(postId);
      if (id != null) _onPostTap?.call(id);
    } else if (noticeId != null) {
      _onNoticeTap?.call();
    }
  }

  /// 로컬 알림 탭 처리 (포그라운드 배너 탭 + 다운로드 알림 탭)
  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // 파일 경로 → 파일 열기 (오디오 다운로드)
    if (payload.startsWith('/') || payload.contains(':\\')) {
      OpenFile.open(payload);
      return;
    }

    // 포그라운드 FCM 배너 탭
    if (payload.startsWith('post:')) {
      final postId = int.tryParse(payload.substring(5));
      if (postId != null) _onPostTap?.call(postId);
    } else if (payload.startsWith('notice:')) {
      _onNoticeTap?.call();
    } else {
      // 하위 호환: 기존 숫자 payload
      final postId = int.tryParse(payload);
      if (postId != null) _onPostTap?.call(postId);
    }
  }

  static Future<void> _registerToken() async {
    FirebaseMessaging.instance.onTokenRefresh.listen(ApiClient.updateFcmToken);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiClient.updateFcmToken(token);
    } catch (_) {
      // 실패 시 무시 — 푸시는 부가 기능
    }
  }
}
