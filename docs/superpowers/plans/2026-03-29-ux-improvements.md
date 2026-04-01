# UX 개선 5종 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 5개 UX 개선 사항 구현 — 내 활동 삭제, 음원 권한 개방, 로그인 후 동아리 추가, 이모지 아이콘 교체, 동아리 프로필 편집 시트 개선

**Architecture:** 모두 Flutter 프론트엔드 전용 변경. 백엔드 신규 엔드포인트 없음. 각 Feature는 독립적이며 순서 무관.

**Tech Stack:** Flutter, Dart, `image_picker` (기존 포함), `http` (기존 포함), Material Icons

---

## Chunk 1: Feature 1 — 내 게시글/댓글 삭제

### Task 1: `MyActivityScreen` 게시글 삭제 기능

**Files:**
- Modify: `lib/screens/my_activity_screen.dart`

- [ ] **Step 1: `_deletePost` 메서드 추가**

`_load()` 메서드 아래에 추가:

```dart
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
```

- [ ] **Step 2: 게시글 ListTile에 trailing 아이콘 추가**

`my_activity_screen.dart` 83~118 구간의 `ListTile` 위젯에 `trailing` 추가:

```dart
// 기존 ListTile(
//   leading: ...,
//   title: ...,
//   subtitle: ...,
// ),
// 변경 후:
ListTile(
  leading: ...,
  title: ...,
  subtitle: ...,
  trailing: IconButton(
    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
    onPressed: () => _deletePost((p['id'] as num).toInt()),
    tooltip: '삭제',
  ),
),
```

- [ ] **Step 3: `_deleteComment` 메서드 추가**

`_deletePost` 아래에 추가:

```dart
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
```

- [ ] **Step 4: 댓글 ListTile에 trailing 아이콘 추가**

`my_activity_screen.dart` 131~174 구간 댓글 `ListTile`에 `trailing` 추가:

```dart
ListTile(
  leading: ...,
  title: ...,
  subtitle: ...,
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
```

- [ ] **Step 5: 수동 확인 (핫 리로드)**

앱 실행 후 내 활동 화면에서:
- 게시글 탭: 삭제 아이콘 확인, 탭 시 다이얼로그 확인, 확인 후 목록에서 제거 + 스낵바 확인
- 댓글 탭: 동일하게 확인

- [ ] **Step 6: 커밋**

```bash
git add lib/screens/my_activity_screen.dart
git commit -m "feat: add delete button to MyActivityScreen posts and comments"
```

---

## Chunk 2: Feature 2 — 음원 제출 권한 전체 개방

### Task 2: `_canSubmitAudio` getter를 `true`로 변경

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: getter 수정**

`home_screen.dart`에서 `_canSubmitAudio` getter를 찾아 변경:

```dart
// 변경 전
bool get _canSubmitAudio => _currentRole == 'team_leader' || _currentRole == 'admin' || _currentRole == 'super_admin';

// 변경 후
bool get _canSubmitAudio => true;
```

- [ ] **Step 2: 수동 확인**

`user` role 계정으로 로그인해 홈 화면에서 음원 제출 탭이 보이는지 확인.

- [ ] **Step 3: 커밋**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: allow all roles to access audio submission tab"
```

---

## Chunk 3: Feature 3 — 로그인 후 동아리 추가

### Task 3: `_ClubSwitcherSheet`에 `onAddClub` 콜백 + 버튼 추가

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: `_ClubSwitcherSheet`에 `onAddClub` 파라미터 추가**

`home_screen.dart` 내 `_ClubSwitcherSheet` StatelessWidget에서:

```dart
// 기존
class _ClubSwitcherSheet extends StatelessWidget {
  final List<Map<String, dynamic>> clubs;
  final int currentClubId;
  final void Function(Map<String, dynamic>) onSelect;

  const _ClubSwitcherSheet({
    required this.clubs,
    required this.currentClubId,
    required this.onSelect,
  });

// 변경 후
class _ClubSwitcherSheet extends StatelessWidget {
  final List<Map<String, dynamic>> clubs;
  final int currentClubId;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback? onAddClub;

