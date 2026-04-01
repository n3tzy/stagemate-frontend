# Comment Likes, Best Comment & FCM Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add comment likes with automatic BEST badge on the top-liked comment per post, and FCM push notifications to post authors when someone comments.

**Architecture:** `comment_likes` join table mirrors existing `post_likes` pattern. Best comment computed dynamically on each `GET /posts/{post_id}/comments` call. FCM push sent via Firebase Admin SDK in FastAPI BackgroundTask. FCM token stored on `users.fcm_token`. Flutter `FcmService` handles token registration and notification routing.

**Tech Stack:** FastAPI + SQLAlchemy (PostgreSQL), `firebase-admin`, Flutter `firebase_core ^3.0.0` + `firebase_messaging ^15.0.0`, Railway env var `FIREBASE_CREDENTIALS_JSON`.

**Spec:** `docs/superpowers/specs/2026-03-28-comment-likes-best-push-notifications-design.md`

---

## Chunk 1: Backend — Comment Likes

### Task 1: Add CommentLike model and fcm_token migration

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py`
- Modify: `C:/projects/performance-manager/backend/main.py` (migration only)

- [ ] **Step 1: Add `CommentLike` model and `likes` relationship to `PostComment` in `db_models.py`**

Find the `PostComment` class (line ~175) and add the `likes` relationship. Then add the new `CommentLike` class immediately after:

```python
# In PostComment class, add after existing fields:
    likes = relationship("CommentLike", back_populates="comment", cascade="all, delete-orphan")


class CommentLike(Base):
    __tablename__ = "comment_likes"
    id         = Column(Integer, primary_key=True, index=True)
    comment_id = Column(Integer, ForeignKey("post_comments.id"), nullable=False)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    comment    = relationship("PostComment", back_populates="likes")
    __table_args__ = (UniqueConstraint("comment_id", "user_id", name="uq_comment_like"),)
```

- [ ] **Step 2: Add `fcm_token` column to `User` model in `db_models.py`**

In the `User` class, add after the last column (before any relationships):
```python
    fcm_token = Column(String, nullable=True)
