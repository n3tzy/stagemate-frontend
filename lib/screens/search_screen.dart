import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../api/api_client.dart';
import 'feed_screen.dart' show FeedUserAvatar;
import 'comments_screen.dart';

class SearchScreen extends StatefulWidget {
  final int myUserId;
  const SearchScreen({super.key, required this.myUserId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final TabController _tabController;
  Timer? _debounce;

  List<dynamic> _results = [];
  bool _isLoading = false;
  bool _searched = false;
  bool _hasError = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) _runSearch();
      });
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _isLoading = false;
        _hasError = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    final isGlobal = _tabController.index == 1;
    final generation = ++_searchGeneration;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _searched = true;
    });

    try {
      final results = await ApiClient.searchPosts(q: q, isGlobal: isGlobal);
      if (generation != _searchGeneration) return;
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (generation != _searchGeneration) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 중 오류가 발생했습니다.')),
        );
      }
    }
  }

  Future<void> _openPost(dynamic post) async {
    final myDisplayName = await ApiClient.getDisplayName() ?? '';
    final role = await ApiClient.getRole() ?? 'member';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          post: post,
          myDisplayName: myDisplayName,
          myUserId: widget.myUserId,
          role: role,
          onChanged: _runSearch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '게시글 검색...',
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  )
                : null,
          ),
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runSearch(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '우리 동아리'),
            Tab(text: '전체 동아리'),
          ],
        ),
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('검색 중 오류가 발생했습니다.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _runSearch,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.magnifyingGlass,
                size: 48, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text('검색어를 2글자 이상 입력해주세요.',
                style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('검색 결과가 없어요.',
            style: TextStyle(color: colorScheme.outline)),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) => _buildCard(_results[i]),
    );
  }

  Widget _buildCard(dynamic post) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaUrls = (post['media_urls'] as List?) ?? [];
    final isAnonymous = post['is_anonymous'] as bool? ?? false;

    const imgExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    final thumbUrl = mediaUrls
        .cast<String>()
        .firstWhere(
          (url) => imgExts.any((ext) => url.toLowerCase().contains(ext)),
          orElse: () => '',
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPost(post),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FeedUserAvatar(
                          name: isAnonymous
                              ? '익명'
                              : (post['author'] as String? ?? '?'),
                          avatarUrl: isAnonymous
                              ? null
                              : (post['author_avatar'] as String?),
                          radius: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isAnonymous
                              ? '익명'
                              : (post['author'] as String? ?? ''),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          post['created_at'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post['content'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.favorite_outline,
                            size: 14, color: colorScheme.outline),
                        const SizedBox(width: 3),
                        Text('${post['like_count'] ?? 0}',
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline)),
                        const SizedBox(width: 12),
                        Icon(Icons.comment_outlined,
                            size: 14, color: colorScheme.outline),
                        const SizedBox(width: 3),
                        Text('${post['comment_count'] ?? 0}',
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline)),
                      ],
                    ),
                  ],
                ),
              ),
              if (thumbUrl.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumbUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
