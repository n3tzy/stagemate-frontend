# StageMate 공연 플랫폼 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 피드 YouTube 링크 미리보기, 동아리 공연 아카이브, 이달의 챌린지 경쟁, 공개 웹 랭킹 페이지를 추가하여 StageMate를 공연 인재 발굴 플랫폼으로 확장한다.

**Architecture:** 백엔드(FastAPI + PostgreSQL)에 5개 테이블 추가 및 기존 posts 테이블 컬럼 추가. Flutter 앱에 YouTube 카드 위젯, 공연 아카이브 화면, 챌린지 화면을 신규 추가. FastAPI + Jinja2로 공개 웹 랭킹 페이지 서빙.

**Tech Stack:** Flutter (Dart), FastAPI (Python), PostgreSQL, SQLAlchemy, Jinja2, `cached_network_image` (Flutter)

**Spec:** `docs/superpowers/specs/2026-04-02-performance-platform-design.md`

---

## 청크 구성

| 청크 | 내용 | 의존성 |
|------|------|--------|
| Chunk 1 | DB 마이그레이션 (전체 신규 테이블) | 없음 |
| Chunk 2 | YouTube 링크 in 게시글 | Chunk 1 |
| Chunk 3 | 공연 아카이브 | Chunk 1 |
| Chunk 4 | 이달의 챌린지 | Chunk 3 |
| Chunk 5 | 공개 웹 랭킹 페이지 | Chunk 3, 4 |

---

## Chunk 1: DB 마이그레이션

### 수정 파일
- Modify: `backend/db_models.py`
- Modify: `backend/main.py` (`_run_migrations()` 함수)
- Modify: `backend/requirements.txt`

---

### Task 1-1: requirements.txt에 jinja2, aiofiles 추가

- [ ] `backend/requirements.txt` 파일 끝에 두 줄 추가:

```
jinja2
aiofiles
```

- [ ] Railway에 배포 시 자동 설치됨. 로컬 테스트 시 수동 설치:

```bash
cd backend
pip install jinja2 aiofiles
```

---

### Task 1-2: db_models.py에 신규 테이블 5개 추가

- [ ] `backend/db_models.py` 파일을 열어 기존 `PostLike` 클래스 아래에 다음 5개 클래스를 추가한다:

```python
# ── 공연 아카이브 ──────────────────────────────
class PerformanceArchive(Base):
    __tablename__ = "performance_archives"

    id               = Column(Integer, primary_key=True, index=True)
    club_id          = Column(Integer, ForeignKey("clubs.id"), nullable=False)
    title            = Column(String, nullable=False)
    description      = Column(Text, nullable=True)
    performance_date = Column(String(10), nullable=False)   # "YYYY-MM-DD"
    youtube_url      = Column(String(500), nullable=True)
    native_video_url = Column(String, nullable=True)        # PRO 전용
    view_count       = Column(Integer, default=0, nullable=False)
    created_at       = Column(DateTime, default=datetime.utcnow)

    club  = relationship("Club")
    likes = relationship("PerformanceArchiveLike", back_populates="archive",
                         cascade="all, delete-orphan")


class PerformanceArchiveLike(Base):
    __tablename__ = "performance_archive_likes"

    id         = Column(Integer, primary_key=True, index=True)
    archive_id = Column(Integer, ForeignKey("performance_archives.id"), nullable=False)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    archive = relationship("PerformanceArchive", back_populates="likes")

    __table_args__ = (
        UniqueConstraint("archive_id", "user_id", name="uq_archive_like"),
    )


# ── 챌린지 ────────────────────────────────────
class Challenge(Base):
    __tablename__ = "challenges"

    id         = Column(Integer, primary_key=True, index=True)
    year_month = Column(String(7), nullable=False)   # "YYYY-MM"
    is_active  = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    entries = relationship("ChallengeEntry", back_populates="challenge",
                           cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("year_month", name="uq_challenge_month"),
    )


class ChallengeEntry(Base):
    __tablename__ = "challenge_entries"

    id           = Column(Integer, primary_key=True, index=True)
    challenge_id = Column(Integer, ForeignKey("challenges.id"), nullable=False)
    club_id      = Column(Integer, ForeignKey("clubs.id"), nullable=False)
    archive_id   = Column(Integer, ForeignKey("performance_archives.id"), nullable=False)
    created_at   = Column(DateTime, default=datetime.utcnow)

    challenge = relationship("Challenge", back_populates="entries")
    club      = relationship("Club")
    archive   = relationship("PerformanceArchive")
    likes     = relationship("ChallengeEntryLike", back_populates="entry",
                             cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("challenge_id", "club_id", name="uq_challenge_entry"),
    )


class ChallengeEntryLike(Base):
    __tablename__ = "challenge_entry_likes"

    id         = Column(Integer, primary_key=True, index=True)
    entry_id   = Column(Integer, ForeignKey("challenge_entries.id"), nullable=False)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    entry = relationship("ChallengeEntry", back_populates="likes")

    __table_args__ = (
        UniqueConstraint("entry_id", "user_id", name="uq_entry_like"),
    )
```

---

### Task 1-3: _run_migrations()에 신규 테이블 생성 SQL 추가

- [ ] `backend/main.py`의 `_run_migrations()` 함수 내 기존 ALTER TABLE 목록 뒤에 추가:

```python
# --- 공연 플랫폼 마이그레이션 ---
"""
CREATE TABLE IF NOT EXISTS performance_archives (
    id               SERIAL PRIMARY KEY,
    club_id          INTEGER NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    title            VARCHAR NOT NULL,
    description      TEXT,
    performance_date VARCHAR(10) NOT NULL,
    youtube_url      VARCHAR(500),
    native_video_url VARCHAR,
    view_count       INTEGER NOT NULL DEFAULT 0,
    created_at       TIMESTAMP DEFAULT NOW()
)
""",
"""
CREATE TABLE IF NOT EXISTS performance_archive_likes (
    id         SERIAL PRIMARY KEY,
    archive_id INTEGER NOT NULL REFERENCES performance_archives(id) ON DELETE CASCADE,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_archive_like UNIQUE (archive_id, user_id)
)
""",
"""
CREATE TABLE IF NOT EXISTS challenges (
    id         SERIAL PRIMARY KEY,
    year_month VARCHAR(7) NOT NULL,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_challenge_month UNIQUE (year_month)
)
""",
"""
CREATE TABLE IF NOT EXISTS challenge_entries (
    id           SERIAL PRIMARY KEY,
    challenge_id INTEGER NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    club_id      INTEGER NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    archive_id   INTEGER NOT NULL REFERENCES performance_archives(id) ON DELETE CASCADE,
    created_at   TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_challenge_entry UNIQUE (challenge_id, club_id)
)
""",
"""
CREATE TABLE IF NOT EXISTS challenge_entry_likes (
    id         SERIAL PRIMARY KEY,
    entry_id   INTEGER NOT NULL REFERENCES challenge_entries(id) ON DELETE CASCADE,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_entry_like UNIQUE (entry_id, user_id)
)
""",
"ALTER TABLE posts ADD COLUMN IF NOT EXISTS youtube_url VARCHAR(500)",
```