  const _ClubSwitcherSheet({
    required this.clubs,
    required this.currentClubId,
    required this.onSelect,
    this.onAddClub,
  });
```

- [ ] **Step 2: 시트 목록 하단에 `+ 새 동아리 추가` ListTile 추가**

`_ClubSwitcherSheet`의 `build()` 내 Column/ListView 마지막에 추가:

```dart
const Divider(),
ListTile(
  leading: Icon(Icons.add_circle_outline,
      color: Theme.of(context).colorScheme.primary),
  title: Text(
    '새 동아리 추가',
    style: TextStyle(color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold),
  ),
  subtitle: const Text('만들거나 코드로 참가할 수 있어요'),
  onTap: () {
    Navigator.pop(context);
    onAddClub?.call();
  },
),
```

- [ ] **Step 3: `showModalBottomSheet` 호출 시 `onAddClub` 전달**

`_HomeScreenState`에서 `_ClubSwitcherSheet` 생성 시:

```dart
_ClubSwitcherSheet(
  clubs: widget.clubs,
  currentClubId: _currentClubId,
  onSelect: (club) { /* 기존 로직 */ },
  onAddClub: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ClubOnboardingScreen(isPostLogin: true),
      ),
    );
  },
)
```

- [ ] **Step 4: 커밋**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add 'new club' button to ClubSwitcherSheet"
```

### Task 4: `ClubOnboardingScreen` / `ClubCreateScreen` / `ClubJoinScreen`에 `isPostLogin` 파라미터 추가

**Files:**
- Modify: `lib/screens/club_onboarding_screen.dart`

- [ ] **Step 1: `ClubOnboardingScreen`에 `isPostLogin` 파라미터 추가**

```dart
class ClubOnboardingScreen extends StatelessWidget {
  final bool isPostLogin;
  const ClubOnboardingScreen({super.key, this.isPostLogin = false});
```

그리고 내부에서 `ClubCreateScreen` / `ClubJoinScreen` push 시 전달:
```dart
MaterialPageRoute(builder: (_) => ClubCreateScreen(isPostLogin: isPostLogin))
MaterialPageRoute(builder: (_) => ClubJoinScreen(isPostLogin: isPostLogin))
```

- [ ] **Step 2: `ClubCreateScreen`에 `isPostLogin` 파라미터 추가**

```dart
class ClubCreateScreen extends StatefulWidget {
  final bool isPostLogin;
  const ClubCreateScreen({super.key, this.isPostLogin = false});
```

`ClubCreateScreen` → `ClubJoinScreen` push 시도 있다면 동일하게 전달:
```dart
MaterialPageRoute(builder: (_) => ClubJoinScreen(isPostLogin: widget.isPostLogin))
```

- [ ] **Step 3: `ClubCreateScreen` 완료 시 `showWelcomeDialog` 조건부 처리**

`_ClubCreateScreenState`에서 동아리 생성 완료 후:
```dart
// 기존
await showWelcomeDialog(context: context, isCreator: true, ...);

// 변경 후
if (!widget.isPostLogin) {
  await showWelcomeDialog(context: context, isCreator: true, ...);
}
```

navigation (`pushAndRemoveUntil`)은 변경 없음 — `isPostLogin` 여부와 무관하게 동일하게 새 `HomeScreen`으로 이동.

- [ ] **Step 4: `ClubJoinScreen`에 `isPostLogin` 파라미터 추가 + welcome dialog 조건부 처리**

```dart
class ClubJoinScreen extends StatefulWidget {
  final bool isPostLogin;
  const ClubJoinScreen({super.key, this.isPostLogin = false});
```

`_ClubJoinScreenState`에서 가입 완료 후:
```dart
if (!widget.isPostLogin) {
  await showWelcomeDialog(context: context, isCreator: false, ...);
}
// 이후 pushAndRemoveUntil은 그대로 유지
```

- [ ] **Step 5: 수동 확인**

1. 동아리 2개 이상 계정으로 로그인
2. 앱바의 switcher 탭 → 바텀시트 열림 확인
3. `새 동아리 추가` 버튼 탭 → 시트 닫히고 ClubOnboardingScreen 열림 확인
4. 동아리 만들기 또는 코드 참가 → welcome dialog 없이 바로 HomeScreen 이동 확인

- [ ] **Step 6: 커밋**

```bash
git add lib/screens/club_onboarding_screen.dart
git commit -m "feat: support post-login club creation and joining"
```

---

## Chunk 4: Feature 4 — group_screen.dart 이모지 → 아이콘 교체

### Task 5: 이모지 7곳 교체

**Files:**
- Modify: `lib/screens/group_screen.dart`

