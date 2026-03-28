import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

Future<void> initDownloadNotifications() async {
  if (_initialized) return;
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await _plugin.initialize(
    settings,
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        OpenFile.open(payload);
      }
    },
  );
  _initialized = true;
}

Future<void> showDownloadNotification({
  required String filePath,
  required String fileName,
}) async {
  if (!Platform.isAndroid) return; // iOS는 no-op
  await initDownloadNotifications();

  // Android 13+ 런타임 권한 요청
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();

  const androidDetails = AndroidNotificationDetails(
    'downloads',
    '다운로드',
    channelDescription: '파일 다운로드 완료 알림',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  const details = NotificationDetails(android: androidDetails);

  await _plugin.show(
    0,
    '다운로드 완료',
    fileName,
    details,
    payload: filePath,
  );
}
