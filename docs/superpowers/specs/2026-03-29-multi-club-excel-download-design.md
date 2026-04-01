---
title: 다중 동아리 지원 + 엑셀 다운로드 알림
date: 2026-03-29
status: approved
---

# 다중 동아리 지원 + 엑셀 다운로드 알림

두 기능을 함께 구현한다. Feature 1은 사용자가 여러 동아리에 속할 수 있도록 앱 구조를 확장하고, Feature 2는 엑셀 파일 저장 후 시스템 알림을 제공한다.

---

## Feature 1: 다중 동아리 지원 (Option C — App Bar Switcher)

### 배경

StageMate는 현재 단일 동아리만 지원한다. 그러나 DB의 `ClubMember` 테이블은 이미 한 유저가 여러 동아리에 속하는 구조를 지원하고 있다. 이번 기능은 백엔드 신규 엔드포인트 1개와 Flutter 3개 파일 수정으로 다중 동아리 전환을 구현한다.

### 확정된 설계 결정

- **재로그인 불필요**: 홈 화면 app bar에서 언제든 동아리를 전환할 수 있다. 토큰 재발급이나 로그아웃 없이 전환된다.
- **탭 유지**: 동아리 전환 시 현재 선택된 하단 네비게이션 탭이 그대로 유지된다.
- **단일 동아리 사용자**: 동아리가 1개뿐인 경우 switcher 버튼을 표시하지 않는다. 기존 동작과 동일하게 유지된다.

### App Bar Switcher UI

동아리가 2개 이상인 경우, 기존 동아리 이름 chip 자리에 탭 가능한 switcher 버튼을 표시한다.

**버튼 표시 형식:**
```
[switch icon]  {동아리명} · {역할 레이블}  [▾]
```

**탭 시 동작:**
- Bottom sheet가 올라온다.
- 현재 동아리는 초록색 하이라이트 + 체크마크로 표시된다.
- 나머지 동아리는 chevron 아이콘과 함께 나열된다.

**역할 레이블 매핑 (DB 실제 값 기준):**

| role 값 | 표시 레이블 |
|---------|------------|
| `super_admin` | 회장 |
| `admin` | 임원진 |
| `team_leader` | 팀장 |
| `user` | 멤버 |

### 앱 재시작 시 동작

- 마지막으로 사용한 `clubId`를 `flutter_secure_storage`에 저장한다.
- 다음 실행 시 저장된 `clubId`를 불러와 `getMyClubs()` 결과와 대조한다.
- 일치하는 동아리가 있으면 해당 동아리로 진입한다.
- 저장된 `clubId`가 목록에 없는 경우(강퇴 등) 첫 번째 동아리를 사용한다.

### 동아리 전환 데이터 흐름

1. 사용자가 bottom sheet에서 동아리를 선택한다.
2. `ApiClient.setClubInfo(clubId, clubName, role)`를 호출한다 (기존 3-param 시그니처 사용). 값은 `flutter_secure_storage`에 저장된다.
3. 이후 모든 API 요청의 `X-Club-Id` 헤더가 자동으로 새 `clubId`를 사용한다. (이미 요청마다 storage에서 읽는 구조)
4. `HomeScreen`에서 `setState()`를 호출해 app bar를 재빌드한다.
5. 현재 탭 인덱스는 변경되지 않는다.

---

### 백엔드 변경 사항

#### 기존 엔드포인트: `GET /clubs/my`

이미 구현되어 있다. 변경 없음.

- **인증**: Bearer token 필수
- **반환**: 현재 로그인한 유저가 속한 모든 동아리 목록

**Response 형식:**
```json
[
  { "club_id": 1, "club_name": "한국대학교 극단", "role": "super_admin" },
  { "club_id": 3, "club_name": "서울댄스클럽", "role": "user" }
]
```

---

### Flutter 변경 사항

#### `lib/api/api_client.dart`

- `getMyClubs()` 메서드가 이미 존재한다 (`GET /clubs/my` 호출, `List<dynamic>` 반환). 변경 없음.

#### `lib/screens/home_screen.dart`

**생성자 변경:**
- 기존: `HomeScreen({required displayName, required role, required clubName})`
- 변경: `HomeScreen({required displayName, required role, required clubName, required List<Map<String,dynamic>> clubs})`
- `clubs`: `getMyClubs()` 결과 전체 목록

**상태 변수 추가:**
- `_currentRole`, `_currentClubName`, `_currentClubId`를 `State` 클래스에 추가한다.
- `initState()`에서 `widget.role`, `widget.clubName`으로 초기화한다.
- 다음 `widget.role` / `widget.clubName` 참조를 모두 `_currentRole` / `_currentClubName`으로 교체한다:
  - line 88–92: `_isSuperAdmin`, `_isAdmin`, `_canSubmitAudio` getters
  - line 103: `AudioSubmissionScreen(role: widget.role)`
  - line 145: `_roleBadgeColor()` switch
  - line 263–265: `showWelcomeDialog(isCreator:, clubName:, role:)`
  - line 858: app bar 내 `widget.clubName` 텍스트

**Switcher 버튼 (동아리 2개 이상일 때만):**
- `widget.clubs.length >= 2`이면 기존 동아리 이름 chip 자리에 switcher 버튼을 표시한다.
- 버튼 형식: `[swap_horiz 아이콘]  {_currentClubName} · {역할레이블}  [expand_more 아이콘]`
- 탭 → `_ClubSwitcherSheet` bottom sheet 표시

