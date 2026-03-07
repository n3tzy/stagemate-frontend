// 플랫폼별 엑셀 저장 구현체를 조건부로 선택
// - 웹(dart:html 사용 가능): excel_save_web.dart
// - Windows / Android / iOS / macOS / Linux: excel_save_io.dart
export 'excel_save_io.dart'
    if (dart.library.html) 'excel_save_web.dart';
