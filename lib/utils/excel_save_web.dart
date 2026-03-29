// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// 웹 전용: dart:html Blob으로 브라우저 자동 다운로드
/// 반환값: null (브라우저가 다운로드를 처리하므로 경로 없음)
Future<String?> saveExcelFile(List<int> bytes, String fileName) async {
  final blob = html.Blob(
    [bytes],
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click())
      .remove();
  html.Url.revokeObjectUrl(url);
  return null; // 브라우저가 다운로드 위치 결정
}