- [ ] **Step 1: line 239 — 저장 성공 스낵바 이모지 제거**

```dart
// 변경 전
content: Text('✅ 저장됐습니다!'),

// 변경 후
content: Text('저장됐습니다!'),
```

- [ ] **Step 2: line 614 — 🏆 → `workspace_premium` 아이콘**

```dart
// 변경 전
Text('🏆', style: TextStyle(fontSize: 20)),

// 변경 후
Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
```

- [ ] **Step 3: line 648 — ✅ 전원 가능 시간 레이블**

```dart
// 변경 전
Text('✅ 전원 가능 시간 ...',

// 변경 후 — Text를 Row로 감쌈
Row(
  children: [
    const Icon(Icons.check_circle, color: Colors.green, size: 18),
    const SizedBox(width: 6),
    Text('전원 가능 시간 ...',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold, color: Colors.green),
    ),
  ],
),
```

- [ ] **Step 4: line 665 — CircleAvatar 내 ✅ → 아이콘**

```dart
// 변경 전
child: const Text('✅'),

// 변경 후
child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
```

- [ ] **Step 5: line 671, 719 — 👥 인원 수 부제목**

두 곳 모두:
```dart
// 변경 전
subtitle: Text('👥 $members'),

// 변경 후
subtitle: Row(
  children: [
    const Icon(Icons.people, size: 14, color: Colors.grey),
    const SizedBox(width: 4),
    Text(members, style: const TextStyle(color: Colors.grey)),
  ],
),
```

- [ ] **Step 6: line 696 — 🔶 일부 가능 시간 레이블**

```dart
// 변경 전
Text('🔶 일부 가능 시간 ...',

// 변경 후 — Row로 감쌈
Row(
  children: [
    const Icon(Icons.schedule, color: Colors.orange, size: 18),
    const SizedBox(width: 6),
    Text('일부 가능 시간 ...',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold, color: Colors.orange),
    ),
  ],
),
```

- [ ] **Step 7: line 713 — CircleAvatar 내 🔶 → 아이콘**

```dart
// 변경 전
child: const Text('🔶'),

// 변경 후
child: const Icon(Icons.schedule, color: Colors.white, size: 20),
```

- [ ] **Step 8: line 750 — 😢 공통 시간 없음 메시지**

```dart
// 변경 전 — Text 단독
Text('😢 공통 가능 시간이 없어요...',

// 변경 후 — Column으로 감쌈
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Icon(Icons.sentiment_dissatisfied, size: 48, color: Colors.grey),
    const SizedBox(height: 8),
    Text('공통 가능 시간이 없어요.\n멤버들의 가능 시간을 다시 확인해주세요!',
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      textAlign: TextAlign.center,
    ),
  ],
),
```

- [ ] **Step 9: 수동 확인**

그룹 화면에서 일정 최적화 결과를 확인해 이모지가 아이콘으로 교체됐는지 확인.

- [ ] **Step 10: 커밋**

```bash
git add lib/screens/group_screen.dart
git commit -m "feat: replace keyboard emojis with Material icons in group_screen"
```

---

## Chunk 5: Feature 5 — 동아리 프로필 편집 시트 개선

### Task 6: 하단 바 겹침 수정 + 이미지 피커 교체

**Files:**
- Modify: `lib/screens/club_profile_sheet.dart`

- [ ] **Step 1: import 추가**

파일 상단에 추가:
```dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
```

- [ ] **Step 2: `_ClubProfileEditSheetState` 상태 변수 교체**

```dart
// 제거
late final TextEditingController _logoCtrl;
late final TextEditingController _bannerCtrl;

// 추가
String? _logoUrl;
String? _bannerUrl;
bool _isUploadingLogo = false;
bool _isUploadingBanner = false;
```

- [ ] **Step 3: `initState` 수정**

```dart
@override
void initState() {
  super.initState();
  _logoUrl = widget.currentProfile['logo_url'] as String?;
  _bannerUrl = widget.currentProfile['banner_url'] as String?;
  _selectedColor = widget.currentProfile['theme_color'] as String?;
}
```

`dispose()`에서 `_logoCtrl.dispose()`, `_bannerCtrl.dispose()` 제거.

- [ ] **Step 4: `_pickAndUpload` 메서드 추가**

