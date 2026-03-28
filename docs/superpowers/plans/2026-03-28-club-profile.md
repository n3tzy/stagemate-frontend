# Club Profile API + Bottom Sheet Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 동아리 프로필(로고·배너·테마 컬러·멤버 수)을 조회/편집하는 API 2개와 Flutter 바텀시트 UI를 구현하고, 핫클럽 순위 탭 시 해당 시트를 열 수 있게 연결한다.

**Architecture:** 백엔드에 `GET/PATCH /clubs/{club_id}/profile` 추가. Flutter는 재사용 가능한 `ClubProfileSheet` 위젯을 만들어 피드 화면(핫클럽 순위)과 동아리 관리 화면 두 곳에서 호출한다.

**Tech Stack:** FastAPI + SQLAlchemy (Python), Flutter/Dart, Pydantic v2

**Spec:** `docs/superpowers/specs/2026-03-28-club-profile-design.md`

---

## File Map

| 파일 | 변경 |
|------|------|
| `backend/models.py` | `ClubProfileUpdate` Pydantic 모델 추가 |
| `backend/main.py` | GET + PATCH 엔드포인트 추가, hot-ranking에 `club_id` 추가 |
| `lib/api/api_client.dart` | `getClubProfile()`, `updateClubProfile()` 추가 |
| `lib/screens/club_profile_sheet.dart` | **신규** — `ClubProfileSheet`, `ClubProfileEditSheet` |
| `lib/screens/feed_screen.dart` | 핫클럽 `ListTile` `onTap` 추가 |
| `lib/screens/club_manage_screen.dart` | 프로필 버튼 섹션 추가 |

---

## Chunk 1: 백엔드

### Task 1: ClubProfileUpdate Pydantic 모델

**Files:**
- Modify: `backend/models.py` (파일 끝에 추가)

- [ ] **Step 1: 모델 추가**

`backend/models.py` 파일 끝에 추가:

```python
class ClubProfileUpdate(BaseModel):
    """PATCH /clubs/{id}/profile 요청 바디.

    model_fields_set으로 생략(변경 없음)과 null(초기화)을 구분한다.
    - 필드 생략 → model_fields_set에 없음 → DB 변경 없음
    - 필드 null  → model_fields_set에 있음, 값은 None → DB None으로 초기화
    - 필드 빈 문자열 → validator에서 400 에러
    """
    logo_url: Optional[str] = None
    banner_url: Optional[str] = None
    theme_color: Optional[str] = None

    @field_validator('logo_url', 'banner_url')
    @classmethod
    def validate_url(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        if v == '':
            raise ValueError('URL은 빈 문자열일 수 없습니다. null을 사용해 초기화하세요.')
        if not re.match(r'^https?://', v):
            raise ValueError('URL은 http:// 또는 https://로 시작해야 합니다.')
        return v

    @field_validator('theme_color')
    @classmethod
    def validate_theme_color(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        if not re.match(r'^#[0-9A-Fa-f]{6}$', v):
            raise ValueError('테마 컬러는 #RRGGBB 형식이어야 합니다. (예: #6750A4)')
        return v
```

`models.py` 상단에 `Optional` import 확인 — `from typing import List, Literal`을 `from typing import List, Literal, Optional`으로 수정.

- [ ] **Step 2: 서버 임포트 확인**

```bash
cd C:/projects/performance-manager/backend
python -c "from models import ClubProfileUpdate; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: 검증 동작 확인**

```bash
python -c "
from models import ClubProfileUpdate
# 정상 케이스
m = ClubProfileUpdate(theme_color='#6750A4')
assert m.theme_color == '#6750A4'
assert 'logo_url' not in m.model_fields_set  # 생략된 필드

# null 케이스
m2 = ClubProfileUpdate(logo_url=None)
assert 'logo_url' in m2.model_fields_set     # 명시적 null

# 잘못된 컬러
try:
    ClubProfileUpdate(theme_color='red')
    assert False, 'should have raised'
except Exception:
    pass
print('All assertions passed')
"
```
Expected: `All assertions passed`

- [ ] **Step 4: 커밋**

```bash
cd C:/projects/performance-manager/backend
git add models.py
git commit -m "feat: add ClubProfileUpdate pydantic model with partial-update semantics"
```

---

### Task 2: GET /clubs/{club_id}/profile

**Files:**
- Modify: `backend/main.py` (동아리 관련 엔드포인트 섹션 끝, `@app.get("/clubs/hot-ranking")` 앞에 삽입)

- [ ] **Step 1: 엔드포인트 추가**

`main.py`에서 `# ════ 핫 동아리 순위` 섹션 바로 위에 삽입.
> **FastAPI 라우팅 주의:** FastAPI는 concrete 경로(`/clubs/hot-ranking`)를 parameterized 경로(`/clubs/{club_id}/profile`)보다 우선 매칭한다. 따라서 순서는 상관없지만, 프로필 엔드포인트를 hot-ranking 앞에 두면 더 명시적이다.

