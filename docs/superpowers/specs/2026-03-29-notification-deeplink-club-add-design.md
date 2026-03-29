# Design: Notification Deep-link & Club Add Button

**Date:** 2026-03-29
**Status:** Approved

---

## Overview

Three independent UI improvements:

1. **Notification Deep-link** — Tapping a notification that has a `post_id` navigates directly to that post's comments sheet.
2. **Club Add Button for Single-Club Users** — Users belonging to only one club cannot access the club switcher or add a new club. This fix makes the button always visible.
3. **Comments Sheet Bottom Bar Overlap (Android)** — System navigation bar overlaps the comment input field on Galaxy devices.

---

## Feature 1: Notification Deep-link

### Goal
When a user taps a notification (in-app or FCM push), if the notification has a `post_id`, the app navigates to the Feed tab and immediately opens the `_CommentsSheet` for that post.

### Current State
- `NotificationsScreen` calls `Navigator.pop(context)` and then invokes `widget.onPostTap!(postId)`. The pop happens inside `NotificationsScreen` itself before the callback fires.
- `HomeScreen` receives `onPostTap` and sets `_currentIndex = 1` (Feed tab). Feed is always at index 1: `NoticeScreen` is unconditional at index 0, `FeedScreen` is unconditional at index 1 — this is true for all roles.
- `body: _screens[_currentIndex]` renders only the active tab. `FeedScreen` is **not** kept mounted when the user is on another tab.
- `fcm_service.dart` `_onPostTap(postId)` uses the same callback path.

### Proposed Changes

#### `HomeScreen`
- Add `int? _pendingPostId` state field.
- **Two places** must be updated to set `_pendingPostId`:
  1. **`NotificationsScreen` callback** (`onPostTap` wired at line ~994): `setState(() { _pendingPostId = postId; _currentIndex = 1; })`.
     - **Do NOT call `Navigator.pop` here** — `NotificationsScreen` already pops itself before invoking this callback.
  2. **`FcmService.init` lambda** (in `initState`, line ~62): update from `setState(() => _currentIndex = 1)` to `setState(() { _pendingPostId = postId; _currentIndex = 1; })`.
- Add code comment at `_currentIndex = 1`: `// Feed is always index 1 (see _screens getter — unconditional, position 1)`
- Pass `pendingPostId: _pendingPostId` and `onPostIdConsumed: () => setState(() { _pendingPostId = null; })` to `FeedScreen`.

#### `FeedScreen`
- Accept `int? pendingPostId` and `VoidCallback? onPostIdConsumed` as constructor parameters.
- Remove `const` from the `FeedScreen()` instantiation in `_screens` — adding non-const parameters requires dropping `const`.
- **Two trigger sites** (required because `FeedScreen` is only mounted when active):
  - **`initState`**: if `widget.pendingPostId != null`, call `WidgetsBinding.instance.addPostFrameCallback((_) => _openPostById(widget.pendingPostId!))`. Handles the primary case: user is on another tab when notification arrives, `FeedScreen` mounts fresh.
  - **`didUpdateWidget`**: if `oldWidget.pendingPostId != widget.pendingPostId && widget.pendingPostId != null`, call `_openPostById(widget.pendingPostId!)`. Handles the case where the user is already on Feed tab when notification arrives.
- Do NOT use `ValueKey` on `FeedScreen` — remounting destroys loaded post lists, scroll position, and TabController state.

#### `_openPostById(int postId)`
1. Check `_clubPosts` / `_globalPosts` for a matching `'id'`; use that entry if found.
2. Otherwise call `await ApiClient.getPost(postId)`.
3. **404 detection**: if result map does not contain key `'id'` (FastAPI 404 returns `{"detail": "Not found"}` — no `'id'` key), treat as not found.
4. If not found or fetch throws, show snackbar "게시글을 찾을 수 없습니다." and return.
5. Call `onPostIdConsumed?.call()`. Safe to call before the sheet opens: the sheet uses the local `post` variable, not `widget.pendingPostId`.
6. `WidgetsBinding.instance.addPostFrameCallback((_) { if (!mounted) return; _showComments(post); })` — call the existing `_showComments(post)` helper, which already constructs `_CommentsSheet` with all required parameters (`myDisplayName`, `role`, `onChanged`, etc.) and configures `showModalBottomSheet` correctly. Do NOT construct `_CommentsSheet` directly in `_openPostById`.