**`_ClubSwitcherSheet` 위젯 (같은 파일 내 추가):**
- `widget.clubs` 목록을 나열한다.
- 현재 동아리(`_currentClubId`)는 초록 하이라이트 + `check` 아이콘.
- 다른 동아리는 `chevron_right` 아이콘.
- 선택 시: `ApiClient.setClubInfo(clubId, clubName, role)` 호출 → `setState()`로 `_currentRole`, `_currentClubName`, `_currentClubId` 갱신 → bottom sheet 닫기.

**단일 동아리일 때:** 기존 chip 그대로 유지. switcher 없음.

#### `HomeScreen` 호출부 전체 수정

`clubs` 파라미터가 `required`이므로 아래 모든 호출부에 `clubs: myClubs`를 추가한다. 각 호출부는 `getMyClubs()` 결과를 먼저 받아 전달한다:

| 파일 | 위치 |
|------|------|
| `lib/main.dart` | line 115 (`_checkToken()` 내) |
| `lib/screens/login_screen.dart` | line 244, line 291 |
| `lib/screens/club_onboarding_screen.dart` | line 431, line 718 |

#### `lib/main.dart` (SplashScreen)

기존 `_checkToken()` 플로우를 다음과 같이 교체한다:

1. 로컬 토큰 확인 → 없으면 `LoginScreen`
2. 클라이언트 측 만료 체크 → 만료면 `LoginScreen`
3. 서버 토큰 유효성 검증 → 실패면 `LoginScreen`
4. `getMyClubs()` 호출
   - 결과가 빈 배열이면 → `ClubOnboardingScreen` (동아리 미가입 상태, 기존과 동일)
   - 결과가 1개이면 → 해당 동아리로 `setClubInfo()` 후 `HomeScreen`
   - 결과가 2개 이상이면:
     - storage의 저장된 `clubId`와 목록을 대조한다.
     - 일치하는 동아리가 있으면 그 동아리로 `setClubInfo()` 후 `HomeScreen`
     - 없으면(강퇴 등) 첫 번째 동아리로 `setClubInfo()` 후 `HomeScreen`

> 기존 `getClubId()` / `getClubName()` / `getRole()` storage 직접 읽는 분기는 제거하고 `getMyClubs()` 결과로 일원화한다. `ClubOnboardingScreen`은 빈 목록 경우에만 진입한다.

---

## Feature 2: 엑셀 다운로드 — 시스템 알림 + 파일 열기

### 배경

현재 `.xlsx` 파일을 `/storage/emulated/0/Download`에 저장한 후 snackbar로 파일명만 표시한다. 시스템 알림이 없고, 탭해서 파일을 바로 열 수도 없다. 이번 기능은 Android 상태바 알림을 추가하고 탭 시 파일을 열도록 개선한다.

### 확정된 설계 결정

- 파일 저장 완료 후 Android 상태바에 알림("다운로드 완료")을 표시한다.
- 사용자가 알림을 탭하면 기기의 기본 앱(Excel, Google Sheets 등)으로 파일이 열린다.
- iOS는 대응하지 않는다. 엑셀 내보내기는 무대순서 화면 전용 기능으로 Android 위주 사용 사례이며, iOS에서는 no-op으로 처리한다.

### 알림 내용

| 항목 | 값 |
|------|-----|
| Title | `다운로드 완료` |
| Body | 파일명 (예: `무대순서_2026-03-29.xlsx`) |
| Tap action | 해당 파일을 기본 앱으로 열기 |

### 사용 패키지

`pubspec.yaml`에 추가:

| 패키지 | 버전 |
|--------|------|
| `flutter_local_notifications` | `^17.0.0` |
| `open_file` | `^3.3.2` |

### Flutter 변경 사항

#### `lib/utils/excel_save_io.dart`

- 파일 저장 완료 후 기존 snackbar 표시 직후에 notification helper를 호출한다.
- 파일 경로를 인자로 전달한다.

#### `lib/utils/download_notification.dart` (신규 파일)

- `FlutterLocalNotificationsPlugin` 초기화 로직을 담는다.
- 파일명과 경로를 받아 알림을 표시하는 함수를 제공한다.
- 알림 탭 시 `OpenFile.open(path)`를 호출한다.
- iOS 초기화는 포함하되 알림 발송 로직은 Android 전용으로 처리한다.

#### Android 알림 권한

- Android 13 이상에서는 `flutter_local_notifications`가 `POST_NOTIFICATIONS` 권한을 런타임에 요청한다.
- 패키지의 manifest merge를 통해 `POST_NOTIFICATIONS` 선언이 자동 추가되지만, 구현 후 `android/app/build/intermediates/merged_manifests/`에서 실제 포함 여부를 확인한다.
- 확인 결과 누락된 경우 `AndroidManifest.xml`에 직접 추가한다:
  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  ```

---

## 범위 외 (Out of Scope)

이번 구현에서 다루지 않는 항목:

- 동아리 생성/삭제 UI
- 동아리에 유저 초대하는 기능
- Emoji → icon 교체 (별도 작업)
- 동아리 전환 이벤트에 대한 push notification
