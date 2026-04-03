import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/onboarding_step.dart';

// ── CustomPainter: 반투명 오버레이 + 구멍 ────────────────────────
class _SpotlightPainter extends CustomPainter {
  final Rect holeRect;

  const _SpotlightPainter(this.holeRect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    // 전체 어둡게 (30%)
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withOpacity(0.30),
    );

    // 구멍 주변 흰색 글로우
    canvas.drawRRect(
      RRect.fromRectAndRadius(holeRect.inflate(6), const Radius.circular(14)),
      Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 탭 위치에 구멍 뚫기
    canvas.drawRRect(
      RRect.fromRectAndRadius(holeRect, const Radius.circular(10)),
      Paint()..blendMode = BlendMode.clear,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.holeRect != holeRect;
}

// ── SpotlightOverlay ─────────────────────────────────────────────
class SpotlightOverlay extends StatefulWidget {
  final List<String> tabKeys;
  final List<GlobalKey> navItemKeys;
  final ScrollController? navScrollController;
  final String role;
  final VoidCallback onDone;

  const SpotlightOverlay({
    super.key,
    required this.tabKeys,
    required this.navItemKeys,
    this.navScrollController,
    required this.role,
    required this.onDone,
  });

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> {
  late final List<OnboardingStep> _steps;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _steps = kOnboardingSteps.where((s) {
      return s.isVisibleForRole(widget.role) &&
          widget.tabKeys.contains(s.menuKey);
    }).toList();

    // 스크롤 중 구멍이 탭을 따라가도록 리스너 등록
    widget.navScrollController?.addListener(_onNavScroll);

    // 첫 단계 탭이 화면 밖에 있을 수 있으므로 초기 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTab(0));
  }

  @override
  void dispose() {
    widget.navScrollController?.removeListener(_onNavScroll);
    super.dispose();
  }

  /// 스크롤 위치가 바뀔 때마다 rebuild → 구멍이 탭을 실시간으로 추적
  void _onNavScroll() {
    if (mounted) setState(() {});
  }

  void _finish() {
    widget.onDone();
  }

  void _next() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      // 스크롤은 바로 시작 (리스너가 rebuild를 유발하므로 구멍이 탭을 따라감)
      _scrollToTab(_currentStep);
    } else {
      _finish();
    }
  }

  /// 해당 단계의 탭이 nav bar 뷰포트 중앙에 오도록 스크롤
  void _scrollToTab(int stepIndex) {
    final sc = widget.navScrollController;
    if (sc == null || !sc.hasClients) return;

    final position = sc.position;
    if (!position.hasContentDimensions) return;
    if (position.maxScrollExtent <= 0) return; // 모두 화면에 보임

    if (stepIndex >= _steps.length) return;
    final menuKey = _steps[stepIndex].menuKey;
    final tabIndex = widget.tabKeys.indexOf(menuKey);
    if (tabIndex < 0 || tabIndex >= widget.navItemKeys.length) return;

    // 탭 하나의 너비 = 전체 콘텐츠 너비 / 탭 수
    final tabCount = widget.navItemKeys.length;
    final totalWidth = position.maxScrollExtent + position.viewportDimension;
    final itemWidth = totalWidth / tabCount;

    // 탭 중앙이 뷰포트 중앙에 오는 스크롤 위치
    final tabCenter = tabIndex * itemWidth + itemWidth / 2;
    final target = (tabCenter - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);

    sc.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Rect _holeRect() {
    final menuKey = _steps[_currentStep].menuKey;
    final tabIndex = widget.tabKeys.indexOf(menuKey);
    if (tabIndex < 0 || tabIndex >= widget.navItemKeys.length) return Rect.zero;

    final ctx = widget.navItemKeys[tabIndex].currentContext;
    if (ctx == null) return Rect.zero;

    final box = ctx.findRenderObject() as RenderBox;
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
    final holeRect = _holeRect();
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    // 말풍선 위치: 탭 바 위쪽에 표시
    final bubbleBottom = holeRect == Rect.zero
        ? 88.0
        : screenHeight - holeRect.top + 12;

    return GestureDetector(
      onTap: isLast ? null : _next,
      child: Stack(
        children: [
          // 오버레이 + 구멍
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _SpotlightPainter(holeRect),
          ),

          // 진행 표시 (1 / N)
          Positioned(
            top: topPadding + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${_currentStep + 1} / ${_steps.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),

          // 우상단 Skip 버튼
          Positioned(
            top: topPadding + 4,
            right: 12,
            child: TextButton(
              onPressed: _finish,
              child: const Text(
                '건너뛰기',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),

          // 말풍선 카드
          Positioned(
            bottom: bubbleBottom,
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
    );
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
              color: Colors.black.withOpacity(0.20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘 + 제목
            Row(
              children: [
                if (step.isFaIcon)
                  FaIcon(FontAwesomeIcons.bullhorn,
                      color: colorScheme.primary, size: 16)
                else if (step.materialIcon != null)
                  Icon(step.materialIcon,
                      color: colorScheme.primary, size: 18),
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
                child: Text(
                  '화면을 터치하면 다음으로 →',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