```

- [ ] **Step 3: Add `fcm_token` migration to `_run_migrations()` in `main.py`**

In `_run_migrations()`, add to the `migrations` list:
```python
        # users 테이블 — FCM 푸시 토큰
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR",
```

- [ ] **Step 4: Verify the backend starts without errors**

```bash
cd C:/projects/performance-manager/backend
uvicorn main:app --reload --port 8000
```
Expected: server starts, `comment_likes` table created automatically by `create_all`, no errors in logs.

- [ ] **Step 5: Commit**

```bash
cd C:/projects/performance-manager
git add backend/db_models.py backend/main.py
git commit -m "feat: add CommentLike model, likes relationship, fcm_token column"
```

---

### Task 2: Comment like toggle endpoint

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: Add the toggle like endpoint after `delete_post_comment` (~line 1540)**

```python
@app.post("/posts/{post_id}/comments/{comment_id}/like")
@limiter.limit("60/minute")
def toggle_comment_like(
    request: Request,
    post_id: int,
    comment_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    """댓글 좋아요 토글 (like ↔ unlike)"""
    comment = db.query(db_models.PostComment).filter(
        db_models.PostComment.id == comment_id,
        db_models.PostComment.post_id == post_id,
    ).first()
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")

    post = db.query(db_models.Post).filter(db_models.Post.id == post_id).first()
    if not post or (not post.is_global and post.club_id != member.club_id):
        raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")

    existing = db.query(db_models.CommentLike).filter(
        db_models.CommentLike.comment_id == comment_id,
        db_models.CommentLike.user_id == member.user_id,
    ).first()

    if existing:
        db.delete(existing)
        db.commit()
        liked = False
    else:
        db.add(db_models.CommentLike(comment_id=comment_id, user_id=member.user_id))
        db.commit()
        liked = True

    like_count = db.query(db_models.CommentLike).filter(
        db_models.CommentLike.comment_id == comment_id
    ).count()

    return {"liked": liked, "like_count": like_count}
```

- [ ] **Step 2: Test the endpoint manually**

With the backend running locally:
```bash
# Like a comment (replace TOKEN, CLUB_ID, POST_ID, COMMENT_ID)
curl -X POST http://localhost:8000/posts/1/comments/1/like \
  -H "Authorization: Bearer TOKEN" \
  -H "X-Club-Id: 1"
# Expected: {"liked": true, "like_count": 1}

# Like again (should unlike)
curl -X POST http://localhost:8000/posts/1/comments/1/like \
  -H "Authorization: Bearer TOKEN" \
  -H "X-Club-Id: 1"
# Expected: {"liked": false, "like_count": 0}
```

- [ ] **Step 3: Commit**

```bash
cd C:/projects/performance-manager
git add backend/main.py
git commit -m "feat: add comment like toggle endpoint"
```

---

### Task 3: Add like_count, is_liked_by_me, is_best to GET comments

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py` (lines ~1430-1463)

- [ ] **Step 1: Replace the `get_post_comments` response body**

First, add `func` to the existing sqlalchemy import line in `main.py`. Find:
```python
from sqlalchemy import desc, nulls_last, text
```
Replace with:
```python
from sqlalchemy import desc, nulls_last, text, func
```
(If `func` is already there, skip this sub-step.)

Then find `get_post_comments` (~line 1430). Replace the entire query/loop section (from `comments = db.query(...)` to `return result`) with:

```python
    comments = db.query(db_models.PostComment).filter(
        db_models.PostComment.post_id == post_id
    ).order_by(db_models.PostComment.created_at.asc()).all()

    # ── 좋아요 집계 (N+1 방지: 한 번에 조회) ──────────────
    comment_ids = [c.id for c in comments]
    if comment_ids:
        like_counts = dict(
            db.query(db_models.CommentLike.comment_id, func.count(db_models.CommentLike.id))
            .filter(db_models.CommentLike.comment_id.in_(comment_ids))
            .group_by(db_models.CommentLike.comment_id)
            .all()
        )
        my_likes = set(
            row[0] for row in
            db.query(db_models.CommentLike.comment_id)
            .filter(
                db_models.CommentLike.comment_id.in_(comment_ids),
                db_models.CommentLike.user_id == member.user_id,
            )
            .all()
        )
    else:
        like_counts, my_likes = {}, set()

    # ── 베스트 댓글 결정 (좋아요 최다, 최소 1개, 동점 시 먼저 작성된 댓글) ──
    best_comment_id = None
    max_likes = 0
    for c in comments:  # already ordered by created_at asc → first encountered wins ties
        count = like_counts.get(c.id, 0)
        if count > max_likes:
            max_likes = count
            best_comment_id = c.id

    result = []
    for c in comments:
        author = db.query(db_models.User).filter(db_models.User.id == c.author_id).first()
        if post and post.is_global:
            author_name = (author.nickname if author and author.nickname else "알 수 없음")
        else:
            author_name = (author.display_name if author else "탈퇴한 사용자")
        result.append({
            "id": c.id,
            "author": author_name,
            "author_id": c.author_id,
            "author_avatar": (author.avatar_url or "") if author else "",
            "content": c.content,
            "created_at": c.created_at.strftime("%Y.%m.%d %H:%M") if c.created_at else "",
            "like_count": like_counts.get(c.id, 0),
            "is_liked_by_me": c.id in my_likes,
            "is_best": c.id == best_comment_id and max_likes > 0,
        })
    return result
```

- [ ] **Step 2: Test via curl**

```bash
curl http://localhost:8000/posts/1/comments \
  -H "Authorization: Bearer TOKEN" \
  -H "X-Club-Id: 1"
# Expected: array with like_count, is_liked_by_me, is_best fields on each comment
# is_best should be true for at most one comment (the one with most likes >= 1)
```

- [ ] **Step 3: Commit**

```bash
cd C:/projects/performance-manager
git add backend/main.py
git commit -m "feat: add like_count, is_liked_by_me, is_best to GET comments response"
```

---

## Chunk 2: Backend — FCM Push

### Task 4: Firebase Admin SDK init and push helper

**Files:**
- Modify: `C:/projects/performance-manager/backend/requirements.txt`
- Modify: `C:/projects/performance-manager/backend/main.py`
- Modify: `C:/projects/performance-manager/backend/models.py`

- [ ] **Step 1: Add `firebase-admin` to requirements.txt**

```
firebase-admin
```

- [ ] **Step 2: Add `BackgroundTasks` to the existing `from fastapi import` line in `main.py`**

Find the line (near the top of main.py):
```python
from fastapi import FastAPI, HTTPException, Depends, Request
```
Replace it with:
```python
from fastapi import FastAPI, HTTPException, Depends, Request, BackgroundTasks
```

- [ ] **Step 3: Add Firebase init block to `main.py` (after existing imports, before FastAPI app creation)**

```python
# ── Firebase Admin SDK 초기화 ──────────────────────────
import firebase_admin
from firebase_admin import credentials as fb_credentials, messaging as fb_messaging
import json

_firebase_app = None
_firebase_creds_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
if _firebase_creds_json:
    try:
        _cred = fb_credentials.Certificate(json.loads(_firebase_creds_json))
        _firebase_app = firebase_admin.initialize_app(_cred)
        logging.info("Firebase Admin SDK initialized.")
    except Exception as _fb_err:
        logging.warning("Firebase init failed: %s", _fb_err)
else:
    logging.info("FIREBASE_CREDENTIALS_JSON not set — push notifications disabled.")
```

- [ ] **Step 4: Add `_send_push` helper function (after Firebase init block)**

```python
def _send_push(token: str, title: str, body: str, post_id: int) -> None:
    """Fire-and-forget FCM push. Errors are logged, never raised."""
    if not _firebase_app or not token:
        return
    try:
        fb_messaging.send(fb_messaging.Message(
            notification=fb_messaging.Notification(title=title, body=body),
            data={"post_id": str(post_id)},
            token=token,
        ))
        logging.info("FCM push sent to token %s...", token[:10])
    except Exception as e:
        logging.warning("FCM send failed (token=%s...): %s", token[:10], e)
```

- [ ] **Step 5: Add `FcmTokenRequest` to `models.py`**

```python
class FcmTokenRequest(BaseModel):
    token: str = Field(..., min_length=1, max_length=512)
```

Add `FcmTokenRequest` to the **existing** `from models import (...)` block in `main.py` (lines ~28-40). Do NOT replace the block — just append `FcmTokenRequest,` to the list. The block currently ends with `BoostRequest,`. Change it to:
```python
    BoostRequest,
    PerformanceCreateRequest, AudioSubmissionRequest,
    FcmTokenRequest,
)
```

- [ ] **Step 6: Verify backend starts without Firebase errors**

```bash
uvicorn main:app --reload --port 8000
```
Expected: "FIREBASE_CREDENTIALS_JSON not set — push notifications disabled." log line (since no local env var). No crash.

- [ ] **Step 7: Commit**

```bash
cd C:/projects/performance-manager
git add backend/requirements.txt backend/main.py backend/models.py
git commit -m "feat: add Firebase Admin SDK init and _send_push helper"
```

---

### Task 5: FCM token endpoint + push on comment creation

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: Add FCM token registration endpoint (near other `/users/me` endpoints)**

```python
@app.patch("/users/me/fcm-token")
def update_fcm_token(
    req: FcmTokenRequest,
    current_user: db_models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """FCM 디바이스 토큰 등록/갱신"""
    current_user.fcm_token = req.token
    db.commit()
    return {"ok": True}
```

- [ ] **Step 2: Modify `create_post_comment` to send FCM push**

The function signature gains `background_tasks: BackgroundTasks`. Find `create_post_comment` (~line 1466) and:

a) Add `background_tasks: BackgroundTasks` to the function parameters (after `request: Request`):
```python
def create_post_comment(
    request: Request,
    background_tasks: BackgroundTasks,
    post_id: int,
    ...
```

