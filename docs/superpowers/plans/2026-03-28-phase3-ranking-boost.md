# Phase 3: Ranking + Boost Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 핫 랭킹 PRO 가중치(1.5×), 전체 채널 부스트 게시글 상단 정렬, Flutter 부스트 토글 UI + 홈 배너/배지 구현

**Architecture:** 기존 `GET /clubs/hot-ranking`에 PRO 조건 분기 추가. `GET /posts` 쿼리를 `is_boosted` 기준 우선 정렬로 수정. `POST /posts/{id}/boost` 신규 엔드포인트. Flutter feed_screen에 부스트 토글/배지 추가, home_screen에 동아리 배너·배지 표시.

**Tech Stack:** FastAPI · SQLAlchemy · PostgreSQL · Flutter (기존 스택)

**Spec:** `docs/superpowers/specs/2026-03-28-club-premium-subscription-design.md` Section 3-2, 3-3, 7

**Depends on:** Phase 1 완료 (is_boosted 컬럼, boost_credits 컬럼, posts/clubs 테이블 변경)

---

## Chunk 1: 백엔드 — 랭킹 + 부스트 API

### Task 1: GET /clubs/hot-ranking PRO 가중치 수정

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: 기존 hot-ranking 엔드포인트 코드 확인**

```bash
grep -n "hot-ranking\|hot_ranking" C:/projects/performance-manager/backend/main.py
```

기존 점수 계산 로직의 라인 번호를 확인한다.

- [ ] **Step 2: PRO 1.5× 가중치 적용**

기존 점수 산출 방식을 찾아 PRO 동아리에 `* 1.5` 적용:

```python
# 기존 코드 패턴 (점수 = 멤버 수 + 최근 게시글 수 등):
# score = member_count + recent_posts

# 수정:
club_plan = getattr(club, 'plan', 'free')
multiplier = 1.5 if club_plan == 'pro' else 1.0
score = (member_count + recent_posts) * multiplier
```

실제 기존 로직에 맞게 적용 (공식이 다르면 해당 공식 변수에 multiplier를 곱함).

- [ ] **Step 3: 응답에 plan 정보 추가 (배지 표시용)**

```python
return {
    ...
    "plan": club.plan,          # "free" | "standard" | "pro"
    # has_badge: 동아리 홈·프로필에서 STANDARD+ 인증 배지 (✦)
    "has_badge": club.plan in ("standard", "pro"),
    # ranking_badge: 랭킹 화면 전용 PRO 배지 — PRO만 표시 (스펙 Section 3-3)
    "ranking_badge": club.plan == "pro",
    "theme_color": club.theme_color,
    "logo_url": club.logo_url,
}
```

- [ ] **Step 4: 테스트 — PRO 동아리가 상위에 위치하는지 확인**

```bash
# PRO 동아리 plan 강제 설정 후 랭킹 조회
curl http://localhost:8000/clubs/hot-ranking
# 기대: PRO 동아리가 동일 활동량에서 FREE보다 위
```

- [ ] **Step 5: Commit**

```bash
git add backend/main.py
git commit -m "feat: apply 1.5x PRO weight in hot-ranking, add plan field to response"
```

---

### Task 2: GET /posts 부스트 게시글 상단 정렬

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: 기존 GET /posts 쿼리 확인**

```bash
grep -n "def.*posts\|GET.*posts\|query.*Post" C:/projects/performance-manager/backend/main.py | head -20
```

- [ ] **Step 2: is_global=true일 때 is_boosted 우선 정렬 추가**

```python
from sqlalchemy import case, func

# 기존 정렬:
# query.order_by(db_models.Post.created_at.desc())

# 수정 (is_global 파라미터가 있는 경우):
# ⚠️ is_boosted=True라도 boost_expires_at이 이미 지난 경우 상단 정렬에서 제외
# (cron이 30분 간격이므로 만료된 부스트가 잠시 상단에 노출될 수 있음 — 백엔드에서 직접 필터)
if is_global:
    boost_active = case(
        (
            (db_models.Post.is_boosted == True) &
            (db_models.Post.boost_expires_at > func.now()),
            1,
        ),
        else_=0,
    )
    query = query.order_by(
        boost_active.desc(),                     # 유효한 부스트 게시글 먼저
        db_models.Post.boost_expires_at.desc(),  # 부스트 중 최근 만료 먼저
        db_models.Post.created_at.desc(),        # 나머지는 최신 순
    )
else:
    query = query.order_by(db_models.Post.created_at.desc())
```

