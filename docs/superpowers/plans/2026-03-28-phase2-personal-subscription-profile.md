# Phase 2: Personal Subscription + Profile System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 개인 구독(PERSONAL ₩2,900/월) + 개인 프로필 페이지 + 아카이브(영상·사진) + 닉네임 효과 구현

**Architecture:** users 테이블에 개인 구독 컬럼을 추가하고 archive_items/comments/likes 테이블을 신설한다. FastAPI에 프로필·아카이브·개인 구독 검증 API를 추가하고, Flutter에 profile_screen·archive_upload·personal_subscription·nickname_style 화면을 신규 생성한다. Phase 1에서 주석 처리된 cron.py users 만료 블록도 활성화한다.

**Tech Stack:** FastAPI · SQLAlchemy · PostgreSQL · slowapi · Cloudflare R2 (boto3) · Flutter · in_app_purchase ^3.2.0 (기존)

**Spec:** `docs/superpowers/specs/2026-03-28-club-premium-subscription-design.md` Section 11~15

**Depends on:** Phase 1 완료 (nickname 컬럼, 실명 노출 차단, presigned URL 개선)

---

## Chunk 1: DB 마이그레이션 + 개인 구독 백엔드 API

### Task 1: users 테이블 개인 구독 컬럼 추가

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py`
- Modify: `C:/projects/performance-manager/backend/main.py` (startup migration)
- Modify: `C:/projects/performance-manager/backend/cron.py`

- [ ] **Step 1: `db_models.py` User 모델에 컬럼 추가**

```python
# db_models.py — User 클래스에 추가
nickname_color           = Column(String(7), nullable=True)    # 닉네임 단색 hex (PERSONAL+)
nickname_color2          = Column(String(7), nullable=True)    # 그라데이션 끝 색 (PERSONAL+)
nickname_bold            = Column(Boolean, default=False, nullable=False)
personal_banner_url      = Column(String, nullable=True)
personal_theme_color     = Column(String(7), nullable=True)
bio                      = Column(String(150), nullable=True)  # 자기소개
instagram_id             = Column(String(50), nullable=True)   # @ 제외 순수 ID
personal_plan            = Column(String(20), default="free", nullable=False)
personal_plan_expires_at = Column(DateTime, nullable=True)
```

- [ ] **Step 2: `main.py` `run_migrations()` ALTER TABLE 추가**

PostgreSQL 9.6+에서 `ADD COLUMN IF NOT EXISTS` 지원 → Railway 재배포 시 중복 실행 안전:

```python
"ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname_color VARCHAR(7)",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname_color2 VARCHAR(7)",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname_bold BOOLEAN DEFAULT FALSE",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS personal_banner_url VARCHAR",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS personal_theme_color VARCHAR(7)",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(150)",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS instagram_id VARCHAR(50)",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS personal_plan VARCHAR(20) DEFAULT 'free'",
"ALTER TABLE users ADD COLUMN IF NOT EXISTS personal_plan_expires_at TIMESTAMP",
```

- [ ] **Step 3: cron.py users 만료 블록 처리**

> ⚠️ `cron.py`가 아직 없으면 Phase 1 계획에서 먼저 생성해야 함. Phase 1 완료 후에는 `cron.py`의 `expire()` 함수에 users 만료 블록이 주석 처리된 상태로 존재한다 (`# Phase 3 only` 주석). 아래와 같이 주석 해제:

`C:/projects/performance-manager/backend/cron.py`의 `expire()` 함수에서 Phase 1 때 주석 처리한 users 블록을 활성화:

```python
def expire():
    """만료된 동아리/개인 구독 다운그레이드"""
    with Session(engine) as db:
        now = datetime.utcnow()
        db.execute(text("""
            UPDATE clubs
            SET plan = 'free', plan_expires_at = NULL, boost_credits = 0
            WHERE plan != 'free' AND plan_expires_at < :now
        """), {"now": now})
        # Phase 2: users.personal_plan 만료 처리 활성화
        db.execute(text("""
            UPDATE users
            SET personal_plan = 'free', personal_plan_expires_at = NULL
            WHERE personal_plan != 'free' AND personal_plan_expires_at < :now
        """), {"now": now})
        db.commit()
    print(f"[cron:expire] done at {now}")
```

- [ ] **Step 4: 서버 재시작 후 마이그레이션 확인**

```bash
cd C:/projects/performance-manager/backend
uvicorn main:app --reload
# 로그에 오류 없이 시작되면 성공
```

- [ ] **Step 5: Commit**

```bash
git add backend/db_models.py backend/main.py backend/cron.py
git commit -m "feat: add personal subscription columns to users, activate cron expire"
```

---

### Task 2: archive_items / archive_comments / archive_likes 테이블 신설

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `db_models.py`에 ArchiveItem 모델 추가**

```python
class ArchiveItem(Base):
    __tablename__ = "archive_items"
    id          = Column(Integer, primary_key=True, index=True)
    user_id     = Column(Integer, ForeignKey("users.id"), nullable=False)
    media_url   = Column(String, nullable=False)
    media_type  = Column(String(10), nullable=False)   # 'image' | 'video'
    caption     = Column(String(500), nullable=True)
    like_count  = Column(Integer, default=0, nullable=False)
    created_at  = Column(DateTime, default=datetime.utcnow)
```

- [ ] **Step 2: `db_models.py`에 ArchiveComment, ArchiveLike 모델 추가**

```python
class ArchiveComment(Base):
    __tablename__ = "archive_comments"
    id              = Column(Integer, primary_key=True, index=True)
    archive_item_id = Column(Integer, ForeignKey("archive_items.id", ondelete="CASCADE"), nullable=False)
    author_id       = Column(Integer, ForeignKey("users.id"), nullable=False)
    content         = Column(String(500), nullable=False)
    created_at      = Column(DateTime, default=datetime.utcnow)

class ArchiveLike(Base):
    __tablename__ = "archive_likes"
    archive_item_id = Column(Integer, ForeignKey("archive_items.id", ondelete="CASCADE"), primary_key=True)
    user_id         = Column(Integer, ForeignKey("users.id"), primary_key=True)
```

- [ ] **Step 3: `main.py` startup migration에 CREATE TABLE 추가**

```python
"""CREATE TABLE IF NOT EXISTS archive_items (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    media_url   VARCHAR NOT NULL,
    media_type  VARCHAR(10) NOT NULL,
    caption     VARCHAR(500),
    like_count  INTEGER DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
)""",
"""CREATE TABLE IF NOT EXISTS archive_comments (
    id              SERIAL PRIMARY KEY,
    archive_item_id INTEGER NOT NULL REFERENCES archive_items(id) ON DELETE CASCADE,
    author_id       INTEGER NOT NULL REFERENCES users(id),
    content         VARCHAR(500) NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
)""",
"""CREATE TABLE IF NOT EXISTS archive_likes (
    archive_item_id INTEGER NOT NULL REFERENCES archive_items(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    PRIMARY KEY (archive_item_id, user_id)
)""",
```