#### `ApiClient.getPost(int postId)`
- `static Future<Map<String, dynamic>> getPost(int postId)`
- `GET /posts/{postId}` with auth headers.
- Uses existing `_parseResponse` — throws `ServerException` on 500+.
- Returns same map shape as items in `getPosts` (contains `'id'` key), compatible with `_showComments` without adaptation.
- 404 returns `{"detail": "Not found"}` — no `'id'` key — caller detects via `result.containsKey('id')`.

### Data Flow
```
User taps notification (in NotificationsScreen)
  → NotificationsScreen: Navigator.pop(context)  ← already in existing code
  → onPostTap(postId)
  → HomeScreen: _pendingPostId = postId, _currentIndex = 1
  → FeedScreen mounted (initState) OR updated (didUpdateWidget)
  → addPostFrameCallback → _openPostById(postId)
    → find in list OR ApiClient.getPost(postId)
    → onPostIdConsumed() → _pendingPostId = null in HomeScreen
    → _showComments(post) → showModalBottomSheet(_CommentsSheet)
```

### Edge Cases
- `post_id` is null: no navigation, normal behavior.
- Post not found: snackbar, no sheet.
- FCM from terminated state: `getInitialMessage` in `fcm_service.dart` uses same callback.
- `if (mounted)` guard prevents setState on unmounted widget.
- `_openPostById` fetches independently, unaffected by `_isLoading`.

---

## Feature 2: Club Add Button for Single-Club Users

### Goal
Users in only one club should be able to add (create or join) another club via the AppBar, reusing `ClubOnboardingScreen(isPostLogin: true)`.

### Current State
```dart
if (widget.clubs.length >= 2)
  GestureDetector(onTap: () => showModalBottomSheet(..._ClubSwitcherSheet...), ...)
else
  Text(_currentClubName)  // no tap target
```

### Proposed Changes
- **`clubs.length >= 2`**: existing behavior unchanged.
- **`clubs.length == 1`**: replace plain `Text` with `IconButton(icon: Icon(Icons.add_circle_outline), iconSize: 16, padding: EdgeInsets.zero)` that pushes `ClubOnboardingScreen(isPostLogin: true)`. Fall back to `AppBar.actions` placement if layout overflow occurs.
- **`clubs.length == 0`**: leave existing `Text(_currentClubName)` untouched (out of scope).

No changes to `_ClubSwitcherSheet` or `ClubOnboardingScreen`.

---

## Feature 3: Comments Sheet Bottom Bar Overlap (Android)

### Goal
Fix comment input field being obscured by Android system navigation bar on Galaxy devices.

### Root Cause
The `_CommentsSheet` outer `Padding` already applies `viewInsets.bottom` to lift the sheet when the keyboard opens. The system navigation bar height (`viewPadding.bottom`, 24–48px depending on nav mode) is not added, so the input row sits behind the nav bar when the keyboard is closed.

### Proposed Fix
In the comment input `Container` (currently `padding: const EdgeInsets.fromLTRB(16, 10, 16, 10)`), add `viewPadding.bottom` to the existing bottom padding value:

```dart
padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).viewPadding.bottom),
```

Do **not** add `viewInsets.bottom` here — the outer `Padding` already handles keyboard lift, and re-applying it would push the input too far up when the keyboard is open.

Confirm `isScrollControlled: true` is set on `showModalBottomSheet` (required for keyboard resize).

No backend changes needed.

---

## Files to Change

| File | Change |
|------|--------|
| `lib/screens/home_screen.dart` | `_pendingPostId` state, `onPostTap` handler + comment, `onPostIdConsumed` callback, AppBar club button logic |
| `lib/screens/feed_screen.dart` | `pendingPostId` + `onPostIdConsumed` params, `initState` + `didUpdateWidget` triggers, `_openPostById`; `_CommentsSheet` input padding fix |
| `lib/api/api_client.dart` | Add `getPost(int postId)` |

---

## Out of Scope
- Audio MP3 submission (separate feature)
- Notification deep-link for non-post notifications (e.g. notice comments)
- Dynamic Feed tab index computation (index 1 is correct for all roles today; deferred)
- `clubs.length == 0` case (left untouched)
