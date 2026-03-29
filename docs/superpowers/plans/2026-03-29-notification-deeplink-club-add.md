# Notification Deep-link, Club Add Button & Bottom Bar Fix Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a notification → open that post's comments sheet directly; always show club add button for single-club users; fix Android bottom bar overlapping comment input.

**Architecture:** Three isolated changes to `feed_screen.dart`, `home_screen.dart`, and `api_client.dart`. No new files. `FeedScreen` gains optional `pendingPostId`/`onPostIdConsumed` params; `HomeScreen` passes them and sets `_pendingPostId` in both FCM and notification callbacks; `ApiClient` gains `getPost(int)`.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `http` package, FastAPI backend on Railway.

**Spec:** `docs/superpowers/specs/2026-03-29-notification-deeplink-club-add-design.md`

---

## Chunk 1: API Layer — `ApiClient.getPost`

**Files:**
- Modify: `lib/api/api_client.dart` (after existing `login` method closing `}` at line 296, before `// ── 동아리 API` at line 298)
- Test: `test/api_client_test.dart`

### Task 1: Add `getPost` unit test

- [ ] **1.1 Create test file**

```dart
// test/api_client_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getPost 404 detection', () {
    test('response without id key is treated as not found', () {
      // Simulates FastAPI 404: {"detail": "Not found"}
      final notFoundResponse = <String, dynamic>{'detail': 'Not found'};
      expect(notFoundResponse.containsKey('id'), isFalse);
    });

    test('valid post response contains id key', () {
      final validPost = <String, dynamic>{
        'id': 42,
        'content': 'hello',
        'author_display_name': 'test',
      };
      expect(validPost.containsKey('id'), isTrue);
    });
  });
}
```

- [ ] **1.2 Run test — expect PASS (pure logic, no HTTP)**

```bash
cd C:/projects/performance_manager
flutter test test/api_client_test.dart -v
```

Expected: `00:00 +2: All tests passed!`

### Task 2: Implement `ApiClient.getPost`

- [ ] **2.1 Add method to `api_client.dart` after the `login` method (~line 296)**

```dart
static Future<Map<String, dynamic>> getPost(int postId) async {
  final headers = await _authOnlyHeaders();
  final response = await http.get(
    Uri.parse('$baseUrl/posts/$postId'),
    headers: headers,
  ).timeout(_timeout);
  return _parseResponse(response);
}
```

- [ ] **2.2 Run tests**

```bash
flutter test test/api_client_test.dart -v
```

Expected: `00:00 +2: All tests passed!`

- [ ] **2.3 Commit**

```bash
cd C:/projects/performance_manager
git add lib/api/api_client.dart test/api_client_test.dart
git commit -m "feat: add ApiClient.getPost for notification deep-link"
```

---

## Chunk 2: FeedScreen — Deep-link Params & `_openPostById`

**Files:**
- Modify: `lib/screens/feed_screen.dart`
  - Lines 9-14: `FeedScreen` class declaration
  - Lines ~40-64: `initState`
  - After `initState`: add `didUpdateWidget`
  - After `_showComments` (~line 235): add `_openPostById`
  - Line 1209: `_CommentsSheet` input container padding

### Task 3: Add constructor params to `FeedScreen`

- [ ] **3.1 Replace `FeedScreen` class declaration (lines 9-14)**

```dart
class FeedScreen extends StatefulWidget {
  final int? pendingPostId;
  final VoidCallback? onPostIdConsumed;

  const FeedScreen({
    super.key,
    this.pendingPostId,
    this.onPostIdConsumed,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}
```

- [ ] **3.2 Run app compiles**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

Expected: build succeeds (no errors referencing `FeedScreen`).

### Task 4: Add `initState` trigger + `didUpdateWidget`

- [ ] **4.1 At the END of `initState` (lines 28-35, before the closing `}`), add the initial deep-link check**

Find the closing `}` of `initState` — the last statement before it is `_loadAll();`. Add just before the closing brace:

```dart
    // Deep-link: open specific post on first mount
    if (widget.pendingPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPostById(widget.pendingPostId!),
      );
    }
```