- [ ] **Step 4: 서버 재시작 후 테이블 생성 확인**

```bash
uvicorn main:app --reload
# 오류 없이 시작되면 성공
```

- [ ] **Step 5: Commit**

```bash
git add backend/db_models.py backend/main.py
git commit -m "feat: add archive_items, archive_comments, archive_likes tables"
```

---

### Task 3: 개인 프로필 API

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 ProfileUpdateRequest 추가**

```python
class ProfileUpdateRequest(BaseModel):
    bio:                  str | None = Field(None, max_length=150)
    instagram_id:         str | None = Field(None, max_length=50)
    nickname_color:       str | None = None    # "#RRGGBB"
    nickname_color2:      str | None = None    # 그라데이션 끝 색
    nickname_bold:        bool | None = None
    personal_banner_url:  str | None = None
    personal_theme_color: str | None = None

    @field_validator('nickname_color', 'nickname_color2', 'personal_theme_color')
    @classmethod
    def valid_hex(cls, v):
        if v and not re.match(r'^#[0-9A-Fa-f]{6}$', v):
            raise ValueError('올바른 hex 색상 코드가 아닙니다 (예: #6750A4)')
        return v

    @field_validator('instagram_id')
    @classmethod
    def valid_instagram(cls, v):
        if v and re.search(r'[^a-zA-Z0-9._]', v):
            raise ValueError('인스타그램 ID는 영문자, 숫자, 점, 밑줄만 가능합니다.')
        return v

    @field_validator('personal_banner_url')
    @classmethod
    def valid_banner_url(cls, v):
        """배너 URL은 R2 profiles/ 키 경로여야 함 — 임의 외부 URL 저장 방지."""
        if v and not v.startswith("profiles/"):
            raise ValueError("personal_banner_url은 R2 profiles/ 경로여야 합니다.")
        return v
```

- [ ] **Step 2: `main.py`에 `GET /users/{user_id}/profile` 추가**

```python
@app.get("/users/{user_id}/profile")
def get_user_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """공개 프로필 조회 — display_name 노출 금지 (스펙 Section 12-2)
    ⚠️ 앱 전용: get_current_user 의존성으로 인증 필수. 비인증 guest 접근 차단 의도적.
    미인증 딥링크 접근이 필요한 경우 get_optional_user 의존성으로 교체 필요.
    """
    user = db.query(db_models.User).filter(
        db_models.User.id == user_id,
        db_models.User.deleted_at == None,
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")

    is_personal = user.personal_plan == "personal"

    # 닉네임 효과 (PERSONAL 구독자만 적용)
    nickname_style = None
    if is_personal and user.nickname_color:
        nickname_style = {
            "color":  user.nickname_color,
            "color2": user.nickname_color2,
            "bold":   user.nickname_bold or False,
        }

    return {
        "user_id":              user.id,
        "nickname":             user.nickname or "알 수 없음",
        # ⚠️ display_name 명시적 제외 — 실명 노출 방지 (스펙 Section 12-2)
        "avatar_url":           getattr(user, "avatar_url", None),  # 스펙 Section 14 필드
        "bio":                  user.bio if is_personal else None,
        "instagram_id":         user.instagram_id if is_personal else None,
        "nickname_style":       nickname_style,
        # is_personal_subscriber: 프로필 '소유자'의 구독 상태. 조회자 구독 여부가 아님.
        # Flutter에서 아카이브 잠금 여부를 판단할 때 이 필드를 사용.
        "personal_banner_url":  user.personal_banner_url if is_personal else None,
        "personal_theme_color": user.personal_theme_color if is_personal else None,
        "is_personal_subscriber": is_personal,
    }
```

- [ ] **Step 3: `main.py`에 `PATCH /users/me/profile` 추가**

```python
@app.patch("/users/me/profile")
@limiter.limit("5/minute")
def update_my_profile(
    request: Request,
    req: ProfileUpdateRequest,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """내 프로필 수정 — PERSONAL 구독 필요 항목은 구독 확인 후 적용"""
    is_personal = current_user.personal_plan == "personal"

    # bio, instagram_id: 비구독자도 설정 가능 (단, 공개 프로필에서는 구독자만 표시)
    if req.bio is not None:
        current_user.bio = req.bio or None
    if req.instagram_id is not None:
        current_user.instagram_id = req.instagram_id or None

    # 닉네임 효과·배너·컬러: PERSONAL 구독자만
    personal_only_fields = [
        req.nickname_color, req.nickname_color2,
        req.nickname_bold, req.personal_banner_url, req.personal_theme_color,
    ]
    if any(f is not None for f in personal_only_fields):
        if not is_personal:
            raise HTTPException(
                status_code=403,
                detail="닉네임 효과와 배너는 PERSONAL 구독이 필요합니다."
            )
        if req.nickname_color is not None:
            current_user.nickname_color = req.nickname_color or None
        if req.nickname_color2 is not None:
            current_user.nickname_color2 = req.nickname_color2 or None
        if req.nickname_bold is not None:
            current_user.nickname_bold = req.nickname_bold
        if req.personal_banner_url is not None:
            current_user.personal_banner_url = req.personal_banner_url or None
        if req.personal_theme_color is not None:
            current_user.personal_theme_color = req.personal_theme_color or None

    db.commit()
    return {"message": "프로필이 업데이트됐습니다."}
```

- [ ] **Step 4: 테스트 — 비구독자가 닉네임 효과 설정 시도 시 403 확인**

```bash
TOKEN="..."  # personal_plan='free' 사용자 토큰
curl -X PATCH http://localhost:8000/users/me/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nickname_color":"#FF0000"}'
# 기대: 403 {"detail": "닉네임 효과와 배너는 PERSONAL 구독이 필요합니다."}
```

- [ ] **Step 5: 테스트 — display_name이 응답에 없는지 확인**

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/users/1/profile
# 기대: 응답 JSON에 "display_name" 키가 없고, "nickname" 키만 있음
```

- [ ] **Step 6: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add GET /users/{id}/profile and PATCH /users/me/profile"
```

---

### Task 4: 아카이브 API (CRUD + 좋아요 + 댓글)

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 ArchiveCommentRequest + ArchiveItemCreateRequest 추가**

```python
class ArchiveCommentRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=500)

    @field_validator('content')
    @classmethod
    def no_html(cls, v: str) -> str:
        import html
        v = html.escape(v.strip())
        if len(v) == 0:
            raise ValueError('댓글 내용을 입력해주세요.')
        return v

class ArchiveItemCreateRequest(BaseModel):
    """아카이브 업로드 요청 — media_url은 R2 오브젝트 key (클라이언트가 전달한 presigned key)."""
    media_url:  str = Field(..., min_length=1, max_length=1000)
    media_type: Literal["image", "video"]
    caption:    str | None = Field(None, max_length=500)

    @field_validator('media_url')
    @classmethod
    def valid_r2_key(cls, v: str) -> str:
        """R2 key는 반드시 'profiles/' 로 시작해야 함 — 임의 외부 URL 저장 방지."""
        if not v.startswith("profiles/"):
            raise ValueError("media_url은 R2 profiles/ 경로여야 합니다.")
        return v
```

