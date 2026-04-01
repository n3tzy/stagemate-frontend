---
title: UX 개선 5종 — 삭제·권한·동아리추가·아이콘·프로필편집
date: 2026-03-29
status: approved
---

# UX 개선 5종 구현 스펙

---

## Feature 1: 내 게시글/댓글에서 삭제 기능

### 배경

`MyActivityScreen`은 내 게시글과 댓글을 탭으로 보여주는 화면이다. 현재 읽기 전용이며 삭제 기능이 없다.

### 설계

- 각 게시글/댓글 항목 오른쪽에 `delete_outline` 아이콘 버튼 추가
- 탭 시 확인 다이얼로그 표시: `"삭제하시겠어요? 이 작업은 되돌릴 수 없어요."`
- 확인 → API 호출 → 성공 시 목록에서 해당 항목 제거 + 스낵바 `"삭제됐어요."`
- 실패 시 스낵바: `friendlyError(e)`

### 백엔드 (변경 없음)

이미 구현된 엔드포인트 사용:
- 게시글: `DELETE /posts/{post_id}`
- 댓글: `DELETE /posts/{post_id}/comments/{comment_id}`

댓글 응답에는 `post_id` 필드가 포함되어 있어 댓글 삭제 API 호출에 사용 가능.

### Flutter 변경

**파일:** `lib/screens/my_activity_screen.dart`

- 게시글 탭: 각 ListTile/Card에 `trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: () => _deletePost(post['id']))` 추가
- 댓글 탭: 각 항목에 `trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: () => _deleteComment(post_id, comment['id']))` 추가
- `_deletePost(int postId)`: 확인 다이얼로그 → `ApiClient.deletePost(postId)` → setState로 목록 갱신
- `_deleteComment(int postId, int commentId)`: 확인 다이얼로그 → `ApiClient.deletePostComment(postId, commentId)` → setState로 목록 갱신
- 댓글 응답에는 `post_id` 필드가 포함됨 (백엔드 `/users/me/activity` 응답 확인). `c['post_id']`로 접근 가능.
- `ApiClient.deletePost(int postId)`: 이미 존재 (`DELETE /posts/{postId}`)
- `ApiClient.deletePostComment(int postId, int commentId)`: 이미 존재 (`DELETE /posts/{postId}/comments/{commentId}`)

---

## Feature 2: 음원 제출 권한 전체 개방

### 설계

`home_screen.dart`의 `_canSubmitAudio` getter를 `true`로 변경:

```dart
// 변경 전
bool get _canSubmitAudio => _currentRole == 'team_leader' || _currentRole == 'admin' || _currentRole == 'super_admin';

// 변경 후
bool get _canSubmitAudio => true;
```

모든 역할(`user` 포함)이 음원 제출 탭에 접근 가능하다.

---

## Feature 3: 로그인 후 동아리 생성/가입

### 배경

현재 `ClubOnboardingScreen`은 최초 로그인 시에만 접근 가능하다. 이미 로그인된 사용자가 추가 동아리에 가입하거나 새 동아리를 만들 방법이 없다.

### 설계

**진입점:** `_ClubSwitcherSheet` 하단에 구분선 + `+ 새 동아리 추가` 버튼

**버튼 탭 시 흐름:**
1. `_ClubSwitcherSheet`의 `onAddClub` 콜백 호출 (시트 내부에서 직접 push하지 않음)
2. `_HomeScreenState`의 `onAddClub` 핸들러가 바텀시트를 닫고 `ClubOnboardingScreen(isPostLogin: true)` push
3. 사용자가 동아리 생성 or 참가 완료
4. `getMyClubs()` 재조회 → 새 동아리로 `setClubInfo()` → `Navigator.pushAndRemoveUntil`로 새 `HomeScreen` 이동 (welcome dialog 생략)

**`_ClubSwitcherSheet` 변경:**
- `VoidCallback? onAddClub` 파라미터 추가
- 동아리 목록 하단에 `Divider` + `ListTile` 추가:
  - 아이콘: `Icons.add_circle_outline`
  - 제목: `새 동아리 추가`
  - 부제목: `만들거나 코드로 참가할 수 있어요`
  - 색상: `colorScheme.primary`
  - `onTap`: `Navigator.pop(context)` 후 `onAddClub?.call()`

**`_HomeScreenState`에서 `showModalBottomSheet` 호출 시 `onAddClub` 전달:**
```dart
onAddClub: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ClubOnboardingScreen(isPostLogin: true)),
  );
},
```

**`ClubOnboardingScreen` 변경:**
- `bool isPostLogin = false` 파라미터 추가
- 내부에서 `ClubCreateScreen(isPostLogin: isPostLogin)` 및 `ClubJoinScreen(isPostLogin: isPostLogin)`으로 전달

**`ClubCreateScreen` / `ClubJoinScreen` 변경:**
- `bool isPostLogin = false` 파라미터 추가
- 완료 시 welcome dialog 조건부 표시:
  ```dart
  if (!widget.isPostLogin) {
    await showWelcomeDialog(...);
  }
  ```
- navigation은 동일하게 `pushAndRemoveUntil`로 `HomeScreen` 이동 (stack 초기화, clubs 최신화):
  ```dart
  // ClubCreateScreen / ClubJoinScreen 완료 시
  final clubs = await ApiClient.getMyClubs();
  final clubList = clubs.cast<Map<String, dynamic>>();
  final target = clubList.last; // 방금 생성/가입한 동아리
  await ApiClient.setClubInfo(
    (target['club_id'] as num).toInt(),
    target['club_name'] as String,
    target['role'] as String,
  );
  if (mounted) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(
        displayName: ...,
        role: target['role'] as String,
        clubName: target['club_name'] as String,
        clubs: clubList,
      )),
      (route) => false,
    );
  }
  ```