- [ ] **4.2 Add `didUpdateWidget` after `initState`**

```dart
  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingPostId != widget.pendingPostId &&
        widget.pendingPostId != null) {
      _openPostById(widget.pendingPostId!);
    }
  }
```

### Task 5: Implement `_openPostById`

- [ ] **5.1 Add `_openPostById` method after `_showComments` (~line 235)**

```dart
  Future<void> _openPostById(int postId) async {
    if (!mounted) return;

    // 1. Check already-loaded posts first (O(n) scan)
    dynamic post;
    try {
      post = _clubPosts.firstWhere((p) => (p['id'] as num?)?.toInt() == postId);
    } catch (_) {
      post = null;
    }
    if (post == null) {
      try {
        post = _globalPosts.firstWhere((p) => (p['id'] as num?)?.toInt() == postId);
      } catch (_) {
        post = null;
      }
    }

    // 2. Fetch from API if not in local list
    if (post == null) {
      try {
        final result = await ApiClient.getPost(postId);
        if (!result.containsKey('id')) {
          // FastAPI 404 → {"detail": "Not found"} — no 'id' key
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('게시글을 찾을 수 없습니다.')),
            );
          }
          return;
        }
        post = result;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('게시글을 찾을 수 없습니다.')),
          );
        }
        return;
      }
    }

    // 3. Signal consumed BEFORE opening sheet (safe: sheet captures local `post`)
    widget.onPostIdConsumed?.call();

    // 4. Open comments sheet after current frame (required — must not call
    //    showModalBottomSheet from initState/didUpdateWidget directly)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showComments(post);
    });
  }
```

- [ ] **5.2 Verify compile**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

Expected: no errors.

### Task 6: Fix `_CommentsSheet` bottom bar overlap (Android)

- [ ] **6.1 Find line 1209 in `feed_screen.dart` — the comment input container padding**

Current:
```dart
padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
```

Replace with:
```dart
padding: EdgeInsets.fromLTRB(
  16, 10, 16, 10 + MediaQuery.of(context).viewPadding.bottom,
),
```

Note: `const` is removed because `viewPadding` is runtime-only. The outer `Padding` in `_CommentsSheet` already handles `viewInsets.bottom` (keyboard), so only `viewPadding.bottom` (nav bar) is added here.

- [ ] **6.2 Verify compile**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

- [ ] **6.3 Commit**

```bash
git add lib/screens/feed_screen.dart
git commit -m "feat: add FeedScreen deep-link params and _openPostById; fix CommentsSheet bottom padding"
```

---

## Chunk 3: HomeScreen — Wire `_pendingPostId`

**Files:**
- Modify: `lib/screens/home_screen.dart`
  - Line 62: `FcmService.init` lambda
  - Line 996: `NotificationsScreen` `onPostTap` callback
  - Line 132: `const FeedScreen()` in `_screens` getter

### Task 7: Add `_pendingPostId` field and wire both callback sites

- [ ] **7.1 Add state field**

In `_HomeScreenState`, add after the existing state fields (near the top of the class, around line ~30):

```dart
int? _pendingPostId;
```

- [ ] **7.2 Update `FcmService.init` lambda (line ~62)**

Current:
```dart
FcmService.init(
  onPostTap: (postId) => setState(() => _currentIndex = 1),
);
```

Replace with:
```dart
FcmService.init(
  onPostTap: (postId) => setState(() {
    _pendingPostId = postId;
    _currentIndex = 1; // Feed is always index 1 (see _screens getter — unconditional, position 1)
  }),
);
```

- [ ] **7.3 Update `NotificationsScreen` `onPostTap` callback (line ~994-997)**

Current:
```dart
onPostTap: (postId) {
  // Switch to feed tab (index 1 = 피드)
  setState(() => _currentIndex = 1);
},
```

Replace with:
```dart
onPostTap: (postId) {
  // NotificationsScreen already calls Navigator.pop before this callback fires.
  // Do NOT call Navigator.pop here.
  setState(() {
    _pendingPostId = postId;
    _currentIndex = 1; // Feed is always index 1 (see _screens getter — unconditional, position 1)
  });
},
```