- [ ] **Step 3: 응답에 is_boosted, boost_expires_at 포함**

```python
return {
    ...
    "is_boosted": post.is_boosted,
    "boost_expires_at": post.boost_expires_at.isoformat() if post.boost_expires_at else None,
}
```

- [ ] **Step 4: 테스트 — 부스트 게시글이 상단 노출 확인**

```bash
# 게시글 하나를 is_boosted=true, boost_expires_at=미래로 직접 DB 수정 후:
curl "http://localhost:8000/posts?is_global=true"
# 기대: is_boosted=true 게시글이 먼저 나옴
```

- [ ] **Step 5: Commit**

```bash
git add backend/main.py
git commit -m "feat: sort boosted posts first in global feed"
```

---

### Task 3: POST /posts/{id}/boost — 부스트 적용 API

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `main.py`에 `POST /posts/{id}/boost` 추가**

```python
@app.post("/posts/{post_id}/boost")
@limiter.limit("10/minute")
async def boost_post(
    request: Request,
    post_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    post = db.query(db_models.Post).filter(db_models.Post.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")

    # 전체 채널 게시글만 부스트 가능
    if not post.is_global:
        raise HTTPException(status_code=400, detail="전체 채널 게시글만 홍보 부스트할 수 있습니다.")

    # 요청자가 해당 게시글의 동아리 super_admin인지 확인 (author 여부는 무관)
    member = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == post.club_id,
        db_models.ClubMember.user_id == current_user.id,
    ).first()
    if not member or member.role != "super_admin":
        raise HTTPException(status_code=403, detail="동아리장만 홍보 부스트를 사용할 수 있습니다.")

    # 동아리 크레딧 확인 — with_for_update로 동시 부스트 레이스 컨디션 방어
    club = db.query(db_models.Club).filter(
        db_models.Club.id == post.club_id
    ).with_for_update().first()
    if not club:
        raise HTTPException(status_code=400, detail="동아리 정보를 찾을 수 없습니다.")

    if club.boost_credits <= 0:
        raise HTTPException(
            status_code=402,
            detail="부스트 크레딧이 없습니다. STANDARD 이상 구독이 필요합니다."
        )

    # 이미 부스트 중인 게시글은 중복 불가
    if post.is_boosted:
        raise HTTPException(status_code=409, detail="이미 부스트 중인 게시글입니다.")

    # 부스트 적용 (24시간)
    post.is_boosted = True
    post.boost_expires_at = datetime.utcnow() + timedelta(hours=24)
    club.boost_credits -= 1
    db.commit()

    return {
        "ok": True,
        "boost_expires_at": post.boost_expires_at.isoformat(),
        "credits_remaining": club.boost_credits,
    }
```

- [ ] **Step 2: 테스트 — 크레딧 없을 때 402 반환 확인**

```bash
TOKEN="..."  # boost_credits=0인 동아리의 super_admin 토큰
curl -X POST http://localhost:8000/posts/1/boost \
  -H "Authorization: Bearer $TOKEN"
# 기대: 402 {"detail": "부스트 크레딧이 없습니다..."}
```

- [ ] **Step 3: 테스트 — 이미 부스트 중인 게시글에 재시도 시 409 반환 확인**

```bash
# 부스트 성공 후 재호출
curl -X POST http://localhost:8000/posts/1/boost \
  -H "Authorization: Bearer $TOKEN"
# 기대: 409
```

- [ ] **Step 4: 테스트 — 타 동아리 게시글 부스트 시 403 확인**

