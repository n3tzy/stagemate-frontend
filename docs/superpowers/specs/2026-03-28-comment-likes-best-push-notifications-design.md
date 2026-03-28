# Comment Likes, Best Comment & Push Notifications Design

**Goal:** Add comment like/upvote system with automatic "BEST" badge on the top-liked comment per post, and FCM push notifications to post authors when someone comments on their post.

**Architecture:** Comment likes use a dedicated `comment_likes` join table (mirroring the existing `post_likes` pattern). The best comment is the highest-liked comment with at least 1 like, computed dynamically on each fetch. FCM push is sent via Firebase Admin SDK in a FastAPI `BackgroundTask` so comment creation is never blocked. FCM tokens are stored on the `users` row.

**Tech Stack:** FastAPI + SQLAlchemy (PostgreSQL), Firebase Admin SDK (`firebase-admin`), Flutter (`firebase_core`, `firebase_messaging`), Railway (env var for Firebase credentials).

---

## Sub-system 1: Comment Likes & Best Comment

### Data Model

**New table — `comment_likes`**
```
id          INTEGER PRIMARY KEY
comment_id  INTEGER FK → post_comments.id  NOT NULL
user_id     INTEGER FK → users.id           NOT NULL
created_at  DATETIME DEFAULT utcnow
UNIQUE(comment_id, user_id)   -- prevents duplicate likes
```

The `comment_likes` table is **new** and will be created by `Base.metadata.create_all()` on startup (not via `_run_migrations()`, which is only for adding columns to existing tables). No manual migration SQL is needed.

`PostComment` gains a SQLAlchemy relationship (no back-reference on `User` — matches the existing `PostLike` pattern):
```python
likes = relationship("CommentLike", back_populates="comment", cascade="all, delete-orphan")
```

`CommentLike` defines:
```python
comment = relationship("PostComment", back_populates="likes")
# No back_populates on User side — consistent with existing PostLike pattern
```

No `like_count` column — counts are computed from the relationship to keep the source of truth in one place.

### Best Comment Rules
- Best = comment with the highest `len(likes)` for a given post
- Minimum 1 like required (a 0-like comment is never "BEST")
- Tie-break: earliest `created_at` wins
- At most one BEST per post at any time

### API Changes

**New endpoint — toggle like:**
```
POST /posts/{post_id}/comments/{comment_id}/like
Auth: require_any_member  (provides member.user_id and club boundary)
Response: { "liked": bool, "like_count": int }
Errors:
  404 — comment not found, or comment.post_id != post_id
  403 — caller is not a member of the club that owns the post (handled by require_any_member)
```
- Self-likes are **permitted** — a user may like their own comment (no restriction)
- If the caller has no existing like → create one (`liked=true`)
- If the caller already liked → delete it (`liked=false`)
- Club boundary: `require_any_member` reads `X-Club-Id` and verifies membership; the handler additionally confirms the post belongs to the same club

**Modified endpoint — get comments:**
```
GET /posts/{post_id}/comments
Auth: require_any_member  (unchanged — needed to compute is_liked_by_me via member.user_id)
```
Each comment object gains three new fields:
```json
{
  "like_count": 5,
  "is_liked_by_me": true,
  "is_best": true
}
```
`is_best` is `true` for exactly one comment per response (the one meeting the BEST rules above). If no comment has ≥1 like, all `is_best` values are `false`.

### Flutter UI — feed_screen.dart

**BEST badge** (shown next to author name when `is_best == true`):
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    border: Border.all(color: Colors.red, width: 2.0),
    borderRadius: BorderRadius.circular(20),
    color: Colors.transparent,
  ),
  child: Text('BEST',
    style: TextStyle(
      color: Colors.red,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    ),
  ),
)
```

Layout: `author name` → `[BEST badge]` (4px gap) → `· timestamp`

```
김민준  BEST  · 2026.03.28
좋은 글이에요!                  ♥ 5
```

**Like button** (trailing area of each comment row):
- `IconButton` with `Icons.favorite_border` (unliked) / `Icons.favorite` (liked, red)
- Like count displayed next to icon; 0 count displayed as empty string (no "0")
- Optimistic UI: toggle state locally on tap, revert on API error
- Shown for all comments in the comment sheet (both post author's and others')

---

## Sub-system 2: FCM Push Notifications

### Firebase Setup (manual steps — required before coding)

**Step 0 — Firebase project already created:** "StageMate" ✅

**Step 1 — Install FlutterFire CLI and configure:**
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id>
```
This generates `lib/firebase_options.dart` (the `DefaultFirebaseOptions` class). Run from the Flutter project root (`C:/projects/performance_manager/`). Select Android and iOS when prompted.

