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

`PostComment` gains a SQLAlchemy relationship:
```python
likes = relationship("CommentLike", back_populates="comment", cascade="all, delete-orphan")
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
Auth: require_any_member
Response: { "liked": bool, "like_count": int }
```
- If the caller has no existing like → create one (liked=true)
- If the caller already liked → delete it (liked=false)
- Returns 404 if comment not found or belongs to different post

**Modified endpoint — get comments:**
```
GET /posts/{post_id}/comments
```
Each comment object gains three new fields:
```json
{
  "like_count": 5,
  "is_liked_by_me": true,
  "is_best": true
}
```
`is_best` is `true` for exactly one comment per response (the one meeting the BEST rules above). If no comment has ≥1 like, all are `false`.

### Flutter UI — feed_screen.dart

**BEST badge** (shown next to author name when `is_best == true`):
- `OutlinedBorder` pill/oval shape
- Color: `Colors.red`
- Border width: 2.0
- No fill (transparent background)
- Text: "BEST", `fontSize: 10`, `fontWeight: FontWeight.bold`, red

```
김민준  [BEST]  · 2025.03.28
좋은 글이에요!                  ♥ 5
```

**Like button** (trailing area of each comment row):
- `IconButton` with `Icons.favorite_border` (unliked) / `Icons.favorite` (liked, red)
- Like count displayed next to icon
- Optimistic UI: toggle state locally on tap, revert on API error
- Only shown when comment sheet is open (not in collapsed preview)

---

## Sub-system 2: FCM Push Notifications

### Firebase Setup (manual steps — before coding)

1. **Firebase Console** ([console.firebase.google.com](https://console.firebase.google.com)) — project already created: "StageMate"

2. **Android app registration:**
   - Package name: from `android/app/build.gradle` → `applicationId`
   - Download `google-services.json` → place at `android/app/google-services.json`

3. **iOS app registration:**
   - Bundle ID: from Xcode / Codemagic project settings
   - Download `GoogleService-Info.plist` → place at `ios/Runner/GoogleService-Info.plist`
   - Upload APNs Auth Key (.p8): Firebase Console → Project Settings → Cloud Messaging → Apple app configuration

4. **Service account key (backend):**
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
One token per user (last-registered device wins — suitable for single-device-per-account usage).

### Backend Changes

**`requirements.txt`** — add `firebase-admin`

**Firebase initialization (`main.py` startup):**
```python
import firebase_admin
from firebase_admin import credentials, messaging
import json, os

_firebase_app = None
_creds_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
if _creds_json:
    cred = credentials.Certificate(json.loads(_creds_json))
    _firebase_app = firebase_admin.initialize_app(cred)
```
If `FIREBASE_CREDENTIALS_JSON` is absent (local dev), Firebase is simply disabled — no crash.

**New endpoint — register FCM token:**
```
PATCH /users/me/fcm-token
Auth: get_current_user (JWT only, no club required)
Body: { "token": "string" }
Response: { "ok": true }
```
Stores token on `current_user.fcm_token`; idempotent.

**Push helper function:**
```python
def _send_push(token: str, title: str, body: str, post_id: int) -> None:
    """Fire-and-forget FCM push. Errors are logged, never raised."""
    if not _firebase_app or not token:
        return
    try:
        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={"post_id": str(post_id)},
            token=token,
        ))
    except Exception as e:
        logging.warning("FCM send failed: %s", e)
```

**Modified `create_post_comment` endpoint:**
After the existing in-app `Notification` row is created, add:
```python
background_tasks.add_task(
    _send_push,
    post_author.fcm_token or "",
    "새 댓글",
    f"{actor_name}님이 댓글을 남겼어요: {preview}",
    post_id,
)
```
The endpoint signature gains `background_tasks: BackgroundTasks`.

### Flutter Changes

**`pubspec.yaml`** — add:
```yaml
firebase_core: ^3.0.0
firebase_messaging: ^15.0.0
```

**New file — `lib/services/fcm_service.dart`:**
Single responsibility: Firebase init, token registration, foreground notification display, and navigation routing on tap.

```dart
class FcmService {
  static Future<void> init(BuildContext context) async { ... }
  static Future<void> _registerToken() async { ... }       // calls PATCH /users/me/fcm-token
  static void _handleMessage(RemoteMessage msg) { ... }    // navigate to post
}
```

**`lib/main.dart`** — after `ApiClient` token check:
```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
// Token registration deferred until after login (inside FcmService.init)
```

**Foreground notifications:**
```dart
FirebaseMessaging.onMessage.listen((msg) {
  // Show local banner using flutter_local_notifications or
  // FirebaseMessaging.setForegroundNotificationPresentationOptions
});
```

**Notification tap → navigate to post:**
- `FirebaseMessaging.onMessageOpenedApp` — app in background, user taps
- `FirebaseMessaging.instance.getInitialMessage()` — app was terminated, user taps
- Both: extract `post_id` from `message.data`, navigate to `FeedScreen` and open the relevant post

**Android config (`android/app/build.gradle`):**
```gradle
apply plugin: 'com.google.gms.google-services'
```
**`android/build.gradle`:**
```gradle
classpath 'com.google.gms:google-services:4.4.2'
```

**iOS config (`ios/Runner/Info.plist`):** no extra keys needed; FCM handles it via `GoogleService-Info.plist` + APNs key. Push Notifications capability must be enabled in Xcode (or via Codemagic entitlements).

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| FCM send fails (invalid token, network) | Logged as warning, comment creation succeeds |
| `FIREBASE_CREDENTIALS_JSON` missing | Firebase disabled, no crash, in-app notifications still work |
| User double-taps like | Second tap de-duped by UniqueConstraint on server; optimistic UI already toggled |
| Comment deleted while being "BEST" | CASCADE deletes `comment_likes`; next fetch recalculates BEST |
| App opened without notification tap | `getInitialMessage()` returns null, no navigation attempted |

---

## Out of Scope
- Like notifications (only comment-on-post triggers push)
- Per-user notification preferences for push (on/off toggle already exists as in-app setting, but doesn't gate FCM)
- Multiple devices per user (last token wins)
- Rich notifications (image, action buttons)
- Notice comment likes / push (피드 게시글 댓글만 해당)
