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
    _animController.dispose();
    widget.navScrollController?.removeListener(_onNavScroll);
    super.dispose();
  }

  void _onNavScroll() {
    if (mounted) setState(() {});
  }

  void _navigateToStep(int stepIndex) {
    if (stepIndex >= _steps.length) return;
    final menuKey = _steps[stepIndex].menuKey;
    final tabIndex = widget.tabKeys.indexOf(menuKey);
    if (tabIndex >= 0) {
      widget.onNavigate(tabIndex);
      _scrollNavToTab(tabIndex);
    }
    // IndexedStack이므로 바로 setState (모든 화면이 이미 mounted)
    if (mounted) setState(() {});
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
      setState(() => _currentStep++);
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

    // 말풍선 위치: 요소 주변 여유 공간을 비교해서 넓은 쪽에 배치
    final (useTop, posValue) = _bubbleLayout(
        elementRect, navRect, screenSize, topPadding);

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
                elementRect: elementRect,
                navRect: navRect,
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

            // 말풍선 카드 — 위/아래 동적 배치
            Positioned(
              top: useTop ? posValue : null,
              bottom: useTop ? null : posValue,
              left: 16,
              right: 16,
              child: _BubbleCard(
                step: step,
                isLast: isLast,
                onNext: _next,
                onDone: _finish,
                colorScheme: colorScheme,
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
      // 요소 없음 → 탭 바 바로 위
      return (false, screenSize.height - navTop + gap);
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

// ── 말풍선 카드 ──────────────────────────────────────────────────
class _BubbleCard extends StatelessWidget {
  final OnboardingStep step;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onDone;
  final ColorScheme colorScheme;

  const _BubbleCard({
    required this.step,
    required this.isLast,
    required this.onNext,
    required this.onDone,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
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
                Text(
                  step.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colorScheme.onSurface,
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
  }
}