b) Inside the `if post.author_id != member.user_id:` block, after the **last** `db.commit()` in that block (the one that commits the in-app notification), add:
```python
        # FCM 푸시 (백그라운드, 논블로킹)
        background_tasks.add_task(
            _send_push,
            post.author.fcm_token or "",   # lazy-loaded via Post.author relationship (one extra query, acceptable per spec)
            "새 댓글",
            f"{actor_name}님이 댓글을 남겼어요: {preview}",
            post_id,
        )
```

Note: `actor_name` and `preview` are already computed earlier in the same `if` block.
`BackgroundTasks` is from `fastapi` — already imported in Task 4 Step 2.

- [ ] **Step 3: Verify BackgroundTasks is imported**

```bash
grep "BackgroundTasks" C:/projects/performance-manager/backend/main.py
```
If missing, add to the `from fastapi import ...` line.

- [ ] **Step 4: Commit**

```bash
cd C:/projects/performance-manager
git add backend/main.py
git commit -m "feat: FCM token endpoint, push on comment creation"
```

- [ ] **Step 5: Set FIREBASE_CREDENTIALS_JSON on Railway**

1. Open Railway dashboard → StageMate backend service → Variables
2. Add new variable:
   - Name: `FIREBASE_CREDENTIALS_JSON`
   - Value: paste the **entire contents** of the service account JSON file downloaded earlier
