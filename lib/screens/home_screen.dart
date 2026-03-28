import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'schedule_screen.dart';
import 'group_screen.dart';
import 'booking_screen.dart';
import 'notice_screen.dart';
import 'club_manage_screen.dart';
import 'club_onboarding_screen.dart';
import 'login_screen.dart';
import '../api/api_client.dart';
import 'feed_screen.dart';
import 'my_activity_screen.dart';
import 'notifications_screen.dart';
import 'audio_submission_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  String? _avatarUrl;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiClient.getAvatarUrl().then((url) {
      if (mounted) setState(() => _avatarUrl = url);
    });
    _loadUnreadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final data = await ApiClient.getNotifications();
      if (mounted) {
        setState(() => _unreadCount = (data['unread_count'] as int?) ?? 0);
      }
    } catch (_) {}
  }

  // 역할별 권한 헬퍼
  bool get _isSuperAdmin => widget.role == 'super_admin';
  bool get _isAdmin => widget.role == 'admin' || _isSuperAdmin;
  bool get _canOptimizeSchedule => _isAdmin;
  bool get _canManageClub => _isSuperAdmin;
  bool get _canSubmitAudio => widget.role == 'team_leader' || widget.role == 'admin' || widget.role == 'super_admin';

  // 역할에 따라 탭 화면 구성
  List<Widget> get _screens {
    return [
      const NoticeScreen(),
      const FeedScreen(),
      if (_canOptimizeSchedule) const ScheduleScreen(),
      const GroupScreen(),
      const BookingScreen(),
      if (_canSubmitAudio)
        AudioSubmissionScreen(role: widget.role),
      if (_canManageClub) const ClubManageScreen(),
    ];
  }

  List<NavigationDestination> get _destinations {
    return [
      const NavigationDestination(
        icon: Icon(Icons.campaign),
        label: '공지사항',
      ),
      const NavigationDestination(
        icon: Icon(Icons.dynamic_feed),
        label: '피드',
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
      if (_canSubmitAudio)
        const NavigationDestination(
          icon: Icon(Icons.audio_file),
          label: '음원 제출',
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
        return '회장';
      case 'admin':
        return '임원진';
      default:
        return '멤버';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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
            // 프로필 헤더
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showAvatarPicker();
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          foregroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: Text(
                            widget.displayName.isNotEmpty ? widget.displayName[0] : '?',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '프로필 사진을 탭해 변경',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ],
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
              leading: const Icon(Icons.history),
              title: const Text('내 게시글 · 댓글'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyActivityScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('커뮤니티 닉네임 설정'),
              subtitle: const Text('전체 커뮤니티 글에 사용되는 닉네임'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showNicknameDialog();
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

  Future<void> _showAvatarPicker() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('사진 삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'delete') {
      try {
        await ApiClient.updateAvatarUrl('');
        if (mounted) setState(() => _avatarUrl = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로필 사진이 삭제됐어요.')),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // 1. 이미지 선택
    final file = await picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return;

    // 2. 크롭 화면 표시 (1:1 정사각형)
    final colorScheme = Theme.of(context).colorScheme;
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      compressFormat: ImageCompressFormat.jpg,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '프로필 사진 편집',
          toolbarColor: colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: colorScheme.primary,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '프로필 사진 편집',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return; // 크롭 취소

    // 로딩 표시
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 사진 업로드 중...'), duration: Duration(seconds: 10)),
      );
    }

    try {
      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final presigned = await ApiClient.getPresignedUrl(filename, 'image/jpeg');
      final uploadUrl = presigned['upload_url'] as String;
      final publicUrl = presigned['public_url'] as String;

      final bytes = await File(cropped.path).readAsBytes();
      final res = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'image/jpeg'},
        body: bytes,
      );

      if (res.statusCode == 200 || res.statusCode == 204) {
        await ApiClient.updateAvatarUrl(publicUrl);
        if (mounted) setState(() => _avatarUrl = publicUrl);
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('프로필 사진이 업데이트됐어요!'),
              backgroundColor: Colors.green,
            ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    }
  }

  void _showNicknameDialog() {
    final nicknameCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('커뮤니티 닉네임 설정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '전체 커뮤니티 게시글에 표시되는 닉네임이에요.\n설정하지 않으면 실명이 사용됩니다.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nicknameCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  hintText: '1~20자',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
                      final nickname = nicknameCtrl.text.trim();
                      if (nickname.isEmpty) return;
                      setDialogState(() => isLoading = true);
                      try {
                        final result = await ApiClient.updateNickname(nickname);
                        if (!mounted) return;
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['message'] ?? result['detail'] ?? '닉네임이 설정됐어요.'),
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
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    // 카카오 유저 여부 확인 (나중에 실제로는 저장된 값으로 판단)
    // 여기서는 hashed_password 없는 카카오 유저의 경우 API 에러로 구분
    final passwordCtrl = TextEditingController();
    final confirmTextCtrl = TextEditingController();
    bool isLoading = false;
    bool isKakaoUser = false; // 기본값; 첫 시도 실패 시 카카오 모드로 전환 가능

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('정말 탈퇴하시겠어요?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '탈퇴하면 계정과 모든 데이터가 삭제되며 복구할 수 없어요.\n탈퇴 후 7일간 재가입이 불가합니다.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (!isKakaoUser) ...[
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호 확인',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                      hintText: '현재 비밀번호를 입력하세요',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setDialogState(() => isKakaoUser = true),
                    child: const Text('카카오로 가입했어요', style: TextStyle(fontSize: 12)),
                  ),
                ] else ...[
                  Text(
                    '카카오 계정 탈퇴를 진행합니다.\n아래에 "탈퇴합니다"를 정확히 입력해주세요.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmTextCtrl,
                    decoration: const InputDecoration(
                      labelText: '탈퇴합니다',
                      border: OutlineInputBorder(),
                      hintText: '탈퇴합니다',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);
                      try {
                        await ApiClient.deleteAccount(
                          password: isKakaoUser ? null : passwordCtrl.text,
                          confirmText: isKakaoUser ? confirmTextCtrl.text : null,
                        );
                        await ApiClient.logout();
                        if (!mounted) return;
                        Navigator.pop(dialogCtx);
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(friendlyError(e)),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('탈퇴하기'),
            ),
          ],
        ),
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
                    'StageMate',
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
          // 알림 벨 아이콘
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  );
                  _loadUnreadCount();
                },
              ),
              if (_unreadCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: _unreadCount < 10 ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: _unreadCount >= 10 ? BorderRadius.circular(8) : null,
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: _destinations,
          ),
        ],
      ),
    );
  }
}