- [ ] **Step 2: `main.py`에 `GET /users/{user_id}/archive` 추가**

```python
@app.get("/users/{user_id}/archive")
@limiter.limit("60/minute")
def get_user_archive(
    request: Request,
    user_id: int,
    offset: int = 0,
    limit: int = 20,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    limit = min(limit, 50)
    target = db.query(db_models.User).filter(
        db_models.User.id == user_id,
        db_models.User.deleted_at == None,
    ).first()
    if not target:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")

    # 비구독자 아카이브 잠금
    if target.personal_plan != "personal":
        return {"items": [], "locked": True, "total": 0}

    items = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.user_id == user_id
    ).order_by(db_models.ArchiveItem.created_at.desc()).offset(offset).limit(limit).all()

    total = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.user_id == user_id
    ).count()

    # N+1 방지: 현재 사용자가 좋아요한 item_id 집합을 한 번에 조회
    item_ids = [item.id for item in items]
    liked_ids: set[int] = set()
    if item_ids:
        liked_rows = db.query(db_models.ArchiveLike.archive_item_id).filter(
            db_models.ArchiveLike.archive_item_id.in_(item_ids),
            db_models.ArchiveLike.user_id == current_user.id,
        ).all()
        liked_ids = {row[0] for row in liked_rows}

    result = []
    for item in items:
        result.append({
            "id":         item.id,
            "media_url":  item.media_url,
            "media_type": item.media_type,
            "caption":    item.caption,
            "like_count": item.like_count,
            "liked":      item.id in liked_ids,
            "created_at": item.created_at.isoformat(),
        })
    return {"items": result, "locked": False, "total": total}
```

- [ ] **Step 3: `main.py`에 `POST /users/me/archive` 추가**

```python
@app.post("/users/me/archive")
@limiter.limit("20/minute")
def upload_archive_item(
    request: Request,
    req: ArchiveItemCreateRequest,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """아카이브 아이템 업로드 (PERSONAL 구독자만 가능)
    media_url은 클라이언트가 presigned URL로 업로드한 후 얻은 R2 오브젝트 key.
    key는 반드시 profiles/{user_id}/ 로 시작해야 하며, ArchiveItemCreateRequest validator가 검증.
    """
    if current_user.personal_plan != "personal":
        raise HTTPException(status_code=403, detail="아카이브는 PERSONAL 구독이 필요합니다.")

    # 소유권 검증: profiles/{user_id}/ 경로인지 확인
    expected_prefix = f"profiles/{current_user.id}/"
    if not req.media_url.startswith(expected_prefix):
        raise HTTPException(status_code=403, detail="본인 경로의 파일만 등록할 수 있습니다.")

    item = db_models.ArchiveItem(
        user_id=current_user.id,
        media_url=req.media_url,
        media_type=req.media_type,
        caption=req.caption,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return {"id": item.id, "media_url": item.media_url, "created_at": item.created_at.isoformat()}
```

- [ ] **Step 4: `main.py`에 `DELETE /users/me/archive/{item_id}` 추가 (원자적 삭제)**

```python
@app.delete("/users/me/archive/{item_id}")
def delete_archive_item(
    item_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """아카이브 삭제 — DB 레코드 + R2 오브젝트를 동일 핸들러 내 원자적으로 처리 (스펙 Section 11-4)"""
    item = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.id == item_id,
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="아카이브 아이템을 찾을 수 없습니다.")
    # 소유권 확인 (IDOR 방어)
    if item.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="본인 아카이브만 삭제할 수 있습니다.")

    # R2 오브젝트 삭제 — 기존 코드패턴과 동일하게 inline boto3 사용 (모듈레벨 s3_client 없음)
    try:
        s3 = boto3.client(
            "s3",
            endpoint_url=settings.R2_ENDPOINT_URL,
            aws_access_key_id=settings.R2_ACCESS_KEY_ID,
            aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        )
        # media_url은 R2 오브젝트 key (presigned key 저장 방식)
        r2_key = item.media_url  # "profiles/{user_id}/{uuid}/{filename}" 형태
        if r2_key:
            s3.delete_object(Bucket=settings.R2_BUCKET_NAME, Key=r2_key)
    except Exception as e:
        logger.error(f"R2 delete failed for archive item {item_id}: {e}")
        # R2 삭제 실패 시 DB 레코드는 계속 삭제 (orphan이 partial failure보다 낫다)

    db.delete(item)
    db.commit()
    return {"message": "아카이브 아이템이 삭제됐습니다."}
```

- [ ] **Step 5: `main.py`에 좋아요 토글 + 댓글 API 추가**

```python
@app.post("/archive/{item_id}/likes")
@limiter.limit("60/minute")
def toggle_archive_like(
    request: Request,
    item_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    item = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.id == item_id
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="아카이브 아이템을 찾을 수 없습니다.")

    existing = db.query(db_models.ArchiveLike).filter(
        db_models.ArchiveLike.archive_item_id == item_id,
        db_models.ArchiveLike.user_id == current_user.id,
    ).first()
    if existing:
        db.delete(existing)
        # 레이스 컨디션 방어: Python 값 직접 변경 대신 SQL UPDATE 사용
        db.execute(
            text("UPDATE archive_items SET like_count = GREATEST(0, like_count - 1) WHERE id = :id"),
            {"id": item_id},
        )
        liked = False
    else:
        db.add(db_models.ArchiveLike(archive_item_id=item_id, user_id=current_user.id))
        db.execute(
            text("UPDATE archive_items SET like_count = like_count + 1 WHERE id = :id"),
            {"id": item_id},
        )
        liked = True
    db.commit()
    # expire() 후 refresh: raw SQL UPDATE가 ORM identity map을 우회했으므로
    # refresh 전 expire로 캐시를 무효화해야 DB에서 최신 값을 가져옴
    db.expire(item)
    db.refresh(item)
    return {"liked": liked, "like_count": item.like_count}

@app.get("/archive/{item_id}/comments")
@limiter.limit("60/minute")
def get_archive_comments(
    request: Request,
    item_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    item = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.id == item_id
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="아카이브 아이템을 찾을 수 없습니다.")

    comments = db.query(db_models.ArchiveComment).filter(
        db_models.ArchiveComment.archive_item_id == item_id
    ).order_by(db_models.ArchiveComment.created_at.asc()).all()

    # N+1 방지: 댓글 작성자 목록을 한 번에 조회
    author_ids = list({c.author_id for c in comments})
    author_map: dict[int, str] = {}
    if author_ids:
        authors = db.query(db_models.User.id, db_models.User.nickname).filter(
            db_models.User.id.in_(author_ids)
        ).all()
        author_map = {row[0]: (row[1] or "알 수 없음") for row in authors}

    result = []
    for c in comments:
        result.append({
            "id":         c.id,
            "author_id":  c.author_id,
            "author":     author_map.get(c.author_id, "알 수 없음"),
            "content":    c.content,
            "created_at": c.created_at.isoformat(),
            "is_mine":    c.author_id == current_user.id,
        })
    return {"comments": result}

@app.post("/archive/{item_id}/comments")
@limiter.limit("30/minute")
def create_archive_comment(
    request: Request,
    item_id: int,
    req: ArchiveCommentRequest,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    item = db.query(db_models.ArchiveItem).filter(
        db_models.ArchiveItem.id == item_id
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="아카이브 아이템을 찾을 수 없습니다.")

    comment = db_models.ArchiveComment(
        archive_item_id=item_id,
        author_id=current_user.id,
        content=req.content,
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return {
        "id":         comment.id,
        "author":     current_user.nickname or "알 수 없음",
        "content":    comment.content,
        "created_at": comment.created_at.isoformat(),
    }

@app.delete("/archive/{item_id}/comments/{comment_id}")
def delete_archive_comment(
    item_id: int,
    comment_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    comment = db.query(db_models.ArchiveComment).filter(
        db_models.ArchiveComment.id == comment_id,
        db_models.ArchiveComment.archive_item_id == item_id,
    ).first()
    if not comment:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다.")
    if comment.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="본인 댓글만 삭제할 수 있습니다.")
    db.delete(comment)
    db.commit()
    return {"message": "댓글이 삭제됐습니다."}
```

