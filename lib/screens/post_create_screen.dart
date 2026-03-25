import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../api/api_client.dart';

class PostCreateScreen extends StatefulWidget {
  final bool isGlobal;

  const PostCreateScreen({super.key, required this.isGlobal});

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final _contentCtrl = TextEditingController();
  final _picker = ImagePicker();
  List<XFile> _selectedFiles = [];
  bool _isSubmitting = false;
  bool _isGlobal = false;

  @override
  void initState() {
    super.initState();
    _isGlobal = widget.isGlobal;
  }

  @override
  void dispose() {
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
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, 'camera'),
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
      } else {
        final file = await _picker.pickImage(source: ImageSource.camera);
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

  Future<List<String>> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return [];
    final urls = <String>[];
    for (final file in _selectedFiles) {
      try {
        final filename = file.name;
        final isVideo = filename.endsWith('.mp4') ||
            filename.endsWith('.mov') ||
            filename.endsWith('.avi');
        final contentType = isVideo ? 'video/mp4' : 'image/jpeg';

        final presigned = await ApiClient.getPresignedUrl(filename, contentType);
        final uploadUrl = presigned['upload_url'] as String;
        final publicUrl = presigned['public_url'] as String;

        final bytes = await File(file.path).readAsBytes();
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
      );

      if (mounted) Navigator.pop(context, true);
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.public),
                    const SizedBox(width: 12),
                    const Text('전체 커뮤니티에 공개'),
                    const Spacer(),
                    Switch(
                      value: _isGlobal,
                      onChanged: (v) => setState(() => _isGlobal = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 내용 입력
            TextField(
              controller: _contentCtrl,
              maxLines: 10,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: '무슨 생각을 하고 있나요?',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
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
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
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
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
