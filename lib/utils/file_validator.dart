import 'dart:typed_data';

/// 파일 검증 결과
class FileValidationResult {
  final bool isValid;
  final String? error;

  const FileValidationResult._ok()
      : isValid = true,
        error = null;
  const FileValidationResult._fail(this.error) : isValid = false;

  factory FileValidationResult.ok() => const FileValidationResult._ok();
  factory FileValidationResult.fail(String msg) =>
      FileValidationResult._fail(msg);
}

/// OWASP Mobile M4 대응 — 파일 시그니처(매직 바이트) 기반 검증
///
/// 검증 레이어:
///  1. 파일 크기 사전 체크
///  2. 매직 바이트(시그니처) — 선언된 타입과 실제 내용 일치 여부
///  3. 악성 스크립트 패턴 스캔 — 폴리글랏 파일 방어
class FileValidator {
  // ── 매직 바이트 시그니처 ──────────────────────────────

  // JPEG: FF D8 FF
  static const _jpeg = [0xFF, 0xD8, 0xFF];

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  static const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  // GIF87a / GIF89a
  static const _gif87 = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
  static const _gif89 = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];

  // WebP: RIFF????WEBP  (offset 0: RIFF, offset 8: WEBP)
  static const _riff = [0x52, 0x49, 0x46, 0x46];

  // MP3 — ID3v2 태그 또는 MPEG 프레임 동기 비트
  static const _id3 = [0x49, 0x44, 0x33];        // ID3
  static const _mpegSync = [
    [0xFF, 0xFB], // MPEG-1 Layer 3
    [0xFF, 0xFA], // MPEG-1 Layer 3 (no protection)
    [0xFF, 0xF3], // MPEG-2 Layer 3
    [0xFF, 0xF2], // MPEG-2.5 Layer 3
    [0xFF, 0xE3], // MPEG-2 Layer 3 (CBR)
  ];

  // MP4 / MOV: ftyp box (오프셋 4-7)
  // WebM: 1A 45 DF A3 (EBML 헤더)
  static const _ebml = [0x1A, 0x45, 0xDF, 0xA3];

  // ── 악성 스크립트 패턴 (헤더 2KB 스캔) ───────────────
  // 폴리글랏 파일(정상 파일처럼 보이지만 스크립트 포함) 방어용
  static const _suspiciousPatterns = [
    '<script',
    'javascript:',
    '<?php',
    '<? ',
    '#!/',
    '<html',
    '<svg',
    '%PDF-',        // PDF 위장
    'PK\x03\x04',  // ZIP/APK 위장 (처음 4바이트가 해당 타입 아닌 경우)
    'MZ',           // Windows PE 실행 파일
    '\x7FELF',      // Linux ELF 실행 파일
  ];

  // ── 내부 헬퍼 ─────────────────────────────────────────

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static bool _isWebP(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return _startsWith(bytes, _riff) &&
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50;  // P
  }

  static bool _isMp4Family(Uint8List bytes) {
    // ftyp box: 크기(4바이트) + 'ftyp'(4바이트)
    if (bytes.length < 8) return false;
    return bytes[4] == 0x66 && // f
        bytes[5] == 0x74 && // t
        bytes[6] == 0x79 && // y
        bytes[7] == 0x70;   // p
  }

  static bool _isWebM(Uint8List bytes) => _startsWith(bytes, _ebml);

  static bool _isMp3(Uint8List bytes) {
    if (_startsWith(bytes, _id3)) return true;
    for (final sync in _mpegSync) {
      if (_startsWith(bytes, sync)) return true;
    }
    return false;
  }

  /// 헤더 최대 2KB를 ASCII로 읽어 악성 패턴 스캔
  static bool _containsSuspiciousScript(Uint8List bytes) {
    final len = bytes.length < 2048 ? bytes.length : 2048;
    // ASCII 범위(0x20~0x7E + 일부 제어문자)만 추출해서 텍스트로 변환
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      final b = bytes[i];
      if (b >= 0x20 && b < 0x7F) buf.writeCharCode(b);
    }
    final header = buf.toString().toLowerCase();
    for (final pattern in _suspiciousPatterns) {
      if (header.contains(pattern.toLowerCase())) return true;
    }
    return false;
  }

  // ── 공개 API ──────────────────────────────────────────

  /// JPEG 이미지 검증
  static FileValidationResult validateJpeg(Uint8List bytes) {
    if (!_startsWith(bytes, _jpeg)) {
      return FileValidationResult.fail(
          '올바른 JPEG 이미지 파일이 아니에요. 다른 이미지를 선택해 주세요.');
    }
    if (_containsSuspiciousScript(bytes)) {
      return FileValidationResult.fail(
          '업로드할 수 없는 파일이에요. 다른 이미지를 선택해 주세요.');
    }
    return FileValidationResult.ok();
  }

  /// 확장자 기반 이미지 검증 (post_create 등 다중 타입 지원)
  ///
  /// [ext] — `.jpg`, `.png` 등 점(.) 포함 소문자 확장자
  static FileValidationResult validateImageByExtension(
      Uint8List bytes, String ext) {
    final e = ext.toLowerCase();
    switch (e) {
      case '.jpg':
      case '.jpeg':
        if (!_startsWith(bytes, _jpeg)) {
          return FileValidationResult.fail('JPEG 이미지 파일 형식이 올바르지 않아요.');
        }
      case '.png':
        if (!_startsWith(bytes, _png)) {
          return FileValidationResult.fail('PNG 이미지 파일 형식이 올바르지 않아요.');
        }
      case '.gif':
        if (!_startsWith(bytes, _gif87) && !_startsWith(bytes, _gif89)) {
          return FileValidationResult.fail('GIF 이미지 파일 형식이 올바르지 않아요.');
        }
      case '.webp':
        if (!_isWebP(bytes)) {
          return FileValidationResult.fail('WEBP 이미지 파일 형식이 올바르지 않아요.');
        }
      default:
        return FileValidationResult.fail('지원하지 않는 이미지 형식이에요: $e');
    }
    if (_containsSuspiciousScript(bytes)) {
      return FileValidationResult.fail('업로드할 수 없는 파일이에요. 다른 파일을 선택해 주세요.');
    }
    return FileValidationResult.ok();
  }

  /// 확장자 기반 동영상 검증
  ///
  /// [ext] — `.mp4`, `.mov`, `.webm` 등 점(.) 포함 소문자 확장자
  static FileValidationResult validateVideoByExtension(
      Uint8List bytes, String ext) {
    final e = ext.toLowerCase();
    switch (e) {
      case '.mp4':
      case '.mov':
        if (!_isMp4Family(bytes)) {
          return FileValidationResult.fail('MP4/MOV 동영상 파일 형식이 올바르지 않아요.');
        }
      case '.webm':
        if (!_isWebM(bytes)) {
          return FileValidationResult.fail('WEBM 동영상 파일 형식이 올바르지 않아요.');
        }
      default:
        return FileValidationResult.fail('지원하지 않는 동영상 형식이에요: $e');
    }
    // 동영상은 바이너리이므로 스크립트 스캔 생략 (false positive 위험)
    return FileValidationResult.ok();
  }

  /// MP3 음원 파일 검증
  static FileValidationResult validateMp3(Uint8List bytes) {
    if (!_isMp3(bytes)) {
      return FileValidationResult.fail(
          '올바른 MP3 파일이 아니에요. MP3 형식만 업로드할 수 있어요.');
    }
    if (_containsSuspiciousScript(bytes)) {
      return FileValidationResult.fail(
          '업로드할 수 없는 파일이에요. 다른 MP3 파일을 선택해 주세요.');
    }
    return FileValidationResult.ok();
  }
}
