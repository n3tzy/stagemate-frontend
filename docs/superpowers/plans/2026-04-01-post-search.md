# Post Search Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 상단 돋보기 아이콘 → 통합 검색 화면에서 피드 게시글을 실시간 검색 (우리 동아리 / 전체 동아리 탭).

**Architecture:** FastAPI에 `/posts/search` 엔드포인트 추가 → `api_client.dart`에 `searchPosts()` 추가 → 새 `SearchScreen` 위젯 → `home_screen.dart` AppBar에 돋보기 버튼 추가.

**Tech Stack:** FastAPI + SQLAlchemy (ILIKE), Flutter + `font_awesome_flutter`, `http` package.

**Spec:** `docs/superpowers/specs/2026-04-01-post-search-design.md`

---

## File Map

| 파일 | 변경 유형 | 역할 |
|------|-----------|------|
| `backend/main.py` | Modify | GET /posts/search 엔드포인트 추가 |
| `lib/api/api_client.dart` | Modify | `searchPosts()` static method 추가 |
| `lib/screens/search_screen.dart` | **Create** | 검색 UI (TextField + 탭 + 결과 카드) |
| `lib/screens/home_screen.dart` | Modify | AppBar에 돋보기 IconButton 추가 |

---

## Chunk 1: 백엔드 검색 엔드포인트

### Task 1: GET /posts/search 엔드포인트 추가

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py` (기존 `get_posts` 함수 아래, 약 line 1506 이후)

- [ ] **Step 1: `main.py`에서 `get_posts` 함수 끝 위치 확인**

  `get_posts` 함수(line ~1445)의 `return result` 직후, 다음 `@app.get("/posts/{post_id}")` 데코레이터 바로 앞에 삽입.

- [ ] **Step 2: 검색 엔드포인트 추가**

  다음 코드를 `@app.get("/posts/{post_id}")` 데코레이터 바로 앞에 삽입:

  ```python
  @app.get("/posts/search")
  @limiter.limit("30/minute")
  def search_posts(
      request: Request,
      q: str = "",
      is_global: bool = False,
      db: Session = Depends(get_db),
      member: db_models.ClubMember = Depends(require_any_member),
  ):
      """게시글 검색 (content ILIKE, 우리동아리/전체동아리)"""
      q_stripped = q.strip()
      if len(q_stripped) < 2:
          return []

      # % 와 _ 와일드카드 이스케이프 (사용자 입력 보호)
      q_safe = q_stripped.replace('%', r'\%').replace('_', r'\_')
      q_like = f"%{q_safe}%"

      query = db.query(db_models.Post).filter(
          db_models.Post.content.ilike(q_like)
      )

      if is_global:
          # 전체 동아리: is_global=True인 게시글은 모든 인증 멤버에게 공개 (의도된 동작)
          query = query.filter(db_models.Post.is_global == True)
      else:
          # 우리 동아리: 요청자의 club_id로 필터
          query = query.filter(
              db_models.Post.is_global == False,
              db_models.Post.club_id == member.club_id,
          )

      posts = query.order_by(desc(db_models.Post.created_at)).limit(20).all()

      result = []
      for p in posts:
          author = db.query(db_models.User).filter(db_models.User.id == p.author_id).first()
          like_count = db.query(db_models.PostLike).filter(db_models.PostLike.post_id == p.id).count()
          comment_count = db.query(db_models.PostComment).filter(db_models.PostComment.post_id == p.id).count()

          if p.is_global:
              display_author = p.post_author_name or "알 수 없음"
          else:
              display_author = p.post_author_name or (author.display_name if author else "탈퇴한 사용자")

          # 익명 글이면 author 이름/아바타 null (author_id는 항상 반환 — "내 글" 판단에 필요)
          author_name = None if p.is_anonymous else display_author
          author_avatar = None if p.is_anonymous else (author.avatar_url if author else None)

          result.append({
              "id": p.id,
              "author": author_name,
              "author_id": p.author_id,
              "author_avatar": author_avatar or "",
              "is_anonymous": p.is_anonymous or False,
              "content": p.content,
              "media_urls": p.media_urls or [],
              "like_count": like_count,
              "comment_count": comment_count,
              "view_count": p.view_count or 0,
              "is_global": p.is_global,
              "club_id": p.club_id,
              "created_at": p.created_at.strftime("%Y.%m.%d %H:%M") if p.created_at else "",
          })
      return result
  ```

  **주의:** `/posts/search` 라우트는 반드시 `/posts/{post_id}` 라우트보다 **앞에** 위치해야 함. 순서가 바뀌면 FastAPI가 "search"를 post_id로 해석해 404 발생.

- [ ] **Step 3: 로컬 테스트 (백엔드 실행 가능한 경우)**

  ```bash
  # Railway는 자동 배포이므로, 코드 푸시 후 확인
  # 로컬 테스트 시:
  curl "http://localhost:8000/posts/search?q=안녕&is_global=false" \
    -H "Authorization: Bearer <token>" \
    -H "X-Club-Id: 1"
  # 기대 결과: [] 또는 게시글 배열
  ```

- [ ] **Step 4: 깃헙 푸시 (Railway 자동 배포)**

  ```bash
  cd C:/projects/performance-manager
  git add backend/main.py
  git commit -m "feat: POST /posts/search 엔드포인트 추가"
  git push
  ```

  Railway 대시보드에서 배포 완료 확인 후 다음 단계로 진행.

---

## Chunk 2: Flutter — API 클라이언트 + SearchScreen

### Task 2: api_client.dart에 searchPosts() 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`
  - `getPosts()` 메서드(line ~570) 바로 아래에 삽입

