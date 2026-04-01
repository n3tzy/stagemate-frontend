import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../utils/file_validator.dart';

// ─── 공지사항 목록 화면 ───────────────────────────────────────────────────────
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  List<dynamic> _notices = [];
  bool _isLoading = false;
  String _role = 'user';
  String _myDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient.getRole(),
        ApiClient.getDisplayName(),
        ApiClient.getNotices(),
      ]);
      setState(() {
        _role = (results[0] as String?) ?? 'user';
        _myDisplayName = (results[1] as String?) ?? '';
        _notices = results[2] as List;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openDetail(dynamic notice) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeDetailScreen(
          noticeId: notice['id'] as int,
          role: _role,
          myDisplayName: _myDisplayName,
          onDeleted: () async {
            await _loadData();
          },
        ),
      ),
    );
    // Refresh list in case notice was deleted
    await _loadData();
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeCreateScreen(
          onCreated: () async {
            await _loadData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          if (_role == 'admin' || _role == 'super_admin')
            FilledButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('작성'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(FontAwesomeIcons.bullhorn,
                          size: MediaQuery.of(context).size.width >= 600 ? 80 : 56,
                          color: colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        '등록된 공지사항이 없어요',
                        style: TextStyle(
                          color: colorScheme.outline,
                          fontSize: MediaQuery.of(context).size.width >= 600 ? 18 : 14,
                        ),
                      ),
                      if (_role == 'admin' || _role == 'super_admin') ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openCreate,
                          icon: const Icon(Icons.add),
                          label: const Text('첫 공지사항 작성하기'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _notices.length,
                    itemBuilder: (context, i) {
                      final notice = _notices[i];
                      final hasMedia = (notice['media_urls'] as List? ?? []).isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${_notices.length - i}',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notice['title'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (hasMedia)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.photo_library_outlined,
                                      size: 14, color: colorScheme.outline),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${notice['author']}  ·  ${notice['created_at']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDetail(notice),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── 공지사항 상세 화면 (풀스크린) ────────────────────────────────────────────
class NoticeDetailScreen extends StatefulWidget {
  final int noticeId;
  final String role;
  final String myDisplayName;
  final Future<void> Function() onDeleted;

  const NoticeDetailScreen({
    super.key,
    required this.noticeId,
    required this.role,
    required this.myDisplayName,
    required this.onDeleted,
  });

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  Map<String, dynamic>? _notice;
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _submitting = false;
  final _ctrl = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_notice == null) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.getNotice(widget.noticeId),
        ApiClient.getComments(widget.noticeId),
      ]);
      if (mounted) {
        setState(() {
          _notice = results[0] as Map<String, dynamic>;
          _comments = results[1] as List<dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.createComment(widget.noticeId, text);
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      await ApiClient.deleteComment(widget.noticeId, commentId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _deleteNotice() async {
    final canDelete = widget.role == 'admin' || widget.role == 'super_admin';
    if (!canDelete) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공지사항 삭제'),
        content: const Text('이 공지사항을 삭제할까요?\n댓글도 함께 삭제됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.deleteNotice(widget.noticeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제되었습니다.')),
      );
      await widget.onDeleted();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _downloadMedia(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('다운로드 중...'),
      duration: Duration(seconds: 60),
    ));
    try {
      final response = await http.get(Uri.parse(url));
      final ext = url.split('.').last.split('?').first.toLowerCase();
      final isVideo = ['mp4', 'mov', 'webm', 'avi'].contains(ext);
      final ts = DateTime.now().millisecondsSinceEpoch;

      if (isVideo) {
        final tempFile = File('${Directory.systemTemp.path}/dl_$ts.$ext');
        await tempFile.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(tempFile.path);
        await tempFile.delete();
      } else {
        await Gal.putImageBytes(response.bodyBytes);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('갤러리에 저장되었습니다!'),
        backgroundColor: Colors.green,
      ));
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('다운로드 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canDelete = widget.role == 'admin' || widget.role == 'super_admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '새로고침',
          ),
          if (canDelete)
            IconButton(
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: _loading ? null : _deleteNotice,
              tooltip: '공지 삭제',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        // 제목 + 작성자
                        Container(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _notice!['title'] as String? ?? '',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_notice!['author'] as String? ?? ''}  ·  ${_notice!['created_at'] as String? ?? ''}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // 본문
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Text(
                            _notice!['content'] as String? ?? '',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                          ),
                        ),
                        // 미디어 (있을 때만)
                        if ((_notice!['media_urls'] as List? ?? []).isNotEmpty) ...[
                          SizedBox(
                            height: 160,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              itemCount: (_notice!['media_urls'] as List).length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (_, i) {
                                final url = (_notice!['media_urls'] as List).cast<String>()[i];
                                final ext = url.split('.').last.split('?').first.toLowerCase();
                                final isVideo = ['mp4', 'mov', 'webm', 'avi'].contains(ext);
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: isVideo
                                          ? Container(
                                              width: 160,
                                              height: 160,
                                              color: Colors.black87,
                                              child: const Icon(Icons.play_circle_fill,
                                                  color: Colors.white, size: 48),
                                            )
                                          : Image.network(url,
                                              height: 160, width: 160, fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      right: 4,
                                      bottom: 4,
                                      child: GestureDetector(
                                        onTap: () => _downloadMedia(url),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Icon(Icons.download,
                                              color: Colors.white, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Divider(color: colorScheme.outlineVariant),
                        // 댓글 헤더
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Text(
                            '댓글 ${_comments.length}개',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.outline,
                                ),
                          ),
                        ),
                        // 댓글 목록
                        if (_comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('첫 댓글을 남겨보세요!',
                                  style: TextStyle(color: colorScheme.outline)),
                            ),
                          )
                        else
                          ...List.generate(_comments.length, (i) {
                            final c = _comments[i];
                            final isMine = c['author'] == widget.myDisplayName;
                            final canDeleteComment = isMine || canDelete;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: colorScheme.secondaryContainer,
                                    child: Text(
                                      (c['author'] as String? ?? '?').isNotEmpty
                                          ? (c['author'] as String)[0]
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              c['author'] ?? '',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              c['created_at'] ?? '',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(color: colorScheme.outline),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(c['content'] ?? '',
                                            style: Theme.of(context).textTheme.bodyMedium),
                                      ],
                                    ),
                                  ),
                                  if (canDeleteComment)
                                    GestureDetector(
                                      onTap: () => _deleteComment(c['id'] as int),
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 4, top: 2),
                                        child: Icon(Icons.close,
                                            size: 16, color: colorScheme.outline),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
            ),
          ),
          // 댓글 입력창
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            padding: EdgeInsets.fromLTRB(
              16, 8, 16,
              8 + (MediaQuery.of(context).viewInsets.bottom > 0
                  ? 0
                  : MediaQuery.of(context).viewPadding.bottom),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: '댓글을 입력하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                _submitting
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(10),
                          minimumSize: const Size(40, 40),
                        ),
                        child: const Icon(Icons.send, size: 18),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 공지사항 작성 화면 (풀스크린) ────────────────────────────────────────────
class NoticeCreateScreen extends StatefulWidget {
  final Future<void> Function() onCreated;

  const NoticeCreateScreen({super.key, required this.onCreated});

  @override
  State<NoticeCreateScreen> createState() => _NoticeCreateScreenState();
}

class _NoticeCreateScreenState extends State<NoticeCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _picker = ImagePicker();
  List<XFile> _selectedFiles = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (_selectedFiles.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('미디어는 최대 5개까지 첨부할 수 있어요.')),
      );
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('사진 촬영'),
              onTap: () => Navigator.pop(ctx, 'camera_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('영상 촬영'),
              onTap: () => Navigator.pop(ctx, 'camera_video'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    try {
      if (choice == 'gallery') {
        final files = await _picker.pickMultipleMedia();
        if (files.isNotEmpty) {
          setState(() {
            _selectedFiles = [..._selectedFiles, ...files].take(5).toList();
          });
        }
      } else if (choice == 'camera_photo') {
        final file = await _picker.pickImage(source: ImageSource.camera);
        if (file != null) {
          setState(() {
            _selectedFiles = [..._selectedFiles, file].take(5).toList();
          });
        }
      } else if (choice == 'camera_video') {
        final file = await _picker.pickVideo(source: ImageSource.camera);
        if (file != null) {
          setState(() {
            _selectedFiles = [..._selectedFiles, file].take(5).toList();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  static const _extToMime = <String, String>{
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.webm': 'video/webm',
  };

  static const _maxImageBytes = 30 * 1024 * 1024;
  static const _maxVideoBytes = 1536 * 1024 * 1024;

  Future<bool> _uploadFile(String uploadUrl, List<int> bytes, String contentType) async {
    try {
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: bytes,
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return [];
    final urls = <String>[];
    for (final file in _selectedFiles) {
      try {
        final filename = file.name;
        final lower = filename.toLowerCase();
        final dotPos = lower.lastIndexOf('.');
        final ext = dotPos != -1 ? lower.substring(dotPos) : '';
        final contentType = _extToMime[ext];
        if (contentType == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('지원하지 않는 파일 형식이에요: $filename')),
            );
          }
          continue;
        }

        final isVideo = contentType.startsWith('video/');
        final maxBytes = isVideo ? _maxVideoBytes : _maxImageBytes;
        final fileSize = await File(file.path).length();
        if (fileSize > maxBytes) {
          final limitMb = maxBytes ~/ (1024 * 1024);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('파일이 너무 커요. 최대 ${limitMb}MB까지 업로드할 수 있어요.')),
            );
          }
          continue;
        }

        final presigned = await ApiClient.getPresignedUrl(filename, contentType);
        final uploadUrl = presigned['upload_url'] as String;
        final publicUrl = presigned['public_url'] as String;

        final bytes = await File(file.path).readAsBytes();

        final validation = isVideo
            ? FileValidator.validateVideoByExtension(bytes, ext)
            : FileValidator.validateImageByExtension(bytes, ext);
        if (!validation.isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(validation.error ?? '파일 검증 실패: $filename')),
            );
          }
          continue;
        }

        final success = await _uploadFile(uploadUrl, bytes, contentType);
        if (success) urls.add(publicUrl);
      } catch (_) {
        // 개별 파일 업로드 실패 시 건너뜀
      }
    }
    return urls;
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      List<String> mediaUrls = [];
      if (_selectedFiles.isNotEmpty) {
        try {
          mediaUrls = await _uploadFiles();
        } catch (_) {
          // 업로드 실패 시 텍스트만 등록
        }
      }

      final result = await ApiClient.createNotice(
        title: title,
        content: content,
        mediaUrls: mediaUrls,
      );

      if (mounted && result.containsKey('id')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공지사항이 등록되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        await widget.onCreated();
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: const Text('공지사항 작성'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('등록', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 2026 봄 공연 무대 순서 확정',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            // 내용
            TextField(
              controller: _contentCtrl,
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '공지 내용을 입력하세요',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 10,
              maxLength: 5000,
            ),
            const SizedBox(height: 12),
            // 미디어 첨부
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickMedia,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('사진/영상 추가'),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedFiles.length}/5',
                  style: TextStyle(color: colorScheme.outline, fontSize: 12),
                ),
              ],
            ),
            if (_selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final name = _selectedFiles[i].name.toLowerCase();
                    final isVid =
                        name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.avi');
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: isVid
                              ? Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.black87,
                                  child: const Icon(Icons.play_circle_fill,
                                      color: Colors.white, size: 40),
                                )
                              : Image.file(
                                  File(_selectedFiles[i].path),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedFiles.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
