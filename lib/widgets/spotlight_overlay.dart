import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/onboarding_step.dart';
import '../utils/onboarding_keys.dart';

// ── 오버레이 페인터: 어둡게 + 구멍 ──────────────────────────────────
class _SpotlightPainter extends CustomPainter {
  final Rect? elementRect; // 화면 내 요소 강조 (주)
  final Rect? navRect;     // 탭 바 강조 (부)

  const _SpotlightPainter({this.elementRect, this.navRect});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    // 전체 반투명 어둡게
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // 주 요소 구멍 (밝은 글로우)
    if (elementRect != null) {
      final inflated = elementRect!.inflate(8);
      final rr = RRect.fromRectAndRadius(inflated, const Radius.circular(16));

      // 글로우 효과
      canvas.drawRRect(
        rr,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      // 실제 구멍
      canvas.drawRRect(
        RRect.fromRectAndRadius(elementRect!.inflate(4), const Radius.circular(14)),
        Paint()..blendMode = BlendMode.clear,
      );
    }

    // 탭 바 보조 구멍 (작게)
    if (navRect != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(navRect!, const Radius.circular(8)),
        Paint()..blendMode = BlendMode.clear,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.elementRect != elementRect || old.navRect != navRect;
}

// ── 화살표 페인터 (말풍선 → 스포트라이트 연결) ──────────────────────
class _ArrowPainter extends CustomPainter {
  final bool pointingUp; // true: ▲ (말풍선 위쪽), false: ▼ (말풍선 아래쪽)

  const _ArrowPainter({required this.pointingUp});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    // 그림자 (살짝 블러)
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // 흰색 채우기 (카드와 동일한 색)
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  Path _buildPath(Size s) {
    final path = Path();
    if (pointingUp) {
      // ▲: 위 꼭짓점 → 좌하단 → 우하단
      path.moveTo(s.width / 2, 0);
      path.lineTo(0, s.height);
      path.lineTo(s.width, s.height);
    } else {
      // ▼: 좌상단 → 우상단 → 아래 꼭짓점
      path.moveTo(0, 0);
      path.lineTo(s.width, 0);
      path.lineTo(s.width / 2, s.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pointingUp != pointingUp;
}

// ── SpotlightOverlay ─────────────────────────────────────────────
class SpotlightOverlay extends StatefulWidget {
  final List<String> tabKeys;
  final List<GlobalKey> navItemKeys;
  final ScrollController? navScrollController;
  final String role;
  final VoidCallback onDone;
  final void Function(int tabIndex) onNavigate; // 탭 전환 콜백

  const SpotlightOverlay({
    super.key,
    required this.tabKeys,
    required this.navItemKeys,
    this.navScrollController,
    required this.role,
    required this.onDone,
    required this.onNavigate,
  });

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay>
    with SingleTickerProviderStateMixin {
  late final List<OnboardingStep> _steps;
  int _currentStep = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  Timer? _positionTimer;
  // rect 확인 전에는 버블 카드를 숨겨 "이중 노출" 방지
  bool _bubbleVisible = false;

  @override
  void initState() {
    super.initState();
    _steps = kOnboardingSteps.where((s) {
      return s.isVisibleForRole(widget.role) &&
          widget.tabKeys.contains(s.menuKey);
    }).toList();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    widget.navScrollController?.addListener(_onNavScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToStep(0);
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _animController.dispose();
    widget.navScrollController?.removeListener(_onNavScroll);
    super.dispose();
  }

  void _onNavScroll() {
    if (mounted) setState(() {});
  }

  void _navigateToStep(int stepIndex) {
    if (stepIndex >= _steps.length) return;
    _positionTimer?.cancel();
    _bubbleVisible = false; // 스텝 이동 시 버블 숨김 (버튼 확인 전까지)

    final menuKey = _steps[stepIndex].menuKey;
    final tabIndex = widget.tabKeys.indexOf(menuKey);
    if (tabIndex >= 0) {
      widget.onNavigate(tabIndex);
      _scrollNavToTab(tabIndex);
    }
    // 1단계: 초기 프레임 기반 빠른 재시도 (최대 30프레임)
    //   버튼이 즉시 트리에 있으면 바로 버블 표시
    //   없으면 → 2단계 타이머에게 위임 (버블 미표시 유지)
    _retryReadPosition(30, stepIndex);
    // 2단계: 100ms 간격 타이머 — API 로드 완료 후 버튼 찾히면 즉시 버블 표시
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _currentStep != stepIndex) {
        timer.cancel();
        return;
      }
      final rect = _elementRect();
      if (rect != null) {
        timer.cancel();
        setState(() => _bubbleVisible = true);
      }
    });
    // 15초 후에도 버튼 못 찾으면 nav 폴백으로 버블 표시 (무한 대기 방지)
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _currentStep == stepIndex && !_bubbleVisible) {
        _positionTimer?.cancel();
        setState(() => _bubbleVisible = true);
      }
    });
  }

  /// elementRect를 찾을 때까지 매 프레임 재시도 (빠른 초기 반응용)
  /// 찾으면 즉시 버블 표시.
  /// 30프레임 후에도 없으면 → 타이머가 이어받으므로 여기서는 아무것도 안 함.
  void _retryReadPosition(int remaining, int stepIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentStep != stepIndex) return;
      final rect = _elementRect();
      if (rect != null) {
        setState(() => _bubbleVisible = true); // 찾음 → 버블 즉시 표시
      } else if (remaining > 1) {
        _retryReadPosition(remaining - 1, stepIndex); // 다음 프레임 재시도
      }
      // remaining == 1이고 rect == null: 타이머에게 위임, 버블 숨김 유지
    });
  }

  void _scrollNavToTab(int tabIndex) {
    final sc = widget.navScrollController;
    if (sc == null || !sc.hasClients) return;
    final position = sc.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) return;

    final tabCount = widget.navItemKeys.length;
    final totalWidth = position.maxScrollExtent + position.viewportDimension;
    final itemWidth = totalWidth / tabCount;
    final tabCenter = tabIndex * itemWidth + itemWidth / 2;
    final target = (tabCenter - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);

    sc.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _next() {
    if (_currentStep < _steps.length - 1) {
      _animController.forward(from: 0);
      setState(() {
        _currentStep++;
        _bubbleVisible = false; // 다음 스텝 버블 숨김 (rect 재확인 전까지)
      });
      _navigateToStep(_currentStep);
    } else {
      widget.onDone();
    }
  }

  void _finish() => widget.onDone();

  /// 화면 내 요소 Rect (spotlightKeys 합집합)
  Rect? _elementRect() {
    final keys = _steps[_currentStep].spotlightKeys;
    if (keys.isEmpty) return null;
    return onboardingKeysUnionRect(keys);
  }

  /// 탭 바 탭 Rect (보조 강조)
  Rect? _navRect() {
    final menuKey = _steps[_currentStep].menuKey;
    final tabIndex = widget.tabKeys.indexOf(menuKey);
    if (tabIndex < 0 || tabIndex >= widget.navItemKeys.length) return null;
    final ctx = widget.navItemKeys[tabIndex].currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final offset = box.localToGlobal(Offset.zero);
    return Rect.fromCenter(
      center: Offset(offset.dx + box.size.width / 2, offset.dy + box.size.height / 2),
      width: 44,
      height: 52,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return const SizedBox.shrink();
    }

    final step = _steps[_currentStep];
    final isLast = _currentStep == _steps.length - 1;
    final elementRect = _elementRect();
    final navRect = _navRect();
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;

    // elementRect 없으면 navRect을 주 스포트라이트로 폴백
    final effectiveElementRect = elementRect ?? (navRect != null
        ? navRect.inflate(6) // nav tab을 약간 크게 강조
        : null);

    // 말풍선 위치: 요소 주변 여유 공간을 비교해서 넓은 쪽에 배치
    final (useTop, posValue) = _bubbleLayout(
        effectiveElementRect, navRect, screenSize, topPadding);

    // 화살표 수평 위치: 카드 왼쪽 끝(left=16)을 기준으로 한 offset
    // effectiveElementRect 중심이 화살표 꼭짓점이 되도록
    const cardInset = 16.0;
    const arrowW = 20.0;
    final double? arrowLeft = effectiveElementRect != null
        ? (effectiveElementRect.center.dx - cardInset)
            .clamp(arrowW / 2, screenSize.width - 2 * cardInset - arrowW / 2)
        : null;

    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onTap: isLast ? null : _next,
        child: Stack(
          children: [
            // 오버레이 페인터
            CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                elementRect: effectiveElementRect,
                // elementRect가 없어서 navRect을 폴백으로 썼다면 보조 구멍은 표시 안 함
                navRect: elementRect != null ? navRect : null,
              ),
            ),

            // 진행 표시
            Positioned(
              top: topPadding + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentStep + 1} / ${_steps.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),

            // 건너뛰기
            Positioned(
              top: topPadding + 4,
              right: 12,
              child: TextButton(
                onPressed: _finish,
                child: const Text('건너뛰기',
                    style: TextStyle(color: Colors.white)),
              ),
            ),

            // 말풍선 카드 — rect 확인 후에만 표시 (이중 노출 방지)
            if (_bubbleVisible)
              Positioned(
                top: useTop ? posValue : null,
                bottom: useTop ? null : posValue,
                left: cardInset,
                right: cardInset,
                child: _BubbleCard(
                  step: step,
                  isLast: isLast,
                  onNext: _next,
                  onDone: _finish,
                  colorScheme: colorScheme,
                  arrowPointsUp: useTop,
                  arrowLeft: arrowLeft,
                ),
              ),

            // rect 확인 중 로딩 인디케이터
            if (!_bubbleVisible)
              Positioned(
                bottom: (navRect?.top ?? screenSize.height - 80) / 2 - 20,
                left: 0, right: 0,
                child: const Center(
                  child: SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }

  /// 말풍선 위치 계산
  /// 반환: (useTop, value)
  ///   useTop=true  → Positioned(top: value)    : 요소 아래에 말풍선
  ///   useTop=false → Positioned(bottom: value) : 요소 위에 말풍선
  (bool useTop, double value) _bubbleLayout(
      Rect? elementRect, Rect? navRect, Size screenSize, double topPadding) {
    // 네비게이션 바 상단 (말풍선이 침범하면 안 되는 경계)
    final navTop = navRect?.top ?? (screenSize.height - 80);
    // 앱바 아래 (상태바 + 앱바 ≈ topPadding + 56)
    final safeTop = topPadding + 56.0;
    const gap = 14.0;

    if (elementRect == null) {
      // 요소를 찾을 수 없으면 앱바-네비바 사이 중앙에 배치
      final safeAreaMid = (safeTop + navTop) / 2;
      return (true, (safeAreaMid - 80.0).clamp(safeTop, navTop - 80.0));
    }

    final spaceAbove = elementRect.top - safeTop;
    final spaceBelow = navTop - elementRect.bottom;

    if (spaceAbove >= spaceBelow) {
      // 위쪽 공간이 더 넓음 → 요소 위에 말풍선 (bottom 기준)
      return (false, screenSize.height - elementRect.top + gap);
    } else {
      // 아래쪽 공간이 더 넓음 → 요소 아래에 말풍선 (top 기준)
      return (true, elementRect.bottom + gap);
    }
  }
}

// ── 말풍선 카드 (화살표 포함) ────────────────────────────────────────
class _BubbleCard extends StatelessWidget {
  final OnboardingStep step;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onDone;
  final ColorScheme colorScheme;
  /// true  → 화살표가 카드 상단에서 위를 가리킴 (▲)
  /// false → 화살표가 카드 하단에서 아래를 가리킴 (▼)
  final bool arrowPointsUp;
  /// 카드 왼쪽 기준 화살표 꼭짓점 x 위치. null이면 화살표 없음.
  final double? arrowLeft;

  const _BubbleCard({
    required this.step,
    required this.isLast,
    required this.onNext,
    required this.onDone,
    required this.colorScheme,
    this.arrowPointsUp = true,
    this.arrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    const arrowH = 10.0;
    const arrowW = 20.0;
    // 화살표 밑단이 카드 모서리와 살짝 겹쳐 이음새가 자연스럽게 보임
    const arrowOverlap = 2.0;

    final cardBody = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (step.isFaIcon)
                  FaIcon(FontAwesomeIcons.bullhorn,
                      color: colorScheme.primary, size: 16)
                else if (step.materialIcon != null)
                  Icon(step.materialIcon, color: colorScheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (isLast)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDone,
                  child: const Text('시작하기!'),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('다음 →', style: TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );

    // 화살표 없으면 카드만 반환
    if (arrowLeft == null) return cardBody;

    // 화살표 꼭짓점 x (카드 기준) — 너무 끝으로 가지 않도록 clamp
    final tipX = arrowLeft!.clamp(arrowW / 2, double.infinity) - arrowW / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 카드: 화살표 공간만큼 패딩 추가 (overlap으로 이음새 자연스럽게)
        Padding(
          padding: EdgeInsets.only(
            top: arrowPointsUp ? arrowH - arrowOverlap : 0,
            bottom: arrowPointsUp ? 0 : arrowH - arrowOverlap,
          ),
          child: cardBody,
        ),
        // 화살표 삼각형
        Positioned(
          top: arrowPointsUp ? 0 : null,
          bottom: arrowPointsUp ? null : 0,
          left: tipX,
          child: SizedBox(
            width: arrowW,
            height: arrowH,
            child: CustomPaint(
              painter: _ArrowPainter(pointingUp: arrowPointsUp),
            ),
          ),
        ),
      ],
    );
  }
}