### Task 8: Pass params to `FeedScreen` in `_screens`

- [ ] **8.1 Replace `const FeedScreen()` in `_screens` getter (line ~132)**

Current:
```dart
const FeedScreen(),
```

Replace with:
```dart
FeedScreen(
  pendingPostId: _pendingPostId,
  onPostIdConsumed: () => setState(() => _pendingPostId = null),
),
```

Note: `const` is dropped because `_pendingPostId` is a runtime value. `isScrollControlled: true` is already set in `_showComments` at line 223 — no change needed there.

- [ ] **8.2 Verify compile**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

Expected: no errors.

- [ ] **8.3 Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: wire _pendingPostId through HomeScreen to FeedScreen for notification deep-link"
```

---

## Chunk 4: HomeScreen — Club Add Button for Single-Club Users

**Files:**
- Modify: `lib/screens/home_screen.dart` (lines ~955-962: `else Text(_currentClubName)`)

### Task 9: Replace plain Text with IconButton for single-club users

- [ ] **9.1 Find the `else` branch (~line 955-962)**

Current:
```dart
                  else
                    Text(
                      _currentClubName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                      ),
                    ),
```

Replace with:
```dart
                  else
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      color: colorScheme.onPrimaryContainer,
                      tooltip: '동아리 추가',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClubOnboardingScreen(isPostLogin: true),
                        ),
                      ),
                    ),
```

- [ ] **9.2 Verify compile**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

Expected: no errors.

- [ ] **9.3 Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: show add-club button in AppBar for single-club users"
```

---

## Chunk 5: Verify & Clean Up

### Task 10: Restore friendly error messages

> During debugging, `login_screen.dart` was modified to show raw errors. Restore it.

- [ ] **10.1 In `lib/screens/login_screen.dart`, restore both catch blocks**

In `_login()` catch:
```dart
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
```

In `_kakaoLogin()` catch (restore `error 1` filter):
```dart
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('canceled') || msg.contains('cancel') ||
          msg.contains('user_cancelled') ||
          msg.contains('webauthnticationsession error 1') ||
          msg.contains('error 1')) {
        return;
      }
      _showError(friendlyError(e));
    } finally {
```

- [ ] **10.2 Verify compile**

```bash
flutter build apk --dart-define-from-file=dart_defines.json 2>&1 | tail -5
```

### Task 11: Full build and manual test

- [ ] **11.1 Run all tests**

```bash
flutter test -v
```

Expected: all tests pass.

- [ ] **11.2 Build release APK**

```bash
flutter build apk --dart-define-from-file=dart_defines.json
```

- [ ] **11.3 Manual test checklist (Android)**

| Scenario | Expected |
|----------|----------|
| Tap notification with post_id (in-app, from another tab) | Switches to Feed, comments sheet opens |
| Tap notification with post_id (in-app, already on Feed tab) | Comments sheet opens |
| Tap notification without post_id | No navigation change |
| Tap notification for deleted post | Snackbar "게시글을 찾을 수 없습니다." |
| Single-club user: AppBar shows + button | Tapping opens ClubOnboardingScreen |
| Multi-club user: AppBar shows switcher chip | Existing behavior unchanged |
| Open comments sheet on Galaxy → keyboard dismissed | Input row sits above nav bar |
| Open comments sheet on Galaxy → keyboard open | Input row sits above keyboard |

- [ ] **11.4 Final commit**

```bash
git add lib/screens/login_screen.dart
git commit -m "fix: restore friendly error messages after debug session"
```

---

## Summary of Changes

| File | What changes |
|------|-------------|
| `lib/api/api_client.dart` | Add `getPost(int postId)` |
| `lib/screens/feed_screen.dart` | Add `pendingPostId`/`onPostIdConsumed` params; `initState` + `didUpdateWidget` triggers; `_openPostById`; CommentsSheet bottom padding |
| `lib/screens/home_screen.dart` | `_pendingPostId` field; update FcmService.init lambda; update NotificationsScreen callback; pass params to FeedScreen; club add button |
| `lib/screens/login_screen.dart` | Restore friendly error messages |
| `test/api_client_test.dart` | 404 detection logic tests |
