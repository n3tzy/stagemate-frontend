# Post Search Feature — Design Spec

**Date:** 2026-04-01
**Status:** Approved

---

## Overview

통합 검색 기능. 홈 상단 돋보기 아이콘 → SearchScreen에서 피드 게시글을 실시간 검색. 우리 동아리 / 전체 동아리 탭으로 범위 선택 가능. 공지사항은 검색 대상 제외.

---

## Architecture

```
홈 AppBar
  └─ FaIcon(FontAwesomeIcons.magnifyingGlass) IconButton
       └─ Navigator.push → SearchScreen

SearchScreen
  ├─ TextField (debounce 300ms)
  ├─ DefaultTabController(length: 2)
  │    ├─ Tab 0: 우리 동아리 → GET /posts/search?q=&is_global=false
  │    └─ Tab 1: 전체 동아리 → GET /posts/search?q=&is_global=true
  └─ ListView (결과 카드)
       └─ onTap → 기존 PostDetailScreen

Backend
  └─ GET /posts/search?q=&is_global=&offset=&limit=
       └─ Post.content ILIKE 검색
```

---

## Backend

### Endpoint

```
GET /posts/search
Query params:
  q         string   검색어 (기본 "", 없으면 빈 문자열 처리)
  is_global bool     false=우리동아리(기본), true=전체동아리
  offset    int      기본 0
  limit     int      기본 20, 최대 50 (서버에서 min(limit, 50) 강제)
Auth: require_any_member
```

### 입력 검증

- `q.strip()`으로 공백 제거 후 **글자 수(문자 단위)** 체크
- `len(q.strip()) < 2` → `[]` 즉시 반환 (DB 쿼리 생략)
- q에 포함된 `%`, `_` 와일드카드는 이스케이프 처리: `q_safe = q.strip().replace('%','\\%').replace('_','\\_')`
- MVP: limit 파라미터 미지원. 항상 최대 20개 반환 (offset 파라미터도 MVP에서는 미사용, 향후 무한스크롤 추가 시 활성화)

### SQL 조건

```python
q_like = f"%{q_safe}%"
query = db.query(Post).filter(Post.content.ilike(q_like))

if is_global:
    # 전체 동아리: is_global=True인 게시글은 설계상 모든 인증 멤버에게 공개 (의도된 동작)
    query = query.filter(Post.is_global == True)
else:
    # require_any_member에서 resolve된 member.club_id 사용
    query = query.filter(
        Post.is_global == False,
        Post.club_id == member.club_id,
    )

posts = query.order_by(desc(Post.created_at)).offset(offset).limit(min(limit, 50)).all()
```

### 응답 스키마

익명 게시글 처리: 기존 `get_posts`와 동일하게 `author_id`는 **항상 반환** (프론트엔드의 "내 글" 판단에 필요). 표시 이름(`author`)과 아바타(`author_avatar`)만 null 처리:

```json
[
  {
    "id": 1,
    "content": "게시글 본문 텍스트",
    "media_urls": ["https://...jpg"],
    "is_anonymous": false,
    "author": "닉네임",       // is_anonymous=true → null (화면에 "익명" 표시)
    "author_id": 42,          // 항상 반환 (익명 여부 무관)
    "author_avatar": "...",   // is_anonymous=true → null
    "like_count": 5,
    "comment_count": 2,
    "created_at": "2026-04-01 12:00",
    "club_id": 3,
    "is_global": true
  }
]
```

페이지네이션: 단순 오프셋 방식. `total` 없이 반환 결과 수가 `limit` 미만이면 마지막 페이지. (MVP 기준 첫 20개만 표시, 무한스크롤 미구현)

---

## Frontend

### SearchScreen (`lib/screens/search_screen.dart`)

**상태**

```dart
List<dynamic> _results = [];
bool _isLoading = false;
bool _searched = false;  // 첫 검색 전/후 구분
bool _hasError = false;
Timer? _debounce;
```

**검색 흐름**

1. 사용자 입력 → 이전 `_debounce` 취소 후 300ms 새 타이머 시작
2. 타이머 만료 시 `_hasError = false`, `_isLoading = true`로 setState 후 API 호출
3. 응답 수신 시 `_results` 업데이트, `_isLoading = false`
4. 오류 발생 시 `_hasError = true`, `_isLoading = false` + SnackBar
5. 탭 전환 시: `_results = []`, offset = 0 리셋 후 동일 키워드 즉시 재검색

**UI 상태**

| 상태 | 표시 |
|------|------|
| 초기 (`!_searched`) | "검색어를 2글자 이상 입력해주세요" |
| 로딩 (`_isLoading`) | `CircularProgressIndicator` (중앙) |
| 오류 (`_hasError`) | "검색 중 오류가 발생했습니다. 다시 시도해주세요" + 재시도 버튼 |
| 결과 없음 | "검색 결과가 없어요" |
| 결과 있음 | 카드 리스트 |

**결과 카드**

- 작성자: `is_anonymous == true`이면 "익명" + 기본 아바타 표시 (`author`/`author_avatar` null 체크)
- 본문: `maxLines: 2, overflow: TextOverflow.ellipsis`
- 이미지 썸네일: `media_urls`에서 확장자가 `.jpg/.jpeg/.png/.gif/.webp`인 첫 URL. 없으면 썸네일 영역 미표시
- 좋아요 수 + 댓글 수
- 작성일

### home_screen.dart 수정

AppBar `actions`에 알림 버튼 앞에 추가:

```dart
IconButton(
  icon: const FaIcon(FontAwesomeIcons.magnifyingGlass),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => SearchScreen(clubId: _currentClub.id)),
  ),
  tooltip: '검색',
),
```

`font_awesome_flutter` import 이미 있음.

### api_client.dart 수정

```dart
Future<List<dynamic>> searchPosts({
  required String q,
  required bool isGlobal,
  int offset = 0,
  int limit = 20,
}) async {
  final res = await _get('/posts/search', queryParams: {
    'q': q,
    'is_global': isGlobal.toString(),
    'offset': offset.toString(),
    'limit': limit.toString(),
  });
  return res as List<dynamic>;
}
```

---

## Error Handling

| 상황 | 처리 |
|------|------|
| 네트워크 오류 | `_hasError = true` + SnackBar + 재시도 버튼 |
| 401 Unauthorized | 기존 `UnauthorizedException` 처리 (자동 로그아웃) |
| 결과 없음 | UI 안내 메시지 (오류 아님) |

---

## Out of Scope

- 공지사항 검색
- 검색어 저장 / 히스토리
- 해시태그 검색
- 검색 결과 정렬 옵션
- 무한 스크롤 페이지네이션
- Zen Serif 폰트 폴백 (별도 작업)
