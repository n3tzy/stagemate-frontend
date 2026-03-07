import 'package:flutter/material.dart';
import 'schedule_screen.dart';
import 'group_screen.dart';
import 'booking_screen.dart';
import 'notice_screen.dart';
import 'club_manage_screen.dart';
import 'club_onboarding_screen.dart';
import 'login_screen.dart';
import '../api/api_client.dart';

class HomeScreen extends StatefulWidget {
  final String displayName;
  final String role;
  final String clubName;

  const HomeScreen({
    super.key,
    required this.displayName,
    required this.role,
    required this.clubName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // 역할별 권한 헬퍼
  bool get _isSuperAdmin => widget.role == 'super_admin';
  bool get _isAdmin => widget.role == 'admin' || _isSuperAdmin;
  bool get _canOptimizeSchedule => _isAdmin;
  bool get _canManageClub => _isSuperAdmin;

  // 역할에 따라 탭 화면 구성
  List<Widget> get _screens {
    return [
      const NoticeScreen(),
      if (_canOptimizeSchedule) const ScheduleScreen(),
      const GroupScreen(),
      const BookingScreen(),
      if (_canManageClub) const ClubManageScreen(),
    ];
  }

  List<NavigationDestination> get _destinations {
    return [
      const NavigationDestination(
        icon: Icon(Icons.campaign),
        label: '공지사항',
      ),
      if (_canOptimizeSchedule)
        const NavigationDestination(
          icon: Icon(Icons.queue_music),
          label: '무대 순서',
        ),
      const NavigationDestination(
        icon: Icon(Icons.group),
        label: '스케줄 조율',
      ),
      const NavigationDestination(
        icon: Icon(Icons.meeting_room),
        label: '연습실 예약',
      ),
      if (_canManageClub)
        const NavigationDestination(
          icon: Icon(Icons.manage_accounts),
          label: '동아리 관리',
        ),
    ];
  }

  // 역할 표시 정보
  String get _roleLabel {
    switch (widget.role) {
      case 'super_admin':
        return '👑 회장';
      case 'admin':
        return '⭐ 임원진';
      default:
        return '🎵 멤버';
    }
  }

  Color _roleBadgeColor(ColorScheme cs) {
    switch (widget.role) {
      case 'super_admin':
        return Colors.amber.shade100;
      case 'admin':
        return Colors.blue.shade100;
      default:
        return cs.secondaryContainer;
    }
  }

  Future<void> _logout() async {
    await ApiClient.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _showAccountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                '계정 관리  ·  ${widget.displayName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('사용 방법'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showWelcomeDialog(
                  context: context,
                  isCreator: widget.role == 'super_admin',
                  clubName: widget.clubName,
                  role: widget.role,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset),
              title: const Text('비밀번호 변경'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showChangePasswordDialog();
              },
            ),
            ListTile(
              leading: Icon(Icons.person_remove, color: Theme.of(context).colorScheme.error),
              title: Text('회원 탈퇴', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showDeleteAccountDialog();
              },
            ),
          ],
        ),
      ),
        ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('비밀번호 변경'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: '현재 비밀번호',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: '새 비밀번호',
                    hintText: '8자 이상, 대문자·소문자·숫자 포함',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: '새 비밀번호 확인',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (newCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('새 비밀번호가 일치하지 않습니다.'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      try {
                        final result = await ApiClient.changePassword(
                          currentPassword: currentCtrl.text,
                          newPassword: newCtrl.text,
                        );
                        if (!mounted) return;
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['message'] ?? result['detail'] ?? '처리 완료'),
                            backgroundColor: result.containsKey('message') ? Colors.green : Colors.red,
                          ),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        setDialogState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('변경'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('정말 탈퇴하시겠어요?'),
        content: const Text(
          '탈퇴하면 계정과 등록한 모든 데이터(가능 시간, 예약 등)가 삭제되며\n복구할 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await ApiClient.deleteAccount();
                await ApiClient.logout();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('탈퇴 실패: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🎭 StageMate',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    widget.clubName,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            // 역할 배지
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _roleBadgeColor(colorScheme),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_roleLabel  ${widget.displayName}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            onPressed: _showAccountSheet,
            tooltip: '계정 관리',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: _destinations,
      ),
    );
  }
}
