import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_notification.dart';

/// 비웹 전용 (Windows / Android / iOS / macOS / Linux):
/// 파일을 저장하고 경로를 반환
/// 반환값: 저장된 절대 경로 (실패 시 null)
Future<String?> saveExcelFile(List<int> bytes, String fileName) async {
  try {
    final sep = Platform.pathSeparator;
    String savePath;

    if (Platform.isAndroid) {
      // Android 10+(scoped storage): /storage/emulated/0/Download 에 직접 쓰면
      // MediaStore 인덱싱이 안 돼 파일 앱에서 보이지 않는 문제가 있음.
      // → 앱 전용 외부 디렉토리에 저장하고 즉시 open_file로 열어주는 방식으로 처리.
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      savePath = dir.path;
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      savePath = dir.path;
    } else {
      // Windows / macOS / Linux
      final home = Platform.environment['USERPROFILE'] ?? // Windows
                   Platform.environment['HOME'] ??         // macOS / Linux
                   Directory.systemTemp.path;
      savePath = '$home${sep}Downloads';
      if (!Directory(savePath).existsSync()) {
        savePath = '$home${sep}Documents';
        if (!Directory(savePath).existsSync()) {
          savePath = Directory.systemTemp.path;
        }
      }
    }

    final filePath = '$savePath$sep$fileName';
    await File(filePath).writeAsBytes(bytes);

    // 알림 표시 (비동기, 실패해도 무시)
    showDownloadNotification(
      filePath: filePath,
      fileName: fileName,
    ).catchError((_) {});

    return filePath;
  } catch (e) {
    return null;
  }
}
