import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'download_notification.dart';

/// 비웹 전용 (Windows / Android / iOS / macOS / Linux):
/// 다운로드 폴더에 파일을 저장하고 경로를 반환
/// 반환값: 저장된 절대 경로 (실패 시 null)
Future<String?> saveExcelFile(List<int> bytes, String fileName) async {
  try {
    final sep = Platform.pathSeparator;
    String savePath;

    if (Platform.isAndroid) {
      const androidDownloads = '/storage/emulated/0/Download';
      if (Directory(androidDownloads).existsSync()) {
        savePath = androidDownloads;
      } else {
        savePath = Directory.systemTemp.path;
      }
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
    File(filePath).writeAsBytesSync(bytes);

    // 알림 표시 (비동기, 실패해도 무시)
    showDownloadNotification(
      filePath: filePath,
      fileName: fileName,
    ).catchError((_) {});

    return filePath;
  } catch (_) {
    return null;
  }
}