> **주의:** `_run_migrations()`의 SQL 실행 루프는 각 항목을 `try/except`로 감쌈. CREATE TABLE IF NOT EXISTS와 ADD COLUMN IF NOT EXISTS를 사용하므로 멱등성 보장.

---

### Task 1-4: 백엔드 재시작 후 테이블 생성 확인

- [ ] 로컬에서 백엔드 실행:

```bash
cd backend
uvicorn main:app --reload
```

- [ ] 서버 시작 로그에서 에러 없음 확인 (마이그레이션 실패 시 traceback 출력됨)
- [ ] Railway 배포 (git push) 후 Railway 로그에서 동일 확인

### Task 1-5: db_models.py의 Post 클래스에 youtube_url 컬럼 추가

- [ ] `backend/db_models.py`에서 `Post` 클래스를 찾아 기존 컬럼들 아래에 추가:

```python
youtube_url = Column(String(500), nullable=True)
```

> `_run_migrations()`에서 ALTER TABLE로 DB 컬럼을 추가했더라도, ORM 모델에도 선언하지 않으면 SQLAlchemy가 `AttributeError`를 발생시킨다.

- [ ] 커밋:

```bash
cd backend
git add db_models.py main.py requirements.txt
git commit -m "feat: 공연 플랫폼 DB 마이그레이션 (아카이브·챌린지 테이블 추가)"
```

---

## Chunk 2: YouTube 링크 in 게시글

### 수정 파일
- Create: `lib/widgets/youtube_card.dart`
- Modify: `lib/screens/post_create_screen.dart`
- Modify: `lib/screens/feed_screen.dart`
- Modify: `lib/api/api_client.dart`
- Modify: `backend/main.py` (create_post, get_post 엔드포인트)
- Modify: `backend/models.py` (PostRequest 스키마)

---

### Task 2-1: PostRequest 스키마에 youtube_url 추가

- [ ] `backend/models.py`에서 `PostRequest` 클래스를 찾아 `youtube_url` 필드 추가:

```python
class PostRequest(BaseModel):
    content: str
    media_urls: list[str] = []
    is_global: bool = False
    is_anonymous: bool = False
    youtube_url: Optional[str] = Field(None, max_length=500)
```

- [ ] 파일 상단에 `from typing import Optional` import 확인 (없으면 추가)

---

### Task 2-2: 백엔드 create_post, get_post/list 엔드포인트에 youtube_url 반영

- [ ] `backend/main.py`에서 `create_post` 함수를 찾아 `post = db_models.Post(...)` 생성 코드에 `youtube_url=req.youtube_url` 추가:

```python
post = db_models.Post(
    club_id=member.club_id if not req.is_global else None,
    author_id=member.user_id,
    content=req.content,
    media_urls=req.media_urls,
    is_global=req.is_global,
    is_anonymous=req.is_anonymous,
    youtube_url=req.youtube_url,   # ← 추가
)
```

- [ ] 게시글 응답 dict에도 `youtube_url` 포함 확인. 다음 명령으로 4곳을 찾아 각각 `"youtube_url": p.youtube_url,` 추가:

```bash
grep -n '"content": p\.' backend/main.py
```

예상 결과 — 4곳이 출력되어야 한다:
1. `GET /posts` 클럽 피드 목록
2. `GET /posts` 전체 피드 목록 (is_global 분기)
3. `GET /posts/{post_id}` 단건 조회
4. `GET /users/me/profile` 또는 유사한 내 게시글 목록

- [ ] 수정 후 검증: `grep -c '"youtube_url"' backend/main.py` 결과가 4 이상인지 확인

- [ ] 백엔드 재시작 후 Swagger(`/docs`)에서 POST /posts body에 `youtube_url` 필드 노출 확인

---

### Task 2-3: Flutter YouTube 카드 위젯 생성

- [ ] `lib/widgets/youtube_card.dart` 파일 새로 생성:

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// YouTube URL에서 Video ID를 추출한다.
/// 지원 형식: youtu.be/{id}, youtube.com/watch?v={id}, youtube.com/shorts/{id}
String? extractYouTubeId(String url) {
  final patterns = [
    RegExp(r'youtu\.be/([^?&]+)'),
    RegExp(r'youtube\.com/watch\?v=([^&]+)'),
    RegExp(r'youtube\.com/shorts/([^?&]+)'),
    RegExp(r'youtube\.com/embed/([^?&]+)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

class YouTubeCard extends StatelessWidget {
  final String youtubeUrl;

  const YouTubeCard({super.key, required this.youtubeUrl});

  @override
  Widget build(BuildContext context) {
    final videoId = extractYouTubeId(youtubeUrl);
    // maxresdefault.jpg가 없는 영상은 HTTP 404 대신 120x90 회색 이미지를 반환한다.
    // Image.network의 errorBuilder가 이를 감지하지 못하므로, hqdefault.jpg 자동 폴백은
    // 불가능하다. 실패 시 플레이스홀더 아이콘 카드를 보여주는 것이 실용적인 대안이다.
    final thumbnailUrl = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg'
        : null;

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(youtubeUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 썸네일
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnailUrl != null
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // 하단 레이블
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'YouTube에서 보기',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.open_in_new,
                      size: 14, color: Colors.grey.shade500),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade900,
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 48),
      ),
    );
  }
}
```

---

### Task 2-4: post_create_screen.dart에 YouTube URL 필드 추가

- [ ] `lib/screens/post_create_screen.dart` 상단에 import 추가:

```dart
import '../widgets/youtube_card.dart';
```

- [ ] 클래스 상태 변수에 추가:

```dart
final _youtubeCtrl = TextEditingController();
bool _showYoutubeField = false;
```

- [ ] `dispose()`에 추가:

```dart
_youtubeCtrl.dispose();
```

- [ ] 미디어 버튼 Row 옆에 YouTube 버튼 추가 (기존 사진/동영상 버튼 근처):

```dart
IconButton(
  icon: const Icon(Icons.ondemand_video, color: Colors.red),
  tooltip: 'YouTube 링크',
  onPressed: () => setState(() => _showYoutubeField = !_showYoutubeField),
),
```

- [ ] YouTube URL 입력 필드 + 미리보기 (버튼 아래 조건부 표시):

```dart
if (_showYoutubeField) ...[
  const SizedBox(height: 8),
  TextField(
    controller: _youtubeCtrl,
    decoration: const InputDecoration(
      labelText: 'YouTube URL',
      prefixIcon: Icon(Icons.link, color: Colors.red),
      border: OutlineInputBorder(),
    ),
    onChanged: (_) => setState(() {}),
  ),
  if (_youtubeCtrl.text.trim().isNotEmpty) ...[
    const SizedBox(height: 8),
    YouTubeCard(youtubeUrl: _youtubeCtrl.text.trim()),
  ],
],
```

- [ ] `_submit()` 함수에서 API 호출 시 `youtubeUrl` 파라미터 전달:

```dart
await ApiClient.createPost(
  content: _contentCtrl.text.trim(),
  mediaUrls: _uploadedUrls,
  isGlobal: _isGlobal,
  isAnonymous: _isAnonymous,
  youtubeUrl: _youtubeCtrl.text.trim().isEmpty
      ? null
      : _youtubeCtrl.text.trim(),
);
```

---

### Task 2-5: ApiClient.createPost에 youtubeUrl 파라미터 추가

- [ ] `lib/api/api_client.dart`에서 `createPost` 메서드를 찾아 수정:

```dart
static Future<Map<String, dynamic>> createPost({
  required String content,
  List<String> mediaUrls = const [],
  bool isGlobal = false,
  bool isAnonymous = false,
  String? youtubeUrl,           // ← 추가
}) async {
  final body = {
    'content': content,
    'media_urls': mediaUrls,
    'is_global': isGlobal,
    'is_anonymous': isAnonymous,
    if (youtubeUrl != null) 'youtube_url': youtubeUrl,  // ← 추가
  };
  // ... 기존 HTTP POST 코드 유지
}
```

---

### Task 2-6: feed_screen.dart 피드 카드에 YouTube 카드 렌더링

- [ ] `lib/screens/feed_screen.dart` 상단에 import 추가:

```dart
import '../widgets/youtube_card.dart';
```

- [ ] 피드 카드 빌더에서 게시글 content 아래 (미디어 이미지 표시 블록 옆) YouTube 카드 조건부 추가:

```dart
// 기존 미디어 이미지 표시 코드 아래에 추가
final youtubeUrl = post['youtube_url'] as String?;
if (youtubeUrl != null && youtubeUrl.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: YouTubeCard(youtubeUrl: youtubeUrl),
  ),