```bash
OTHER_CLUB_TOKEN="..."
curl -X POST http://localhost:8000/posts/99/boost \
  -H "Authorization: Bearer $OTHER_CLUB_TOKEN"
# 기대: 403 (본인 동아리 게시글이 아님)
```

- [ ] **Step 5: Commit**

```bash
git add backend/main.py
git commit -m "feat: add POST /posts/{id}/boost with credit check and auth guard"
```

---

### Task 4: GET /clubs/{id}/subscription — 구독 상태 조회 API

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

> **목적**: Flutter 구독 화면에서 현재 플랜·크레딧·사용량을 표시하기 위한 엔드포인트.

- [ ] **Step 1: `main.py`에 `GET /clubs/{id}/subscription` 추가**

```python
@app.get("/clubs/{club_id}/subscription")
@limiter.limit("30/minute")
async def get_club_subscription(
    request: Request,
    club_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    # 멤버십 확인
    member = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id,
        db_models.ClubMember.user_id == current_user.id,
    ).first()
    if not member:
        raise HTTPException(status_code=403, detail="해당 동아리 멤버만 조회할 수 있습니다.")

    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")

    # 플랜별 기본 쿼터 (MB)
    QUOTA_MAP = {"free": 10_240, "standard": 30_720, "pro": 102_400}
    base_quota = QUOTA_MAP.get(club.plan, 10_240)
    total_quota = base_quota + (club.storage_quota_extra_mb or 0)

    return {
        "plan": club.plan,
        "plan_expires_at": club.plan_expires_at.isoformat() if club.plan_expires_at else None,
        "storage_used_mb": club.storage_used_mb,
        "storage_quota_mb": total_quota,
        "boost_credits": club.boost_credits,
        "has_badge": club.plan in ("standard", "pro"),
    }
```

- [ ] **Step 2: Commit**

```bash
git add backend/main.py
git commit -m "feat: add GET /clubs/{id}/subscription status endpoint"
```

---

## Chunk 2: Flutter — 부스트 토글 UI + 홈 배너/배지

### Task 5: ApiClient 부스트/구독상태 메서드 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`

- [ ] **Step 1: 부스트·구독상태·랭킹 API 메서드 추가**

```dart
// api_client.dart에 추가
// ⚠️ 기존 ApiClient의 _get / _post 헬퍼가 있으면 그것을 사용 (아래는 없는 경우 패턴)
// 기존 코드에 _parseResponse 또는 _get/_post 헬퍼가 있으면 해당 헬퍼를 사용할 것

static Future<Map<String, dynamic>> boostPost(int postId) async {
  // _post 헬퍼가 있으면: return await _post('/posts/$postId/boost', {});
  final token = await getToken();
  final res = await http.post(
    Uri.parse('$baseUrl/posts/$postId/boost'),
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 30));
  return _parseResponse(res);  // 기존 _parseResponse 헬퍼 사용 (에러 메시지 일관성)
}

static Future<Map<String, dynamic>> getClubSubscription(int clubId) async {
  // _get 헬퍼가 있으면: return await _get('/clubs/$clubId/subscription');
  final token = await getToken();
  final res = await http.get(
    Uri.parse('$baseUrl/clubs/$clubId/subscription'),
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 30));
  return _parseResponse(res);
}

static Future<Map<String, dynamic>> getClubProfile(int clubId) async {
  // _get 헬퍼가 있으면: return await _get('/clubs/$clubId/profile');
  final token = await getToken();
  final res = await http.get(
    Uri.parse('$baseUrl/clubs/$clubId/profile'),
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 30));
  return _parseResponse(res);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/api/api_client.dart
git commit -m "feat: add boostPost, getClubSubscription, getClubProfile API methods"
```

---

### Task 6: feed_screen.dart 부스트 토글 + 배지 UI

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/feed_screen.dart`

> **목적**: 전체 채널 게시글에서 (1) 부스트된 게시글에 배지 표시, (2) 동아리장에게 부스트 버튼 노출, (3) 크레딧 0이면 잠금 + 구독 유도 메시지 표시.

- [ ] **Step 1: 전체 채널 게시글 카드에 부스트 배지 추가**

`feed_screen.dart`의 게시글 렌더링 부분에 추가:
```dart
// 게시글 카드 상단 또는 우측 상단에 배지 표시
if (post['is_boosted'] == true)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.purple.shade700,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.rocket_launch, size: 12, color: Colors.white),
        SizedBox(width: 4),
        Text('부스트', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    ),
  ),
