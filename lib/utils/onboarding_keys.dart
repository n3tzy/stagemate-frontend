import 'package:flutter/material.dart';

/// 온보딩 스포트라이트용 전역 GlobalKey 레지스트리
/// 각 화면 State가 initState에서 등록 (dispose에서는 제거 안 함 — 스포트라이트 오버레이가 stale 확인)
final Map<String, GlobalKey> onboardingKeys = {};

/// 디버그: initState에서 키가 등록된 총 횟수
int onboardingKeyRegTotal = 0;

/// 등록된 키의 화면상 Rect 반환 (없으면 null)
Rect? onboardingKeyRect(String keyName) {
  final key = onboardingKeys[keyName];
  if (key == null) return null;
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null) return null;
  // attached 여부 확인 (detach된 render object는 localToGlobal 불가)
  if (!box.attached) return null;
  try {
    final size = box.size;
    // 크기가 0이면 무효
    if (size.isEmpty) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & size;
  } catch (e, st) {
    debugPrint('onboardingKeyRect[$keyName] EXCEPTION: $e\n$st');
    return null;
  }
}

/// 여러 키의 합집합(bounding box) Rect 반환
Rect? onboardingKeysUnionRect(List<String> keyNames) {
  Rect? result;
  for (final name in keyNames) {
    final r = onboardingKeyRect(name);
    if (r == null) continue;
    result = result == null ? r : result.expandToInclude(r);
  }
  return result;
}
