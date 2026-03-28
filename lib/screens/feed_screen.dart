import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../api/api_client.dart';
import 'post_create_screen.dart';
import 'club_profile_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _clubPosts = [];
  List<dynamic> _globalPosts = [];
  List<dynamic> _hotClubs = [];
  bool _isLoading = false;
  String _myDisplayName = '';
  String _role = 'user';
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient.getPosts(isGlobal: false),
        ApiClient.getPosts(isGlobal: true),
        ApiClient.getHotClubs(),
        ApiClient.getDisplayName(),
        ApiClient.getRole(),
        ApiClient.getUserId(),
      ]);
      setState(() {
        _clubPosts = results[0] as List;
        _globalPosts = results[1] as List;
        _hotClubs = results[2] as List;
        _myDisplayName = (results[3] as String?) ?? '';
        _role = (results[4] as String?) ?? 'user';
        _myUserId = results[5] as int?;
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

  Future<void> _toggleLike(dynamic post, bool isGlobal) async {
    try {
      final result = await ApiClient.togglePostLike(post['id']);
      setState(() {
        final list = isGlobal ? _globalPosts : _clubPosts;
        final idx = list.indexWhere((p) => p['id'] == post['id']);
        if (idx >= 0) {
          list[idx] = {
            ...list[idx],
            'my_liked': result['liked'],
            'like_count': result['like_count'],
          };
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _deletePost(int postId, bool isGlobal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('이 게시글을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.deletePost(postId);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  void _showComments(dynamic post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CommentsSheet(
        post: post,
        myDisplayName: _myDisplayName,
        myUserId: _myUserId,
        role: _role,
        onChanged: _loadAll,
      ),
    );
  }

  // ── 게시글 수정 다이얼로그 ─────────────────────────
  Future<void> _showEditPostDialog(dynamic post, bool isGlobal) async {
    final ctrl = TextEditingController(text: post['content'] as String? ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 수정'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != true) return;
    try {
      await ApiClient.updatePost(post['id'], ctrl.text.trim());
      await _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  // ── 신고 다이얼로그 ──────────────────────────────
  Future<void> _showReportDialog({required int postId, int? commentId}) async {
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
      if (commentId != null) {
        await ApiClient.reportPostComment(postId, commentId, result);
      } else {
        await ApiClient.reportPost(postId, result);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수됐어요.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  // ── 게시글 홍보(부스트) ──────────────────────────
  Future<void> _boostPost(dynamic post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 홍보'),
        content: const Text(
          '홍보 크레딧 1개를 사용해 이 게시글을 전체 채널 상단에 24시간 노출합니다.\n계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('홍보하기'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.boostPost(post['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('홍보가 시작됐습니다! 🚀'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildPostCard(dynamic post, bool isGlobal) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMyPost = (post['author_id'] as int?) == _myUserId;
    final mediaUrls = (post['media_urls'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showComments(post),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _UserAvatar(
                    name: post['author'] as String? ?? '?',
                    avatarUrl: post['author_avatar'] as String?,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post['author'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          post['created_at'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 18, color: colorScheme.outline),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onSelected: (v) {
                      if (v == 'edit') _showEditPostDialog(post, isGlobal);
                      if (v == 'delete') _deletePost(post['id'], isGlobal);
                      if (v == 'report') _showReportDialog(postId: post['id']);
                      if (v == 'boost') _boostPost(post);
                    },
                    itemBuilder: (_) => [
                      if (isMyPost) ...[
                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('수정')])),
                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: colorScheme.error), const SizedBox(width: 8), Text('삭제', style: TextStyle(color: colorScheme.error))])),
                      ] else ...[
                        const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18), SizedBox(width: 8), Text('신고')])),
                      ],
                      if (isGlobal && _role == 'super_admin' && !(post['is_boosted'] as bool? ?? false))
                        const PopupMenuItem(value: 'boost', child: Row(children: [Icon(Icons.rocket_launch, size: 18, color: Colors.orange), SizedBox(width: 8), Text('홍보하기')])),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (post['is_boosted'] as bool? ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rocket_launch, size: 12, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              '홍보 중',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                post['content'] ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              if (mediaUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: mediaUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => _MediaThumbnail(
                      urls: mediaUrls.cast<String>(),
                      index: i,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _toggleLike(post, isGlobal),
                    child: Row(
                      children: [
                        Icon(
                          (post['my_liked'] as bool? ?? false)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                          color: (post['my_liked'] as bool? ?? false)
                              ? Colors.red
                              : colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post['like_count'] ?? 0}',
                          style: TextStyle(fontSize: 13, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.chat_bubble_outline, size: 16, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '${post['comment_count'] ?? 0}',
                    style: TextStyle(fontSize: 13, color: colorScheme.outline),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.visibility_outlined, size: 16, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '${post['view_count'] ?? 0}',
                    style: TextStyle(fontSize: 13, color: colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostList(List<dynamic> posts, bool isGlobal) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: CustomScrollView(
        slivers: [
          if (isGlobal && _hotClubs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.local_fire_department, color: Colors.orange),
                    title: const Text(
                      '이번 주 핫한 동아리',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    initiallyExpanded: false,
                    children: _hotClubs
                        .map<Widget>(
                          (club) => ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: _rankColor(club['rank']),
                              child: Text(
                                '${club['rank']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(club['club_name'] ?? ''),
                            trailing: Text(
                              '${club['score']}점',
                              style: const TextStyle(fontSize: 12),
                            ),
                            dense: true,
                            onTap: club['club_id'] != null
                                ? () => showClubProfile(
                                      context,
                                      club['club_id'] as int,
                                      isOwner: false,
                                    )
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          if (posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dynamic_feed,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '아직 게시글이 없어요',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _buildPostCard(posts[i], isGlobal),
                childCount: posts.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.blueGrey.shade400;
      case 3:
        return Colors.brown.shade400;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGlobal = _tabController.index == 1;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: const Text('피드'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '우리 동아리'),
            Tab(text: '전체 커뮤니티'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostList(_clubPosts, false),
          _buildPostList(_globalPosts, true),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => PostCreateScreen(isGlobal: isGlobal),
            ),
          );
          if (result != null) {
            await _loadAll();
            // 작성한 게시글 탭으로 이동 (true=전체커뮤니티, false=우리동아리)
            _tabController.animateTo(result ? 1 : 0);
          }
        },
        tooltip: '게시글 작성',
        child: const Icon(Icons.edit),
      ),
    );
  }
}

// ── 댓글 바텀시트 ────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final dynamic post;
  final String myDisplayName;
  final int? myUserId;
  final String role;
  final VoidCallback onChanged;

  const _CommentsSheet({
    required this.post,
    required this.myDisplayName,
    this.myUserId,
    required this.role,
    required this.onChanged,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _submitting = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final comments = await ApiClient.getPostComments(widget.post['id']);
      setState(() => _comments = comments);
    } catch (_) {
      // 댓글 로드 실패 시 무시
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.createPostComment(widget.post['id'], text);
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
      await ApiClient.deletePostComment(widget.post['id'], commentId);
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
      await ApiClient.updatePostComment(widget.post['id'], comment['id'], ctrl.text.trim());
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
      await ApiClient.reportPostComment(widget.post['id'], commentId, result);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수됐어요.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 게시글 전체 내용
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _UserAvatar(
                      name: widget.post['author'] as String? ?? '?',
                      avatarUrl: widget.post['author_avatar'] as String?,
                      radius: 16,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post['author'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          widget.post['created_at'] ?? '',
                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.post['content'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
                if ((widget.post['media_urls'] as List? ?? []).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: (widget.post['media_urls'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => _MediaThumbnail(
                        urls: (widget.post['media_urls'] as List).cast<String>(),
                        index: i,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('댓글', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.outline, fontSize: 13)),
          ),
          // 댓글 목록
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? Center(
                        child: Text(
                          '첫 댓글을 남겨보세요!',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final isMine = (c['author_id'] as int?) == widget.myUserId;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _UserAvatar(
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
                                      const SizedBox(height: 2),
                                      Text(
                                        c['content'] ?? '',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, size: 16, color: colorScheme.outline),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onSelected: (v) {
                                    if (v == 'edit') _showEditCommentDialog(c);
                                    if (v == 'delete') _delete(c['id']);
                                    if (v == 'report') _showReportCommentDialog(c['id']);
                                  },
                                  itemBuilder: (_) => [
                                    if (isMine) ...[
                                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('수정')])),
                                      PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: colorScheme.error), SizedBox(width: 8), Text('삭제', style: TextStyle(color: colorScheme.error))])),
                                    ] else ...[
                                      const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18), SizedBox(width: 8), Text('신고')])),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          // 댓글 입력
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
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
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: '댓글을 입력하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
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
          ),
        ],
      ),
    );
  }
}

// ── 미디어 썸네일 (사진/영상 공통) ────────────────────
class _MediaThumbnail extends StatefulWidget {
  final List<String> urls;
  final int index;
  final double size;

  const _MediaThumbnail({
    required this.urls,
    required this.index,
    this.size = 160,
  });

  static bool isVideo(String u) {
    final l = u.toLowerCase();
    return l.contains('.mp4') || l.contains('.mov') ||
           l.contains('.avi') || l.contains('.webm');
  }

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<_MediaThumbnail> {
  Uint8List? _thumbData;
  bool _thumbError = false;

  String get _url => widget.urls[widget.index];

  @override
  void initState() {
    super.initState();
    if (_MediaThumbnail.isVideo(_url)) _loadThumb();
  }

  Future<void> _loadThumb() async {
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: _url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.size.toInt() * 2,
        quality: 70,
      );
      if (mounted) setState(() => _thumbData = data);
    } catch (_) {
      if (mounted) setState(() => _thumbError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVid = _MediaThumbnail.isVideo(_url);
    final sz = widget.size;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MediaViewerScreen(
            urls: widget.urls,
            initialIndex: widget.index,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: isVid
            ? Stack(
                children: [
                  _thumbData != null
                      ? Image.memory(_thumbData!, width: sz, height: sz, fit: BoxFit.cover)
                      : Container(
                          width: sz, height: sz,
                          color: Colors.black87,
                          child: _thumbError
                              ? const Icon(Icons.videocam, color: Colors.white38, size: 36)
                              : const Center(
                                  child: SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                                  ),
                                ),
                        ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 44),
                    ),
                  ),
                ],
              )
            : Image.network(
                _url,
                width: sz, height: sz,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        width: sz, height: sz,
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  width: sz, height: sz,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
      ),
    );
  }
}

// ── 슬라이드 미디어 뷰어 ──────────────────────────────
class _MediaViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _MediaViewerScreen({required this.urls, required this.initialIndex});

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late final PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        // n / total 표시
        title: widget.urls.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              )
            : null,
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return _MediaThumbnail.isVideo(url)
              ? _VideoPage(url: url, isActive: i == _currentIndex)
              : _PhotoPage(url: url);
        },
      ),
    );
  }
}

// ── 사진 페이지 (핀치 줌) ─────────────────────────────
class _PhotoPage extends StatelessWidget {
  final String url;
  const _PhotoPage({required this.url});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(color: Colors.white)),
          errorBuilder: (_, __, ___) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 64),
              SizedBox(height: 8),
              Text('이미지를 불러올 수 없어요', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 영상 페이지 ───────────────────────────────────────
class _VideoPage extends StatefulWidget {
  final String url;
  final bool isActive;
  const _VideoPage({required this.url, required this.isActive});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        if (widget.isActive) _ctrl.play();
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      widget.isActive ? _ctrl.play() : _ctrl.pause();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text('영상을 불러올 수 없어요', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _ctrl.value.aspectRatio,
          child: VideoPlayer(_ctrl),
        ),
        const SizedBox(height: 8),
        VideoProgressIndicator(
          _ctrl,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.white,
            bufferedColor: Colors.white30,
            backgroundColor: Colors.white12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_ctrl.value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(_fmt(_ctrl.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play(),
          icon: Icon(
            _ctrl.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
            size: 56,
          ),
        ),
      ],
    );
  }
}

// ── 유저 아바타 (프로필 사진 or 이니셜) ──────────────
class _UserAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double radius;

  const _UserAvatar({
    required this.name,
    required this.avatarUrl,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = name.isNotEmpty ? name[0] : '?';
    final hasImage = avatarUrl != null && avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      foregroundImage: hasImage ? NetworkImage(avatarUrl!) : null,
      onForegroundImageError: hasImage ? (_, __) {} : null,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.72,
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