3. Railway will redeploy automatically

- [ ] **Step 6: Deploy and verify**

```bash
cd C:/projects/performance-manager
git push
```
Expected Railway log: "Firebase Admin SDK initialized."

---

## Chunk 3: Flutter — FCM + ApiClient

### Task 6: pubspec.yaml and main.dart Firebase init

**Files:**
- Modify: `C:/projects/performance_manager/pubspec.yaml`
- Modify: `C:/projects/performance_manager/lib/main.dart`

- [ ] **Step 1: Add Firebase packages to `pubspec.yaml`**

Under `dependencies:`, add:
```yaml
  firebase_core: ^3.0.0
  firebase_messaging: ^15.0.0
```

- [ ] **Step 2: Run pub get**

```bash
cd C:/projects/performance_manager
flutter pub get
```
Expected: resolves without errors.

- [ ] **Step 3: Update `main.dart` — add Firebase init before `runApp`**

Replace the existing `main()` function:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  KakaoSdk.init(nativeAppKey: 'e7ed5581ca9a2f18837aefb77b5a4f3f');
  runApp(const MyApp());
}
```

Add imports at the top of `main.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
```

- [ ] **Step 4: Verify app builds**

```bash
flutter build apk --debug
```
Expected: builds successfully, no Firebase import errors.

- [ ] **Step 5: Commit**

```bash
cd C:/projects/performance_manager
git add pubspec.yaml pubspec.lock lib/main.dart lib/firebase_options.dart
git commit -m "feat: add firebase_core + firebase_messaging, init Firebase in main"
```

---

### Task 7: FcmService + HomeScreen integration

**Files:**
- Create: `C:/projects/performance_manager/lib/services/fcm_service.dart`
- Modify: `C:/projects/performance_manager/lib/screens/home_screen.dart`

- [ ] **Step 1: Create `lib/services/fcm_service.dart`**

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import '../api/api_client.dart';

typedef PostTapCallback = void Function(int postId);

class FcmService {
  static PostTapCallback? _onPostTap;

  /// Call once from HomeScreen.initState() after login is confirmed.
  /// [onPostTap] switches the home screen to the Feed tab.
  static Future<void> init({required PostTapCallback onPostTap}) async {
    _onPostTap = onPostTap;

    await FirebaseMessaging.instance.requestPermission();
    await _registerToken();

    // Show system banner even when app is in foreground
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground: message received while app is open
    FirebaseMessaging.onMessage.listen(_handleMessage);

    // Background: user taps notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // Terminated: app opened via notification tap
    // getInitialMessage() runs inside HomeScreen.initState() which is
    // after MaterialApp is built — no race condition.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  static Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiClient.updateFcmToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(ApiClient.updateFcmToken);
    } catch (_) {
      // Fail silently — push is a nice-to-have
    }
  }

  static void _handleMessage(RemoteMessage message) {
    final postIdStr = message.data['post_id'];
    if (postIdStr == null) return;
    final postId = int.tryParse(postIdStr);
    if (postId == null || _onPostTap == null) return;
    // Switch to Feed tab (index 1) — same as in-app notification tap behaviour
    _onPostTap!(postId);
  }
}
```