- [ ] **Step 1: `searchPosts` 메서드 추가**

  `getPosts` 메서드 끝 `}` 바로 뒤에 삽입:

  ```dart
  static Future<List<dynamic>> searchPosts({
    required String q,
    required bool isGlobal,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/posts/search?q=${Uri.encodeQueryComponent(q)}&is_global=$isGlobal',
    );
    final response = await http.get(
      uri,
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }
  ```

### Task 3: search_screen.dart 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/search_screen.dart`

- [ ] **Step 1: 파일 생성**

  ```dart
  import 'dart:async';
  import 'package:flutter/material.dart';
  import 'package:font_awesome_flutter/font_awesome_flutter.dart';
  import '../api/api_client.dart';
  import 'feed_screen.dart'; // FeedUserAvatar, _showComments 재사용을 위해

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

    @override
    void initState() {
      super.initState();
      _tabController = TabController(length: 2, vsync: this)
        ..addListener(() {
          if (!_tabController.indexIsChanging) _runSearch();
        });
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

      setState(() {
        _isLoading = true;
        _hasError = false;
        _searched = true;
      });

      try {
        final results = await ApiClient.searchPosts(q: q, isGlobal: isGlobal);
        if (mounted) {
          setState(() {
            _results = results;
            _isLoading = false;
          });
        }
      } catch (e) {
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
      final isMyPost = (post['author_id'] as int?) == widget.myUserId;
      final mediaUrls = (post['media_urls'] as List?) ?? [];
      final isAnonymous = post['is_anonymous'] as bool? ?? false;

      // 이미지 썸네일: jpg/jpeg/png/gif/webp 중 첫 번째 URL
      const _imgExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
      final thumbUrl = mediaUrls
          .cast<String>()
          .firstWhere(
            (url) => _imgExts.any((ext) => url.toLowerCase().contains(ext)),
            orElse: () => '',
          );

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // 게시글 상세(댓글) 화면으로 이동 — feed_screen의 PostDetailScreen 재사용
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  myUserId: widget.myUserId,
                  isMyPost: isMyPost,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 작성자 행
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
                      // 본문
                      Text(
                        post['content'] as String? ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      // 좋아요 + 댓글 수
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
                // 이미지 썸네일 (있을 경우)
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
  ```

  **주의:** `FeedUserAvatar`와 `PostDetailScreen`은 `feed_screen.dart`에 정의되어 있음. import 경로 확인 필요. 만약 `PostDetailScreen`이 `feed_screen.dart` 내부의 private class라면 별도 처리 필요 (아래 Task 4 참고).

