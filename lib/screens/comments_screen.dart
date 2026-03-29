import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import 'feed_screen.dart' show FeedUserAvatar;

class CommentsScreen extends StatefulWidget {
  final dynamic post;
  final String myDisplayName;
  final int? myUserId;
  final String role;
  final VoidCallback onChanged;

  const CommentsScreen({
    super.key,
    required this.post,
    required this.myDisplayName,
    required this.myUserId,
    required this.role,
    required this.onChanged,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  late Map<String, dynamic> _post;
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _submitting = false;
  final _ctrl = TextEditingController();
  OverlayEntry? _commentMenuOverlay;
  final _scrollController = ScrollController();
  Map<String, dynamic>? _replyingTo;
  final _textFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _post = Map<String, dynamic>.from(widget.post as Map);
    _load();
  }

  @override
  void dispose() {
    _hideCommentMenu();
    _ctrl.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _hideCommentMenu() {
    _commentMenuOverlay?.remove();
    _commentMenuOverlay = null;
  }

  void _showCommentMenu({
    required BuildContext iconContext,
    required dynamic comment,
    required bool isMine,
  }) {
    _hideCommentMenu();
    final renderBox = iconContext.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final colorScheme = Theme.of(context).colorScheme;

    _commentMenuOverlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _hideCommentMenu,
        onVerticalDragStart: (_) => _hideCommentMenu(),
        child: Stack(
          children: [
            Positioned(
              top: offset.dy + size.height,
              right: MediaQuery.of(context).size.width - offset.dx - size.width,
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isMine) ...[
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.reply, size: 18),
                            title: const Text('답글'),
                            onTap: () {
                              _hideCommentMenu();
                              setState(() => _replyingTo = comment as Map<String, dynamic>);
                              FocusScope.of(context).requestFocus(_textFocusNode);
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.edit_outlined, size: 18),
                            title: const Text('수정'),
                            onTap: () {
                              _hideCommentMenu();
                              _showEditCommentDialog(comment);
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                            title: Text('삭제', style: TextStyle(color: colorScheme.error)),
                            onTap: () {
                              _hideCommentMenu();
                              _delete(comment['id']);
                            },
                          ),
                        ] else ...[
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.reply, size: 18),
                            title: const Text('답글'),
                            onTap: () {
                              _hideCommentMenu();
                              setState(() => _replyingTo = comment as Map<String, dynamic>);
                              FocusScope.of(context).requestFocus(_textFocusNode);
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.flag_outlined, size: 18),
                            title: const Text('신고'),
                            onTap: () {
                              _hideCommentMenu();
                              _showReportCommentDialog(comment['id']);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_commentMenuOverlay!);
  }

  Future<void> _load() async {
    if (_comments.isEmpty) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.getPost(_post['id'] as int),
        ApiClient.getPostComments(_post['id'] as int),
      ]);

      final freshPost = results[0] as Map<String, dynamic>;
      final comments = results[1] as List<dynamic>;

      if (mounted) {
        setState(() {
          if (freshPost.containsKey('id')) {
            _post = freshPost;
          }
          _comments = comments;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('불러오기 실패: ${friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final parentId = _replyingTo?['id'] as int?;
      await ApiClient.createPostComment(_post['id'], text, parentId: parentId);
      setState(() => _replyingTo = null);
      _ctrl.clear();
      await _load();
      widget.onChanged();
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

  Future<void> _delete(int commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('이 댓글을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.deletePostComment(_post['id'], commentId);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _showEditCommentDialog(dynamic comment) async {
    final ctrl = TextEditingController(text: comment['content'] as String? ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 수정'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await ApiClient.updatePostComment(_post['id'], comment['id'], ctrl.text.trim());
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showReportCommentDialog(int commentId) async {
    String? selected;
    final reasons = ['성희롱·음란물', '욕설·비방', '스팸·광고', '개인정보 노출', '기타'];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('신고하기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons.map((r) => RadioListTile<String>(
              value: r, groupValue: selected,
              title: Text(r),
              dense: true,
              onChanged: (v) => setState(() => selected = v),
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
              child: const Text('신고'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await ApiClient.reportPostComment(_post['id'], commentId, result);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수됐어요.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  void _showEditPostDialog() {
    final ctrl = TextEditingController(text: _post['content'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 수정'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              try {
                await ApiClient.updatePost(_post['id'] as int, text);
                if (mounted) {
                  _post['content'] = text; // optimistic update
                  setState(() {});
                  Navigator.pop(ctx);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('수정 실패: ${friendlyError(e)}')),
                  );
                }
              }
            },
            child: const Text('수정'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(dynamic comment) async {
    final commentId = comment['id'] as int;
    final wasLiked = comment['is_liked_by_me'] as bool? ?? false;
    final prevCount = comment['like_count'] as int? ?? 0;

    // Optimistic update
    setState(() {
      comment['is_liked_by_me'] = !wasLiked;
      comment['like_count'] = prevCount + (wasLiked ? -1 : 1);
    });
    _recalculateBest();

    try {
      final result = await ApiClient.toggleCommentLike(
        _post['id'] as int,
        commentId,
      );
      if (mounted) {
        setState(() {
          comment['is_liked_by_me'] = result['liked'] as bool;
          comment['like_count'] = result['like_count'] as int;
        });
        _recalculateBest();
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          comment['is_liked_by_me'] = wasLiked;
          comment['like_count'] = prevCount;
        });
        _recalculateBest();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('좋아요 처리 중 오류가 발생했어요.')),
        );
      }
    }
  }

  void _recalculateBest() {
    for (final c in _comments) {
      c['is_best'] = false;
    }
    int maxLikes = 0;
    dynamic bestComment;
    for (final c in _comments) {
      final likes = c['like_count'] as int? ?? 0;
      if (likes > maxLikes) {
        maxLikes = likes;
        bestComment = c;
      }
    }
    if (bestComment != null && maxLikes > 0) {
      bestComment['is_best'] = true;
    }
    setState(() {});
  }

  Future<void> _downloadMedia(BuildContext context, String url) async {
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
        content: Text('갤러리에 저장됐습니다!'),
        backgroundColor: Colors.green,
      ));
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('다운로드 실패')));
    }
  }

  Widget _buildCommentTile(dynamic c, ColorScheme colorScheme) {
    final isMine = (c['author_id'] as int?) == widget.myUserId;
    final isReply = (c['parent_id'] as int?) != null;
    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: isReply ? 48.0 : 16.0,
        right: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FeedUserAvatar(
            name: c['author'] as String? ?? '?',
            avatarUrl: c['author_avatar'] as String?,
            radius: 16,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (c['is_best'] == true) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: Colors.red, width: 2.0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'BEST',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      c['created_at'] ?? '',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  c['content'] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // 좋아요 버튼
          GestureDetector(
            onTap: () => _toggleLike(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (c['is_liked_by_me'] as bool? ?? false)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 16,
                    color: (c['is_liked_by_me'] as bool? ?? false)
                        ? Colors.red
                        : colorScheme.outline,
                  ),
                  if ((c['like_count'] as int? ?? 0) > 0)
                    Text(
                      '${c['like_count']}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Builder(
            builder: (iconContext) => IconButton(
              icon: Icon(Icons.more_vert, size: 16, color: colorScheme.outline),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _showCommentMenu(
                iconContext: iconContext,
                comment: c,
                isMine: isMine,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final post = _post;

    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? '댓글' : '댓글 ${_comments.length}개'),
        actions: [
          if (_post['author_id'] == widget.myUserId)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _showEditPostDialog,
              tooltip: '게시글 수정',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _load();
              },
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 8),
              children: [
                // Post author + timestamp
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      FeedUserAvatar(
                        name: post['author'] as String? ?? '?',
                        avatarUrl: post['author_avatar'] as String?,
                        radius: 16,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post['author'] as String? ?? '알 수 없음',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            post['created_at'] as String? ?? '',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Post content text
                if ((post['content'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      post['content'] as String,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                // Media thumbnails
                if ((post['media_urls'] as List? ?? []).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      itemCount: (post['media_urls'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final url = (post['media_urls'] as List).cast<String>()[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(url, height: 200, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: GestureDetector(
                                onTap: () => _downloadMedia(context, url),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.download, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Divider(color: colorScheme.outlineVariant),
                // Comments header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    '댓글',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
                // Comments list
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '첫 댓글을 남겨보세요!',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ),
                  )
                else
                  ...List.generate(
                    _comments.length,
                    (i) => _buildCommentTile(_comments[i], colorScheme),
                  ),
              ],
            ),
            ),
          ),
          // Comment input — rises above keyboard automatically
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16, 8, 16,
              8 + (MediaQuery.of(context).viewInsets.bottom > 0
                  ? 0
                  : MediaQuery.of(context).viewPadding.bottom),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.reply, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${_replyingTo!['author'] as String? ?? '알 수 없음'}에게 답글',
                          style: TextStyle(fontSize: 12, color: colorScheme.primary),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _replyingTo = null),
                          child: Icon(Icons.close, size: 14, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _textFocusNode,
                        decoration: InputDecoration(
                          hintText: '댓글을 입력하세요...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