- [ ] **Step 2: Create `lib/services/` directory if needed**

The file creation above handles this. Verify:
```bash
ls C:/projects/performance_manager/lib/services/
```

- [ ] **Step 3: Add `FcmService.init()` call to `HomeScreen.initState()`**

In `home_screen.dart`, inside `initState()`, add after `_loadNotificationSetting()`:
```dart
    FcmService.init(
      onPostTap: (postId) => setState(() => _currentIndex = 1),
    );
```

Add import at the top of `home_screen.dart`:
```dart
import '../services/fcm_service.dart';
```

- [ ] **Step 4: Build and test**

```bash
flutter build apk --debug
```
Expected: no compile errors.

- [ ] **Step 5: Commit**

```bash
cd C:/projects/performance_manager
git add lib/services/fcm_service.dart lib/screens/home_screen.dart
git commit -m "feat: FcmService with token registration and notification routing"
```

---

### Task 8: ApiClient — updateFcmToken and toggleCommentLike

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`

- [ ] **Step 1: Add `updateFcmToken` method (near other `/users/me` methods)**

```dart
  /// FCM 토큰을 백엔드에 등록/갱신. Fire-and-forget — 실패해도 무시.
  static Future<void> updateFcmToken(String token) async {
    try {
      await http.patch(
        Uri.parse('$baseUrl/users/me/fcm-token'),
        headers: await _authOnlyHeaders(),
        body: jsonEncode({'token': token}),
      ).timeout(_timeout);
    } catch (_) {
      // fire-and-forget
    }
  }
```

- [ ] **Step 2: Add `toggleCommentLike` method (after audio submission section, or near comment methods)**

```dart
  static Future<Map<String, dynamic>> toggleCommentLike(
      int postId, int commentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId/like'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '좋아요 처리에 실패했습니다'));
  }
```

- [ ] **Step 3: Verify `getPostComments` method returns the new fields**

```bash
grep -n "getPostComments" C:/projects/performance_manager/lib/api/api_client.dart
```
The existing method decodes the response as a List — the new fields (`like_count`, `is_liked_by_me`, `is_best`) are returned by the backend and automatically available in the map objects. No change needed to `getPostComments`.

- [ ] **Step 4: Commit**

```bash
cd C:/projects/performance_manager
git add lib/api/api_client.dart
git commit -m "feat: add updateFcmToken and toggleCommentLike to ApiClient"
```

---

## Chunk 4: Flutter — Comment UI (BEST badge + Like button)

### Task 9: Add BEST badge and like button to comment rows

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/feed_screen.dart`

- [ ] **Step 1: Add `_toggleLike` and `_recalculateBest` methods to `_CommentsSheetState`**

Add these two methods to `_CommentsSheetState` (e.g., after `_showReportCommentDialog`):

```dart
  Future<void> _toggleLike(dynamic comment) async {
    final commentId = comment['id'] as int;
    final wasLiked = comment['is_liked_by_me'] as bool? ?? false;
    final prevCount = comment['like_count'] as int? ?? 0;

    // Optimistic update
    setState(() {
      comment['is_liked_by_me'] = !wasLiked;
      comment['like_count'] = prevCount + (wasLiked ? -1 : 1);
    });
    _recalculateBest();

    try {
      final result = await ApiClient.toggleCommentLike(
        widget.post['id'] as int,
        commentId,
      );
      if (mounted) {
        setState(() {
          comment['is_liked_by_me'] = result['liked'] as bool;
          comment['like_count'] = result['like_count'] as int;
        });
        _recalculateBest();
      }
    } catch (_) {
      // Revert on error
      if (mounted) {
        setState(() {
          comment['is_liked_by_me'] = wasLiked;
          comment['like_count'] = prevCount;
        });
        _recalculateBest();
      }
    }
  }

  void _recalculateBest() {
    // Reset all
    for (final c in _comments) {
      c['is_best'] = false;
    }
    // Find comment with most likes (>= 1); tie-break: first in list (earliest created_at)
    int maxLikes = 0;
    dynamic bestComment;
    for (final c in _comments) {
      final likes = c['like_count'] as int? ?? 0;
      if (likes > maxLikes) {
        maxLikes = likes;
        bestComment = c;
      }
    }
    if (bestComment != null && maxLikes > 0) {
      bestComment['is_best'] = true;
    }
    setState(() {});
  }
```