- [ ] **Step 2: feed_screen.dart에서 공개 export 확인**

  ```bash
  grep -n "class FeedUserAvatar\|class PostDetailScreen\|class _PostDetailScreen" \
    C:/projects/performance_manager/lib/screens/feed_screen.dart
  ```

  - `FeedUserAvatar`가 public class → import 가능
  - `PostDetailScreen`이 public class → import 가능
  - `_PostDetailScreen` (private) → `_showComments` 방식으로 대체 필요

  **만약 PostDetailScreen이 private이라면:** `onTap`을 다음으로 교체:
  ```dart
  onTap: () async {
    final postId = post['id'] as int;
    // 피드 상세 화면 없이 댓글 화면 직접 push
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(postId: postId),
      ),
    );
  },
  ```

- [ ] **Step 3: `flutter analyze` 실행하여 컴파일 오류 확인**

  ```bash
  cd C:/projects/performance_manager
  flutter analyze lib/screens/search_screen.dart
  ```

  Expected: 오류 없음 (info 레벨 경고는 무시)

---

## Chunk 3: home_screen.dart 연결 + 빌드

### Task 4: home_screen.dart AppBar에 돋보기 버튼 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/home_screen.dart`

- [ ] **Step 1: import 추가**

  `home_screen.dart` 상단에 (아직 없다면):
  ```dart
  import 'search_screen.dart';
  ```
  (`font_awesome_flutter` import는 v32에서 이미 추가됨)

- [ ] **Step 2: AppBar actions에 돋보기 버튼 추가**

  `home_screen.dart` 약 line 1087 부근, 알림 버튼(`Icons.notifications_outlined`) 바로 앞에 삽입:

  ```dart
  IconButton(
    icon: const FaIcon(FontAwesomeIcons.magnifyingGlass),
    onPressed: () async {
      final userId = await ApiClient.getUserId() ?? 0;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchScreen(myUserId: userId),
        ),
      );
    },
    tooltip: '검색',
  ),
  ```

- [ ] **Step 3: `flutter analyze` 전체 실행**

  ```bash
  cd C:/projects/performance_manager
  flutter analyze
  ```

  Expected: 오류 없음

### Task 5: AAB 빌드 + 깃헙 푸시

- [ ] **Step 1: 버전 번호 올리기**

  `pubspec.yaml`:
  ```
  version: 1.0.0+33
  ```

- [ ] **Step 2: AAB 빌드**

  ```bash
  cd C:/projects/performance_manager
  flutter build appbundle --dart-define-from-file=dart_defines.json
  ```

  Expected: `✓ Built build\app\outputs\bundle\release\app-release.aab`

- [ ] **Step 3: 깃헙 푸시**

  ```bash
  git add lib/screens/search_screen.dart lib/screens/home_screen.dart \
          lib/api/api_client.dart pubspec.yaml
  git commit -m "feat: 검색 기능 추가 (피드 우리동아리/전체동아리)"
  git push
  ```

---

## 수동 테스트 체크리스트

빌드 후 앱에서 다음을 확인:

- [ ] 홈 AppBar에 돋보기 아이콘 표시됨
- [ ] 돋보기 탭 → 검색 화면 진입, 키보드 자동 포커스
- [ ] 1글자 입력 시 검색 미실행, 결과 없음 안내 표시
- [ ] 2글자 이상 입력 후 300ms 뒤 자동 검색
- [ ] "우리 동아리" 탭 결과 = 해당 동아리 게시글만
- [ ] "전체 동아리" 탭 결과 = 전체 공개 게시글
- [ ] 탭 전환 시 동일 키워드로 재검색
- [ ] 익명 게시글 → 작성자 "익명" 표시
- [ ] 이미지 있는 게시글 → 썸네일 표시
- [ ] 결과 카드 탭 → 댓글/상세 화면 진입
- [ ] X 버튼으로 검색어 초기화