**Step 2 — Android app registration:**
- Package name: from `android/app/build.gradle.kts` → `applicationId`
- `flutterfire configure` handles this, but also manually confirm `google-services.json` is at `android/app/google-services.json`

**Step 3 — iOS app registration:**
- Bundle ID: from Xcode / Codemagic project settings
- `flutterfire configure` places `GoogleService-Info.plist` at `ios/Runner/GoogleService-Info.plist`
- **APNs Auth Key (.p8):** Firebase Console → Project Settings → Cloud Messaging → Apple app configuration → upload APNs key (from Apple Developer account)

**Step 4 — Service account key (backend):**
- Firebase Console → Project Settings → Service Accounts → Generate new private key
- Copy entire JSON content → set as Railway env var `FIREBASE_CREDENTIALS_JSON`

### Data Model

**Existing `users` table — new column:**
```
fcm_token  VARCHAR  NULLABLE
```
Added via `_run_migrations()`:
```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR;
```

### Backend Changes

**`requirements.txt`** — add `firebase-admin`

**`models.py`** — add Pydantic model:
```python
class FcmTokenRequest(BaseModel):
    token: str = Field(..., min_length=1, max_length=512)
```

**Firebase initialization (`main.py` startup, after existing imports):**
```python
import firebase_admin
from firebase_admin import credentials, messaging
import json, os

_firebase_app = None
_creds_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
if _creds_json:
    try:
        cred = credentials.Certificate(json.loads(_creds_json))
        _firebase_app = firebase_admin.initialize_app(cred)
    except Exception as e:
        logging.warning("Firebase init failed: %s", e)
# If FIREBASE_CREDENTIALS_JSON is absent (local dev), Firebase is disabled — no crash.
```

**Push helper function:**
```python
def _send_push(token: str, title: str, body: str, post_id: int) -> None:
    """Fire-and-forget FCM push. Errors are logged, never raised.
    Stale/invalid tokens are logged but NOT cleared from the DB
    (out of scope for this version — acceptable for small user base).
    """
    if not _firebase_app or not token:
        return
    try:
        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={"post_id": str(post_id)},
            token=token,
        ))
    except Exception as e:
        logging.warning("FCM send failed (token=%s...): %s", token[:10], e)
```

**New endpoint — register FCM token:**
```
PATCH /users/me/fcm-token
Auth: get_current_user (JWT only — no X-Club-Id required)
Body: FcmTokenRequest { "token": "string" }
Response: { "ok": true }
```
Stores token on `current_user.fcm_token`; idempotent. Last-registered device wins.

**Modified `create_post_comment` endpoint:**
- Gains `background_tasks: BackgroundTasks` parameter
- Push fires **only inside the existing `if post.author_id != member.user_id:` block** (same guard as in-app notification — no push for self-comments)
- Push preview: reuses the same 30-char `preview` variable and `actor_name` variable already computed for the in-app notification earlier in the same block — both are in scope at the insertion point
- `post.author` is already a loaded SQLAlchemy relationship on the `Post` model (`author = relationship("User")`); use it directly instead of an extra query
- Full diff:
```python
# existing block — ADD the background_tasks call after db.commit():
if post.author_id != member.user_id:
    # ... existing actor_name, preview, Notification creation, db.commit() ...
    # NEW — use already-loaded relationship, no extra query:
    background_tasks.add_task(
        _send_push,
        post.author.fcm_token or "",   # post.author loaded via relationship
        "새 댓글",
        f"{actor_name}님이 댓글을 남겼어요: {preview}",  # actor_name & preview already in scope
        post_id,
    )
```

### Flutter Changes

**`pubspec.yaml`** — add:
```yaml
firebase_core: ^3.0.0
firebase_messaging: ^15.0.0
```

**Android — `android/app/build.gradle.kts`** (Kotlin DSL):
```kotlin
plugins {
    id("com.google.gms.google-services")  // add this line
}
```
**`android/build.gradle.kts`** (Kotlin DSL):
```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false  // add
}
```