```python
# ════════════════════════════════════════════════
#  동아리 프로필
# ════════════════════════════════════════════════

@app.get("/clubs/{club_id}/profile")
def get_club_profile(
    club_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """동아리 프로필 조회 (로그인한 사용자 누구나)"""
    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    member_count = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id
    ).count()
    return {
        "club_id": club.id,
        "name": club.name,
        "logo_url": club.logo_url,
        "banner_url": club.banner_url,
        "theme_color": club.theme_color,
        "member_count": member_count,
    }
```

- [ ] **Step 2: 서버 재시작 없이 문법 확인**

```bash
cd C:/projects/performance-manager/backend
python -c "import main; print('syntax OK')"
```
Expected: `syntax OK`

- [ ] **Step 3: 수동 테스트**

서버가 실행 중이면:
```bash
curl -H "Authorization: Bearer <토큰>" http://localhost:8000/clubs/1/profile
# 존재하지 않는 ID:
curl -H "Authorization: Bearer <토큰>" http://localhost:8000/clubs/99999/profile
```
Expected: 첫 번째 200 + JSON, 두 번째 404

- [ ] **Step 4: 커밋**

```bash
git add main.py
git commit -m "feat: add GET /clubs/{club_id}/profile endpoint"
```

---

### Task 3: PATCH /clubs/{club_id}/profile

**Files:**
- Modify: `backend/main.py` (GET 엔드포인트 바로 아래)
- Modify: `backend/main.py` (imports — `ClubProfileUpdate` 추가)

- [ ] **Step 1: import 추가 확인**

`main.py` 상단의 `from models import (...)` 블록에 `ClubProfileUpdate` 추가:

```python
from models import (
    PerformanceConfig, RoomBooking,
    RegisterRequest, ClubCreateRequest, ClubJoinRequest,
    RoleUpdateRequest, NoticeRequest, SlotRequest,
    ChangePasswordRequest, ForgotPasswordRequest,
    KakaoLoginRequest, CommentRequest,
    DeleteAccountRequest, PostRequest, PostCommentRequest, NicknameRequest,
    PostEditRequest, ReportRequest,
    ClubProfileUpdate,   # ← 추가
)
```

- [ ] **Step 2: PATCH 엔드포인트 추가 (GET 바로 아래)**

```python
@app.patch("/clubs/{club_id}/profile")
@limiter.limit("10/minute")
def update_club_profile(
    request: Request,
    club_id: int,
    req: ClubProfileUpdate,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """동아리 프로필 수정 (해당 동아리 super_admin만)"""
    # 1) 동아리 존재 확인 (먼저 404, 그 다음 403)
    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")

    # 2) 권한 확인: path param club_id 기준으로 super_admin 체크
    membership = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id,
        db_models.ClubMember.user_id == current_user.id,
        db_models.ClubMember.role == "super_admin",
    ).first()
    if not membership:
        raise HTTPException(status_code=403, detail="동아리 프로필 수정 권한이 없습니다.")

    # 3) model_fields_set으로 명시적으로 전달된 필드만 업데이트
    for field in req.model_fields_set:
        setattr(club, field, getattr(req, field))

    db.commit()
    db.refresh(club)

    member_count = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id
    ).count()
    return {
        "club_id": club.id,
        "name": club.name,
        "logo_url": club.logo_url,
        "banner_url": club.banner_url,
        "theme_color": club.theme_color,
        "member_count": member_count,
    }
```

- [ ] **Step 3: 문법 확인**

```bash
python -c "import main; print('syntax OK')"
```

- [ ] **Step 4: 수동 테스트 (서버 실행 중)**

```bash
# super_admin 토큰으로 업데이트
curl -X PATCH -H "Authorization: Bearer <슈퍼_어드민_토큰>" \
  -H "Content-Type: application/json" \
  -d '{"theme_color": "#1976D2"}' \
  http://localhost:8000/clubs/1/profile

# 일반 멤버 토큰으로 시도 → 403
curl -X PATCH -H "Authorization: Bearer <멤버_토큰>" \
  -H "Content-Type: application/json" \
  -d '{"theme_color": "#1976D2"}' \
  http://localhost:8000/clubs/1/profile

# 잘못된 컬러 → 422
curl -X PATCH -H "Authorization: Bearer <슈퍼_어드민_토큰>" \
  -H "Content-Type: application/json" \
  -d '{"theme_color": "red"}' \
  http://localhost:8000/clubs/1/profile
```

