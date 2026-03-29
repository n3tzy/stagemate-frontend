import 'package:flutter/material.dart';
import '../api/api_client.dart';

class MyActivityScreen extends StatefulWidget {
  const MyActivityScreen({super.key});

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _posts = [];
  List<dynamic> _comments = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deletePost(int postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('삭제하시겠어요? 이 작업은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.deletePost(postId);
      setState(() => _posts.removeWhere((p) => p['id'] == postId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제됐어요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _deleteComment(int postId, int commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('삭제하시겠어요? 이 작업은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.deletePostComment(postId, commentId);
      setState(() => _comments.removeWhere((c) => c['id'] == commentId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제됐어요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.getMyActivity();
      setState(() {
        _posts = (data['posts'] as List?) ?? [];
        _comments = (data['comments'] as List?) ?? [];
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: const Text('내 게시글 · 댓글'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '내 게시글 (${_posts.length})'),
            Tab(text: '내 댓글 (${_comments.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 내 게시글 탭
                _posts.isEmpty
                    ? Center(
                        child: Text(
                          '작성한 게시글이 없어요',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _posts.length,
                          itemBuilder: (_, i) {
                            final p = _posts[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  p['is_global'] == true
                                      ? Icons.public
                                      : Icons.group,
                                  color: colorScheme.primary,
                                ),
                                title: Text(
                                  p['content'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      '${p['created_at'] ?? ''}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.favorite_border, size: 12),
                                    const SizedBox(width: 2),
                                    Text('${p['like_count'] ?? 0}', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chat_bubble_outline, size: 12),
                                    const SizedBox(width: 2),
                                    Text('${p['comment_count'] ?? 0}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deletePost((p['id'] as num).toInt()),
                                  tooltip: '삭제',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                // 내 댓글 탭
                _comments.isEmpty
                    ? Center(
                        child: Text(
                          '작성한 댓글이 없어요',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) {
                            final c = _comments[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.comment_outlined,
                                  color: colorScheme.secondary,
                                ),
                                title: Text(
                                  c['content'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '원글: ${c['post_preview'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    Text(
                                      c['created_at'] ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deleteComment(
                                    (c['post_id'] as num).toInt(),
                                    (c['id'] as num).toInt(),
                                  ),
                                  tooltip: '삭제',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ],
            ),
    );
  }
}
