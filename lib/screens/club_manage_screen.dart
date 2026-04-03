import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import 'club_profile_sheet.dart';
import 'subscription_screen.dart';

class ClubManageScreen extends StatefulWidget {
  const ClubManageScreen({super.key});

  @override
  State<ClubManageScreen> createState() => _ClubManageScreenState();
}

class _ClubManageScreenState extends State<ClubManageScreen> {
  int? _clubId;
  Map<String, dynamic>? _inviteInfo;
  Map<String, dynamic>? _clubProfile;
  List<dynamic> _members = [];
  bool _isLoadingCode = false;
  bool _isLoadingMembers = false;
  String _myRole = 'member';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final id = await ApiClient.getClubId();
    if (id == null) return;
    setState(() => _clubId = id);
    await Future.wait([_loadInviteCode(), _loadMembers(), _loadProfile()]);
  }

  Future<void> _loadProfile() async {
    if (_clubId == null) return;
    try {
      final data = await ApiClient.getClubProfile(_clubId!);
      if (mounted) setState(() => _clubProfile = data);
    } catch (_) {}
  }

  Future<void> _loadInviteCode() async {
    if (_clubId == null) return;
    setState(() => _isLoadingCode = true);
    try {
      final data = await ApiClient.getInviteCode(_clubId!);
      if (mounted) setState(() => _inviteInfo = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('초대 코드를 불러오지 못했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingCode = false);
    }
  }

  Future<void> _regenerateInviteCode() async {
    if (_clubId == null) return;
    setState(() => _isLoadingCode = true);
    try {
      final data = await ApiClient.regenerateInviteCode(_clubId!);
      if (mounted) {
        setState(() => _inviteInfo = data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('새 초대 코드가 발급되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('코드 발급에 실패했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingCode = false);
    }
  }

  Future<void> _loadMembers() async {
    if (_clubId == null) return;
    setState(() => _isLoadingMembers = true);
    try {
      final data = await ApiClient.getMembers(_clubId!);
      final myId = await ApiClient.getUserId();
      if (mounted) {
        setState(() {
          _members = data;

          // 역할 우선순위: 회장 > 임원진 > 일반멤버, 동일 역할 내 가나다순
          int _roleOrder(String role) {
            switch (role) {
              case 'super_admin': return 0;
              case 'admin':       return 1;
              default:            return 2;
            }
          }
          _members.sort((a, b) {
            final ra = _roleOrder(a['role'] as String? ?? 'user');
            final rb = _roleOrder(b['role'] as String? ?? 'user');
            if (ra != rb) return ra.compareTo(rb);
            final na = a['display_name'] as String? ?? '';
            final nb = b['display_name'] as String? ?? '';
            return na.compareTo(nb);
          });

          // 현재 유저의 role 파악 (isOwner 판단에 사용)
          final me = _members.firstWhere(
            (m) => m['user_id'] == myId,
            orElse: () => <String, dynamic>{},
          );
          _myRole = (me['role'] as String?) ?? 'member';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('멤버 목록을 불러오지 못했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  // 초대 코드 클립보드 복사
  Future<void> _copyCode() async {
    final code = _inviteInfo?['invite_code'];
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('초대 코드가 복사되었습니다.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // 역할 변경 다이얼로그
  Future<void> _showRoleDialog(Map<String, dynamic> member) async {
    String selectedRole = member['role'] ?? 'user';
    // super_admin은 변경 불가
    if (selectedRole == 'super_admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회장의 역할은 변경할 수 없습니다.')),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: Text('${member['display_name']} 역할 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleOption(selectedRole, 'admin', '임원진',
                  '공지 작성·삭제, 무대순서 최적화',
                  (v) => setDs(() => selectedRole = v!)),
              _roleOption(selectedRole, 'user', '일반 멤버',
                  '공지·스케줄 조율·연습실 예약',
                  (v) => setDs(() => selectedRole = v!)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedRole),
              child: const Text('변경'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result == member['role']) return;

    try {
      await ApiClient.updateMemberRole(_clubId!, member['user_id'], result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${member['display_name']} 역할이 ${_roleKo(result)}(으)로 변경되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('역할 변경에 실패했어요. ${friendlyError(e)}')),
        );
      }
    }
  }

  Widget _roleOption(String selectedRole, String value, String label, String desc,
      ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      value: value,
      groupValue: selectedRole,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
      contentPadding: EdgeInsets.zero,
    );
  }

  // 임시 비밀번호 발급
  Future<void> _resetPassword(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('임시 비밀번호 발급'),
        content: Text(
          '${member['display_name']}님의 비밀번호를 임시 비밀번호로 초기화할까요?\n'
          '발급된 임시 비밀번호를 해당 멤버에게 전달하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('발급'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final data = await ApiClient.resetMemberPassword(
          _clubId!, member['user_id']);
      final tempPwd = data['temp_password'] as String?;
      final sentToEmail = data['sent_to_email'] == true;
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('임시 비밀번호 발급 완료'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sentToEmail) ...[
                Text('${member['display_name']}님에게 임시 비밀번호가 이메일로 발송되었습니다.'),
                const SizedBox(height: 8),
                const Text(
                  '멤버가 이메일을 확인한 후 로그인하도록 안내해 주세요.',
                  style: TextStyle(fontSize: 12),
                ),
              ] else ...[
                Text('${member['display_name']}님의 임시 비밀번호:'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    tempPwd ?? '',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '이 비밀번호를 해당 멤버에게 직접 전달하세요.\n'
                  '멤버는 로그인 후 비밀번호를 변경할 수 있습니다.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            if (!sentToEmail && tempPwd != null)
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tempPwd));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('임시 비밀번호가 복사되었습니다.'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('복사'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('임시 비밀번호 발급에 실패했어요. ${friendlyError(e)}')),
        );
      }
    }
  }

  // 멤버 강제탈퇴 확인
  Future<void> _kickMember(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 강제탈퇴'),
        content: Text(
          '${member['display_name']}님을 동아리에서 내보낼까요?\n이 작업은 취소할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('내보내기'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiClient.kickMember(_clubId!, member['user_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member['display_name']}님을 내보냈습니다.'),
          ),
        );
        await _loadMembers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('멤버 내보내기에 실패했어요. ${friendlyError(e)}')),
        );
      }
    }
  }

  String _roleKo(String role) {
    switch (role) {
      case 'super_admin':
        return '회장';
      case 'admin':
        return '임원진';
      default:
        return '일반 멤버';
    }
  }

  Color _roleColor(String role, ColorScheme cs) {
    switch (role) {
      case 'super_admin':
        return Colors.amber.shade300;
      case 'admin':
        return Colors.blue.shade300;
      default:
        return cs.outline;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'super_admin':
        return Icons.star;
      case 'admin':
        return Icons.manage_accounts;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('동아리 관리'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 동아리 프로필 카드 ────────────────────────
            Card(
              child: ListTile(
                leading: const Icon(Icons.business_outlined),
                title: const Text('동아리 프로필'),
                subtitle: Text(_myRole == 'super_admin' ? '로고·배너·테마 편집 가능' : '프로필 보기'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _clubId == null
                    ? null
                    : () => showClubProfile(
                          context,
                          _clubId!,
                          isOwner: _myRole == 'super_admin',
                        ),
              ),
            ),
            // ── SNS 바로가기 ─────────────────────────
            if (_clubProfile != null &&
                (_clubProfile!['instagram_url'] != null ||
                 _clubProfile!['youtube_url'] != null))
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_clubProfile!['instagram_url'] != null)
                      _SnsButton(
                        icon: FontAwesomeIcons.instagram,
                        color: const Color(0xFFE1306C),
                        tooltip: 'Instagram',
                        url: _clubProfile!['instagram_url'],
                      ),
                    if (_clubProfile!['instagram_url'] != null &&
                        _clubProfile!['youtube_url'] != null)
                      const SizedBox(width: 16),
                    if (_clubProfile!['youtube_url'] != null)
                      _SnsButton(
                        icon: FontAwesomeIcons.youtube,
                        color: const Color(0xFFFF0000),
                        tooltip: 'YouTube',
                        url: _clubProfile!['youtube_url'],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // ── 구독 / 플랜 카드 ─────────────────────────
            if (_myRole == 'super_admin')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('플랜 & 구독'),
                  subtitle: const Text('스토리지·홍보 크레딧 관리'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _clubId == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClubSubscriptionScreen(clubId: _clubId!),
                            ),
                          ),
                ),
              ),
            if (_myRole == 'super_admin') const SizedBox(height: 8),
            // ── 초대 코드 섹션 ────────────────────────
            Text(
              '초대 코드',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isLoadingCode
                    ? const Center(child: CircularProgressIndicator())
                    : _inviteInfo == null
                        ? const Text('코드 정보를 불러올 수 없습니다.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 코드 표시
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _inviteInfo!['invite_code'] ?? '------',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 8,
                                      color: colorScheme.onPrimaryContainer,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 만료 시간
                              Row(
                                children: [
                                  Icon(Icons.timer_outlined,
                                      size: 16, color: colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    '만료: ${_inviteInfo!['expires_at'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 버튼 행
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _copyCode,
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('복사'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _isLoadingCode
                                          ? null
                                          : _regenerateInviteCode,
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('새 코드 발급'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
              ),
            ),

            const SizedBox(height: 20),

            // ── 멤버 목록 섹션 ────────────────────────
            Row(
              children: [
                Text(
                  '멤버 목록',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_members.length}명',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_isLoadingMembers)
              const Center(child: CircularProgressIndicator())
            else if (_members.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      '멤버가 없습니다.',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                ),
              )
            else
              ...(_members.map((member) {
                final role = member['role']?.toString() ?? 'user';
                final isSuperAdmin = role == 'super_admin';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _roleColor(role, colorScheme),
                      child: Icon(
                        _roleIcon(role),
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            member['display_name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _roleColor(role, colorScheme)
                                .withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _roleKo(role),
                            style: TextStyle(
                              fontSize: 11,
                              color: _roleColor(role, colorScheme)
                                  .withOpacity(1.0),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '가입일: ${member['joined_at']?.toString().substring(0, 10) ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: isSuperAdmin
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'password') _resetPassword(member);
                              else if (value == 'role') _showRoleDialog(member);
                              else if (value == 'kick') _kickMember(member);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'password',
                                child: ListTile(
                                  leading: Icon(Icons.key_outlined),
                                  title: Text('임시 비밀번호 발급'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'role',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('역할 변경'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'kick',
                                child: ListTile(
                                  leading: Icon(Icons.person_remove_outlined,
                                      color: colorScheme.error),
                                  title: Text('강제탈퇴',
                                      style: TextStyle(color: colorScheme.error)),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              })),
          ],
        ),
      ),
    );
  }
}

class _SnsButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final String? url;

  const _SnsButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: url == null
            ? null
            : () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.12),
          ),
          child: Center(
            child: FaIcon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