```

- [ ] 앱 실행 후 수동 테스트:
  - 게시글 작성 → YouTube 아이콘 탭 → URL 입력 → 미리보기 표시 확인
  - 피드에서 카드에 썸네일 표시 확인
  - 카드 탭 → YouTube 앱/브라우저 이동 확인
  - 잘못된 URL 입력 시 플레이스홀더 표시 확인

- [ ] 커밋:

```bash
cd flutter_app  # C:/projects/performance_manager
git add lib/widgets/youtube_card.dart \
        lib/screens/post_create_screen.dart \
        lib/screens/feed_screen.dart \
        lib/api/api_client.dart
git commit -m "feat: 게시글 YouTube 링크 미리보기 추가"

cd ../performance-manager/backend
git add main.py models.py
git commit -m "feat: posts 테이블 youtube_url 컬럼 추가 및 API 반영"
```

---

## Chunk 3: 공연 아카이브

### 수정 파일
- Create: `lib/screens/performance_archive_screen.dart`
- Modify: `lib/api/api_client.dart`
- Modify: `lib/screens/home_screen.dart` (탭 추가)
- Modify: `backend/main.py` (아카이브 CRUD 엔드포인트 추가)

---

### Task 3-1: 백엔드 공연 아카이브 CRUD 엔드포인트 추가

- [ ] `backend/models.py`에 요청 스키마 추가:

```python
class PerformanceArchiveRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=1000)
    performance_date: str = Field(..., pattern=r'^\d{4}-\d{2}-\d{2}$')
    youtube_url: Optional[str] = Field(None, max_length=500)
```

- [ ] `backend/main.py`에서 `# ── 공지사항 댓글` 위쪽에 아카이브 엔드포인트 블록 추가:

```python
# ── 공연 아카이브 ──────────────────────────────────────────────

def _archive_to_dict(a, likes_count: int, my_liked: bool) -> dict:
    return {
        "id": a.id,
        "club_id": a.club_id,
        "title": a.title,
        "description": a.description,
        "performance_date": a.performance_date,
        "youtube_url": a.youtube_url,
        "native_video_url": a.native_video_url,
        "view_count": a.view_count,
        "likes_count": likes_count,
        "my_liked": my_liked,
        "created_at": a.created_at.strftime("%Y-%m-%d"),
    }


@app.get("/clubs/{club_id}/performance-archives")
def list_performance_archives(
    club_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    # 다른 동아리의 아카이브 접근 차단
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    archives = db.query(db_models.PerformanceArchive).filter(
        db_models.PerformanceArchive.club_id == club_id
    ).order_by(db_models.PerformanceArchive.performance_date.desc()).all()

    result = []
    for a in archives:
        likes_count = db.query(db_models.PerformanceArchiveLike).filter_by(archive_id=a.id).count()
        my_liked = db.query(db_models.PerformanceArchiveLike).filter_by(
            archive_id=a.id, user_id=member.user_id
        ).first() is not None
        result.append(_archive_to_dict(a, likes_count, my_liked))
    return result


@app.post("/clubs/{club_id}/performance-archives")
def create_performance_archive(
    club_id: int,
    req: PerformanceArchiveRequest,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    # 다른 동아리의 아카이브 접근 차단
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    # 무료 플랜 15개 한도
    if member.club.plan == "free":
        count = db.query(db_models.PerformanceArchive).filter_by(club_id=club_id).count()
        if count >= 15:
            raise HTTPException(
                status_code=403,
                detail="무료 플랜은 최대 15개까지 저장할 수 있어요. 무제한은 PRO 플랜으로 업그레이드하세요.",
            )
    archive = db_models.PerformanceArchive(
        club_id=club_id,
        title=req.title,
        description=req.description,
        performance_date=req.performance_date,
        youtube_url=req.youtube_url,
    )
    db.add(archive)
    db.commit()
    db.refresh(archive)
    return {"message": "등록되었습니다.", "id": archive.id}


@app.get("/clubs/{club_id}/performance-archives/{archive_id}")
def get_performance_archive(
    club_id: int,
    archive_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    # 다른 동아리의 아카이브 접근 차단
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    a = db.query(db_models.PerformanceArchive).filter_by(
        id=archive_id, club_id=club_id
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="공연 기록을 찾을 수 없습니다.")
    # view_count 증가
    a.view_count += 1
    db.commit()
    likes_count = db.query(db_models.PerformanceArchiveLike).filter_by(archive_id=archive_id).count()
    my_liked = db.query(db_models.PerformanceArchiveLike).filter_by(
        archive_id=archive_id, user_id=member.user_id
    ).first() is not None
    return _archive_to_dict(a, likes_count, my_liked)


@app.post("/clubs/{club_id}/performance-archives/{archive_id}/like")
def toggle_archive_like(
    club_id: int,
    archive_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    # 다른 동아리의 아카이브 접근 차단
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    # 아카이브 존재 및 club_id 소속 확인
    archive = db.query(db_models.PerformanceArchive).filter_by(
        id=archive_id, club_id=club_id
    ).first()
    if not archive:
        raise HTTPException(status_code=404, detail="공연 기록을 찾을 수 없습니다.")

    existing = db.query(db_models.PerformanceArchiveLike).filter_by(
        archive_id=archive_id, user_id=member.user_id
    ).first()
    if existing:
        db.delete(existing)
        db.commit()
        return {"liked": False}
    db.add(db_models.PerformanceArchiveLike(archive_id=archive_id, user_id=member.user_id))
    db.commit()
    return {"liked": True}


@app.delete("/clubs/{club_id}/performance-archives/{archive_id}")
def delete_performance_archive(
    club_id: int,
    archive_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    # 다른 동아리의 아카이브 접근 차단
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    a = db.query(db_models.PerformanceArchive).filter_by(
        id=archive_id, club_id=club_id
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="공연 기록을 찾을 수 없습니다.")
    db.delete(a)
    db.commit()
    return {"message": "삭제되었습니다."}
```

