# Design: Notification Deep-link & Club Add Button

**Date:** 2026-03-29
**Status:** Approved

---

## Overview

Two independent UI improvements:

1. **Notification Deep-link** — Tapping a notification that has a `post_id` navigates directly to that post's comments sheet.
2. **Club Add Button for Single-Club Users** — Users belonging to only one club cannot currently access the club switcher or add a new club. This fix makes the button always visible.

---

## Feature 1: Notification Deep-link

### Goal
When a user taps a notification (in-app or FCM push), if the notification has a `post_id`, the app navigates to the Feed tab and immediately opens the `_CommentsSheet` for that post.

### Current State
- `NotificationsScreen` has an `onPostTap(int postId)` callback.
- `HomeScreen` receives this callback and switches to the Feed tab (`_currentIndex = 1`).
- `FeedScreen` is displayed but does **not** auto-open any specific post.
- `fcm_service.dart` has `_onPostTap(postId)` which also calls the same callback path.

### Proposed Changes

**`HomeScreen`**
- Add `int? _pendingPostId` state field.
- In `onPostTap`, set `_pendingPostId = postId` and switch to feed tab.
- Pass `pendingPostId` to `FeedScreen` and reset it immediately after to prevent re-trigger.

**`FeedScreen`**
- Accept optional `int? initialPostId` parameter.
- In `initState` / `didUpdateWidget`: if `initialPostId` is non-null, call a new `_openPostById(int postId)` method.
- `_openPostById`: fetch the post via `ApiClient.getPost(postId)` (or find it in the loaded list if already present), then call `showModalBottomSheet` with `_CommentsSheet` for that post.
- If the post is not in the current feed list (e.g. belongs to another club's global feed), fetch it individually and open the sheet anyway.

**API**
- If `ApiClient.getPost(postId)` does not exist, add a `GET /posts/{post_id}` endpoint call.

**`FeedScreen` key strategy**
- Use `ValueKey(_pendingPostId)` on `FeedScreen` so Flutter rebuilds it when postId changes, triggering `initState` cleanly.

### Data Flow
```
Notification tap
  → NotificationsScreen.onPostTap(postId)
  → HomeScreen._pendingPostId = postId, _currentIndex = 1
  → FeedScreen(initialPostId: postId) rebuilt via ValueKey
  → initState → _openPostById(postId)
  → showModalBottomSheet(_CommentsSheet)
```

### Edge Cases
- `post_id` is null: no navigation, normal behavior.
- Post deleted or inaccessible: show a snackbar "게시글을 찾을 수 없습니다." and do nothing.
- App launched from terminated state via FCM: handled by existing `fcm_service.dart` `getInitialMessage` path, same callback.

---

## Feature 2: Club Add Button for Single-Club Users

### Goal
Users in only one club should always be able to add (create or join) another club via the AppBar, reusing the existing `ClubOnboardingScreen(isPostLogin: true)`.

### Current State
```dart
if (widget.clubs.length >= 2)
  GestureDetector(
    onTap: () => showModalBottomSheet(..._ClubSwitcherSheet...),
    ...
  )
```
The button is hidden when `clubs.length < 2`, so single-club users have no way to add another club.

### Proposed Changes

**`HomeScreen` AppBar**

Split into two cases:

- **`clubs.length >= 2`**: existing behavior — show club name chip, tap opens `_ClubSwitcherSheet` (which already has an "동아리 추가" option internally).
- **`clubs.length == 1`**: show a small `IconButton` with `Icons.add_circle_outline` that navigates directly to `ClubOnboardingScreen(isPostLogin: true)`.

No changes needed to `_ClubSwitcherSheet` or `ClubOnboardingScreen`.

### UI Placement
The add button sits in the same AppBar location as the existing switcher chip — to the right of the "StageMate" title text.

---

## Files to Change

| File | Change |
|------|--------|
| `lib/screens/home_screen.dart` | `_pendingPostId` state, `onPostTap` handler, AppBar club button logic |
| `lib/screens/feed_screen.dart` | `initialPostId` param, `_openPostById` method |
| `lib/api/api_client.dart` | Add `getPost(postId)` if not present |

---

## Out of Scope
- Audio MP3 submission (separate feature)
- Notification deep-link for non-post notifications (e.g. notice comments)