- [ ] **Step 6: 테스트 — 비구독자 아카이브 업로드 시 403 확인**

```bash
TOKEN="..."  # personal_plan='free' 사용자 (user_id=1) 토큰
# media_url은 valid R2 key (profiles/ 시작) 사용 — 외부 URL은 422를 유발해 403 체크 불가
curl -X POST http://localhost:8000/users/me/archive \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"media_url":"profiles/1/test-uuid/file.jpg","media_type":"image"}'
# 기대: 403 {"detail": "아카이브는 PERSONAL 구독이 필요합니다."}
```

- [ ] **Step 7: 테스트 — 타인 아카이브 삭제 시 403 확인**

```bash
OTHER_TOKEN="..."
curl -X DELETE http://localhost:8000/users/me/archive/1 \
  -H "Authorization: Bearer $OTHER_TOKEN"
# 기대: 403 (소유권 불일치)
```

- [ ] **Step 8: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add archive CRUD, like toggle, comments with ownership checks"
```

---

### Task 5: 개인 구독 검증 API + 웹훅 개인 구독 처리

> ⚠️ **Phase 1 전제조건 확인**: 이 Task를 시작하기 전 반드시 확인:
> 1. `db_models.py`에 `SubscriptionTransaction` 모델이 존재하는지
> 2. `main.py`에 `PLAN_MAP`, `_extend_subscription`, `_cancel_subscription` 함수가 존재하는지
>
> 없다면 Phase 1 계획 (`2026-03-28-phase1-foundation-club-subscription.md`)의 Task 7을 먼저 완료해야 함.

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 PersonalSubscriptionVerifyRequest 추가**

```python
class PersonalSubscriptionVerifyRequest(BaseModel):
    product_id:     str   # "stagemate_personal_monthly"
    transaction_id: str
    platform:       Literal["apple", "google"]
    receipt_data:   str   # base64 영수증 (Apple) 또는 purchase_token (Google)
    # ⚠️ expires_at은 클라이언트가 전달하지 않음 — 서버에서 purchased_at + 31일로 계산