```dart
Future<String?> _pickAndUpload(String field) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 80,
  );
  if (picked == null) return null;

  final filename = '${field}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final presigned = await ApiClient.getPresignedUrl(filename, 'image/jpeg');
  final uploadUrl = presigned['upload_url'] as String;
  final publicUrl = presigned['public_url'] as String;

  final bytes = await File(picked.path).readAsBytes();
  final res = await http.put(
    Uri.parse(uploadUrl),
    body: bytes,
    headers: {'Content-Type': 'image/jpeg'},
  );
  if (res.statusCode != 200) throw Exception('이미지 업로드에 실패했어요.');
  return publicUrl;
}
```

- [ ] **Step 5: `_save()` 메서드 수정**

URL 텍스트 컨트롤러 대신 `_logoUrl` / `_bannerUrl` 상태 변수 사용:

```dart
Future<void> _save() async {
  setState(() => _isSaving = true);
  try {
    final body = <String, dynamic>{};
    if (_logoUrl != (widget.currentProfile['logo_url'] as String?)) {
      body['logo_url'] = _logoUrl;
    }
    if (_bannerUrl != (widget.currentProfile['banner_url'] as String?)) {
      body['banner_url'] = _bannerUrl;
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
    // 기존 error handling 유지
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```

- [ ] **Step 6: `build()` — padding 수정 (하단 바 겹침 수정)**

```dart
// 변경 전
padding: EdgeInsets.only(
  left: 24, right: 24, top: 24,
  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
),

// 변경 후
builder: (context) {
  final bottomInset = MediaQuery.of(context).viewInsets.bottom;
  final bottomPad   = MediaQuery.of(context).padding.bottom;
  return Padding(
    padding: EdgeInsets.only(
      left: 24, right: 24, top: 24,
      bottom: (bottomInset > 0 ? bottomInset : bottomPad) + 24,
    ),
    // ...
  );
}
```

- [ ] **Step 7: `build()` — URL TextField를 이미지 피커 버튼으로 교체**

로고 부분:
```dart
// 기존 TextField 제거하고 아래로 교체
_ImagePickerRow(
  label: '로고 이미지',
  imageUrl: _logoUrl,
  isUploading: _isUploadingLogo,
  onTap: () async {
    setState(() => _isUploadingLogo = true);
    try {
      final url = await _pickAndUpload('logo');
      if (url != null) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  },
),
const SizedBox(height: 16),
_ImagePickerRow(
  label: '배너 이미지',
  imageUrl: _bannerUrl,
  isUploading: _isUploadingBanner,
  onTap: () async {
    setState(() => _isUploadingBanner = true);
    try {
      final url = await _pickAndUpload('banner');
      if (url != null) setState(() => _bannerUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingBanner = false);
    }
  },
),
```

- [ ] **Step 8: `_ImagePickerRow` 위젯 추가 (파일 하단)**

```dart
class _ImagePickerRow extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final bool isUploading;
  final VoidCallback onTap;

  const _ImagePickerRow({
    required this.label,
    required this.imageUrl,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 썸네일
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: imageUrl != null
                ? Image.network(imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image, color: Colors.grey)))
                : Container(color: Colors.grey.shade200,
                    child: const Icon(Icons.image_outlined, color: Colors.grey)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: isUploading ? null : onTap,
                icon: isUploading
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined, size: 16),
                label: Text(isUploading ? '업로드 중...' : '사진 선택'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 9: 수동 확인**

1. 동아리 관리 → 동아리 프로필 → 프로필 편집 탭
2. 시트 하단이 네비게이션 바에 가려지지 않는지 확인
3. 로고/배너 `사진 선택` 버튼 탭 → 갤러리 열림 확인
4. 이미지 선택 → 업로드 중 indicator → 썸네일 업데이트 확인
5. 저장 버튼 탭 → 프로필 화면에서 새 이미지 반영 확인

- [ ] **Step 10: 커밋**

```bash
git add lib/screens/club_profile_sheet.dart
git commit -m "feat: fix bottom bar overlap and add image picker to club profile edit"
```

---

## Final Step: 전체 확인 및 빌드

- [ ] **Step 1: flutter analyze 실행**

```bash
cd C:/projects/performance_manager
flutter analyze
```

오류 없음 확인.

- [ ] **Step 2: Android 빌드 확인**

```bash
flutter build apk --debug
```

빌드 성공 확인.

- [ ] **Step 3: 최종 커밋 (필요시)**

```bash
git log --oneline -8
```

모든 feature 커밋이 있는지 확인.
