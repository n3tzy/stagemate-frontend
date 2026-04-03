import 'package:excel/excel.dart';
import 'excel_save_helper.dart'; // 플랫폼별 저장 구현체 자동 선택

/// 무대 순서 결과를 .xlsx 파일로 내보내기
/// 반환값:
///   - 웹: null (브라우저 자동 다운로드)
///   - 데스크탑/모바일: 저장된 파일 경로 (실패 시 null)
class ExcelExporter {
  static Future<String?> exportSchedule(Map<String, dynamic> result) async {
    final excel = Excel.createExcel();
    const sheetName = '무대순서';

    // 기본 Sheet1 → 시트명 변경
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    // ── 헤더 행 ────────────────────────────────────
    final headers = [
      '순서',
      '곡명',
      '멤버',
      '곡 길이(분)',
      '소개시간(분)',
      '시작 시각',
      '종료 시각',
      '경고',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#6750A4'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // ── 경고 맵 구성 ────────────────────────────────
    final warnings = (result['warnings'] as List?) ?? [];
    final Map<int, String> warnByOrder = {};
    for (final w in warnings) {
      final s = w.toString();
      final match = RegExp(r'순서\s+(\d+)→(\d+)').firstMatch(s);
      if (match != null) {
        final from = int.tryParse(match.group(1) ?? '');
        final to = int.tryParse(match.group(2) ?? '');
        if (from != null) warnByOrder[from] = s;
        if (to != null) warnByOrder[to] = (warnByOrder[to] ?? '') + ' / $s';
      }
    }

    // ── 데이터 행 ───────────────────────────────────
    final stages = (result['stages'] as List?) ?? [];
    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i] as Map<String, dynamic>;
      final song = stage['song'] as Map<String, dynamic>;
      final order = stage['order'] as int;
      final members = (song['members'] as List).join(', ');
      final duration = (song['duration'] as num).toDouble();
      final introTime = (song['intro_time'] as num?)?.toDouble() ?? 1.5;
      final startTime = (stage['start_time'] as num).toDouble();
      final endTime = (stage['end_time'] as num).toDouble();
      final warning = warnByOrder[order] ?? '';

      final rowData = [
        IntCellValue(order),
        TextCellValue(song['title']?.toString() ?? ''),
        TextCellValue(members),
        DoubleCellValue(duration),
        DoubleCellValue(introTime),
        TextCellValue(_formatClock(startTime)),
        TextCellValue(_formatClock(endTime)),
        TextCellValue(warning),
      ];

      for (var j = 0; j < rowData.length; j++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = rowData[j];

        // 경고 있는 행 강조
        if (warning.isNotEmpty) {
          cell.cellStyle = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('#FFF3CD'),
          );
        }
      }
    }

    // ── 열 너비 ─────────────────────────────────────
    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 30);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 12);
    sheet.setColumnWidth(6, 12);
    sheet.setColumnWidth(7, 40);

    // ── 파일 저장 (플랫폼별 구현체 호출) ──────────────
    final bytes = excel.encode();
    if (bytes == null) return null;

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = '무대순서_$dateStr.xlsx';

    return await saveExcelFile(bytes, fileName);
  }

  static String _formatClock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