**iOS — Push Notifications capability:**
- Enable in Xcode: Signing & Capabilities → + Capability → Push Notifications
- Or via Codemagic: add `aps-environment` entitlement

**New file — `lib/services/fcm_service.dart`:**
```dart
// Single responsibility: Firebase init, token registration,
// foreground notification display, and navigation via callback.

typedef PostTapCallback = void Function(int postId);

class FcmService {
  static PostTapCallback? _onPostTap;

  /// Call once from HomeScreen.initState() after login is confirmed.
  /// [onPostTap] switches the home screen to the feed tab — same callback
  /// already used by NotificationsScreen.
  /// Ordering note: HomeScreen.initState() runs after MaterialApp is fully
  /// built, so there is no race condition for cold-start notifications.
  static Future<void> init({required PostTapCallback onPostTap}) async {
    _onPostTap = onPostTap;
    await FirebaseMessaging.instance.requestPermission();
    await _registerToken();

    // Foreground: show system banner
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // Foreground message received
    FirebaseMessaging.onMessage.listen(_handleMessage);

    // Background → user taps notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // App was terminated → user taps notification → app opens
    // getInitialMessage() is awaited inside initState (already inside widget tree)
    // so _onPostTap callback is guaranteed to be set before this executes.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  static Future<void> _registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await ApiClient.updateFcmToken(token);
    FirebaseMessaging.instance.onTokenRefresh.listen(ApiClient.updateFcmToken);
  }

  static void _handleMessage(RemoteMessage message) {
    final postIdStr = message.data['post_id'];
    if (postIdStr == null) return;
    final postId = int.tryParse(postIdStr);
    if (postId == null || _onPostTap == null) return;
    // Reuse the same mechanism as NotificationsScreen.onPostTap:
    // switches HomeScreen to the Feed tab (index 1).
    // The feed tab does not auto-scroll to a specific post (v1 scope).
    _onPostTap!(postId);
  }
}
```

**`lib/main.dart`:**
- No `navigatorKey` needed — navigation handled via callback
- Firebase initialised before `runApp`:
```dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
runApp(const MyApp());
```

**`lib/screens/home_screen.dart`:**
- `initState()` calls:
```dart
FcmService.init(onPostTap: (postId) => setState(() => _currentIndex = 1));
```
- This is identical to how `NotificationsScreen.onPostTap` already works — switches to the Feed tab. The post is not auto-opened (consistent with existing in-app notification tap behaviour; deeper deep-link is out of scope for v1).

**`lib/api/api_client.dart`** — add:
```dart
static Future<void> updateFcmToken(String token) async {
  // Uses _authOnlyHeaders() which already includes 'Content-Type: application/json'
  // and 'Authorization: Bearer <token>' — no X-Club-Id needed for this endpoint.
  await http.patch(
    Uri.parse('$baseUrl/users/me/fcm-token'),
    headers: await _authOnlyHeaders(),
    body: jsonEncode({'token': token}),
  ).timeout(_timeout);
  // Fire-and-forget — ignore failures silently
}
```

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| FCM send fails (invalid/stale token, network) | Logged as warning; stale token NOT cleared from DB (out of scope v1) |
| `FIREBASE_CREDENTIALS_JSON` missing | Firebase disabled; in-app notifications still work normally |
| User double-taps like | Second tap de-duped by UniqueConstraint on server; optimistic UI already toggled |
| Comment deleted while being "BEST" | CASCADE deletes `comment_likes`; next fetch recalculates BEST |
| App opened without notification tap | `getInitialMessage()` returns null; no navigation attempted |
| Self-comment | Push and in-app notification both suppressed (`if author_id != member.user_id`) |
| FCM token not yet registered (first launch) | `fcm_token` is NULL; `_send_push` returns early; no error |

---

## Out of Scope
- Notice comment likes or push (피드 게시글 댓글만 해당)
- Per-user push on/off toggle gating FCM (the existing in-app notification toggle does not suppress FCM push — this is a deliberate v1 decision; full push preferences can be added later)
- Multiple devices per user (last-registered token wins)
- Rich notifications (image, action buttons)
- Automatic stale FCM token cleanup
- Reply-to-comment notifications (only post-level comment triggers push)
