import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../utils/file_validator.dart';
import '../services/fcm_service.dart';
import 'feed_screen.dart';
import 'my_activity_screen.dart';
import 'notifications_screen.dart';
import 'audio_submission_screen.dart';

class HomeScreen extends StatefulWidget {
  final String displayName;
  final String role;
  final String clubName;
  final List<Map<String, dynamic>> clubs; // 추가

  const HomeScreen({
    super.key,
    required this.displayName,
    required this.role,
    required this.clubName,
    required this.clubs, // 추가
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int? _pendingPostId;
  String? _avatarUrl;
  int _unreadCount = 0;
  bool _notificationsEnabled = true;
  late String _currentRole;
  late String _currentClubName;
  late int _currentClubId;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    _currentClubName = widget.clubName;
    _currentClubId = 0; // _initClub()에서 비동기로 확정
    _buildScreens();
    _initClub();
    WidgetsBinding.instance.addObserver(this);
    ApiClient.getAvatarUrl().then((url) {
      if (mounted) setState(() => _avatarUrl = url);
    });
    _loadUnreadCount();
    _loadNotificationSetting();
    FcmService.init(
      onPostTap: (postId) => setState(() {
        _pendingPostId = postId;
        _currentIndex = 1; // Feed is always index 1 (see _screens getter — unconditional, position 1)
        _buildScreens();
      }),
      onNoticeTap: () => setState(() => _currentIndex = 0), // 0 = 공지사항 tab
    );
  }

  Future<void> _initClub() async {
    final savedClubId = await ApiClient.getClubId();
    if (savedClubId != null && widget.clubs.isNotEmpty) {
      final matched = widget.clubs.firstWhere(
        (c) => (c['club_id'] as num).toInt() == savedClubId,
        orElse: () => widget.clubs[0],
      );
      if (mounted) {
        setState(() {
          _currentClubId = (matched['club_id'] as num).toInt();
          _currentClubName = matched['club_name'] as String;
          _currentRole = matched['role'] as String;
          _buildScreens();
        });
      }
    } else if (widget.clubs.isNotEmpty) {
      final first = widget.clubs[0];
      if (mounted) {
        setState(() {
          _currentClubId = (first['club_id'] as num).toInt();
          _buildScreens();
        });
      }
    }
  }

  Future<void> _loadNotificationSetting() async {
    final val = await ApiClient.getStoredValue('notifications_enabled');
    if (mounted) {
      setState(() => _notificationsEnabled = val != 'false');
    }
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
      if (!_notificationsEnabled) {
        if (mounted) setState(() => _unreadCount = 0);
        return;
      }
      final data = await ApiClient.getNotifications();
      if (mounted) {
        setState(() => _unreadCount = (data['unread_count'] as int?) ?? 0);
      }
    } catch (_) {}
  }

  // 역할별 권한 헬퍼
  bool get _isSuperAdmin => _currentRole == 'super_admin';
  bool get _isAdmin => _currentRole == 'admin' || _isSuperAdmin;
  bool get _canOptimizeSchedule => _isAdmin;
  bool get _canManageClub => _isSuperAdmin;
  bool get _canSubmitAudio => true;

  // 역할에 따라 탭 화면 구성 (IndexedStack용 캐시 — 인스턴스 안정성 보장)
  late List<Widget> _screenWidgets;

  void _buildScreens() {
    _screenWidgets = [
      NoticeScreen(key: ValueKey('notice_$_currentClubId')),
      FeedScreen(
        key: ValueKey('feed_$_currentClubId'),
        pendingPostId: _pendingPostId,
        onPostIdConsumed: () => setState(() {
          _pendingPostId = null;
          _buildScreens();
        }),
      ),
      if (_canOptimizeSchedule) ScheduleScreen(key: ValueKey('schedule_$_currentClubId')),
      GroupScreen(key: ValueKey('group_$_currentClubId')),
      BookingScreen(key: ValueKey('booking_$_currentClubId')),
      if (_canSubmitAudio)
        AudioSubmissionScreen(key: ValueKey('audio_$_currentClubId'), role: _currentRole),
      if (_canManageClub) ClubManageScreen(key: ValueKey('clubManage_$_currentClubId')),
    ];
  }

