import 'package:flutter/material.dart';
import '../api/api_client.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 공지사항 작성 다이얼로그 (admin만)
  Future<void> _showWriteDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공지사항 작성'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 2026 봄 공연 무대 순서 확정',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    hintText: '공지 내용을 입력하세요',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final content = contentController.text.trim();
              if (title.isEmpty || content.isEmpty) return;

              final result = await ApiClient.createNotice(
                title: title,
                content: content,
              );
              Navigator.pop(dialogContext);

              if (result.containsKey('id')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ 공지사항이 등록됐습니다!'),
                    backgroundColor: Colors.green,
                  ),
                );
                await _loadData();
              }
            },
            child: const Text('등록'),
          ),
        ],
      ),
    );
  }

  // 공지사항 상세 보기
  Future<void> _showDetail(int id) async {
    final notice = await ApiClient.getNotice(id);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => _NoticeDetailDialog(
        notice: notice,
        role: _role,
        myDisplayName: _myDisplayName,
        onDelete: () async {
          await ApiClient.deleteNotice(id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제됐습니다.')),
          );
          await _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📢 공지사항'),
        backgroundColor: colorScheme.primaryContainer,
        // admin / super_admin만 작성 버튼 표시
        actions: [
          if (_role == 'admin' || _role == 'super_admin')
            FilledButton.icon(
              onPressed: _showWriteDialog,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('작성'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      Icon(Icons.campaign,
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
                          onPressed: _showWriteDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('첫 공지사항 작성하기'),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: MediaQuery.of(context).size.width >= 600 ? 24 : 16,
                              vertical: MediaQuery.of(context).size.width >= 600 ? 16 : 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notices.length,
                    itemBuilder: (context, i) {
                      final notice = _notices[i];
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
                          title: Text(
                            notice['title'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${notice['author']}  ·  ${notice['created_at']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showDetail(notice['id']),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── 공지사항 상세 + 댓글 다이얼로그 ───────────────────────────────────────
class _NoticeDetailDialog extends StatefulWidget {
  final Map<String, dynamic> notice;
  final String role;
  final String myDisplayName;
  final Future<void> Function() onDelete;

  const _NoticeDetailDialog({
    required this.notice,
    required this.role,
    required this.myDisplayName,
    required this.onDelete,
  });

  @override
  State<_NoticeDetailDialog> createState() => _NoticeDetailDialogState();
}

class _NoticeDetailDialogState extends State<_NoticeDetailDialog> {
  List<dynamic> _comments = [];
  bool _loadingComments = true;
  bool _submitting = false;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      final comments = await ApiClient.getComments(widget.notice['id']);
      setState(() => _comments = comments);
    } catch (_) {
      // 댓글 로드 실패 시 빈 목록 유지
    } finally {
      setState(() => _loadingComments = false);
    }
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      await ApiClient.createComment(widget.notice['id'], content);
      _commentController.clear();
      await _loadComments();
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
      await ApiClient.deleteComment(widget.notice['id'], commentId);
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canDelete = widget.role == 'admin' || widget.role == 'super_admin';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // ── 헤더 ──────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.notice['title'] ?? '',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.notice['author'] ?? ''}  ·  ${widget.notice['created_at'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 삭제 버튼 (admin/super_admin만)
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: colorScheme.error,
                      tooltip: '공지 삭제',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('공지사항 삭제'),
                            content: const Text('이 공지사항을 삭제할까요?\n댓글도 함께 삭제됩니다.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('취소'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.error,
                                ),
                                child: const Text('삭제'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (!mounted) return;
                          Navigator.pop(context);
                          await widget.onDelete();
                        }
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── 본문 + 댓글 목록 (스크롤 영역) ──────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 공지 본문
                    Text(
                      widget.notice['content'] ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                    const SizedBox(height: 24),

                    // 댓글 구분선
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      '댓글',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 댓글 목록
                    if (_loadingComments)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '아직 댓글이 없어요. 첫 댓글을 남겨보세요!',
                          style: TextStyle(
                            color: colorScheme.outline,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ...(_comments.map((c) {
                        final isMine = c['author'] == widget.myDisplayName;
                        final canDeleteComment = isMine || canDelete;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          c['created_at'] ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colorScheme.outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      c['content'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              if (canDeleteComment)
                                GestureDetector(
                                  onTap: () => _deleteComment(c['id']),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4, top: 2),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList()),
                  ],
                ),
              ),
            ),

            // ── 댓글 입력창 ──────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.of(context).viewInsets.bottom + 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: '댓글을 입력하세요...',
                        hintStyle: TextStyle(color: colorScheme.outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitComment(),
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
                          onPressed: _submitComment,
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
      ),
    );
  }
}
