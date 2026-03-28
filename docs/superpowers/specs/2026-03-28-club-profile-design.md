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

- **권한:** 로그인한 사용자 누구나 (`get_current_user`)
- **응답:**
  ```json
  {
    "club_id": 1,
    "name": "한양대 GROOVE",
    "logo_url": "https://...",
    "banner_url": "https://...",
    "theme_color": "#6750A4",
    "member_count": 23
  }
  ```
- logo_url, banner_url, theme_color는 null 가능

### 2. `PATCH /clubs/{club_id}/profile`

- **권한:** 해당 동아리 super_admin만
- **바디 (모두 선택):**
  ```json
  {
    "logo_url": "https://...",
    "banner_url": "https://...",
    "theme_color": "#RRGGBB"
  }
  ```
- theme_color 유효성 검사: `#RRGGBB` 형식 (7자)
- logo_url / banner_url: `http(s)://` 형식 검사
- **응답:** 수정된 프로필 전체 반환

### 3. `GET /clubs/hot-ranking` 응답 수정

기존 응답에 `club_id` 필드 추가:
```json
{ "rank": 1, "club_name": "GROOVE", "club_id": 3, "score": 42 }
```

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
   - 탭 시 `ClubProfileEditSheet` 열기

### `ClubProfileEditSheet` (편집, super_admin만)

같은 파일 내 별도 위젯. 구성:
- 로고 URL 입력 필드
- 배너 URL 입력 필드
- 테마 컬러: `ColorPicker` 대신 미리 정의된 6가지 컬러 칩으로 단순화
  (Material 3 기본 팔레트: 보라, 파랑, 초록, 주황, 빨강, 분홍)
- 저장 → `PATCH /clubs/{id}/profile` → 성공 시 부모 시트 `setState`로 갱신

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
