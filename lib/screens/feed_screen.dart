import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../api/api_client.dart';
import '../widgets/youtube_card.dart';
import 'comments_screen.dart';
import 'post_create_screen.dart';
import 'club_profile_sheet.dart';

class FeedScreen extends StatefulWidget {
  final int? pendingPostId;
  final VoidCallback? onPostIdConsumed;

  const FeedScreen({
    super.key,
    this.pendingPostId,
    this.onPostIdConsumed,
  });

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
  OverlayEntry? _postMenuOverlay;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAll();
    // Deep-link: open specific post on first mount
    if (widget.pendingPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPostById(widget.pendingPostId!),
      );
    }
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingPostId != widget.pendingPostId &&
        widget.pendingPostId != null) {
      _openPostById(widget.pendingPostId!);
    }
  }

  @override
  void dispose() {
    _hidePostMenu();
    _tabController.dispose();
    super.dispose();
  }

  void _hidePostMenu() {
    _postMenuOverlay?.remove();
    _postMenuOverlay = null;
  }

  void _showPostMenu({
    required BuildContext iconContext,
    required dynamic post,
    required bool isMyPost,
    required bool isGlobal,
  }) {
    _hidePostMenu();
    final renderBox = iconContext.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final colorScheme = Theme.of(context).colorScheme;

    _postMenuOverlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _hidePostMenu,
        onVerticalDragStart: (_) => _hidePostMenu(),
        child: Stack(
          children: [
            Positioned(
              top: offset.dy + size.height,
              right: MediaQuery.of(context).size.width - offset.dx - size.width,
              child: GestureDetector(
                onTap: () {}, // prevent tap-through on menu itself
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isMyPost) ...[
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.edit_outlined, size: 18),
                            title: const Text('수정'),
                            onTap: () {
                              _hidePostMenu();
                              _showEditPostDialog(post, isGlobal);
                            },
                          ),
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                            title: Text('삭제', style: TextStyle(color: colorScheme.error)),
                            onTap: () {
                              _hidePostMenu();
                              _deletePost(post['id'], isGlobal);
                            },
                          ),
                        ] else ...[
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.flag_outlined, size: 18),
                            title: const Text('신고'),
                            onTap: () {
                              _hidePostMenu();
                              _showReportDialog(postId: post['id']);
                            },
                          ),
                        ],
                        if (isGlobal && _role == 'super_admin' && !(post['is_boosted'] as bool? ?? false))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.rocket_launch, size: 18, color: Colors.orange),
                            title: const Text('홍보하기', style: TextStyle(color: Colors.orange)),
                            onTap: () {
                              _hidePostMenu();
                              _boostPost(post);
                            },
                          ),
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
    Overlay.of(context).insert(_postMenuOverlay!);
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          post: post,
          myDisplayName: _myDisplayName,
          myUserId: _myUserId,
          role: _role,
          onChanged: _loadAll,
        ),
      ),
    );
  }

  Future<void> _openPostById(int postId) async {
    if (!mounted) return;

    // 1. Check already-loaded posts first (O(n) scan)
    dynamic post;
    try {
      post = _clubPosts.firstWhere((p) => (p['id'] as num?)?.toInt() == postId);
    } catch (_) {
      post = null;
    }
    if (post == null) {
      try {
        post = _globalPosts.firstWhere((p) => (p['id'] as num?)?.toInt() == postId);
      } catch (_) {
        post = null;
      }
    }

    // 2. Fetch from API if not in local list
    if (post == null) {
      try {
        final result = await ApiClient.getPost(postId);
        if (!result.containsKey('id')) {
          // FastAPI 404 → {"detail": "Not found"} — no 'id' key
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('게시글을 찾을 수 없습니다.')),
            );
          }
          return;
        }
        post = result;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('게시글을 찾을 수 없습니다.')),
          );
        }
        return;
      }
    }

    // 3. Signal consumed BEFORE opening sheet (safe: sheet captures local `post`)
    widget.onPostIdConsumed?.call();

    // 4. Open comments sheet after current frame (required — must not call
    //    showModalBottomSheet from initState/didUpdateWidget directly)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showComments(post);
    });
  }

  // ── 게시글 수정 (풀스크린) ─────────────────────────
  Future<void> _showEditPostDialog(dynamic post, bool isGlobal) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PostEditScreen(
          postId: post['id'] as int,
          initialContent: post['content'] as String? ?? '',
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == true) await _loadAll();
  }

  // ── 신고 다이얼로그 ──────────────────────────────
  Future<void> _showReportDialog({required int postId, int? commentId}) async {
    String? selected;
    final etcController = TextEditingController();
    final reasons = ['성희롱·음란물', '욕설·비방', '스팸·광고', '개인정보 노출', '기타'];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('신고하기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...reasons.map((r) => RadioListTile<String>(
                value: r, groupValue: selected,
                title: Text(r),
                dense: true,
                onChanged: (v) => setState(() => selected = v),
              )),
              if (selected == '기타')
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
                  child: TextField(
                    controller: etcController,
                    autofocus: true,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      hintText: '신고 사유를 직접 입력해주세요',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: selected == null ? null : () {
                final reason = selected == '기타' && etcController.text.trim().isNotEmpty
                    ? '기타: ${etcController.text.trim()}'
                    : selected;
                Navigator.pop(ctx, reason);
              },
              child: const Text('신고'),
            ),
          ],
        ),
      ),
    );
    etcController.dispose();
    if (result == null) return;
    try {
      if (commentId != null) {
        await ApiClient.reportPostComment(postId, commentId, result);
      } else {
        await ApiClient.reportPost(postId, result);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수되었어요.'), backgroundColor: Colors.orange),
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
            content: Text('홍보가 시작되었습니다! 🚀'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildPostCard(dynamic post, bool isGlobal) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMyPost = (post['author_id'] as int?) == _myUserId;
    final mediaUrls = (post['media_urls'] as List?) ?? [];
    final youtubeUrl = post['youtube_url'] as String?;

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
                  FeedUserAvatar(
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
                  Builder(
                    builder: (iconContext) => IconButton(
                      icon: Icon(Icons.more_vert, size: 18, color: colorScheme.outline),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _showPostMenu(
                        iconContext: iconContext,
                        post: post,
                        isMyPost: isMyPost,
                        isGlobal: isGlobal,
                      ),
                    ),
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
                    itemBuilder: (_, i) => FeedMediaThumbnail(
                      urls: mediaUrls.cast<String>(),
                      index: i,
                    ),
                  ),
                ),
              ],
              if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: YouTubeCard(youtubeUrl: youtubeUrl),
                ),
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

// ── 미디어 썸네일 (사진/영상 공통) ────────────────────
class FeedMediaThumbnail extends StatefulWidget {
  final List<String> urls;
  final int index;
  final double size;

  const FeedMediaThumbnail({
    super.key,
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
  State<FeedMediaThumbnail> createState() => FeedMediaThumbnailState();
}

class FeedMediaThumbnailState extends State<FeedMediaThumbnail> {
  Uint8List? _thumbData;
  bool _thumbError = false;

  String get _url => widget.urls[widget.index];

  @override
  void initState() {
    super.initState();
    if (FeedMediaThumbnail.isVideo(_url)) _loadThumb();
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
    final isVid = FeedMediaThumbnail.isVideo(_url);
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

  Future<void> _download() async {
    final url = widget.urls[_currentIndex];
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('다운로드 중...'),
      duration: Duration(seconds: 60),
    ));
    try {
      final response = await http.get(Uri.parse(url));
      final ext = url.split('.').last.split('?').first.toLowerCase();
      final isVideo = ['mp4', 'mov', 'webm', 'avi'].contains(ext);
      if (isVideo) {
        final ts = DateTime.now().millisecondsSinceEpoch;
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
      messenger.showSnackBar(const SnackBar(content: Text('다운로드에 실패했어요.')));
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: _download,
            tooltip: '저장',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return FeedMediaThumbnail.isVideo(url)
              ? _VideoPage(url: url, isActive: i == _currentIndex)
              : _PhotoPage(url: url);
        },
      ),
    );
  }
}

// ── 게시글 수정 풀스크린 ─────────────────────────────
class _PostEditScreen extends StatefulWidget {
  final int postId;
  final String initialContent;
  const _PostEditScreen({required this.postId, required this.initialContent});

  @override
  State<_PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<_PostEditScreen> {
  late final TextEditingController _ctrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updatePost(widget.postId, text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글 수정'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('저장'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                maxLength: 2000,
                autofocus: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '내용을 입력하세요...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
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
class FeedUserAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double radius;

  const FeedUserAvatar({
    super.key,
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