```

- [ ] **Step 2: 동아리장에게 부스트 버튼 + 잠금 상태 UI 추가**

게시글 카드 액션 영역 (좋아요·댓글 버튼 옆)에 추가:

```dart
// 전체 채널 & 본인 게시글 & super_admin인 경우만 표시
if (post['is_global'] == true &&
    post['author_id'] == currentUserId &&
    currentUserRole == 'super_admin' &&
    post['is_boosted'] != true)
  _BoostButton(
    postId: post['id'],
    clubId: post['club_id'],
    onBoosted: () => setState(() {}),  // 새로고침
  ),
```

- [ ] **Step 3: `_BoostButton` 위젯 구현**

```dart
class _BoostButton extends StatefulWidget {
  final int postId;
  final int clubId;
  final VoidCallback onBoosted;
  const _BoostButton({required this.postId, required this.clubId, required this.onBoosted});

  @override
  State<_BoostButton> createState() => _BoostButtonState();
}

class _BoostButtonState extends State<_BoostButton> {
  int? _credits;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    try {
      final sub = await ApiClient.getClubSubscription(widget.clubId);
      if (mounted) setState(() => _credits = sub['boost_credits'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _boost() async {
    setState(() => _loading = true);
    try {
      await ApiClient.boostPost(widget.postId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('홍보 부스트가 적용됐습니다! (24시간)')));
        widget.onBoosted();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('크레딧')) {
          _showSubscribeDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSubscribeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('부스트 크레딧 없음'),
        content: const Text('STANDARD 이상 구독 시 홍보 부스트를 사용할 수 있습니다.\n\nSTANDARD: 월 1회 / PRO: 월 3회'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: ClubSubscriptionScreen으로 이동 (Phase 1에서 구현됨)
            },
            child: const Text('구독하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credits = _credits;
    final hasCredits = credits != null && credits > 0;

    return GestureDetector(
      onTap: (hasCredits && !_loading) ? _boost : (hasCredits ? null : _showSubscribeDialog),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: hasCredits ? Colors.purple : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _loading
                ? const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple))
                : Icon(
                    hasCredits ? Icons.rocket_launch : Icons.lock_outline,
                    size: 14,
                    color: hasCredits ? Colors.purple : Colors.grey,
                  ),
            const SizedBox(width: 4),
            Text(
              hasCredits ? '부스트 ($credits)' : '부스트 잠금',
              style: TextStyle(
                fontSize: 12,
                color: hasCredits ? Colors.purple : Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/feed_screen.dart
git commit -m "feat: add boost badge and boost button with credit/lock UI in feed"
```

---

### Task 7: home_screen.dart 동아리 배너·배지·컬러 적용

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/home_screen.dart`

> **목적**: 동아리 홈 화면 상단에 배너 이미지, 포인트 컬러, STANDARD+ 인증 배지(✦) 표시.

- [ ] **Step 1: home_screen.dart에서 동아리 프로필 로드 추가**

```dart
// HomeScreen의 initState 또는 _loadData()에 추가
Map<String, dynamic>? _clubProfile;

Future<void> _loadClubProfile() async {
  final clubId = /* 현재 동아리 ID (기존 state에서 가져옴) */;
  if (clubId == null) return;
  try {
    final profile = await ApiClient.getClubProfile(clubId);
    if (mounted) setState(() => _clubProfile = profile);
  } catch (_) {}
}
```

- [ ] **Step 2: 동아리 헤더 영역에 배너·로고·배지 적용**

```dart
// 기존 동아리 이름 표시 영역을 확장
Widget _buildClubHeader() {
  final profile = _clubProfile;
  final themeColor = _parseHex(profile?['theme_color']);
  final hasBadge = profile?['has_badge'] == true;
  final bannerUrl = profile?['banner_url'] as String?;
  final logoUrl = profile?['logo_url'] as String?;

  return Column(
    children: [
      // 배너 (STANDARD+)
      if (bannerUrl != null)
        SizedBox(
          height: 120,
          width: double.infinity,
          child: Image.network(bannerUrl, fit: BoxFit.cover),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 로고
            CircleAvatar(
              radius: 28,
              backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
              backgroundColor: themeColor?.withOpacity(0.2) ?? Colors.grey.shade200,
              child: logoUrl == null
                  ? const Icon(Icons.group, size: 28) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    /* 동아리 이름 */,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                    ),
                  ),
                  // 인증 배지 (STANDARD+)
                  if (hasBadge) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified, size: 18, color: themeColor ?? Colors.purple),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Color? _parseHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  try { return Color(int.parse('FF${hex.substring(1)}', radix: 16)); }
  catch (_) { return null; }
}
```

- [ ] **Step 3: 테스트 — PRO 동아리 배너·배지 표시 확인**

디버그 모드에서 plan='pro', banner_url, theme_color가 설정된 동아리로 로그인 후 홈 화면 확인.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: show club banner, logo, theme color and badge in HomeScreen"
```

---

### Task 8: hot_ranking 화면 PRO 배지 표시

**Files:**
- Modify: 랭킹 화면 파일 (아래 Step 1에서 grep으로 확인)

- [ ] **Step 1: 랭킹 화면 파일 경로 확인**

```bash
grep -rn "hot.ranking\|hot_ranking\|HotRanking\|getHotClubs\|랭킹" \
  C:/projects/performance_manager/lib/ --include="*.dart" | head -20
```

결과에서 UI 렌더링이 있는 파일(Screen/Widget 파일)을 특정한다.
예상 경로: `lib/screens/home_screen.dart` 또는 별도 `lib/screens/ranking_screen.dart`.
**이 Step 완료 후 Step 3의 `git add` 경로를 실제 확인된 파일 경로로 대체할 것.**

- [ ] **Step 2: 랭킹 리스트 아이템에 PRO 배지(✦) 추가**

Step 1에서 확인한 파일에서 클럽 이름 렌더링 위치를 수정:

```dart
// 기존: Text(club['name'])
// 수정:
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(club['name'] ?? ''),
    // ranking_badge: PRO 전용 (스펙 Section 3-3) — has_badge(STANDARD+)와 구분
    if (club['ranking_badge'] == true) ...[
      const SizedBox(width: 4),
      const Text('✦', style: TextStyle(color: Colors.purple, fontSize: 14)),
    ],
  ],
),
```

- [ ] **Step 3: Commit**

```bash
# ⚠️ 'lib/' 전체 대신 Step 1에서 확인한 실제 파일 경로 사용
# 예: git add lib/screens/ranking_screen.dart
git add lib/screens/<Step1에서_확인한_파일명>.dart
git commit -m "feat: show PRO badge in hot-ranking list"
```

---

## Phase 3 검증 체크리스트

- [ ] `GET /clubs/hot-ranking`: PRO 동아리가 동일 활동량에서 FREE보다 위
- [ ] `GET /posts?is_global=true`: is_boosted=true 게시글이 상단 정렬
- [ ] `POST /posts/{id}/boost`: boost_credits=0이면 402 반환
- [ ] `POST /posts/{id}/boost`: 이미 부스트 중이면 409 반환
- [ ] `POST /posts/{id}/boost`: 타 동아리 super_admin이 시도 시 403 반환
- [ ] 부스트 후 `boost_credits` 1 감소 확인
- [ ] Flutter: 부스트된 게시글에 배지 표시
- [ ] Flutter: 크레딧 0이면 '부스트 잠금' + 구독 유도 다이얼로그
- [ ] Flutter: STANDARD+ 동아리 홈화면에 배지(✦) 표시
- [ ] Flutter: 배너 이미지가 있는 동아리 홈화면에 배너 표시
