import 'package:flutter/material.dart';
import '../api/api_client.dart';

// ── 컬러 칩에 쓸 6가지 프리셋 ──────────────────────────
const _kColorPresets = [
  {'label': '보라', 'hex': '#6750A4'},
  {'label': '파랑', 'hex': '#1976D2'},
  {'label': '초록', 'hex': '#388E3C'},
  {'label': '주황', 'hex': '#F57C00'},
  {'label': '빨강', 'hex': '#D32F2F'},
  {'label': '분홍', 'hex': '#C2185B'},
];

Color _hexToColor(String? hex) {
  if (hex == null || hex.length != 7) return const Color(0xFF6750A4);
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

// ── 외부에서 바텀시트를 여는 헬퍼 함수 ────────────────
Future<void> showClubProfile(
  BuildContext context,
  int clubId, {
  required bool isOwner,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ClubProfileSheet(clubId: clubId, isOwner: isOwner),
  );
}

// ── 프로필 조회 시트 ───────────────────────────────────
class ClubProfileSheet extends StatefulWidget {
  final int clubId;
  final bool isOwner;

  const ClubProfileSheet({
    super.key,
    required this.clubId,
    required this.isOwner,
  });

  @override
  State<ClubProfileSheet> createState() => _ClubProfileSheetState();
}

class _ClubProfileSheetState extends State<ClubProfileSheet> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.getClubProfile(widget.clubId);
      if (mounted) setState(() { _profile = data; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        final rawMsg = e.toString();
        final msg = rawMsg.startsWith('Exception: ')
            ? rawMsg.replaceFirst('Exception: ', '')
            : friendlyError(e);
        setState(() { _error = msg; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _profile == null) {
      // 404 등 에러 시 시트를 닫고 SnackBar 표시 (spec 요구사항)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_error ?? '동아리 정보를 불러올 수 없습니다.')),
          );
        }
      });
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile!;
    final themeColor = _hexToColor(profile['theme_color'] as String?);
    final logoUrl = profile['logo_url'] as String?;
    final bannerUrl = profile['banner_url'] as String?;
    final name = profile['name'] as String? ?? '';
    final memberCount = profile['member_count'] as int? ?? 0;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 배너 영역
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // 배너
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: bannerUrl != null
                      ? Image.network(
                          bannerUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: themeColor),
                        )
                      : Container(color: themeColor),
                ),
              ),
              // 로고 아바타 (배너 위에 오버랩)
              Positioned(
                bottom: -36,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: colorScheme.surface,
                  child: CircleAvatar(
                    radius: 33,
                    backgroundColor: themeColor.withValues(alpha: 0.2),
                    backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                    onBackgroundImageError: logoUrl != null ? (_, __) {} : null,
                    child: logoUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48), // 아바타 오버랩 공간
          // 동아리 정보
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '멤버 $memberCount명',
                  style: TextStyle(color: colorScheme.outline),
                ),
                const SizedBox(height: 24),
                // 편집 버튼 (super_admin만)
                if (widget.isOwner)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => ClubProfileEditSheet(
                          clubId: widget.clubId,
                          currentProfile: profile,
                          onSaved: (updated) {
                            if (mounted) setState(() => _profile = updated);
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('프로필 편집'),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 프로필 편집 시트 (super_admin만) ──────────────────
class ClubProfileEditSheet extends StatefulWidget {
  final int clubId;
  final Map<String, dynamic> currentProfile;
  final void Function(Map<String, dynamic> updated) onSaved;

  const ClubProfileEditSheet({
    super.key,
    required this.clubId,
    required this.currentProfile,
    required this.onSaved,
  });

  @override
  State<ClubProfileEditSheet> createState() => _ClubProfileEditSheetState();
}

class _ClubProfileEditSheetState extends State<ClubProfileEditSheet> {
  late final TextEditingController _logoCtrl;
  late final TextEditingController _bannerCtrl;
  String? _selectedColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _logoCtrl = TextEditingController(
        text: widget.currentProfile['logo_url'] as String? ?? '');
    _bannerCtrl = TextEditingController(
        text: widget.currentProfile['banner_url'] as String? ?? '');
    _selectedColor = widget.currentProfile['theme_color'] as String?;
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _bannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      // 변경된 필드만 body에 포함
      final body = <String, dynamic>{};
      final logoText = _logoCtrl.text.trim();
      final bannerText = _bannerCtrl.text.trim();

      // 로고: 빈 문자열이면 null(초기화), 값 있으면 포함
      if (logoText != (widget.currentProfile['logo_url'] ?? '')) {
        body['logo_url'] = logoText.isEmpty ? null : logoText;
      }
      if (bannerText != (widget.currentProfile['banner_url'] ?? '')) {
        body['banner_url'] = bannerText.isEmpty ? null : bannerText;
      }
      if (_selectedColor != widget.currentProfile['theme_color']) {
        body['theme_color'] = _selectedColor;
      }

      if (body.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final updated = await ApiClient.updateClubProfile(widget.clubId, body);
      if (mounted) {
        widget.onSaved(updated);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        final rawMsg = e.toString();
        final msg = rawMsg.startsWith('Exception: ')
            ? rawMsg.replaceFirst('Exception: ', '')
            : friendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '프로필 편집',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _logoCtrl,
              decoration: const InputDecoration(
                labelText: '로고 이미지 URL',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bannerCtrl,
              decoration: const InputDecoration(
                labelText: '배너 이미지 URL',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('테마 컬러',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _kColorPresets.map((preset) {
                final hex = preset['hex']!;
                final color = _hexToColor(hex);
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