---

### Task 3-2: ApiClient에 아카이브 메서드 추가

- [ ] `lib/api/api_client.dart`에 추가:

```dart
// ── 공연 아카이브 API ─────────────────────────────────────
static Future<List<dynamic>> getPerformanceArchives(int clubId) async {
  final response = await http.get(
    Uri.parse('$baseUrl/clubs/$clubId/performance-archives'),
    headers: await _headers(),
  ).timeout(_timeout);
  if (response.statusCode == 401) throw const UnauthorizedException();
  if (response.statusCode >= 500) throw ServerException();
  return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
}

static Future<Map<String, dynamic>> createPerformanceArchive(
  int clubId, {
  required String title,
  required String performanceDate,
  String? description,
  String? youtubeUrl,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/clubs/$clubId/performance-archives'),
    headers: await _headers(),
    body: jsonEncode({
      'title': title,
      'performance_date': performanceDate,
      if (description != null) 'description': description,
      if (youtubeUrl != null) 'youtube_url': youtubeUrl,
    }),
  ).timeout(_timeout);
  return _parseResponse(response);
}

static Future<Map<String, dynamic>> toggleArchiveLike(
  int clubId,
  int archiveId,
) async {
  final response = await http.post(
    Uri.parse('$baseUrl/clubs/$clubId/performance-archives/$archiveId/like'),
    headers: await _headers(),
  ).timeout(_timeout);
  return _parseResponse(response);
}

static Future<Map<String, dynamic>> deletePerformanceArchive(
  int clubId,
  int archiveId,
) async {
  final response = await http.delete(
    Uri.parse('$baseUrl/clubs/$clubId/performance-archives/$archiveId'),
    headers: await _headers(),
  ).timeout(_timeout);
  return _parseResponse(response);
}
```

---

### Task 3-3: PerformanceArchiveScreen 생성

- [ ] `lib/screens/performance_archive_screen.dart` 새 파일 생성:

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../widgets/youtube_card.dart';
import '../utils/error_utils.dart'; // friendlyError

class PerformanceArchiveScreen extends StatefulWidget {
  final int clubId;
  final bool isAdmin; // 추가/삭제 권한

  const PerformanceArchiveScreen({
    super.key,
    required this.clubId,
    required this.isAdmin,
  });

  @override
  State<PerformanceArchiveScreen> createState() =>
      _PerformanceArchiveScreenState();
}

