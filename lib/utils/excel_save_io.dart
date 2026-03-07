import 'dart:io';

/// 비웹 전용 (Windows / Android / iOS / macOS / Linux):
/// 다운로드 폴더에 파일을 저장하고 경로를 반환
/// 반환값: 저장된 절대 경로 (실패 시 null)
String? saveExcelFile(List<int> bytes, String fileName) {
  try {
    final sep = Platform.pathSeparator;

    // 플랫폼별 홈 디렉토리
    final home = Platform.environment['USERPROFILE'] ?? // Windows
                 Platform.environment['HOME'] ??         // macOS / Linux
                 Directory.systemTemp.path;

    // 저장 경로: 홈/Downloads/ (없으면 Documents/)
    String savePath = '$home${sep}Downloads';
    if (!Directory(savePath).existsSync()) {
      savePath = '$home${sep}Documents';
      if (!Directory(savePath).existsSync()) {
        savePath = Directory.systemTemp.path;
      }
    }

    final filePath = '$savePath$sep$fileName';
    File(filePath).writeAsBytesSync(bytes);
    return filePath;
  } catch (_) {
    return null;
  }
}
