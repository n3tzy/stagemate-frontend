import 'package:flutter/material.dart';

/// 온보딩 스포트라이트용 전역 GlobalKey 레지스트리
/// 각 화면 State가 initState에서 등록, dispose에서 해제
final Map<String, GlobalKey> onboardingKeys = {};

/// 등록된 키의 화면상 Rect 반환 (없으면 null)
Rect? onboardingKeyRect(String keyName) {
  final key = onboardingKeys[keyName];
  if (key == null) return null;
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
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