class _PerformanceArchiveScreenState extends State<PerformanceArchiveScreen> {
  List<dynamic> _archives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.getPerformanceArchives(widget.clubId);
      if (mounted) setState(() { _archives = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _toggleLike(dynamic archive) async {
    try {
      await ApiClient.toggleArchiveLike(
        widget.clubId, archive['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _delete(int archiveId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 기록 삭제'),
        content: const Text('이 공연 기록을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.deletePerformanceArchive(widget.clubId, archiveId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _openAdd() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArchiveAddScreen(clubId: widget.clubId),
        fullscreenDialog: true,
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('공연 기록'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openAdd,
              tooltip: '공연 기록 추가',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _archives.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined,
                              size: 56, color: colorScheme.outline),
                          const SizedBox(height: 8),
                          Text('등록된 공연 기록이 없어요',
                              style: TextStyle(color: colorScheme.outline)),
                          if (widget.isAdmin) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _openAdd,
                              icon: const Icon(Icons.add),
                              label: const Text('첫 공연 기록 추가하기'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _archives.length,
                      itemBuilder: (context, i) {
                        final a = _archives[i];
                        final youtubeUrl = a['youtube_url'] as String?;
                        final liked = a['my_liked'] as bool? ?? false;
                        final likesCount = a['likes_count'] as int? ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: YouTubeCard(youtubeUrl: youtubeUrl),
                                ),
                              ListTile(
                                title: Text(a['title'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(a['performance_date'] as String? ?? ''),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        liked ? Icons.favorite : Icons.favorite_border,
                                        color: liked ? Colors.red : null,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleLike(a),
                                    ),
                                    Text('$likesCount',
                                        style: const TextStyle(fontSize: 12)),
                                    if (widget.isAdmin)
                                      IconButton(
                                        icon: Icon(Icons.delete_outline,
                                            color: colorScheme.error, size: 20),
                                        onPressed: () =>
                                            _delete(a['id'] as int),
                                      ),
                                  ],
                                ),
                              ),
                              if ((a['description'] as String?)?.isNotEmpty ?? false)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Text(a['description'] as String,
                                      style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 13)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ── 공연 기록 추가 화면 ────────────────────────────────────────
class _ArchiveAddScreen extends StatefulWidget {
  final int clubId;
  const _ArchiveAddScreen({required this.clubId});

  @override
  State<_ArchiveAddScreen> createState() => _ArchiveAddScreenState();
}

class _ArchiveAddScreenState extends State<_ArchiveAddScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ApiClient.createPerformanceArchive(
        widget.clubId,
        title: _titleCtrl.text.trim(),
        performanceDate:
            '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        youtubeUrl: _youtubeCtrl.text.trim().isEmpty ? null : _youtubeCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('공연 기록 추가'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '공연 제목 *',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('공연 날짜 *'),
              subtitle: Text(
                '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _youtubeCtrl,
              decoration: const InputDecoration(
                labelText: 'YouTube URL (선택)',
                prefixIcon: Icon(Icons.link, color: Colors.red),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_youtubeCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              YouTubeCard(youtubeUrl: _youtubeCtrl.text.trim()),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '설명 (선택, 셋리스트 등)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              maxLength: 1000,
            ),
          ],
        ),
      ),
    );
  }
}
```

---

### Task 3-4: home_screen.dart에 공연 기록 탭 추가

- [ ] `lib/screens/home_screen.dart` 상단에 import 추가:

```dart
import 'performance_archive_screen.dart';
```

- [ ] `_buildScreens()` 함수의 `_screenWidgets` 리스트에 피드 뒤에 추가:

```dart
PerformanceArchiveScreen(
  key: ValueKey('archive_$_currentClubId'),
  clubId: _currentClubId,
  isAdmin: _isAdmin,
),
```

- [ ] `_destinations` 리스트에 피드 탭 뒤에 추가:

```dart
const NavigationDestination(
  icon: Icon(Icons.videocam_outlined),
  selectedIcon: Icon(Icons.videocam),
  label: '공연 기록',
),
```

- [ ] 앱 실행 후 수동 테스트:
  - 하단 탭에 "공연 기록" 탭 표시 확인
  - admin으로 로그인 → 공연 기록 추가 버튼 확인
  - YouTube URL 입력 → 미리보기 확인
  - 저장 후 목록에 카드 표시 확인
  - 무료 플랜 15개 초과 시 에러 메시지 확인

- [ ] 커밋:

```bash
git add lib/screens/performance_archive_screen.dart \
        lib/screens/home_screen.dart \
        lib/api/api_client.dart
git commit -m "feat: 공연 아카이브 탭 추가"

cd ../performance-manager/backend
git add main.py models.py
git commit -m "feat: 공연 아카이브 CRUD API 추가"
```

---

## Chunk 4: 이달의 챌린지

### 수정 파일
- Create: `lib/screens/challenge_screen.dart`
- Modify: `lib/api/api_client.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `backend/main.py`
- Modify: `backend/models.py`

---

### Task 4-1: 챌린지 헬퍼 함수 및 lazy 생성 로직 추가 (백엔드)

- [ ] `backend/main.py` 파일 **상단 import 블록**에 다음 두 줄이 없으면 추가한다:

```python
from datetime import datetime
import calendar
```

- [ ] 같은 파일에 챌린지 헬퍼 함수 추가 (공연 아카이브 블록 바로 아래):

```python
def _get_or_create_current_challenge(db: Session) -> db_models.Challenge:
    """현재 월의 챌린지를 가져오거나 없으면 생성. 이전 월은 모두 비활성화."""
    current_ym = datetime.utcnow().strftime("%Y-%m")

    # 이전 월 모두 비활성화
    db.query(db_models.Challenge).filter(
        db_models.Challenge.year_month < current_ym,
        db_models.Challenge.is_active == True,
    ).update({"is_active": False})
    db.commit()

    challenge = db.query(db_models.Challenge).filter_by(year_month=current_ym).first()
    if not challenge:
        challenge = db_models.Challenge(year_month=current_ym)
        db.add(challenge)
        db.commit()
        db.refresh(challenge)
    return challenge
```

---

### Task 4-2: 챌린지 API 엔드포인트 추가 (백엔드)

- [ ] `backend/models.py`에 챌린지 제출 요청 스키마 추가:

```python
class ChallengeEntryRequest(BaseModel):
    archive_id: int
```

- [ ] `backend/main.py`에서 공연 아카이브 엔드포인트 블록 아래에 추가:

```python
# ── 챌린지 ────────────────────────────────────────────────────

@app.get("/challenge/current")
def get_current_challenge(
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    """현재 월 챌린지 정보 + 랭킹 반환"""
    challenge = _get_or_create_current_challenge(db)
    entries = challenge.entries  # already loaded via relationship

    result = []
    for entry in entries:
        likes_count = db.query(db_models.ChallengeEntryLike).filter_by(
            entry_id=entry.id
        ).count()
        my_liked = db.query(db_models.ChallengeEntryLike).filter_by(
            entry_id=entry.id, user_id=member.user_id
        ).first() is not None
        archive = entry.archive
        result.append({
            "entry_id": entry.id,
            "club_id": entry.club_id,
            "club_name": entry.club.name,
            "archive_id": archive.id,
            "archive_title": archive.title,
            "youtube_url": archive.youtube_url,
            "likes_count": likes_count,
            "my_liked": my_liked,
        })

    # 좋아요 많은 순 정렬
    result.sort(key=lambda x: x["likes_count"], reverse=True)

    # D-day 계산 (해당 월 말일까지)
    now = datetime.utcnow()
    last_day = calendar.monthrange(now.year, now.month)[1]
    end_of_month = datetime(now.year, now.month, last_day, 23, 59, 59)
    days_left = (end_of_month - now).days

    return {
        "challenge_id": challenge.id,
        "year_month": challenge.year_month,
        "is_active": challenge.is_active,
        "days_left": days_left,
        "entry_count": len(result),
        "entries": result,
        "my_club_id": member.club_id,
    }


@app.post("/challenge/entries")
def submit_challenge_entry(
    req: ChallengeEntryRequest,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    """현재 월 챌린지에 동아리 대표 공연 제출"""
    challenge = _get_or_create_current_challenge(db)

    if not challenge.is_active:
        raise HTTPException(status_code=400, detail="종료된 챌린지입니다.")

    # 이미 제출한 경우 확인
    existing = db.query(db_models.ChallengeEntry).filter_by(
        challenge_id=challenge.id, club_id=member.club_id
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="이미 이번 달 챌린지에 참가했어요. 기존 제출을 취소하고 다시 제출하세요.")

    # 해당 아카이브가 우리 동아리 것인지 확인
    archive = db.query(db_models.PerformanceArchive).filter_by(
        id=req.archive_id, club_id=member.club_id
    ).first()
    if not archive:
        raise HTTPException(status_code=404, detail="공연 기록을 찾을 수 없습니다.")

    entry = db_models.ChallengeEntry(
        challenge_id=challenge.id,
        club_id=member.club_id,
        archive_id=req.archive_id,
    )
    db.add(entry)
    db.commit()
    return {"message": "챌린지에 참가되었습니다!", "entry_id": entry.id}


@app.delete("/challenge/entries/mine")
def withdraw_challenge_entry(
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    """현재 월 챌린지 참가 취소"""
    challenge = _get_or_create_current_challenge(db)
    entry = db.query(db_models.ChallengeEntry).filter_by(
        challenge_id=challenge.id, club_id=member.club_id
    ).first()
    if not entry:
        raise HTTPException(status_code=404, detail="참가 내역이 없습니다.")
    db.delete(entry)
    db.commit()
    return {"message": "참가가 취소되었습니다."}


@app.post("/challenge/entries/{entry_id}/like")
def toggle_challenge_like(
    entry_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    entry = db.query(db_models.ChallengeEntry).get(entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="참가 항목을 찾을 수 없습니다.")

    challenge = db.query(db_models.Challenge).get(entry.challenge_id)
    if not challenge or not challenge.is_active:
        raise HTTPException(status_code=400, detail="투표 기간이 종료되었습니다.")

    existing = db.query(db_models.ChallengeEntryLike).filter_by(
        entry_id=entry_id, user_id=member.user_id
    ).first()
    if existing:
        db.delete(existing)
        db.commit()
        return {"liked": False}
    db.add(db_models.ChallengeEntryLike(entry_id=entry_id, user_id=member.user_id))
    db.commit()
    return {"liked": True}
```

---

### Task 4-3: ApiClient에 챌린지 메서드 추가

- [ ] `lib/api/api_client.dart`에 추가:

```dart
// ── 챌린지 API ──────────────────────────────────────────
static Future<Map<String, dynamic>> getCurrentChallenge() async {
  final response = await http.get(
    Uri.parse('$baseUrl/challenge/current'),
    headers: await _headers(),
  ).timeout(_timeout);
  if (response.statusCode == 401) throw const UnauthorizedException();
  if (response.statusCode >= 500) throw ServerException();
  return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
}

static Future<Map<String, dynamic>> submitChallengeEntry(int archiveId) async {
  final response = await http.post(
    Uri.parse('$baseUrl/challenge/entries'),
    headers: await _headers(),
    body: jsonEncode({'archive_id': archiveId}),
  ).timeout(_timeout);
  return _parseResponse(response);
}

static Future<Map<String, dynamic>> withdrawChallengeEntry() async {
  final response = await http.delete(
    Uri.parse('$baseUrl/challenge/entries/mine'),
    headers: await _headers(),
  ).timeout(_timeout);
  return _parseResponse(response);
}

static Future<Map<String, dynamic>> toggleChallengeLike(int entryId) async {
  final response = await http.post(
    Uri.parse('$baseUrl/challenge/entries/$entryId/like'),
    headers: await _headers(),
  ).timeout(_timeout);
  return _parseResponse(response);
}
```

---

### Task 4-4: ChallengeScreen 생성

- [ ] `lib/screens/challenge_screen.dart` 새 파일 생성:

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../utils/error_utils.dart';
import '../widgets/youtube_card.dart';
import 'performance_archive_screen.dart';

class ChallengeScreen extends StatefulWidget {
  final bool isAdmin;
  final int clubId;

  const ChallengeScreen({
    super.key,
    required this.isAdmin,
    required this.clubId,
  });

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.getCurrentChallenge();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _toggleLike(int entryId) async {
    try {
      await ApiClient.toggleChallengeLike(entryId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _submit() async {
    // 아카이브 목록에서 선택
    final archives =
        await ApiClient.getPerformanceArchives(widget.clubId);
    if (!mounted || archives.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('먼저 공연 기록 탭에서 공연을 추가해주세요!')));
      }
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: archives.length,
        itemBuilder: (_, i) {
          final a = archives[i];
          return ListTile(
            title: Text(a['title'] as String),
            subtitle: Text(a['performance_date'] as String),
            onTap: () => Navigator.pop(ctx, a as Map<String, dynamic>),
          );
        },
      ),
    );
    if (selected == null) return;

    try {
      await ApiClient.submitChallengeEntry(selected['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('챌린지에 참가되었습니다!')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = (_data?['entries'] as List<dynamic>?) ?? [];
    final daysLeft = _data?['days_left'] as int? ?? 0;
    final entryCount = _data?['entry_count'] as int? ?? 0;
    final yearMonth = _data?['year_month'] as String? ?? '';
    final myClubId = _data?['my_club_id'] as int?;
    final isParticipating = entries.any(
        (e) => (e as Map)['club_id'] == myClubId);

    return Scaffold(
      appBar: AppBar(
        title: Text('$yearMonth 챌린지'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // D-day 배너
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('결과 발표까지',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12)),
                            Text('D-$daysLeft',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('참가 동아리',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12)),
                            Text('$entryCount개',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 참가 버튼 (admin + 미참가)
                  if (widget.isAdmin && !isParticipating)
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add_circle),
                      label: const Text('우리 동아리 영상 제출하기'),
                    ),
                  if (widget.isAdmin && isParticipating)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ApiClient.withdrawChallengeEntry();
                        await _load();
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('제출 취소'),
                    ),
                  const SizedBox(height: 16),

                  // 랭킹 목록
                  ...entries.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final entry = e.value as Map<String, dynamic>;
                    final liked = entry['my_liked'] as bool? ?? false;
                    final likesCount = entry['likes_count'] as int? ?? 0;
                    final youtubeUrl = entry['youtube_url'] as String?;
                    final isFirst = rank == 1;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: isFirst
                          ? RoundedRectangleBorder(
                              side: BorderSide(
                                  color: Colors.amber.shade600, width: 2),
                              borderRadius: BorderRadius.circular(12))
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Stack(
                                children: [
                                  YouTubeCard(youtubeUrl: youtubeUrl),
                                  if (isFirst)
                                    Positioned(
                                      top: 8, left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade600,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.workspace_premium,
                                                size: 14,
                                                color: Colors.white),
                                            SizedBox(width: 3),
                                            Text('1위',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isFirst
                                  ? Colors.amber.shade100
                                  : colorScheme.surfaceContainerHighest,
                              child: Text('$rank',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isFirst
                                          ? Colors.amber.shade800
                                          : null)),
                            ),
                            title: Text(
                                entry['club_name'] as String? ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                entry['archive_title'] as String? ?? ''),
                            trailing: GestureDetector(
                              onTap: () => _toggleLike(
                                  entry['entry_id'] as int),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: liked ? Colors.red : null,
                                    size: 22,
                                  ),
                                  Text('$likesCount',
                                      style:
                                          const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
```

---

### Task 4-5: home_screen.dart에 챌린지 탭 추가

- [ ] `lib/screens/home_screen.dart` import 추가:

```dart
import 'challenge_screen.dart';
```

- [ ] `_buildScreens()`에서 공연 기록 탭 뒤에 추가:

```dart
ChallengeScreen(
  key: ValueKey('challenge_$_currentClubId'),
  isAdmin: _isAdmin,
  clubId: _currentClubId,
),
```

- [ ] `_destinations`에 공연 기록 탭 뒤에 추가:

```dart
const NavigationDestination(
  icon: Icon(Icons.emoji_events_outlined),
  selectedIcon: Icon(Icons.emoji_events),
  label: '챌린지',
),
```

- [ ] 앱 실행 후 수동 테스트:
  - 챌린지 탭 표시 확인
  - D-day 배너 표시 확인
  - admin으로 아카이브 공연 선택해서 제출 확인
  - 다른 동아리 공연에 좋아요 → 실시간 순위 변동 확인

- [ ] 커밋:

```bash
git add lib/screens/challenge_screen.dart \
        lib/screens/home_screen.dart \
        lib/api/api_client.dart
git commit -m "feat: 이달의 챌린지 화면 추가"

cd ../performance-manager/backend
git add main.py
git commit -m "feat: 챌린지 API 추가 (lazy 생성, 제출, 투표)"
```

---

## Chunk 5: 공개 웹 랭킹 페이지

### 수정 파일
- Create: `backend/templates/ranking.html`
- Create: `backend/templates/club_profile.html`
- Modify: `backend/main.py` (Jinja2 설정 + 공개 라우트)

---

### Task 5-1: Jinja2 설정 및 templates 디렉토리 생성

- [ ] `backend/templates/` 디렉토리 생성:

```bash
mkdir backend/templates
```

- [ ] `backend/main.py` 상단 import에 추가 (없는 것만):

```python
import os
from fastapi.templating import Jinja2Templates
from fastapi import Request
from fastapi.responses import HTMLResponse
```

- [ ] `app = FastAPI(...)` 선언 아래에 추가:

```python
templates = Jinja2Templates(
    directory=os.path.join(os.path.dirname(__file__), "templates")
)
```

> **Railway 주의:** `directory="templates"` 처럼 상대 경로를 쓰면 Railway에서 실행 위치에 따라 `templates` 폴더를 찾지 못할 수 있다. `os.path.dirname(__file__)`로 `main.py` 파일 기준 절대 경로를 구성해야 한다.

---

### Task 5-2: ranking.html 템플릿 생성

- [ ] `backend/templates/ranking.html` 생성:

```html
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>StageMate — 이달의 공연 랭킹</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           background: #f8fafc; color: #1e293b; }
    header { background: #0f172a; padding: 14px 20px;
             display: flex; align-items: center; justify-content: space-between; }
    .logo { display: flex; align-items: center; gap: 10px; color: white;
            font-weight: 700; font-size: 1.1em; text-decoration: none; }
    .download-btn { background: #6366f1; color: white; padding: 6px 14px;
                    border-radius: 8px; font-size: 0.8em; text-decoration: none; }
    .url-bar { background: #1e293b; padding: 5px 14px; font-size: 0.72em; color: #94a3b8; }
    main { max-width: 680px; margin: 0 auto; padding: 20px 16px; }
    .title-section { text-align: center; margin-bottom: 20px; }
    .title-section h1 { font-size: 1.4em; margin-bottom: 4px; }
    .title-section p { color: #64748b; font-size: 0.9em; }
    .top-card { border-radius: 14px; overflow: hidden; margin-bottom: 14px;
                box-shadow: 0 4px 16px rgba(0,0,0,.12); }
    .top-thumb { background: linear-gradient(135deg, #1a1a2e, #533483);
                 height: 180px; display: flex; align-items: center;
                 justify-content: center; position: relative; }
    .play-btn { width: 56px; height: 56px; background: #ff0000; border-radius: 14px;
                display: flex; align-items: center; justify-content: center; font-size: 1.6em; }
    .rank-badge { position: absolute; top: 10px; left: 12px; background: #f59e0b;
                  color: white; padding: 4px 10px; border-radius: 6px; font-size: 0.8em;
                  font-weight: bold; }
    .top-info { background: white; padding: 12px 14px;
                display: flex; justify-content: space-between; align-items: center; }
    .top-info h2 { font-size: 1em; }
    .top-info p { color: #64748b; font-size: 0.8em; margin-top: 2px; }
    .likes { display: flex; align-items: center; gap: 4px; color: #ef4444; font-weight: bold; }
    .list-card { background: white; border-radius: 12px; overflow: hidden;
                 box-shadow: 0 2px 8px rgba(0,0,0,.06); margin-bottom: 14px; }
    .list-item { display: flex; align-items: center; gap: 12px; padding: 11px 14px;
                 border-bottom: 1px solid #f1f5f9; text-decoration: none; color: inherit; }
    .list-item:last-child { border-bottom: none; }
    .rank-circle { width: 30px; height: 30px; background: #e2e8f0; border-radius: 50%;
                   display: flex; align-items: center; justify-content: center;
                   font-weight: bold; font-size: 0.85em; flex-shrink: 0; }
    .thumb-small { width: 50px; height: 36px; background: linear-gradient(135deg,#1e3a5f,#533483);
                   border-radius: 6px; display: flex; align-items: center;
                   justify-content: center; flex-shrink: 0; color: white; }
    .item-info { flex: 1; }
    .item-info strong { font-size: 0.9em; display: block; }
    .item-info span { font-size: 0.78em; color: #94a3b8; }
    .item-likes { color: #94a3b8; font-size: 0.85em; }
    .cta { background: linear-gradient(135deg, #4f46e5, #7c3aed); border-radius: 12px;
           padding: 16px; color: white; display: flex; justify-content: space-between;
           align-items: center; margin-top: 4px; }
    .cta p { font-size: 0.8em; opacity: .85; margin-top: 3px; }
    .cta-btn { background: white; color: #4f46e5; padding: 8px 14px; border-radius: 8px;
               font-weight: bold; font-size: 0.8em; text-decoration: none;
               white-space: nowrap; }
  </style>
</head>
<body>
  <header>
    <a class="logo" href="/ranking">
      <span>🎭</span> StageMate
    </a>
    <a class="download-btn" href="#">앱 다운로드</a>
  </header>
  <div class="url-bar">🔒 stagemate.app/ranking</div>

  <main>
    <div class="title-section">
      <h1>🏆 {{ year_month }} 인기 공연</h1>
      <p>전국 공연 동아리들의 이달의 무대를 만나보세요</p>
    </div>

    {% if entries %}
      {% set top = entries[0] %}
      <a href="/clubs/{{ top.club_id }}" class="top-card" style="display:block;text-decoration:none;color:inherit;">
        <div class="top-thumb">
          <div class="play-btn">▶</div>
          <div class="rank-badge">🏆 이달의 1위</div>
        </div>
        <div class="top-info">
          <div>
            <h2>{{ top.club_name }}</h2>
            <p>{{ top.archive_title }}</p>
          </div>
          <div class="likes">❤️ {{ top.likes_count }}</div>
        </div>
      </a>

      {% if entries|length > 1 %}
      <div class="list-card">
        {% for entry in entries[1:] %}
        <a href="/clubs/{{ entry.club_id }}" class="list-item">
          <div class="rank-circle">{{ loop.index + 1 }}</div>
          <div class="thumb-small">▶</div>
          <div class="item-info">
            <strong>{{ entry.club_name }}</strong>
            <span>{{ entry.archive_title }}</span>
          </div>
          <div class="item-likes">❤️ {{ entry.likes_count }}</div>
        </a>
        {% endfor %}
      </div>
      {% endif %}
    {% else %}
      <p style="text-align:center;color:#94a3b8;padding:40px 0;">
        아직 이달의 참가 동아리가 없어요.<br>앱에서 챌린지에 참가해보세요!
      </p>
    {% endif %}

    <div class="cta">
      <div>
        <strong>우리 동아리도 도전하세요</strong>
        <p>StageMate 앱에서 챌린지에 참가할 수 있어요</p>
      </div>
      <a class="cta-btn" href="#">앱 받기</a>
    </div>
  </main>
</body>
</html>
```

---

### Task 5-3: club_profile.html 템플릿 생성

- [ ] `backend/templates/club_profile.html` 생성:

```html
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ club_name }} — StageMate</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           background: #f8fafc; color: #1e293b; }
    header { background: #0f172a; padding: 14px 20px;
             display: flex; align-items: center; justify-content: space-between; }
    .logo { display: flex; align-items: center; gap: 10px; color: white;
            font-weight: 700; font-size: 1.1em; text-decoration: none; }
    .download-btn { background: #6366f1; color: white; padding: 6px 14px;
                    border-radius: 8px; font-size: 0.8em; text-decoration: none; }
    main { max-width: 680px; margin: 0 auto; padding: 20px 16px; }
    .club-header { text-align: center; margin-bottom: 24px; }
    .club-header h1 { font-size: 1.5em; margin-bottom: 4px; }
    .club-header p { color: #64748b; }
    .archive-card { background: white; border-radius: 12px; overflow: hidden;
                    margin-bottom: 12px; box-shadow: 0 2px 8px rgba(0,0,0,.06); }
    .thumb { background: linear-gradient(135deg, #1a1a2e, #533483); height: 140px;
             display: flex; align-items: center; justify-content: center; }
    .play-btn { width: 44px; height: 44px; background: #ff0000; border-radius: 12px;
                display: flex; align-items: center; justify-content: center;
                font-size: 1.4em; color: white; text-decoration: none; }
    .card-info { padding: 12px 14px; display: flex; justify-content: space-between; }
    .card-info strong { display: block; }
    .card-info span { font-size: 0.8em; color: #94a3b8; }
    .likes { display: flex; align-items: center; gap: 4px; color: #ef4444; }
    .back-link { display: inline-block; margin-bottom: 16px; color: #6366f1;
                 text-decoration: none; font-size: 0.9em; }
  </style>
</head>
<body>
  <header>
    <a class="logo" href="/ranking">
      <span>🎭</span> StageMate
    </a>
    <a class="download-btn" href="#">앱 다운로드</a>
  </header>

  <main>
    <a class="back-link" href="/ranking">← 랭킹으로 돌아가기</a>

    <div class="club-header">
      <h1>{{ club_name }}</h1>
      <p>공연 기록 {{ archives|length }}개</p>
    </div>

    {% for a in archives %}
    <div class="archive-card">
      <div class="thumb">
        {% if a.youtube_url %}
        <a class="play-btn" href="{{ a.youtube_url }}" target="_blank">▶</a>
        {% else %}
        <div class="play-btn" style="background:#555;">▶</div>
        {% endif %}
      </div>
      <div class="card-info">
        <div>
          <strong>{{ a.title }}</strong>
          <span>{{ a.performance_date }}</span>
        </div>
        <div class="likes">❤️ {{ a.likes_count }}</div>
      </div>
    </div>
    {% else %}
    <p style="text-align:center;color:#94a3b8;padding:40px 0;">
      아직 등록된 공연 기록이 없습니다.
    </p>
    {% endfor %}
  </main>
</body>
</html>
```

---

### Task 5-4: 공개 API 엔드포인트 및 웹 라우트 추가 (백엔드)

- [ ] `backend/main.py`에 추가 (파일 끝 또는 챌린지 엔드포인트 뒤):

```python
# ── 공개 API (인증 없음) ───────────────────────────────────────

@app.get("/public/ranking")
def public_ranking_api(db: Session = Depends(get_db)):
    """랭킹 JSON 데이터 — 인증 불필요"""
    current_ym = datetime.utcnow().strftime("%Y-%m")
    challenge = db.query(db_models.Challenge).filter_by(year_month=current_ym).first()
    if not challenge:
        return {"year_month": current_ym, "entries": []}

    entries = []
    for entry in challenge.entries:
        likes_count = db.query(db_models.ChallengeEntryLike).filter_by(
            entry_id=entry.id).count()
        entries.append({
            "club_id": entry.club_id,
            "club_name": entry.club.name,
            "archive_id": entry.archive_id,
            "archive_title": entry.archive.title,
            "youtube_url": entry.archive.youtube_url,
            "likes_count": likes_count,
        })
    entries.sort(key=lambda x: x["likes_count"], reverse=True)
    return {"year_month": current_ym, "entries": entries}


@app.get("/public/clubs/{club_id}")
def public_club_api(club_id: int, db: Session = Depends(get_db)):
    """동아리 공개 프로필 + 아카이브 JSON — 인증 불필요"""
    club = db.query(db_models.Club).filter_by(id=club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    archives = db.query(db_models.PerformanceArchive).filter_by(
        club_id=club_id
    ).order_by(db_models.PerformanceArchive.performance_date.desc()).all()

    result = []
    for a in archives:
        likes_count = db.query(db_models.PerformanceArchiveLike).filter_by(
            archive_id=a.id).count()
        result.append({
            "id": a.id,
            "title": a.title,
            "performance_date": a.performance_date,
            "youtube_url": a.youtube_url,
            "view_count": a.view_count,
            "likes_count": likes_count,
        })
    return {"club_name": club.name, "archives": result}


# ── 웹 페이지 라우트 ───────────────────────────────────────────

@app.get("/ranking")
def web_ranking(request: Request, db: Session = Depends(get_db)):
    data = public_ranking_api(db)
    return templates.TemplateResponse("ranking.html", {
        "request": request,
        "year_month": data["year_month"],
        "entries": data["entries"],
    })


@app.get("/clubs/{club_id}/profile")
def web_club_profile(club_id: int, request: Request, db: Session = Depends(get_db)):
    club = db.query(db_models.Club).filter_by(id=club_id).first()
    if not club:
        return HTMLResponse("<h1>404 — 동아리를 찾을 수 없습니다</h1>", status_code=404)
    data = public_club_api(club_id, db)
    return templates.TemplateResponse("club_profile.html", {
        "request": request,
        "club_name": data["club_name"],
        "archives": data["archives"],
    })
```

> **라우트 명명 규칙:** 웹 페이지 라우트를 `/clubs/{club_id}/profile`로 지정하여 기존 인증 API 경로(`/clubs/{club_id}/...`)와 충돌하지 않도록 한다. 기존 API 경로는 `/clubs/{club_id}/performance-archives`, `/clubs/{club_id}/members` 등 세부 경로를 가지므로 `/clubs/{club_id}` 단독 경로와는 겹치지 않으나, 명시적인 `/profile` suffix로 의도를 분명히 한다.

- [ ] `backend/templates/ranking.html`의 동아리 링크를 업데이트한다 (`/clubs/...` → `/clubs/.../profile`):

```html
<a href="/clubs/{{ top.club_id }}/profile" class="top-card" ...>
...
<a href="/clubs/{{ entry.club_id }}/profile" class="list-item">
```

- [ ] `backend/templates/club_profile.html`의 뒤로 가기 링크도 확인:

```html
<a class="back-link" href="/ranking">← 랭킹으로 돌아가기</a>
```

---

### Task 5-5: 웹 페이지 동작 확인

- [ ] 백엔드 로컬 실행 후 브라우저에서 테스트:

```
http://localhost:8000/ranking          → HTML 랭킹 페이지 확인
http://localhost:8000/clubs/1/profile  → 동아리 공개 프로필 확인
http://localhost:8000/public/ranking   → JSON 응답 확인
http://localhost:8000/clubs/999/profile → 존재하지 않는 동아리 → 404 상태코드 확인
```

- [ ] 모바일 화면(375px)에서 레이아웃 깨지지 않는지 확인 (브라우저 DevTools → 반응형 모드)
- [ ] 챌린지 참가 데이터가 없을 때 빈 상태 메시지 표시 확인

- [ ] Railway 배포 후 Railway 로그에서 `templates` 디렉토리 오류 없는지 확인

- [ ] 커밋:

```bash
cd backend
git add main.py templates/ranking.html templates/club_profile.html
git commit -m "feat: 공개 웹 랭킹 페이지 추가 (Jinja2)"
```

---

## 버전 업데이트

- [ ] `pubspec.yaml` 버전을 `1.0.0+35`로 업데이트
- [ ] APK 빌드:

```bash
cd C:/projects/performance_manager
flutter build apk --release --dart-define-from-file=dart_defines.json
```

- [ ] 최종 커밋:

```bash
git add pubspec.yaml
git commit -m "chore: v35 공연 플랫폼 기능 (YouTube 링크·아카이브·챌린지·웹랭킹)"
git push origin main
```