**`_ClubSwitcherSheet` `onTap` 처리 순서 (context 이슈 방지):**
1. `_ClubSwitcherSheet`의 ListTile `onTap`에서 먼저 `Navigator.pop(context)` 호출 (시트 닫기)
2. 그 직후 `onAddClub?.call()` 호출
3. `_HomeScreenState`의 콜백 내에서 `Navigator.push(...)` 실행
→ pop과 push가 분리되어 있어 BuildContext unmount 문제 없음

---

## Feature 4: group_screen.dart 이모지 → Flutter 아이콘 교체

### 대상 이모지 및 교체 아이콘

| 위치 | 현재 이모지 | 교체 |
|------|-----------|------|
| line 614 — 최적 추천 시간 레이블 | 🏆 | `Icon(Icons.workspace_premium, color: Colors.amber)` |
| line 648 — 전원 가능 시간 레이블 | ✅ | `Icon(Icons.check_circle, color: Colors.green)` |
| line 665 — CircleAvatar (전원 가능) | ✅ | `Icon(Icons.check_circle, color: Colors.white, size: 16)` |
| line 671, 719 — 인원 수 부제목 | 👥 | `Icon(Icons.people, size: 14, color: Colors.grey)` (텍스트와 Row로 감쌈) |
| line 696 — 일부 가능 시간 레이블 | 🔶 | `Icon(Icons.schedule, color: Colors.orange)` |
| line 713 — CircleAvatar (일부 가능) | 🔶 | `Icon(Icons.schedule, color: Colors.white, size: 16)` |
| line 750 — 공통 시간 없음 메시지 | 😢 | `Icon(Icons.sentiment_dissatisfied, size: 48, color: Colors.grey)` |
| line 239 — 저장 성공 스낵바 | ✅ | 이모지 제거, 텍스트만 (`'저장됐습니다!'`) |

---

---

## Feature 5: 동아리 프로필 편집 시트 개선

### 배경

`ClubProfileEditSheet` (파일: `lib/screens/club_profile_sheet.dart`)에 두 가지 문제가 있다:
1. Android 시스템 네비게이션 바(하단 바)가 시트 콘텐츠를 가린다 — `저장` 버튼이 잘 보이지 않음.
2. 로고·배너 이미지를 URL 텍스트로 직접 입력해야 한다 — UX가 불편하고 일반 사용자가 사용하기 어렵다.

### 설계

#### 5-1. 하단 바 겹침 수정

현재 padding:
```dart
bottom: MediaQuery.of(context).viewInsets.bottom + 24,
```

수정 후:
```dart
bottom: MediaQuery.of(context).viewInsets.bottom
      + MediaQuery.of(context).padding.bottom
      + 24,
```

`padding.bottom`은 시스템 네비게이션 바 높이를 포함한다. 키보드가 올라온 경우 `viewInsets.bottom`이 `padding.bottom`보다 커지므로 두 값을 더하는 것이 아니라 `max`를 취해야 안전하다:

```dart
final bottomInset = MediaQuery.of(context).viewInsets.bottom;
final bottomPad   = MediaQuery.of(context).padding.bottom;
// ...
bottom: (bottomInset > 0 ? bottomInset : bottomPad) + 24,
```

#### 5-2. 이미지 URL → 갤러리 선택으로 교체

**변경 내용:**
- `TextEditingController _logoCtrl`, `_bannerCtrl` 제거
- `String? _logoUrl`, `String? _bannerUrl` 상태 변수로 교체 (현재 업로드된 URL 보관)
- 로고·배너 각각 `_ImagePickerTile` 위젯으로 교체:
  - 현재 이미지 미리보기 (썸네일) 또는 빈 자리 표시
  - `사진 선택` 버튼 → `image_picker`로 갤러리에서 이미지 선택
  - 선택 즉시 업로드 시작 (loading indicator 표시)
  - 업로드 완료 시 `_logoUrl` / `_bannerUrl` 갱신

**업로드 방식:** 기존 Presigned URL 패턴 사용 (이미 `ApiClient.getPresignedUrl(filename, 'image/jpeg')` 구현됨)

```dart
Future<String?> _pickAndUpload(String field) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
  if (picked == null) return null;

  final filename = '${field}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final presigned = await ApiClient.getPresignedUrl(filename, 'image/jpeg');
  final uploadUrl = presigned['upload_url'] as String;
  final publicUrl = presigned['public_url'] as String;

  final bytes = await File(picked.path).readAsBytes();
  final res = await http.put(Uri.parse(uploadUrl), body: bytes,
      headers: {'Content-Type': 'image/jpeg'});
  if (res.statusCode != 200) throw Exception('이미지 업로드 실패');
  return publicUrl;
}
```

**`_save()` 수정:** `_logoUrl` / `_bannerUrl`을 기존 URL과 비교해 변경된 경우만 body에 포함 (기존 로직 유지).

**사용 패키지:** `image_picker` (이미 `pubspec.yaml`에 포함됨), `http` (이미 포함됨)

---

## 범위 외 (Out of Scope)

- 관리자의 타인 게시글 삭제 (별도 기능)
- 동아리 탈퇴 기능
- 동아리 전환 후 welcome dialog 표시
- 이미지 크롭 기능 (현재 구현 범위 외)
