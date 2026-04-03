import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../api/api_client.dart';
import '../utils/file_validator.dart';
import '../widgets/youtube_card.dart';

class PostCreateScreen extends StatefulWidget {
  final bool isGlobal;

  const PostCreateScreen({super.key, required this.isGlobal});

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final _contentCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _picker = ImagePicker();
  List<XFile> _selectedFiles = [];
  bool _isSubmitting = false;
  bool _isGlobal = false;
  bool _isAnonymous = false;
  bool _showYoutubeField = false;

  @override
  void initState() {
    super.initState();
    _isGlobal = widget.isGlobal;
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _youtubeCtrl.dispose();
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

  // 허용 확장자 → MIME 타입 매핑 (서버 화이트리스트와 동일하게 유지)
  static const _extToMime = <String, String>{
    '.jpg':  'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png':  'image/png',
    '.gif':  'image/gif',
    '.webp': 'image/webp',
    '.mp4':  'video/mp4',
    '.mov':  'video/quicktime',
    '.webm': 'video/webm',
  };

  static const _maxImageBytes = 30 * 1024 * 1024;        // 30 MB
  static const _maxVideoBytes = 1536 * 1024 * 1024;      // 1.5 GB

  Future<List<String>> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return [];
    final urls = <String>[];
    for (final file in _selectedFiles) {
      try {
        final filename = file.name;
        final lower = filename.toLowerCase();
        final dotPos = lower.lastIndexOf('.');
        final ext = dotPos != -1 ? lower.substring(dotPos) : '';

        // 확장자 화이트리스트 검사
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

        // 파일 크기 사전 검사
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

        // 매직 바이트 + 악성 스크립트 시그니처 검증
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
        if (success) {
          urls.add(publicUrl);
        }
      } catch (_) {
        // 개별 파일 업로드 실패 시 건너뜀
      }
    }
    return urls;
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해주세요.')),
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
          // R2 미설정이면 텍스트만 게시
        }
      }

      await ApiClient.createPost(
        content: content,
        mediaUrls: mediaUrls,
        isGlobal: _isGlobal,
        isAnonymous: _isAnonymous,
        youtubeUrl: _youtubeCtrl.text.trim().isEmpty
            ? null
            : _youtubeCtrl.text.trim(),
      );

      if (mounted) Navigator.pop(context, _isGlobal);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
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
        title: const Text('게시글 작성'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '게시',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 채널 선택
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.public),
                        const SizedBox(width: 12),
                        const Text('전체 커뮤니티에 공개'),
                        const Spacer(),
                        Switch(
                          value: _isGlobal,
                          onChanged: (v) => setState(() {
                            _isGlobal = v;
                            _isAnonymous = v;
                          }),
                        ),
                      ],
                    ),
                  ),
                  if (_isGlobal) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_off_outlined),
                          const SizedBox(width: 12),
                          const Text('익명으로 게시'),
                          const Spacer(),
                          Switch(
                            value: _isAnonymous,
                            onChanged: (v) => setState(() => _isAnonymous = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 내용 입력
            TextField(
              controller: _contentCtrl,
              style: const TextStyle(fontFamily: 'AritaBuri'),
              maxLines: 10,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: '무슨 생각을 하고 있나요?',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            // 커뮤니티 이용 안내
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '성희롱·음란물, 과도한 욕설·비방이 포함된 게시글은 신고되거나 삭제 처리될 수 있어요.',
                      style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer, height: 1.5),
                    ),
                  ),
                ],
              ),
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.ondemand_video, color: Colors.red),
                  tooltip: 'YouTube 링크',
                  onPressed: () => setState(() => _showYoutubeField = !_showYoutubeField),
                ),
              ],
            ),
            if (_showYoutubeField) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _youtubeCtrl,
                decoration: const InputDecoration(
                  labelText: 'YouTube URL',
                  prefixIcon: Icon(Icons.link, color: Colors.red),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_youtubeCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                YouTubeCard(youtubeUrl: _youtubeCtrl.text.trim()),
              ],
            ],
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
                    final isVid = name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.avi');
                    return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isVid
                            ? Container(
                                width: 100,
                                height: 100,
                                color: Colors.black87,
                                child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
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
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );},
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