```

- [ ] **Step 2: `main.py` PLAN_MAP에 personal 제품 ID 추가**

```python
# Phase 1에서 작성된 PLAN_MAP에 stagemate_personal_monthly 추가:
# (PLAN_MAP이 없으면 Phase 1 Task 7 먼저 완료)
PLAN_MAP = {
    "stagemate_standard_monthly": "standard",
    "stagemate_standard_early":   "standard",
    "stagemate_pro_monthly":      "pro",
    "stagemate_pro_early":        "pro",
    "stagemate_storage_1gb":      None,         # 소모성 (플랜 변경 없음)
    "stagemate_personal_monthly": "personal",   # Phase 2 추가
}
```

- [ ] **Step 3: `main.py`에 `POST /users/me/subscription/verify` 추가**

```python
@app.post("/users/me/subscription/verify")
@limiter.limit("5/minute")
def verify_personal_subscription(
    request: Request,
    req: PersonalSubscriptionVerifyRequest,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """개인 인앱결제 영수증 검증 후 personal_plan 업데이트"""
    # 중복 transaction_id 방지 (리플레이 어택 차단)
    dup = db.query(db_models.SubscriptionTransaction).filter(
        db_models.SubscriptionTransaction.transaction_id == req.transaction_id
    ).first()
    if dup:
        raise HTTPException(status_code=409, detail="이미 처리된 영수증입니다.")

    if req.product_id != "stagemate_personal_monthly":
        raise HTTPException(status_code=400, detail="올바르지 않은 개인 구독 상품입니다.")

    # 영수증 서버 검증 — 프로덕션 배포 전 반드시 구현 필요
    # RECEIPT_VERIFICATION_ENABLED=true 환경변수로 스위치 (기본 false = 개발 스텁)
    RECEIPT_VERIFICATION_ENABLED = os.getenv("RECEIPT_VERIFICATION_ENABLED", "false") == "true"
    if not req.receipt_data:
        raise HTTPException(status_code=400, detail="영수증 데이터가 없습니다.")
    if RECEIPT_VERIFICATION_ENABLED:
        # 프로덕션: 실제 검증 로직 구현 필요
        # Apple: App Store Server API V2 JWS — GET /inApps/v2/history/{transactionId}
        # Google: Google Play Developer API — purchases.subscriptions.get
        raise HTTPException(
            status_code=501,
            detail="영수증 서버 검증이 아직 구현되지 않았습니다. RECEIPT_VERIFICATION_ENABLED=false로 우회하세요.",
        )
    # 개발/스테이징: 영수증 검증 스킵 (더미 영수증 허용)

    # expires_at은 서버에서 계산 — 클라이언트 신뢰 없음
    purchased_at = datetime.utcnow()
    expires_at = purchased_at + timedelta(days=31)

    current_user.personal_plan = "personal"
    current_user.personal_plan_expires_at = expires_at

    txn = db_models.SubscriptionTransaction(
        club_id=None,   # 개인 구독 — club_id NULL (스펙 Section 5)
        user_id=current_user.id,
        product_id=req.product_id,
        transaction_id=req.transaction_id,
        platform=req.platform,
        purchased_at=purchased_at,
        expires_at=expires_at,
        status="active",
        raw_payload=req.receipt_data[:2000],  # Apple JWS 토큰은 수 KB — 디버깅용으로 2000자 저장
    )
    db.add(txn)
    db.commit()
    return {
        "message": "PERSONAL 플랜이 활성화됐습니다.",
        "personal_plan": "personal",
        "expires_at": expires_at.isoformat(),
    }
```

- [ ] **Step 4: `main.py`의 `_extend_subscription` / `_cancel_subscription`에 개인 구독 처리 추가**

Phase 1에서 작성한 두 함수를 아래와 같이 수정:

```python
def _extend_subscription(txn: db_models.SubscriptionTransaction, db: Session):
    from datetime import timedelta
    if txn.club_id:
        # 동아리 구독
        club = db.query(db_models.Club).filter(db_models.Club.id == txn.club_id).first()
        if club:
            # ⚠️ +31일은 근사값 (Phase 1 주석 참조)
            club.plan_expires_at = (club.plan_expires_at or datetime.utcnow()) + timedelta(days=31)
            db.commit()
    else:
        # 개인 구독 (club_id = NULL)
        user = db.query(db_models.User).filter(db_models.User.id == txn.user_id).first()
        if user:
            user.personal_plan_expires_at = (
                user.personal_plan_expires_at or datetime.utcnow()
            ) + timedelta(days=31)
            db.commit()

def _cancel_subscription(txn: db_models.SubscriptionTransaction, db: Session):
    if txn.club_id:
        # 동아리 구독
        club = db.query(db_models.Club).filter(db_models.Club.id == txn.club_id).first()
        if club:
            club.plan = "free"
            club.plan_expires_at = None
            club.boost_credits = 0
    else:
        # 개인 구독
        user = db.query(db_models.User).filter(db_models.User.id == txn.user_id).first()
        if user:
            user.personal_plan = "free"
            user.personal_plan_expires_at = None
    txn.status = "cancelled"
    db.commit()
```

- [ ] **Step 5: 테스트 — 중복 transaction_id 재시도 시 409 확인**

```bash
TOKEN="..."
curl -X POST http://localhost:8000/users/me/subscription/verify \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"product_id":"stagemate_personal_monthly","transaction_id":"txn_001","platform":"apple","receipt_data":"abc123"}'
# 첫 번째 호출: 200
# 두 번째 동일 호출: 409
```

- [ ] **Step 6: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add POST /users/me/subscription/verify and personal webhook handling"
```

---

## Chunk 2: Flutter — 프로필 + 아카이브 + 개인 구독

### Task 6: ApiClient 개인 구독·프로필·아카이브 메서드 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`

- [ ] **Step 0: `api_client.dart`에 `_get`/`_post`/`_patch`/`_delete` 헬퍼 존재 여부 확인 후 추가**

기존 `api_client.dart`는 헬퍼 없이 `http.get/post`를 inline으로 사용한다.
헬퍼 추가 전에 기존 코드에서 `_authOnlyHeaders()`, `_timeout` 상수가 있는지 확인한다:

```bash
grep -n "_authOnlyHeaders\|_headers\|_timeout" C:/projects/performance_manager/lib/api/api_client.dart | head -20
```

존재하면 그 패턴을 그대로 사용. 없으면 아래를 클래스 내에 추가:

```dart
// ⚠️ 기존 _authOnlyHeaders(), _timeout이 있으면 이 블록 대신 그것을 사용
static const _timeout = Duration(seconds: 30);

static Future<Map<String, String>> _authOnlyHeaders() async {
  final token = await getToken();
  return {'Authorization': 'Bearer $token'};
}

static Future<Map<String, dynamic>> _get(String path) async {
  final res = await http.get(
    Uri.parse('$baseUrl$path'),
    headers: await _authOnlyHeaders(),
  ).timeout(_timeout);
  return _parseResponse(res);
}

static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
  final headers = await _authOnlyHeaders();
  headers['Content-Type'] = 'application/json';
  final res = await http.post(
    Uri.parse('$baseUrl$path'),
    headers: headers,
    body: jsonEncode(body),
  ).timeout(_timeout);
  return _parseResponse(res);
}

static Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
  final headers = await _authOnlyHeaders();
  headers['Content-Type'] = 'application/json';
  final res = await http.patch(
    Uri.parse('$baseUrl$path'),
    headers: headers,
    body: jsonEncode(body),
  ).timeout(_timeout);
  return _parseResponse(res);
}

static Future<void> _delete(String path) async {
  final res = await http.delete(
    Uri.parse('$baseUrl$path'),
    headers: await _authOnlyHeaders(),
  ).timeout(_timeout);
  _parseResponse(res);
}
```

- [ ] **Step 1: 프로필·구독·아카이브 메서드 추가**

```dart
// api_client.dart에 추가

// 공개 프로필 조회
static Future<Map<String, dynamic>> getUserProfile(int userId) async {
  return await _get('/users/$userId/profile');
}

// 내 프로필 수정
static Future<void> updateMyProfile(Map<String, dynamic> fields) async {
  await _patch('/users/me/profile', fields);
}

// 아카이브 목록
static Future<Map<String, dynamic>> getUserArchive(int userId, {int offset = 0, int limit = 20}) async {
  return await _get('/users/$userId/archive?offset=$offset&limit=$limit');
}

// 아카이브 업로드
static Future<Map<String, dynamic>> uploadArchiveItem({
  required String mediaUrl,
  required String mediaType,
  String? caption,
}) async {
  return await _post('/users/me/archive', {
    'media_url':  mediaUrl,
    'media_type': mediaType,
    if (caption != null) 'caption': caption,
  });
}

// 아카이브 삭제
static Future<void> deleteArchiveItem(int itemId) async {
  await _delete('/users/me/archive/$itemId');
}

// 아카이브 좋아요 토글
static Future<Map<String, dynamic>> toggleArchiveLike(int itemId) async {
  return await _post('/archive/$itemId/likes', {});
}

// 아카이브 댓글 목록
static Future<Map<String, dynamic>> getArchiveComments(int itemId) async {
  return await _get('/archive/$itemId/comments');
}

// 아카이브 댓글 작성
static Future<Map<String, dynamic>> createArchiveComment(int itemId, String content) async {
  return await _post('/archive/$itemId/comments', {'content': content});
}

// 아카이브 댓글 삭제
static Future<void> deleteArchiveComment(int itemId, int commentId) async {
  await _delete('/archive/$itemId/comments/$commentId');
}

// 개인 구독 검증
static Future<Map<String, dynamic>> verifyPersonalSubscription({
  required String transactionId,
  required String platform,
  required String receiptData,
}) async {
  return await _post('/users/me/subscription/verify', {
    'product_id':     'stagemate_personal_monthly',
    'transaction_id': transactionId,
    'platform':       platform,
    'receipt_data':   receiptData,
  });
}

// R2 퍼블릭 베이스 URL — R2 key를 표시용 URL로 변환할 때 사용
// 기존 getPresignedUrl 응답의 public_url 패턴과 일치하도록 설정
static const String r2PublicBaseUrl = String.fromEnvironment(
  'R2_PUBLIC_BASE_URL',
  defaultValue: 'https://your-r2-bucket.r2.dev',  // 실제 R2 퍼블릭 URL로 교체
);
```

> **주의**: `_get`/`_post`/`_patch`/`_delete` 헬퍼는 Step 0에서 추가한 것을 사용.

- [ ] **Step 2: Commit**

```bash
git add lib/api/api_client.dart
git commit -m "feat: add personal subscription, profile, archive API client methods"
```

---

### Task 7: profile_screen.dart + profile_card_widget.dart 신규 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/profile_screen.dart`
- Create: `C:/projects/performance_manager/lib/widgets/profile_card_widget.dart`

- [ ] **Step 1: `profile_screen.dart` 생성 — 풀 프로필 페이지**

```dart
// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _archive;
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ApiClient.getUserProfile(widget.userId);
      final archive = await ApiClient.getUserArchive(widget.userId);
      if (mounted) setState(() { _profile = profile; _archive = archive; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color? _parseHex(String? hex) {
    if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
    try { return Color(int.parse('FF${hex.substring(1)}', radix: 16)); }
    catch (_) { return null; }
  }

  Widget _buildNickname(Map<String, dynamic> profile) {
    final style    = profile['nickname_style'] as Map<String, dynamic>?;
    final nickname = profile['nickname'] ?? '알 수 없음';
    final bold     = style?['bold'] == true;

    if (style == null) {
      return Text(nickname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white));
    }

    final color1 = _parseHex(style['color'] as String?);
    final color2 = _parseHex(style['color2'] as String?);

    if (color2 != null && color1 != null) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(colors: [color1, color2]).createShader(bounds),
        child: Text(nickname, style: TextStyle(
          fontSize: 20, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: Colors.white,
        )),
      );
    }

    return Text(nickname, style: TextStyle(
      fontSize: 20, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color1 ?? Colors.white,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final profile = _profile;
    if (profile == null) return const Scaffold(body: Center(child: Text('프로필을 불러올 수 없습니다.')));

    final themeColor = _parseHex(profile['personal_theme_color'] as String?);
    final bannerUrl  = profile['personal_banner_url'] as String?;
    final isPersonal = profile['is_personal_subscriber'] == true;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: bannerUrl != null ? 200 : 80,
            pinned: true,
            backgroundColor: themeColor ?? Theme.of(context).colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: bannerUrl != null
                  // bannerUrl은 R2 key ("profiles/...") — 표시용 URL로 변환 필요
                  ? Image.network(
                      '${ApiClient.r2PublicBaseUrl}/$bannerUrl',
                      fit: BoxFit.cover,
                    )
                  : Container(color: themeColor?.withOpacity(0.3)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: themeColor?.withOpacity(0.2) ?? Colors.grey.shade200,
                      child: const Icon(Icons.person, size: 32),
                    ),
                    const SizedBox(width: 12),
                    _buildNickname(profile),
                  ]),
                  if (isPersonal && profile['bio'] != null) ...[
                    const SizedBox(height: 8),
                    Text(profile['bio'] as String, style: const TextStyle(fontSize: 13)),
                  ],
                  if (isPersonal && profile['instagram_id'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@${profile['instagram_id']}',
                      style: TextStyle(color: themeColor ?? Colors.blue, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    tabs: const [Tab(text: '아카이브'), Tab(text: '정보')],
                    labelColor: themeColor ?? Colors.purple,
                    indicatorColor: themeColor ?? Colors.purple,
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildArchiveTab(_archive, isPersonal),
                const Center(child: Text('추가 정보 준비 중')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveTab(Map<String, dynamic>? archive, bool isPersonal) {
    if (!isPersonal || archive?['locked'] == true) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('PERSONAL 구독 시 아카이브를 볼 수 있습니다', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final items = (archive?['items'] as List<dynamic>?) ?? [];
    if (items.isEmpty) return const Center(child: Text('아카이브가 비어있습니다.'));

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i] as Map<String, dynamic>;
        // media_url은 R2 key (e.g. "profiles/1/uuid/file.jpg") — 표시용 URL로 변환
        final r2Key    = item['media_url'] as String;
        final imageUrl = '${ApiClient.r2PublicBaseUrl}/$r2Key';
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(imageUrl, fit: BoxFit.cover),
            if (item['media_type'] == 'video')
              const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 32)),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: `profile_card_widget.dart` 생성 — 바텀시트 프로필 카드**

```dart
// lib/widgets/profile_card_widget.dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../screens/profile_screen.dart';

class ProfileCardWidget extends StatefulWidget {
  final int userId;
  const ProfileCardWidget({super.key, required this.userId});

  static void show(BuildContext context, int userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ProfileCardWidget(userId: userId),
    );
  }

  @override
  State<ProfileCardWidget> createState() => _ProfileCardWidgetState();
}

