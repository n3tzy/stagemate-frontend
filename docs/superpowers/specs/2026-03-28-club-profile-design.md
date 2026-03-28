# Task 5: 동아리 프로필 API + 바텀시트 UI

**날짜:** 2026-03-28
**범위:** 백엔드 API 2개 + hot-ranking 응답 수정 + Flutter 바텀시트 UI

---

## 목표

- 핫클럽 순위에서 동아리 이름 탭 시 프로필 바텀시트 표시
- 동아리 관리 화면에서도 동일한 프로필 시트 접근 가능
- super_admin(회장)은 로고/배너/테마 컬러 편집 가능

---

## 백엔드

### 1. `GET /clubs/{club_id}/profile`

- **권한:** `get_current_user` (로그인한 사용자 누구나)
  - **⚠️ 구현 주의:** `require_any_member`를 사용하지 말 것. 그 의존성은 `X-Club-Id` 헤더 기반으로 다른 동아리를 체크함. 이 엔드포인트는 path parameter `club_id`를 기준으로 조회만 하면 됨.
- **응답:**
  ```json
  {
    "club_id": 1,
    "name": "한양대 GROOVE",
    "logo_url": "https://...",
    "banner_url": null,
    "theme_color": "#6750A4",
    "member_count": 23
  }
  ```
- logo_url, banner_url, theme_color는 null 가능
- **404:** `club_id`에 해당하는 동아리가 없으면 `404 Not Found` 반환

### 2. `PATCH /clubs/{club_id}/profile`

- **권한:** path parameter `club_id`에 해당하는 동아리의 super_admin만
  - **⚠️ 구현 주의:** `require_super_admin` 의존성을 그대로 사용하지 말 것 (헤더 기반). 대신 `get_current_user`로 유저를 가져온 뒤, `ClubMember` 테이블에서 `club_id=path_club_id AND user_id=current_user.id AND role='super_admin'`을 직접 조회.
- **바디 (모두 선택):**
  ```json
  {
    "logo_url": "https://...",
    "banner_url": null,
    "theme_color": "#6750A4"
  }
  ```
- `theme_color` 유효성 검사: 정규식 `^#[0-9A-Fa-f]{6}$`
- `logo_url` / `banner_url`: `http://` 또는 `https://`로 시작해야 함. `null`은 허용 (해당 필드 초기화). 빈 문자열 `""`은 400 에러.
- **응답:** GET과 동일한 형태 반환 (`member_count` 포함):
  ```json
  {
    "club_id": 1, "name": "...", "logo_url": "...",
    "banner_url": null, "theme_color": "#6750A4", "member_count": 23
  }
  ```

### 3. `GET /clubs/hot-ranking` 응답 수정

기존 응답에 `club_id` 필드 추가:
```json
{ "rank": 1, "club_name": "GROOVE", "club_id": 3, "score": 42 }
```
- 기존 `require_any_member` 권한 유지 (로그인 + 동아리 소속 필요)

---

## Flutter

### 파일 구조

```
lib/screens/club_profile_sheet.dart   (신규)
lib/screens/club_manage_screen.dart   (수정 — 프로필 버튼 추가)
lib/screens/feed_screen.dart          (수정 — hot ranking onTap 추가)
lib/api/api_client.dart               (수정 — 2개 메서드 추가)
```

### `ClubProfileSheet` (조회)

`showModalBottomSheet`로 열림. 구성:

1. **배너 영역 (120px):**
   - `banner_url` 있으면 `Image.network` (BoxFit.cover)
   - 없으면 `theme_color` 단색 (null이면 primary 컬러)

2. **로고 아바타:**
   - 배너 하단에 오버랩 (`CircleAvatar`, 반지름 36)
   - `logo_url` 있으면 `NetworkImage`, 없으면 이니셜 텍스트

3. **본문:**
   - 동아리 이름 (titleLarge, bold)
   - 멤버 수 (outline 색상)

4. **편집 버튼:**
   - `isOwner == true`일 때만 표시
   - `isOwner`는 호출 시점에서 **신선한 role 값** 기반으로 전달 (`club_manage_screen`의 경우 `_loadMembers()` 결과에서 현재 유저 role 확인)
   - 탭 시 `ClubProfileEditSheet` 열기

### `ClubProfileEditSheet` (편집, super_admin만)

같은 파일 내 별도 위젯. 구성:
- 로고 URL 입력 필드
- 배너 URL 입력 필드
- 테마 컬러: `ColorPicker` 대신 미리 정의된 6가지 컬러 칩으로 단순화:
  | 이름 | 헥스값 |
  |------|--------|
  | 보라 (기본) | `#6750A4` |
  | 파랑 | `#1976D2` |
  | 초록 | `#388E3C` |
  | 주황 | `#F57C00` |
  | 빨강 | `#D32F2F` |
  | 분홍 | `#C2185B` |
- 저장 → `PATCH /clubs/{id}/profile` → 성공 시 `onSaved` 콜백 호출
- `ClubProfileEditSheet`는 `VoidCallback onSaved` 파라미터를 받음
- 부모 `ClubProfileSheet`는 `onSaved`에서 `setState(() => _profile = updatedProfile)` 실행

### 연결 포인트

**`feed_screen.dart`:**
```dart
ListTile(
  onTap: () => showClubProfile(context, club['club_id'], isOwner: false),
  ...
)
```

**`club_manage_screen.dart`:**
- 상단 섹션에 "동아리 프로필" 카드 추가
- 탭 시 `showClubProfile(context, _clubId!, isOwner: role == 'super_admin')`

### `ApiClient` 신규 메서드

```dart
static Future<Map<String, dynamic>> getClubProfile(int clubId)
static Future<Map<String, dynamic>> updateClubProfile(int clubId, Map<String, dynamic> data)
```

---

## 오류 처리

| 상황 | 처리 |
|------|------|
| 이미지 로드 실패 | `errorBuilder`로 아이콘 대체 |
| PATCH 권한 없음 (403) | SnackBar "권한이 없습니다" |
| 네트워크 실패 | SnackBar `friendlyError(e)` |
| theme_color 형식 오류 | 클라이언트 측 색상 칩 선택이므로 서버 검증만 |

---

## 범위 외 (YAGNI)

- 동아리 생성 시 사진 설정 단계 추가 → 별도 태스크
- 팔로우/구독 기능
- 동아리 소개글 필드
