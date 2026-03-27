import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../api/api_client.dart';
import 'post_create_screen.dart';

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
      ]);
      setState(() {
        _clubPosts = results[0] as List;
        _globalPosts = results[1] as List;
        _hotClubs = results[2] as List;
        _myDisplayName = (results[3] as String?) ?? '';
        _role = (results[4] as String?) ?? 'user';
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
        role: _role,
        onChanged: _loadAll,
      ),
    );
  }

  Widget _buildPostCard(dynamic post, bool isGlobal) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMyPost = post['author'] == _myDisplayName;
    final isAdmin = _role == 'admin' || _role == 'super_admin';
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
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      (post['author'] as String? ?? '?').isNotEmpty
                          ? (post['author'] as String)[0]
                          : '?',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
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
                  if (isMyPost || isAdmin)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      onPressed: () => _deletePost(post['id'], isGlobal),
                      tooltip: '삭제',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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
                    itemBuilder: (_, i) => _MediaThumbnail(url: mediaUrls[i] as String),
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
  final String role;
  final VoidCallback onChanged;

  const _CommentsSheet({
    required this.post,
    required this.myDisplayName,
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAdmin = widget.role == 'admin' || widget.role == 'super_admin';

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
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        (widget.post['author'] as String? ?? '?').isNotEmpty
                            ? (widget.post['author'] as String)[0]
                            : '?',
                        style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
                      ),
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
                        url: (widget.post['media_urls'] as List)[i] as String,
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
                          final isMine = c['author'] == widget.myDisplayName;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
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
                                      const SizedBox(height: 2),
                                      Text(
                                        c['content'] ?? '',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isMine || isAdmin)
                                  GestureDetector(
                                    onTap: () => _delete(c['id']),
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
class _MediaThumbnail extends StatelessWidget {
  final String url;
  final double size;

  const _MediaThumbnail({required this.url, this.size = 160});

  static bool _isVideo(String u) {
    final l = u.toLowerCase();
    return l.contains('.mp4') || l.contains('.mov') ||
           l.contains('.avi') || l.contains('.webm');
  }

  @override
  Widget build(BuildContext context) {
    final video = _isVideo(url);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => video
              ? _VideoPlayerScreen(url: url)
              : _PhotoViewScreen(url: url),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: video
            ? Container(
                width: size,
                height: size,
                color: Colors.black87,
                child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
              )
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        width: size,
                        height: size,
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  width: size,
                  height: size,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
      ),
    );
  }
}

// ── 사진 전체화면 뷰어 ────────────────────────────────
class _PhotoViewScreen extends StatelessWidget {
  final String url;

  const _PhotoViewScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(color: Colors.white),
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
      ),
    );
  }
}

// ── 영상 플레이어 화면 ────────────────────────────────
class _VideoPlayerScreen extends StatefulWidget {
  final String url;

  const _VideoPlayerScreen({required this.url});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
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
        _ctrl.play();
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: _error
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white54, size: 64),
                    SizedBox(height: 12),
                    Text('영상을 불러올 수 없어요', style: TextStyle(color: Colors.white54)),
                  ],
                )
              : !_initialized
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: _ctrl.value.aspectRatio,
                          child: VideoPlayer(_ctrl),
                        ),
                        const SizedBox(height: 8),
                        // 진행 바
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
                        // 시간 표시
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmtDuration(_ctrl.value.position),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                _fmtDuration(_ctrl.value.duration),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // 재생/일시정지
                        IconButton(
                          onPressed: () => _ctrl.value.isPlaying
                              ? _ctrl.pause()
                              : _ctrl.play(),
                          icon: Icon(
                            _ctrl.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