- [ ] **Step 2: Replace the comment row widget in `ListView.builder`**

Find the `itemBuilder` in `_CommentsSheetState.build` (~line 1022). Replace the inner `Padding` widget with:

```dart
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _UserAvatar(
                                name: c['author'] as String? ?? '?',
                                avatarUrl: c['author_avatar'] as String?,
                                radius: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          c['author'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (c['is_best'] == true) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.transparent,
                                              border: Border.all(
                                                  color: Colors.red, width: 2.0),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'BEST',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        Text(
                                          c['created_at'] ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colorScheme.outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c['content'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              // 좋아요 버튼
                              GestureDetector(
                                onTap: () => _toggleLike(c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        (c['is_liked_by_me'] as bool? ?? false)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 16,
                                        color: (c['is_liked_by_me'] as bool? ??
                                                false)
                                            ? Colors.red
                                            : colorScheme.outline,
                                      ),
                                      if ((c['like_count'] as int? ?? 0) > 0)
                                        Text(
                                          '${c['like_count']}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colorScheme.outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (iconContext) => IconButton(
                                  icon: Icon(Icons.more_vert,
                                      size: 16, color: colorScheme.outline),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  onPressed: () => _showCommentMenu(
                                    iconContext: iconContext,
                                    comment: c,
                                    isMine: isMine,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
```

- [ ] **Step 3: Run flutter analyze**

```bash
cd C:/projects/performance_manager
flutter analyze lib/screens/feed_screen.dart
```
Expected: no errors (warnings about `use_build_context_synchronously` that already existed are acceptable).

- [ ] **Step 4: Build and smoke test on device/emulator**

```bash
flutter run
```
1. Open Feed → tap a post → comment sheet opens
2. Tap the heart icon on a comment → should toggle red/outline and update count
3. When a comment gets the most likes (≥1), "BEST" red oval badge appears next to author name
4. Tap heart again → count decreases, BEST badge removed if back to 0

- [ ] **Step 5: Commit**

```bash
cd C:/projects/performance_manager
git add lib/screens/feed_screen.dart
git commit -m "feat: comment like button with optimistic UI and BEST badge"
```

---

## Chunk 5: Deploy & Final Wiring

### Task 10: Deploy backend + build release APK

- [ ] **Step 1: Push backend to Railway**

```bash
cd C:/projects/performance-manager
git push
```
Expected: Railway deploys, logs show "Firebase Admin SDK initialized."

- [ ] **Step 2: Verify push via Railway logs**

After deploying, post a comment on someone else's post via the app and check Railway logs for:
```
FCM push sent to token <first-10-chars>...
```

- [ ] **Step 3: Build release APK**

```bash
cd C:/projects/performance_manager
flutter build apk --release
```

- [ ] **Step 4: Bump version in pubspec.yaml**

```yaml
version: 1.0.0+15   # increment build number
```

- [ ] **Step 5: Final commit**

```bash
cd C:/projects/performance_manager
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.0+15"
git push
```

- [ ] **Step 6: iOS — APNs key upload to Firebase (for iOS push)**

1. [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → Keys
2. Create new key → enable "Apple Push Notifications service (APNs)" → download .p8 file
3. Firebase Console → StageMate → Project Settings → Cloud Messaging → Apple app configuration
4. Upload the .p8 file + enter Key ID + Team ID

---

## Testing Checklist

- [ ] Comment like toggles correctly (like → unlike → like)
- [ ] Like count updates in real time (optimistic UI)
- [ ] BEST badge appears on comment with most likes (≥1)
- [ ] BEST badge moves when another comment overtakes
- [ ] BEST badge disappears when best comment has 0 likes
- [ ] Push notification received when someone comments on your post (Android)
- [ ] Tapping push notification switches app to Feed tab
- [ ] No push for self-comments
- [ ] App works normally when `FIREBASE_CREDENTIALS_JSON` missing (local dev)