class _ProfileCardWidgetState extends State<ProfileCardWidget> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    ApiClient.getUserProfile(widget.userId).then((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: profile == null
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.grey.shade200,
                  child: const Icon(Icons.person, size: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  profile['nickname'] ?? '알 수 없음',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (profile['bio'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile['bio'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      // use-after-pop 방지: pop 전에 navigator 참조를 캡처
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: widget.userId),
                      ));
                    },
                    child: const Text('프로필 보기'),
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/profile_screen.dart lib/widgets/profile_card_widget.dart
git commit -m "feat: add ProfileScreen and ProfileCardWidget (bottom sheet)"
```

---

### Task 8: archive_upload_screen.dart 신규 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/archive_upload_screen.dart`

- [ ] **Step 1: `archive_upload_screen.dart` 생성**

```dart
// lib/screens/archive_upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';

class ArchiveUploadScreen extends StatefulWidget {
  const ArchiveUploadScreen({super.key});

  @override
  State<ArchiveUploadScreen> createState() => _ArchiveUploadScreenState();
}

class _ArchiveUploadScreenState extends State<ArchiveUploadScreen> {
  File?   _file;
  String? _mediaType;  // 'image' | 'video'
  final _captionCtrl = TextEditingController();
  bool _uploading = false;

  static const _maxImageBytes = 30 * 1024 * 1024;   // 30MB
  static const _maxVideoBytes = 1536 * 1024 * 1024; // 1.5GB

  Future<void> _pick(bool isVideo) async {
    final picker = ImagePicker();
    final XFile? picked = isVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file  = File(picked.path);
    final bytes = await file.length();
    final maxBytes = isVideo ? _maxVideoBytes : _maxImageBytes;
    if (bytes > maxBytes) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isVideo ? '영상 크기는 1.5GB 이하여야 합니다.' : '이미지 크기는 30MB 이하여야 합니다.'),
      ));
      return;
    }
    setState(() { _file = file; _mediaType = isVideo ? 'video' : 'image'; });
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null || _mediaType == null) return;
    setState(() => _uploading = true);

    try {
      final ext  = file.path.split('.').last.toLowerCase();
      // MIME 타입은 확장자 기반으로 결정 (하드코딩 방지)
      final mime = _mediaType == 'video'
          ? (ext == 'mov' ? 'video/quicktime' : 'video/mp4')
          : (ext == 'png' ? 'image/png' : ext == 'gif' ? 'image/gif' : 'image/jpeg');
      // 개인 아카이브 presigned URL: club_id 없음, 쿼터 없음 (PERSONAL 구독 = 무제한)
      // 기존 getPresignedUrl 시그니처: (String filename, String contentType) — 위치 인수 사용
      final presigned = await ApiClient.getPresignedUrl(
        'archive.$ext',
        mime,
      );

      // 백엔드 GET /upload/presigned 응답 필드:
      //   upload_url: R2에 PUT할 presigned URL (서명 포함)
      //   public_url: R2 public 접근 URL (미리보기용)
      //   key: R2 오브젝트 key ("profiles/{user_id}/{uuid}/{filename}")
      final uploadUrl = presigned['upload_url'] as String;
      final r2Key     = presigned['key'] as String;
      final fileBytes = await file.readAsBytes();
      await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': mime},
        body: fileBytes,
      );

      // ⚠️ media_url은 R2 key만 전달 (full URL 아님)
      // 백엔드 ArchiveItemCreateRequest.valid_r2_key가 "profiles/" 시작 여부를 검증
      await ApiClient.uploadArchiveItem(
        mediaUrl:  r2Key,    // "profiles/{user_id}/uuid/file.jpg" 형태
        mediaType: _mediaType!,
        caption:   _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('아카이브에 업로드됐습니다.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('아카이브 업로드')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('사진 선택'),
                onPressed: () => _pick(false),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('영상 선택'),
                onPressed: () => _pick(true),
              )),
            ]),
            if (_file != null) ...[
              const SizedBox(height: 12),
              Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _mediaType == 'image'
                    ? Image.file(_file!, fit: BoxFit.cover)
                    : const Center(child: Icon(Icons.videocam, size: 64, color: Colors.grey)),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _captionCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '설명 (선택사항)', border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_file != null && !_uploading) ? _upload : null,
                child: _uploading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('업로드'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/archive_upload_screen.dart
git commit -m "feat: add ArchiveUploadScreen with image/video picker and R2 upload"
```

---

### Task 9: nickname_style_screen.dart 신규 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/nickname_style_screen.dart`

- [ ] **Step 1: `nickname_style_screen.dart` 생성**

```dart
// lib/screens/nickname_style_screen.dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';

enum NicknameStyleType { solid, gradient, boldSolid }

class NicknameStyleScreen extends StatefulWidget {
  final String nickname;
  const NicknameStyleScreen({super.key, required this.nickname});

  @override
  State<NicknameStyleScreen> createState() => _NicknameStyleScreenState();
}

class _NicknameStyleScreenState extends State<NicknameStyleScreen> {
  NicknameStyleType _type = NicknameStyleType.solid;
  Color _color1 = Colors.purple;
  Color _color2 = Colors.blue;
  bool  _saving = false;

  String _toHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}'
      '${c.green.toRadixString(16).padLeft(2, '0')}'
      '${c.blue.toRadixString(16).padLeft(2, '0')}';

  Widget _buildPreview() {
    final nickname = widget.nickname;
    switch (_type) {
      case NicknameStyleType.solid:
        return Text(nickname, style: TextStyle(fontSize: 22, color: _color1));
      case NicknameStyleType.boldSolid:
        return Text(nickname, style: TextStyle(fontSize: 22, color: _color1, fontWeight: FontWeight.bold));
      case NicknameStyleType.gradient:
        return ShaderMask(
          shaderCallback: (b) => LinearGradient(colors: [_color1, _color2]).createShader(b),
          child: Text(nickname, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
        );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        'nickname_color': _toHex(_color1),
        'nickname_bold':  _type == NicknameStyleType.boldSolid,
        'nickname_color2': _type == NicknameStyleType.gradient ? _toHex(_color2) : null,
      };
      await ApiClient.updateMyProfile(fields);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임 효과가 저장됐습니다.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickColor(int which) {
    final presets = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.white, Colors.grey,
    ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('색상 $which 선택'),
        content: Wrap(
          spacing: 8, runSpacing: 8,
          children: presets.map((c) => GestureDetector(
            onTap: () {
              setState(() { if (which == 1) _color1 = c; else _color2 = c; });
              Navigator.pop(context);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('닉네임 효과')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(8)),
                child: _buildPreview(),
              ),
            ),
            const SizedBox(height: 20),
            const Text('스타일', style: TextStyle(fontWeight: FontWeight.bold)),
            SegmentedButton<NicknameStyleType>(
              segments: const [
                ButtonSegment(value: NicknameStyleType.solid,     label: Text('단색')),
                ButtonSegment(value: NicknameStyleType.boldSolid, label: Text('볼드+색상')),
                ButtonSegment(value: NicknameStyleType.gradient,  label: Text('그라데이션')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            _colorRow(1, _color1),
            if (_type == NicknameStyleType.gradient) ...[
              const SizedBox(height: 8),
              _colorRow(2, _color2),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(int which, Color color) {
    return Row(children: [
      Text('색상 $which:'),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _pickColor(which),
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(_toHex(color)),
    ]);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/nickname_style_screen.dart
git commit -m "feat: add NicknameStyleScreen with color picker and gradient preview"
```

---

### Task 10: personal_subscription_screen.dart 신규 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/personal_subscription_screen.dart`

- [ ] **Step 1: `personal_subscription_screen.dart` 생성**

```dart
// lib/screens/personal_subscription_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';   // defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../api/api_client.dart';

const _kPersonalProductId = 'stagemate_personal_monthly';

class PersonalSubscriptionScreen extends StatefulWidget {
  const PersonalSubscriptionScreen({super.key});

  @override
  State<PersonalSubscriptionScreen> createState() => _PersonalSubscriptionScreenState();
}

class _PersonalSubscriptionScreenState extends State<PersonalSubscriptionScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? _product;
  bool _loading = true;
  bool _purchasing = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;  // 스트림 구독 누수 방지

  @override
  void initState() {
    super.initState();
    // purchaseStream 구독: OS 결제 완료 시 백엔드 검증 + completePurchase 호출
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (err) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('결제 오류: $err')));
      },
    );
    _load();
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != _kPersonalProductId) continue;
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          // 백엔드 영수증 검증 + personal_plan 활성화
          final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';
          final receipt = purchase.verificationData.serverVerificationData;
          await ApiClient.verifyPersonalSubscription(
            transactionId: purchase.purchaseID ?? purchase.verificationData.localVerificationData,
            platform: platform,
            receiptData: receipt,
          );
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PERSONAL 구독이 활성화됐습니다.')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('구독 검증 실패: $e')));
        }
        // iOS는 반드시 completePurchase 호출 (영수증 pending 상태 해제)
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('결제 실패: ${purchase.error?.message}')));
      }
    }
    if (mounted) setState(() => _purchasing = false);
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();  // 스트림 구독 해제
    super.dispose();
  }

  Future<void> _load() async {
    final available = await _iap.isAvailable();
    if (!available) { if (mounted) setState(() => _loading = false); return; }
    final res = await _iap.queryProductDetails({_kPersonalProductId});
    if (mounted) setState(() {
      _product = res.productDetails.isNotEmpty ? res.productDetails.first : null;
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    final product = _product;
    if (product == null) return;
    setState(() => _purchasing = true);
    try {
      // buyNonConsumable은 구독에도 사용 (in_app_purchase ^3.x 권장 방식)
      // 실제 활성화는 _purchaseSub → _onPurchaseUpdated에서 처리
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제 처리 중입니다...')));
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    // _purchasing = false는 _onPurchaseUpdated에서 처리
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인 구독')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('PERSONAL', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              _product?.price ?? '₩2,900',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                            ),
                            const Text('/월', style: TextStyle(color: Colors.grey)),
                          ]),
                          const SizedBox(height: 16),
                          ..._features().map((f) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              const Icon(Icons.check, size: 16, color: Colors.purple),
                              const SizedBox(width: 8),
                              Expanded(child: Text(f)),
                            ]),
                          )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: (_product != null && !_purchasing) ? _purchase : null,
                      child: _purchasing
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('구독 시작하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '* 구독은 매월 자동 갱신됩니다. App Store / Google Play에서 관리할 수 있습니다.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }

  List<String> _features() => [
    '개인 프로필 페이지 (배너, 소개, 인스타 링크)',
    '개인 아카이브 (영상·사진 무제한 업로드)',
    '닉네임 컬러·그라데이션 효과',
    '개인 포인트 컬러',
  ];
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/personal_subscription_screen.dart
git commit -m "feat: add PersonalSubscriptionScreen with in_app_purchase integration"
```

---

### Task 11: feed_screen.dart — 아바타/닉네임 탭 → 프로필 카드 연결

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/feed_screen.dart`

- [ ] **Step 1: feed_screen.dart 상단에 ProfileCardWidget import 추가**

```dart
// 기존 import 목록에 추가
import '../widgets/profile_card_widget.dart';
```

- [ ] **Step 1b: feed_screen.dart에서 author_id 필드명 확인**

`GET /posts` 응답에서 실제 author_id 키 이름을 grep으로 확인:

```bash
# 기존 feed_screen.dart에서 author 관련 키 확인
grep -n "author" C:/projects/performance_manager/lib/screens/feed_screen.dart | head -30
```

응답에 `author_id`가 없고 `post_author_id` 등 다른 이름이면 Step 2~3 코드에서 키 이름을 해당 값으로 교체.
`author_id`가 응답에 없을 경우 백엔드 `GET /posts` 응답 스키마를 확인하고 필요시 추가.

- [ ] **Step 2: 게시글 author 표시 위젯을 GestureDetector로 감싸기**

기존 author 이름 렌더링을 찾아 (보통 `Text(post['author'] ?? '')` 형태):

```dart
// 기존:
// Text(post['author'] ?? '')

// 수정: (아래 코드에서 post['author'], post['author_id']의 실제 키 이름을 기존 코드에 맞게 확인)
GestureDetector(
  onTap: () {
    final authorId = post['author_id'] as int?;
    if (authorId != null) ProfileCardWidget.show(context, authorId);
  },
  child: Text(
    post['author'] ?? '',
    style: const TextStyle(fontWeight: FontWeight.w600),
  ),
),
```

- [ ] **Step 3: 댓글 author 표시에도 동일하게 적용**

```dart
GestureDetector(
  onTap: () {
    final authorId = comment['author_id'] as int?;
    if (authorId != null) ProfileCardWidget.show(context, authorId);
  },
  child: Text(comment['author'] ?? ''),
),
```

- [ ] **Step 4: 테스트 — 전체 채널 게시글 author 탭 시 바텀시트 팝업 확인**

디버그 모드에서 전체 채널 게시글 작성자 이름 탭 후 프로필 카드 바텀시트가 표시되는지 확인.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/feed_screen.dart
git commit -m "feat: tap author in feed to show profile card popup"
```

---

## Phase 2 검증 체크리스트

- [ ] `GET /users/{user_id}/profile`: 응답에 `display_name` 없음, `nickname` 있음
- [ ] `GET /users/{user_id}/profile`: 비구독자는 `bio`, `instagram_id`, `personal_banner_url` null 반환
- [ ] `PATCH /users/me/profile`: 비구독자가 닉네임 효과 설정 시 403
- [ ] `GET /users/{user_id}/archive`: 비구독자는 `locked: true`, 빈 배열
- [ ] `POST /users/me/archive`: 비구독자는 403
- [ ] `DELETE /users/me/archive/{id}`: 타인 아이템 삭제 시 403
- [ ] `DELETE /users/me/archive/{id}`: 성공 시 R2 delete 시도 (백엔드 로그 확인)
- [ ] `DELETE /archive/{id}/comments/{comment_id}`: 타인 댓글 삭제 시 403
- [ ] `POST /users/me/subscription/verify`: 중복 transaction_id 시 409
- [ ] `POST /users/me/subscription/verify`: 잘못된 product_id 시 400
- [ ] cron.py `expire` 실행 후 `personal_plan_expires_at < NOW()` 사용자 다운그레이드 확인
- [ ] Flutter: 전체 채널 게시글 author 탭 → 프로필 카드 바텀시트 팝업
- [ ] Flutter: "프로필 보기" 버튼 → ProfileScreen 이동
- [ ] Flutter: 비구독자 ProfileScreen 아카이브 탭에 잠금 UI 표시
- [ ] Flutter: NicknameStyleScreen 색상 선택 시 미리보기 실시간 반영
- [ ] Flutter: PersonalSubscriptionScreen in_app_purchase 상품 로드 확인
- [ ] Flutter: PersonalSubscriptionScreen 구독 완료 후 `verifyPersonalSubscription` 백엔드 호출 확인 (로그 확인)
- [ ] Flutter: PersonalSubscriptionScreen dispose 시 purchaseStream 구독 취소 확인 (메모리 누수 없음)
- [ ] Flutter: feed_screen.dart author_id 필드명이 실제 API 응답과 일치하는지 확인
