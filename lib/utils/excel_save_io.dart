import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 비웹 전용 (Android / iOS / Windows / macOS / Linux)
///
/// - 모바일(Android / iOS): 임시 파일 생성 후 네이티브 공유 시트 표시
///   → iOS "파일에 저장" / Android "Downloads 저장" 등 사용자가 직접 선택
/// - 데스크탑(Windows / macOS / Linux): ~/Downloads 또는 ~/Documents에 직접 저장
///
/// 반환값: 저장 또는 공유에 성공하면 임시 파일 경로, 실패 시 null
Future<String?> saveExcelFile(List<int> bytes, String fileName) async {
  try {
    final sep = Platform.pathSeparator;

    // ── 모바일: 임시 디렉토리에 쓰고 공유 시트로 내보내기 ──────────────
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}$sep$fileName';
      await File(filePath).writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [
          XFile(
            filePath,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            name: fileName,
          )
        ],
        subject: fileName,
      );

      return filePath;
    }

    // ── 데스크탑: ~/Downloads 또는 ~/Documents에 직접 저장 ─────────────
    final home = Platform.environment['USERPROFILE'] ?? // Windows
        Platform.environment['HOME'] ?? // macOS / Linux
        Directory.systemTemp.path;

    String savePath = '$home${sep}Downloads';
    if (!Directory(savePath).existsSync()) {
      savePath = '$home${sep}Documents';
      if (!Directory(savePath).existsSync()) {
        savePath = Directory.systemTemp.path;
      }
    }

    final filePath = '$savePath$sep$fileName';
    await File(filePath).writeAsBytes(bytes, flush: true);
    return filePath;
  } catch (e) {
    return null;
  }
}
