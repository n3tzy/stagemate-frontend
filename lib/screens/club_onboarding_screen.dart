import 'package:flutter/material.dart';
import '../api/api_client.dart';
import 'home_screen.dart';

// ── 동아리 온보딩 (만들기 / 참가하기 선택) ─────────────
class ClubOnboardingScreen extends StatelessWidget {
  const ClubOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '동아리에 참여하세요',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '새 동아리를 만들거나\n초대 코드로 기존 동아리에 참가하세요',
                      style: TextStyle(color: colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // 동아리 만들기
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ClubCreateScreen()),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 48, color: colorScheme.primary),
                              const SizedBox(height: 12),
                              Text(
                                '동아리 만들기',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '새 동아리를 개설하고 회장이 되세요',
                                style: TextStyle(
                                    color: colorScheme.outline, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 초대 코드로 참가
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ClubJoinScreen()),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.group_add,
                                  size: 48, color: colorScheme.secondary),
                              const SizedBox(height: 12),
                              Text(
                                '초대 코드로 참가',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '동아리장에게 받은 코드로 참가하세요',
                                style: TextStyle(
                                    color: colorScheme.outline, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ── 가입/생성 후 환영 알림창 ─────────────────────────
Future<void> showWelcomeDialog({
  required BuildContext context,
  required bool isCreator, // 동아리를 만든 경우 true, 참가한 경우 false
  required String clubName,
  required String role,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;

      // 역할 이름 변환
      String roleLabel;
      switch (role) {
        case 'super_admin':
          roleLabel = '회장';
          break;
        case 'admin':
          roleLabel = '임원진';
          break;
        default:
          roleLabel = '멤버';
      }

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'StageMate에 오신 것을\n환영해요!',
                        style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$clubName · $roleLabel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),

                // 1. 초대 코드 위치
                _WelcomeSection(
                  icon: Icons.vpn_key,
                  iconColor: Colors.amber,
                  title: '초대 코드는 어디서 보나요?',
                  content: isCreator
                      ? '하단 메뉴 ▶ 동아리 관리 탭에서\n초대 코드를 확인하고 복사할 수 있어요.\n멤버에게 코드를 공유해서 초대하세요!'
                      : '동아리장(회장)이 초대 코드를 관리해요.\n코드가 필요하면 회장에게 요청하세요.\n코드는 생성 후 2일간 유효해요.',
                ),
                const SizedBox(height: 16),

                // 2. 스케줄 조율 사용법
                _WelcomeSection(
                  icon: Icons.group,
                  iconColor: Colors.green,
                  title: '스케줄 조율 사용법',
                  content:
                      '① 하단 메뉴 ▶ 스케줄 조율 탭 이동\n'
                      '② 팀명(방 코드) 입력 (예: A팀, TEAM1)\n'
                      '③ 내 가능 시간 추가 버튼으로 등록\n'
                      '④ 같은 팀명으로 조회하면\n   팀원들의 가능 시간을 비교하고\n   최적 연습 시간을 찾아줘요!',
                ),
                const SizedBox(height: 16),

                // 3. 역할별 권한
                _WelcomeSection(
                  icon: Icons.star,
                  iconColor: Colors.blue,
                  title: '역할별 권한 안내',
                  content:
                      '회장: 모든 기능 + 동아리 관리\n'
                      '임원진: 공지 작성, 무대 순서 최적화\n'
                      '멤버: 공지·스케줄 조율·연습실 예약',
                ),
                const SizedBox(height: 16),

                // 4. 추가 기능 안내
                _WelcomeSection(
                  icon: Icons.lightbulb,
                  iconColor: Colors.orange,
                  title: '이런 기능도 있어요',
                  content:
                      '공지사항: 임원진이 올린 공지 확인\n'
                      '무대 순서: 최적 공연 순서 생성\n'
                      '연습실 예약: 날짜·시간별 공간 예약\n'
                      '   (모든 멤버 예약 가능)',
                ),
                const SizedBox(height: 24),

                // 시작 버튼
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.rocket_launch),
                    label: const Text(
                      '시작하기!',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── 환영 다이얼로그 섹션 위젯 ─────────────────────────
class _WelcomeSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String content;

  const _WelcomeSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.75),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ── 동아리 만들기 화면 ──────────────────────────────
class ClubCreateScreen extends StatefulWidget {
  const ClubCreateScreen({super.key});

  @override
  State<ClubCreateScreen> createState() => _ClubCreateScreenState();
}

class _ClubCreateScreenState extends State<ClubCreateScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  int _step = 1;

  // Step 2 state
  Map<String, dynamic>? _createdClub;   // API response from createClub
  final _logoUrlController = TextEditingController();
  bool _isSavingLogo = false;

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  Future<void> _createClub() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.createClub(name);
      if (!mounted) return;

      if (data.containsKey('club_id')) {
        setState(() {
          _createdClub = data;
          _step = 2;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? '동아리를 만들지 못했어요. 잠시 후 다시 시도해 주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishOnboarding({bool saveLogo = false}) async {
    if (_createdClub == null) return;

    if (saveLogo) {
      final logoUrl = _logoUrlController.text.trim();
      if (logoUrl.isNotEmpty) {
        setState(() => _isSavingLogo = true);
        try {
          await ApiClient.updateClubProfile(_createdClub!['club_id'], {
            'logo_url': logoUrl,
          });
        } catch (_) {
          // 로고 저장 실패 시 무시하고 진행
        } finally {
          if (mounted) setState(() => _isSavingLogo = false);
        }
      }
    }

    if (!mounted) return;

    final displayName = await ApiClient.getDisplayName() ?? '';

    await showWelcomeDialog(
      context: context,
      isCreator: true,
      clubName: _createdClub!['club_name'],
      role: 'super_admin',
    );
    if (!mounted) return;

    final myClubs = await ApiClient.getMyClubs();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          displayName: displayName,
          role: 'super_admin',
          clubName: _createdClub!['club_name'],
          clubs: myClubs.cast<Map<String, dynamic>>(),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _step == 1 ? _buildStep1(context) : _buildStep2(context);
  }

  Widget _buildStep1(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('동아리 만들기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            // Step indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepDot(active: true, label: '1'),
                Container(width: 32, height: 2, color: colorScheme.outlineVariant),
                _StepDot(active: false, label: '2'),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '어떤 동아리를 만드시나요?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '동아리 이름',
                hintText: '예: 한양대 댄스동아리 GROOVE',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group),
              ),
              onSubmitted: (_) => _createClub(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '생성하면 자동으로 회장(동아리장)이 됩니다.\n초대 코드로 멤버를 초대할 수 있어요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isLoading ? null : _createClub,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_isLoading ? '생성 중...' : '다음'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ClubJoinScreen()),
                );
              },
              child: const Text('초대 코드로 참가하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('동아리 만들기'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            // Step indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepDot(active: false, label: '1'),
                Container(
                  width: 32,
                  height: 2,
                  color: colorScheme.primary,
                ),
                _StepDot(active: true, label: '2'),
              ],
            ),
            const SizedBox(height: 24),
            // Success badge
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle,
                    size: 48, color: Colors.green.shade700),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '\'${_createdClub?['club_name']}\' 생성 완료!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '로고 URL을 추가해서 동아리를 꾸며보세요 (선택)',
              style: TextStyle(color: colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _logoUrlController,
              decoration: const InputDecoration(
                labelText: '로고 이미지 URL (선택)',
                hintText: 'https://example.com/logo.png',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.image_outlined),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_isLoading || _isSavingLogo)
                  ? null
                  : () => _finishOnboarding(saveLogo: true),
              icon: (_isSavingLogo)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSavingLogo ? '저장 중...' : '완료'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: (_isLoading || _isSavingLogo)
                  ? null
                  : () => _finishOnboarding(saveLogo: false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('나중에'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 스텝 인디케이터 점 ──────────────────────────────
class _StepDot extends StatelessWidget {
  final bool active;
  final String label;

  const _StepDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: active ? colorScheme.onPrimary : colorScheme.outline,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── 초대 코드로 참가 화면 ───────────────────────────
class ClubJoinScreen extends StatefulWidget {
  const ClubJoinScreen({super.key});

  @override
  State<ClubJoinScreen> createState() => _ClubJoinScreenState();
}

class _ClubJoinScreenState extends State<ClubJoinScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinClub() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초대 코드는 6자리입니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.joinClub(code);
      if (!mounted) return;

      if (data.containsKey('club_id')) {
        final displayName = await ApiClient.getDisplayName() ?? '';

        // ── 환영 알림창 표시 ──
        await showWelcomeDialog(
          context: context,
          isCreator: false,
          clubName: data['club_name'],
          role: data['role'],
        );
        if (!mounted) return;

        final myClubs = await ApiClient.getMyClubs();
        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              displayName: displayName,
              role: data['role'],
              clubName: data['club_name'],
              clubs: myClubs.cast<Map<String, dynamic>>(),
            ),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['detail'] ?? '동아리 참가에 실패했어요. 코드를 다시 확인해 주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('동아리 참가')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🔑', style: TextStyle(fontSize: 48), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text(
              '초대 코드 입력',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '동아리장에게 받은 6자리 코드를 입력하세요',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '초대 코드 (6자리)',
                hintText: '예: AB12CD',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              style: const TextStyle(
                letterSpacing: 4,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              onSubmitted: (_) => _joinClub(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isLoading ? null : _joinClub,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isLoading ? '참가 중...' : '참가하기'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ClubCreateScreen()),
                );
              },
              child: const Text('새 동아리 만들기'),
            ),
          ],
        ),
      ),
    );
  }
}