  List<NavigationDestination> get _destinations {
    return [
      const NavigationDestination(
        icon: FaIcon(FontAwesomeIcons.bullhorn),
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

  Color _roleBadgeColor(ColorScheme cs) {
    switch (_currentRole) {
      case 'super_admin':
        return Colors.amber.shade100;
      case 'admin':
        return Colors.blue.shade100;
      default:
        return cs.secondaryContainer;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin': return '회장';
      case 'admin':       return '임원진';
      case 'team_leader': return '팀장';
      default:            return '멤버';
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
                  isCreator: _currentRole == 'super_admin',
                  clubName: _currentClubName,
                  role: _currentRole,
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
            StatefulBuilder(
              builder: (_, setSheetState) => SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('알림'),
                subtitle: const Text('댓글/좋아요 알림 수신'),
                value: _notificationsEnabled,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onChanged: (val) async {
                  await ApiClient.storeValue('notifications_enabled', val ? 'true' : 'false');
                  setSheetState(() {});
                  setState(() {
                    _notificationsEnabled = val;
                    if (!val) _unreadCount = 0;
                  });
                },
              ),
            ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('동아리 생성 & 가입'),
                  onTap: () {
                    Navigator.pop(context); // Close the sheet first
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClubOnboardingScreen(isPostLogin: true),
                      ),
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('개인정보처리방침'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                launchUrl(
                  Uri.parse('https://skillful-unity-production-e922.up.railway.app/privacy'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('이용약관'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                launchUrl(
                  Uri.parse('https://skillful-unity-production-e922.up.railway.app/terms'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            const Divider(height: 1),
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
            const SnackBar(content: Text('프로필 사진이 삭제되었어요.')),
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

      // 매직 바이트 + 악성 스크립트 시그니처 검증
      final validation = FileValidator.validateJpeg(bytes);
      if (!validation.isValid) throw Exception(validation.error);

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
              content: Text('프로필 사진이 업데이트되었어요!'),
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
                            content: Text(result['message'] ?? result['detail'] ?? '닉네임이 설정되었어요.'),
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

  Widget _buildBottomNav(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = _destinations;
    const minItemWidth = 68.0;
    return SafeArea(
      top: false,
      child: Container(
        color: colorScheme.surfaceContainer,
        height: 72,
        child: LayoutBuilder(
        builder: (context, constraints) {
          // 화면 너비를 아이템 수로 나눠서 균등 배분, 최소 68px 보장
          final itemWidth = (constraints.maxWidth / destinations.length)
              .clamp(minItemWidth, double.infinity);
          final totalWidth = itemWidth * destinations.length;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: totalWidth,
              child: Row(
                children: [
                  for (int i = 0; i < destinations.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        indent: 10,
                        endIndent: 10,
                        color: colorScheme.outlineVariant,
                      ),
                    SizedBox(
                      width: itemWidth - (i > 0 ? 1 : 0),
                      child: _buildNavItem(context, i, destinations),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int i, List<NavigationDestination> destinations) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _currentIndex = i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: Duration.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _currentIndex == i
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconTheme(
              data: IconThemeData(
                color: _currentIndex == i
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
                size: 22,
              ),
              child: _currentIndex == i
                  ? (destinations[i].selectedIcon ?? destinations[i].icon)
                  : destinations[i].icon,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destinations[i].label,
            style: TextStyle(
              fontSize: 10,
              color: _currentIndex == i
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
              fontWeight: _currentIndex == i
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1줄: StageMate + 내 이름 배지
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'StageMate',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _roleBadgeColor(colorScheme),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.displayName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // 2줄: 동아리명 (항상 탭 가능 — 1개여도 스위처 열어서 추가 가능)
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (_) => _ClubSwitcherSheet(
                    clubs: widget.clubs,
                    currentClubId: _currentClubId,
                    onSelect: (club) async {
                      await ApiClient.setClubInfo(
                        (club['club_id'] as num).toInt(),
                        club['club_name'] as String,
                        club['role'] as String,
                      );
                      setState(() {
                        _currentClubId = (club['club_id'] as num).toInt();
                        _currentClubName = club['club_name'] as String;
                        _currentRole = club['role'] as String;
                        _buildScreens();
                      });
                    },
                    onAddClub: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClubOnboardingScreen(isPostLogin: true),
                        ),
                      );
                    },
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz, size: 13, color: colorScheme.primary),
                  const SizedBox(width: 3),
                  Text(
                    '$_currentClubName · ${_roleLabel(_currentRole)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onPrimaryContainer.withOpacity(0.85),
                    ),
                  ),
                  Icon(Icons.expand_more, size: 13, color: colorScheme.primary),
                ],
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
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        onPostTap: (postId) {
                          // NotificationsScreen already calls Navigator.pop before this callback fires.
                          // Do NOT call Navigator.pop here.
                          setState(() {
                            _pendingPostId = postId;
                            _currentIndex = 1; // Feed is always index 1 (see _screens getter — unconditional, position 1)
                            _buildScreens();
                          });
                        },
                      ),
                    ),
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
      body: IndexedStack(
        index: _currentIndex,
        children: _screenWidgets,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1),
          _buildBottomNav(context),
        ],
      ),
    );
  }
}

class _ClubSwitcherSheet extends StatelessWidget {
  final List<Map<String, dynamic>> clubs;
  final int currentClubId;
  final Future<void> Function(Map<String, dynamic> club) onSelect;
  final VoidCallback? onAddClub;

  const _ClubSwitcherSheet({
    required this.clubs,
    required this.currentClubId,
    required this.onSelect,
    this.onAddClub,
  });

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin': return '회장';
      case 'admin':       return '임원진';
      case 'team_leader': return '팀장';
      default:            return '멤버';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('동아리 선택',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('입장할 동아리를 선택하세요',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: 14),
            ...clubs.map((club) {
              final isSelected = (club['club_id'] as num).toInt() == currentClubId;
              return GestureDetector(
                onTap: isSelected
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await onSelect(club);
                      },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : Colors.grey[50],
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.grey[200]!,
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : Colors.grey[400],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.theater_comedy,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              club['club_name'] as String,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _roleLabel(club['role'] as String),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : Colors.grey,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.check : Icons.chevron_right,
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_circle_outline,
                  color: colorScheme.primary),
              title: Text(
                '새 동아리 추가',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('만들거나 코드로 참가할 수 있어요'),
              onTap: () {
                Navigator.pop(context);
                onAddClub?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