- [ ] **Step 5: 커밋**

```bash
git add main.py
git commit -m "feat: add PATCH /clubs/{club_id}/profile endpoint (super_admin only)"
```

---

### Task 4: hot-ranking에 club_id 추가

**Files:**
- Modify: `backend/main.py` (get_hot_clubs 함수 내 result.append 부분)

- [ ] **Step 1: club_id 필드 추가**

`main.py`의 `get_hot_clubs` 함수에서:

```python
# 기존:
result.append({"rank": rank, "club_name": club.name, "score": score})

# 변경:
result.append({"rank": rank, "club_id": club.id, "club_name": club.name, "score": score})
```

- [ ] **Step 2: 커밋**

```bash
cd C:/projects/performance-manager/backend
git add main.py
git commit -m "feat: add club_id to hot-ranking response"
```

---

## Chunk 2: Flutter

### Task 5: ApiClient 메서드 추가

**Files:**
- Modify: `lib/api/api_client.dart`

`ApiClient` 클래스 끝 (`deletePostComment` 이후 어딘가)에 추가:

- [ ] **Step 1: getClubProfile 추가**

```dart
static Future<Map<String, dynamic>> getClubProfile(int clubId) async {
  final response = await http.get(
    Uri.parse('$baseUrl/clubs/$clubId/profile'),
    headers: await _headers(),
  ).timeout(_timeout);
  return _parseResponse(response);
}
```

- [ ] **Step 2: updateClubProfile 추가**

```dart
static Future<Map<String, dynamic>> updateClubProfile(
  int clubId,
  Map<String, dynamic> data,
) async {
  final response = await http.patch(
    Uri.parse('$baseUrl/clubs/$clubId/profile'),
    headers: await _headers(),
    body: jsonEncode(data),
  ).timeout(_timeout);
  return _parseResponse(response);
}
```

- [ ] **Step 3: 컴파일 확인**

```bash
cd C:/projects/performance_manager
flutter analyze lib/api/api_client.dart
```
Expected: No issues.

- [ ] **Step 4: 커밋 (Flutter 브랜치에서)**

```bash
git add lib/api/api_client.dart
git commit -m "feat: add getClubProfile and updateClubProfile ApiClient methods"
```

---

### Task 6: ClubProfileSheet + ClubProfileEditSheet 신규 파일

**Files:**
- Create: `lib/screens/club_profile_sheet.dart`

전체 파일 내용:

- [ ] **Step 1: 파일 생성**

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';

// ── 컬러 칩에 쓸 6가지 프리셋 ──────────────────────────
const _kColorPresets = [
  {'label': '보라', 'hex': '#6750A4'},
  {'label': '파랑', 'hex': '#1976D2'},
  {'label': '초록', 'hex': '#388E3C'},
  {'label': '주황', 'hex': '#F57C00'},
  {'label': '빨강', 'hex': '#D32F2F'},
  {'label': '분홍', 'hex': '#C2185B'},
];

