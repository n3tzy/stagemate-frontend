import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import '../utils/file_validator.dart';

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
  bool _popScheduled = false;

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
        setState(() { _error = friendlyError(e); _isLoading = false; });
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
      if (!_popScheduled) {
        _popScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_error ?? '동아리 정보를 불러올 수 없습니다.')),
            );
          }
        });
      }
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile!;
    final themeColor = _hexToColor(profile['theme_color'] as String?);
    final logoUrl = profile['logo_url'] as String?;
    final bannerUrl = profile['banner_url'] as String?;
    final name = profile['name'] as String? ?? '';
    final memberCount = profile['member_count'] as int? ?? 0;
    final instagramUrl = profile['instagram_url'] as String?;
    final youtubeUrl = profile['youtube_url'] as String?;

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
                // SNS 링크 버튼
                if (instagramUrl != null || youtubeUrl != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (instagramUrl != null)
                        _SnsIconButton(
                          icon: FontAwesomeIcons.instagram,
                          color: const Color(0xFFE1306C),
                          tooltip: 'Instagram',
                          url: instagramUrl,
                        ),
                      if (instagramUrl != null && youtubeUrl != null)
                        const SizedBox(width: 16),
                      if (youtubeUrl != null)
                        _SnsIconButton(
                          icon: FontAwesomeIcons.youtube,
                          color: const Color(0xFFFF0000),
                          tooltip: 'YouTube',
                          url: youtubeUrl,
                        ),
                    ],
                  ),
                ],
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
  String? _logoUrl;
  String? _bannerUrl;
  String? _selectedColor;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _youtubeCtrl;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.currentProfile['logo_url'] as String?;
    _bannerUrl = widget.currentProfile['banner_url'] as String?;
    _selectedColor = widget.currentProfile['theme_color'] as String?;
    _instagramCtrl = TextEditingController(
      text: widget.currentProfile['instagram_url'] as String? ?? '',
    );
    _youtubeCtrl = TextEditingController(
      text: widget.currentProfile['youtube_url'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _instagramCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<String?> _pickAndUpload(String field) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final filename = '${field}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final presigned = await ApiClient.getPresignedUrl(filename, 'image/jpeg');
    final uploadUrl = presigned['upload_url'] as String;
    final publicUrl = presigned['public_url'] as String;

    final bytes = await File(picked.path).readAsBytes();

    // 매직 바이트 + 악성 스크립트 시그니처 검증
    final validation = FileValidator.validateJpeg(bytes);
    if (!validation.isValid) throw Exception(validation.error);

    final res = await http.put(
      Uri.parse(uploadUrl),
      body: bytes,
      headers: {'Content-Type': 'image/jpeg'},
    );
    if (res.statusCode != 200) throw Exception('이미지 업로드에 실패했어요.');
    return publicUrl;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final body = <String, dynamic>{};
      if (_logoUrl != (widget.currentProfile['logo_url'] as String?)) {
        body['logo_url'] = _logoUrl;
      }
      if (_bannerUrl != (widget.currentProfile['banner_url'] as String?)) {
        body['banner_url'] = _bannerUrl;
      }
      if (_selectedColor != widget.currentProfile['theme_color']) {
        body['theme_color'] = _selectedColor;
      }
      final instaVal = _instagramCtrl.text.trim().isEmpty ? null : _instagramCtrl.text.trim();
      if (instaVal != (widget.currentProfile['instagram_url'] as String?)) {
        body['instagram_url'] = instaVal;
      }
      final ytVal = _youtubeCtrl.text.trim().isEmpty ? null : _youtubeCtrl.text.trim();
      if (ytVal != (widget.currentProfile['youtube_url'] as String?)) {
        body['youtube_url'] = ytVal;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: (bottomInset > 0 ? bottomInset : bottomPad) + 24,
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
            _ImagePickerRow(
              label: '로고 이미지',
              imageUrl: _logoUrl,
              isUploading: _isUploadingLogo,
              onTap: () async {
                setState(() => _isUploadingLogo = true);
                try {
                  final url = await _pickAndUpload('logo');
                  if (url != null) setState(() => _logoUrl = url);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isUploadingLogo = false);
                }
              },
            ),
            const SizedBox(height: 16),
            _ImagePickerRow(
              label: '배너 이미지',
              imageUrl: _bannerUrl,
              isUploading: _isUploadingBanner,
              onTap: () async {
                setState(() => _isUploadingBanner = true);
                try {
                  final url = await _pickAndUpload('banner');
                  if (url != null) setState(() => _bannerUrl = url);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isUploadingBanner = false);
                }
              },
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
            const SizedBox(height: 20),
            // ── SNS 링크 ──────────────────────────────────
            Row(
              children: [
                FaIcon(FontAwesomeIcons.instagram,
                    size: 18, color: const Color(0xFFE1306C)),
                const SizedBox(width: 8),
                Text('Instagram',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _instagramCtrl,
              decoration: const InputDecoration(
                hintText: 'https://www.instagram.com/계정명',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FaIcon(FontAwesomeIcons.youtube,
                    size: 18, color: const Color(0xFFFF0000)),
                const SizedBox(width: 8),
                Text('YouTube',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _youtubeCtrl,
              decoration: const InputDecoration(
                hintText: 'https://www.youtube.com/@채널명',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
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

// ── SNS 아이콘 버튼 ──────────────────────────────────
class _SnsIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final String url;

  const _SnsIconButton({
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
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: FaIcon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

// ── 이미지 선택 행 위젯 ──────────────────────────────
class _ImagePickerRow extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final bool isUploading;
  final VoidCallback onTap;

  const _ImagePickerRow({
    required this.label,
    required this.imageUrl,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: imageUrl != null
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  )
                : Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_outlined, color: Colors.grey),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: isUploading ? null : onTap,
                icon: isUploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined, size: 16),
                label: Text(isUploading ? '업로드 중...' : '사진 선택'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