Color _hexToColor(String? hex) {
  if (hex == null || hex.length != 7) return const Color(0xFF6750A4);
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

// ── 외부에서 바텀시트를 여는 헬퍼 함수 ────────────────
Future<void> showClubProfile(
  BuildContext context,
  int clubId, {
  required bool isOwner,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ClubProfileSheet(clubId: clubId, isOwner: isOwner),
  );
}

// ── 프로필 조회 시트 ───────────────────────────────────
class ClubProfileSheet extends StatefulWidget {
  final int clubId;
  final bool isOwner;

  const ClubProfileSheet({
    super.key,
    required this.clubId,
    required this.isOwner,
  });

  @override
  State<ClubProfileSheet> createState() => _ClubProfileSheetState();
}

class _ClubProfileSheetState extends State<ClubProfileSheet> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.getClubProfile(widget.clubId);
      if (mounted) setState(() { _profile = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _profile == null) {
      // 404 등 에러 시 시트를 닫고 SnackBar 표시 (spec 요구사항)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_error ?? '동아리 정보를 불러올 수 없습니다.')),
          );
        }
      });
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile!;
    final themeColor = _hexToColor(profile['theme_color'] as String?);
    final logoUrl = profile['logo_url'] as String?;
    final bannerUrl = profile['banner_url'] as String?;
    final name = profile['name'] as String? ?? '';
    final memberCount = profile['member_count'] as int? ?? 0;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 배너 영역
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // 배너
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: bannerUrl != null
                      ? Image.network(
                          bannerUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: themeColor),
                        )
                      : Container(color: themeColor),
                ),
              ),
              // 로고 아바타 (배너 위에 오버랩)
              Positioned(
                bottom: -36,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: colorScheme.surface,
                  child: CircleAvatar(
                    radius: 33,
                    backgroundColor: themeColor.withValues(alpha: 0.2),
                    backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                    onBackgroundImageError: logoUrl != null ? (_, __) {} : null,
                    child: logoUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48), // 아바타 오버랩 공간
          // 동아리 정보
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '멤버 $memberCount명',
                  style: TextStyle(color: colorScheme.outline),
                ),
                const SizedBox(height: 24),
                // 편집 버튼 (super_admin만)
                if (widget.isOwner)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => ClubProfileEditSheet(
                          clubId: widget.clubId,
                          currentProfile: profile,
                          onSaved: (updated) {
                            if (mounted) setState(() => _profile = updated);
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('프로필 편집'),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 프로필 편집 시트 (super_admin만) ──────────────────
class ClubProfileEditSheet extends StatefulWidget {
  final int clubId;
  final Map<String, dynamic> currentProfile;
  // onSaved: 저장 완료 후 부모 시트가 프로필을 갱신할 수 있도록 업데이트된 데이터를 전달.
  // spec에서 VoidCallback으로 명시했으나, 갱신된 프로필 맵을 직접 전달하는 방식이 state refresh에 필요하므로 Function(Map)을 사용.
  final void Function(Map<String, dynamic> updated) onSaved;

  const ClubProfileEditSheet({
    super.key,
    required this.clubId,
    required this.currentProfile,
    required this.onSaved,
  });

  @override
  State<ClubProfileEditSheet> createState() => _ClubProfileEditSheetState();
}

class _ClubProfileEditSheetState extends State<ClubProfileEditSheet> {
  late final TextEditingController _logoCtrl;
  late final TextEditingController _bannerCtrl;
  String? _selectedColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _logoCtrl = TextEditingController(
        text: widget.currentProfile['logo_url'] as String? ?? '');
    _bannerCtrl = TextEditingController(
        text: widget.currentProfile['banner_url'] as String? ?? '');
    _selectedColor = widget.currentProfile['theme_color'] as String?;
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _bannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      // 변경된 필드만 body에 포함
      final body = <String, dynamic>{};
      final logoText = _logoCtrl.text.trim();
      final bannerText = _bannerCtrl.text.trim();

      // 로고: 빈 문자열이면 null(초기화), 값 있으면 포함
      if (logoText != (widget.currentProfile['logo_url'] ?? '')) {
        body['logo_url'] = logoText.isEmpty ? null : logoText;
      }
      if (bannerText != (widget.currentProfile['banner_url'] ?? '')) {
        body['banner_url'] = bannerText.isEmpty ? null : bannerText;
      }
      if (_selectedColor != widget.currentProfile['theme_color']) {
        body['theme_color'] = _selectedColor;
      }

      if (body.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final updated = await ApiClient.updateClubProfile(widget.clubId, body);
      if (mounted) {
        widget.onSaved(updated);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '프로필 편집',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _logoCtrl,
              decoration: const InputDecoration(
                labelText: '로고 이미지 URL',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bannerCtrl,
              decoration: const InputDecoration(
                labelText: '배너 이미지 URL',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('테마 컬러',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _kColorPresets.map((preset) {
                final hex = preset['hex']!;
                final color = _hexToColor(hex);
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 컴파일 확인**

```bash
cd C:/projects/performance_manager
flutter analyze lib/screens/club_profile_sheet.dart
```
Expected: No issues.

- [ ] **Step 3: 커밋**

```bash
git add lib/screens/club_profile_sheet.dart
git commit -m "feat: add ClubProfileSheet and ClubProfileEditSheet"
```

---

### Task 7: feed_screen.dart — 핫클럽 onTap 연결

**Files:**
- Modify: `lib/screens/feed_screen.dart`

- [ ] **Step 1: import 추가**

`feed_screen.dart` 상단 imports에 추가:
```dart
import 'club_profile_sheet.dart';
```

- [ ] **Step 2: ListTile에 onTap 추가**

`_hotClubs.map<Widget>` 안의 `ListTile`에 `onTap` 추가:

```dart
// 기존:
(club) => ListTile(
  leading: CircleAvatar(...),
  title: Text(club['club_name'] ?? ''),
  trailing: Text('${club['score']}점', ...),
  dense: true,
),

// 변경:
(club) => ListTile(
  leading: CircleAvatar(...),
  title: Text(club['club_name'] ?? ''),
  trailing: Text('${club['score']}점', ...),
  dense: true,
  onTap: club['club_id'] != null
      ? () => showClubProfile(
            context,
            club['club_id'] as int,
            isOwner: false,  // 핫클럽 순위는 탐색 맥락, 편집 불가
          )
      : null,
),
```

- [ ] **Step 3: 컴파일 확인**

```bash
flutter analyze lib/screens/feed_screen.dart
```

- [ ] **Step 4: 커밋**

```bash
git add lib/screens/feed_screen.dart
git commit -m "feat: open club profile sheet on hot-ranking tap"
```

---

### Task 8: club_manage_screen.dart — 프로필 버튼 추가

**Files:**
- Modify: `lib/screens/club_manage_screen.dart`

- [ ] **Step 1: import 추가**

```dart
import 'club_profile_sheet.dart';
```

- [ ] **Step 2: _role 상태 변수 추가**

`_ClubManageScreenState`의 `bool _isLoadingMembers = false;` 바로 다음 줄에 추가:

```dart
// 기존:
bool _isLoadingMembers = false;

// 변경:
bool _isLoadingMembers = false;
String _myRole = 'member';
```

- [ ] **Step 3: _loadMembers 교체**

기존 `_loadMembers` 전체를 아래로 교체 (에러 처리 유지):

```dart
// 기존 메서드를 아래로 완전 교체:
Future<void> _loadMembers() async {
  if (_clubId == null) return;
  setState(() => _isLoadingMembers = true);
  try {
    final data = await ApiClient.getMembers(_clubId!);
    final myId = await ApiClient.getUserId();
    if (mounted) {
      setState(() {
        _members = data;
        // 현재 유저의 role 파악 (isOwner 판단에 사용)
        final me = _members.firstWhere(
          (m) => m['user_id'] == myId,
          orElse: () => <String, dynamic>{},
        );
        _myRole = (me['role'] as String?) ?? 'member';
      });
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('멤버 목록 불러오기 실패: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoadingMembers = false);
  }
}
```

- [ ] **Step 4: 프로필 카드 UI 추가**

`build` 메서드의 `ListView` children 최상단에 삽입. 기존 코드에서 아래 anchor를 찾아 그 바로 앞에 삽입:

```dart
// 이 줄 바로 앞에 프로필 카드 삽입:
//   padding: const EdgeInsets.all(16),
//   children: [
//     Card(   ← 기존 첫 번째 Card (초대코드 섹션)
```

```dart
// 동아리 프로필 카드 — 목록 맨 위에 추가
Card(
  child: ListTile(
    leading: const Icon(Icons.business_outlined),
    title: const Text('동아리 프로필'),
    subtitle: Text(_myRole == 'super_admin' ? '로고·배너·테마 편집 가능' : '프로필 보기'),
    trailing: const Icon(Icons.chevron_right),
    onTap: _clubId == null
        ? null
        : () => showClubProfile(
              context,
              _clubId!,
              isOwner: _myRole == 'super_admin',
            ),
  ),
),
const SizedBox(height: 8),
```

- [ ] **Step 5: 컴파일 확인**

```bash
flutter analyze lib/screens/club_manage_screen.dart
```

- [ ] **Step 6: 전체 테스트**

```bash
flutter test
```
Expected: All tests passed.

- [ ] **Step 7: 최종 커밋**

```bash
git add lib/screens/club_manage_screen.dart
git commit -m "feat: add club profile button to club manage screen"
```

---

## 최종 확인 체크리스트

- [ ] 백엔드: `GET /clubs/{club_id}/profile` — 존재하지 않는 ID → 404 확인
- [ ] 백엔드: `PATCH /clubs/{club_id}/profile` — 멤버 토큰 → 403, super_admin → 200 확인
- [ ] 백엔드: `PATCH` 필드 생략 시 기존 값 유지 확인 (`model_fields_set`)
- [ ] 백엔드: hot-ranking 응답에 `club_id` 포함 확인
- [ ] Flutter: 핫클럽 탭 → 바텀시트 열림, 이미지 없을 때 테마 컬러 단색 표시
- [ ] Flutter: super_admin 계정에서 편집 버튼 보임, 일반 멤버에게 안 보임
- [ ] Flutter: 편집 저장 후 시트 새로고침 (테마 컬러 즉시 반영)
