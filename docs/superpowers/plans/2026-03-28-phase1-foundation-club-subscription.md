# Phase 1: Foundation + Club Subscription Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DB 마이그레이션, 보안 패치, Cron 서비스, 동아리 구독 API 및 Flutter UI 구현

**Architecture:** FastAPI 백엔드에 동아리 플랜/쿼터/부스트 컬럼을 추가하고 구독 검증·프로필·스토리지 API를 신설한다. Flutter에서 2단계 온보딩, 동아리 꾸미기 화면, 구독 요금제 화면을 구현하고 `in_app_purchase`로 인앱결제를 연동한다.

**Tech Stack:** FastAPI · SQLAlchemy · PostgreSQL · slowapi · Cloudflare R2 (boto3) · Flutter · in_app_purchase ^3.2.0 · image_picker (기존)

**Spec:** `docs/superpowers/specs/2026-03-28-club-premium-subscription-design.md`

---

## Chunk 1: DB 마이그레이션 + 보안 패치

### Task 1: clubs 테이블 컬럼 추가

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py`
- Modify: `C:/projects/performance-manager/backend/main.py` (startup migration)

- [ ] **Step 1: `db_models.py`에 Club 모델 컬럼 추가**

```python
# db_models.py — Club 클래스에 추가
logo_url             = Column(String, nullable=True)
banner_url           = Column(String, nullable=True)
theme_color          = Column(String(7), nullable=True)   # "#RRGGBB"
plan                 = Column(String(20), default="free", nullable=False)
plan_expires_at      = Column(DateTime, nullable=True)
storage_used_mb      = Column(BigInteger, default=0, nullable=False)
storage_quota_extra_mb = Column(BigInteger, default=0, nullable=False)
boost_credits        = Column(Integer, default=0, nullable=False)
```

- [ ] **Step 2: posts 테이블 컬럼 추가**

```python
# db_models.py — Post 클래스에 추가
is_boosted       = Column(Boolean, default=False, nullable=False)
boost_expires_at = Column(DateTime, nullable=True)
```

- [ ] **Step 3: `main.py` startup migration에 ALTER TABLE 추가**

`run_migrations()` 함수 안의 for 루프에 아래 항목 추가:
```python
"ALTER TABLE clubs ADD COLUMN logo_url VARCHAR",
"ALTER TABLE clubs ADD COLUMN banner_url VARCHAR",
"ALTER TABLE clubs ADD COLUMN theme_color VARCHAR(7)",
"ALTER TABLE clubs ADD COLUMN plan VARCHAR(20) DEFAULT 'free'",
"ALTER TABLE clubs ADD COLUMN plan_expires_at TIMESTAMP",
"ALTER TABLE clubs ADD COLUMN storage_used_mb BIGINT DEFAULT 0",
"ALTER TABLE clubs ADD COLUMN storage_quota_extra_mb BIGINT DEFAULT 0",
"ALTER TABLE clubs ADD COLUMN boost_credits INTEGER DEFAULT 0",
"ALTER TABLE posts ADD COLUMN is_boosted BOOLEAN DEFAULT FALSE",
"ALTER TABLE posts ADD COLUMN boost_expires_at TIMESTAMP",
```

- [ ] **Step 4: 서버 재시작 후 마이그레이션 확인**

```bash
cd C:/projects/performance-manager/backend
uvicorn main:app --reload
# 로그에 오류 없이 시작되면 성공
```

- [ ] **Step 5: Commit**

```bash
git add backend/db_models.py backend/main.py
git commit -m "feat: add club plan/storage/boost columns to DB"
```

---

### Task 2: subscription_transactions + presign_requests 테이블 신설

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `db_models.py`에 SubscriptionTransaction 모델 추가**

```python
class SubscriptionTransaction(Base):
    __tablename__ = "subscription_transactions"
    id             = Column(Integer, primary_key=True, index=True)
    club_id        = Column(Integer, ForeignKey("clubs.id"), nullable=True)   # 개인 구독 시 NULL
    user_id        = Column(Integer, ForeignKey("users.id"), nullable=False)
    product_id     = Column(String, nullable=False)
    transaction_id = Column(String, unique=True, nullable=False)
    platform       = Column(String(10), nullable=False)   # "apple" | "google"
    purchased_at   = Column(DateTime, nullable=False)
    expires_at     = Column(DateTime, nullable=True)
    status         = Column(String(20), default="active", nullable=False)
    raw_payload    = Column(Text, nullable=True)
    created_at     = Column(DateTime, default=datetime.utcnow)
```

- [ ] **Step 2: `db_models.py`에 PresignRequest 모델 추가**

```python
class PresignRequest(Base):
    __tablename__ = "presign_requests"
    key          = Column(String, primary_key=True)
    club_id      = Column(Integer, nullable=True)
    user_id      = Column(Integer, ForeignKey("users.id"), nullable=False)
    file_size_mb = Column(Integer, nullable=False)
    expires_at   = Column(DateTime, nullable=False)
```

- [ ] **Step 3: `main.py` startup migration에 CREATE TABLE 추가**

```python
"""CREATE TABLE IF NOT EXISTS subscription_transactions (
    id SERIAL PRIMARY KEY,
    club_id INTEGER REFERENCES clubs(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    product_id VARCHAR NOT NULL,
    transaction_id VARCHAR UNIQUE NOT NULL,
    platform VARCHAR(10) NOT NULL,
    purchased_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active',
    raw_payload TEXT,
    created_at TIMESTAMP DEFAULT NOW()
)""",
"""CREATE TABLE IF NOT EXISTS presign_requests (
    key VARCHAR PRIMARY KEY,
    club_id INTEGER,
    user_id INTEGER NOT NULL REFERENCES users(id),
    file_size_mb INTEGER NOT NULL,
    expires_at TIMESTAMP NOT NULL
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
git commit -m "feat: add subscription_transactions and presign_requests tables"
```

---

### Task 3: 닉네임 필수화 + 실명 노출 차단

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`
- Modify: `C:/projects/performance_manager/lib/screens/login_screen.dart` (RegisterScreen)

- [ ] **Step 1: `models.py` RegisterRequest에 nickname 필드 추가**

```python
class RegisterRequest(BaseModel):
    username:     str = Field(..., min_length=3, max_length=20)
    display_name: str = Field(..., min_length=1, max_length=30)
    nickname:     str = Field(..., min_length=2, max_length=20,
                              description="전체 커뮤니티 표시명, 필수")
    email:        EmailStr
    password:     str = Field(..., min_length=8, max_length=100)

    @field_validator('nickname')
    @classmethod
    def nickname_valid(cls, v: str) -> str:
        v = v.strip()
        if re.search(r'[<>"\'&]', v):
            raise ValueError('닉네임에 특수문자(<, >, ", \', &)를 사용할 수 없습니다.')
        return v

    # 기존 username_alphanumeric, display_name_no_html 유지
```

- [ ] **Step 2: `main.py` register 엔드포인트에 nickname 저장 추가**

```python
# 닉네임 중복 확인 추가 (display_name 중복 확인 아래에)
if db.query(db_models.User).filter(
    db_models.User.nickname == req.nickname
).first():
    raise HTTPException(status_code=400, detail="이미 사용 중인 닉네임입니다.")

user = db_models.User(
    username=req.username,
    display_name=req.display_name,
    nickname=req.nickname,       # ← 추가
    email=req.email,
    hashed_password=hash_password(req.password),
)
```

- [ ] **Step 3: 전체 채널 게시글/댓글 응답에서 실명 폴백 제거**

`GET /posts?is_global=true` 응답의 author 필드:
```python
# 기존 코드 (위험):
display_author = p.post_author_name or (author.display_name if author else "탈퇴한 사용자")

# 수정:
if p.is_global:
    # 전체 채널: post_author_name(닉네임 or "익명")만 사용, display_name 폴백 금지
    display_author = p.post_author_name or "알 수 없음"
else:
    # 동아리 내부: 실명 사용
    display_author = p.post_author_name or (author.display_name if author else "탈퇴한 사용자")
```

`GET /posts/{post_id}/comments` 응답의 author 필드:
```python
# comment author 조회 후:
post = db.query(db_models.Post).filter(db_models.Post.id == post_id).first()
for c in comments:
    author = db.query(db_models.User).filter(db_models.User.id == c.author_id).first()
    if post and post.is_global:
        author_name = (author.nickname if author and author.nickname else "알 수 없음")
    else:
        author_name = (author.display_name if author else "탈퇴한 사용자")
    result.append({
        ...
        "author": author_name,
        ...
    })
```

- [ ] **Step 4: Flutter RegisterScreen에 nickname 입력 필드 추가**

`lib/screens/login_screen.dart` (RegisterScreen 위젯) 내:
- `_nicknameCtrl` TextEditingController 추가
- `display_name` 입력란 아래에 nickname 입력란 추가
- `ApiClient.register()` 호출 시 `nickname` 파라미터 전달

`lib/api/api_client.dart` `register()` 메서드에 `nickname` 파라미터 추가:
```dart
static Future<Map<String, dynamic>> register({
  required String username,
  required String displayName,
  required String nickname,   // 추가
  required String email,
  required String password,
}) async {
  ...
  body: jsonEncode({
    'username': username,
    'display_name': displayName,
    'nickname': nickname,      // 추가
    'email': email,
    'password': password,
  }),
  ...
}
```

- [ ] **Step 5: 테스트 — 회원가입 시 nickname 없으면 400 확인**

```bash
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test1","display_name":"테스트","email":"t@t.com","password":"Test1234"}'
# 기대: 422 (nickname 필드 누락)
```

- [ ] **Step 6: Commit**

```bash
git add backend/models.py backend/main.py lib/screens/login_screen.dart lib/api/api_client.dart
git commit -m "feat: make nickname required on register, block display_name in global channel"
```

---

### Task 4: Cron 서비스 구성

**Files:**
- Create: `C:/projects/performance-manager/backend/cron.py`
- Create: `C:/projects/performance-manager/backend/railway.toml`

- [ ] **Step 1: `cron.py` 작성**

```python
# cron.py
import sys
from datetime import datetime
from database import engine
from sqlalchemy.orm import Session
from sqlalchemy import text

def expire():
    """만료된 동아리/개인 구독 다운그레이드"""
    with Session(engine) as db:
        now = datetime.utcnow()
        db.execute(text("""
            UPDATE clubs
            SET plan = 'free', plan_expires_at = NULL, boost_credits = 0
            WHERE plan != 'free' AND plan_expires_at < :now
        """), {"now": now})
        # ⚠️ Phase 3 only — users.personal_plan / personal_plan_expires_at 컬럼은
        # Phase 2 마이그레이션 완료 후 아래 블록 주석 해제
        # db.execute(text("""
        #     UPDATE users
        #     SET personal_plan = 'free', personal_plan_expires_at = NULL
        #     WHERE personal_plan != 'free' AND personal_plan_expires_at < :now
        # """), {"now": now})
        db.commit()
    print(f"[cron:expire] done at {now}")

def reset_boosts():
    """매월 1일 부스트 크레딧 초기화"""
    with Session(engine) as db:
        db.execute(text("""
            UPDATE clubs SET boost_credits = CASE
                WHEN plan = 'standard' THEN 1
                WHEN plan = 'pro'      THEN 3
                ELSE 0
            END
        """))
        db.commit()
    print(f"[cron:reset_boosts] done at {datetime.utcnow()}")

def expire_boosts():
    """만료된 홍보 부스트 해제 (30분마다)"""
    with Session(engine) as db:
        db.execute(text("""
            UPDATE posts
            SET is_boosted = FALSE, boost_expires_at = NULL
            WHERE is_boosted = TRUE AND boost_expires_at < :now
        """), {"now": datetime.utcnow()})
        db.commit()
    print(f"[cron:expire_boosts] done at {datetime.utcnow()}")

def cleanup_presign():
    """만료된 presign_requests 행 삭제 (10분마다)"""
    with Session(engine) as db:
        db.execute(text(
            "DELETE FROM presign_requests WHERE expires_at < :now"
        ), {"now": datetime.utcnow()})
        db.commit()
    print(f"[cron:cleanup_presign] done at {datetime.utcnow()}")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    match cmd:
        case "expire":         expire()
        case "reset_boosts":   reset_boosts()
        case "expire_boosts":  expire_boosts()
        case "cleanup_presign": cleanup_presign()
        case _:
            print(f"Unknown command: {cmd}")
            sys.exit(1)
```

- [ ] **Step 2: `railway.toml` 작성**

```toml
[build]
builder = "DOCKERFILE"
dockerfilePath = "Dockerfile"

[[services]]
name = "web"
startCommand = "uvicorn main:app --host 0.0.0.0 --port $PORT"

[[services]]
name = "cron"
startCommand = "echo 'cron service ready'"

[[services.cronJobs]]
schedule = "0 2 * * *"
command  = "python cron.py expire"

[[services.cronJobs]]
schedule = "0 0 1 * *"
command  = "python cron.py reset_boosts"

[[services.cronJobs]]
schedule = "*/30 * * * *"
command  = "python cron.py expire_boosts"

[[services.cronJobs]]
schedule = "*/10 * * * *"
command  = "python cron.py cleanup_presign"
```

- [ ] **Step 3: 로컬 cron 테스트**

```bash
cd C:/projects/performance-manager/backend
python cron.py expire
python cron.py reset_boosts
python cron.py expire_boosts
python cron.py cleanup_presign
# 각각 "done at ..." 출력되면 성공
```

- [ ] **Step 4: Commit**

```bash
git add backend/cron.py backend/railway.toml
git commit -m "feat: add cron.py for subscription expiry, boost reset, presign cleanup"
```

---

## Chunk 2: 동아리 구독 백엔드 API

### Task 5: 동아리 프로필 API

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 ClubProfileUpdateRequest 추가**

```python
class ClubProfileUpdateRequest(BaseModel):
    logo_url:    str | None = None   # 이미 R2에 업로드된 URL
    banner_url:  str | None = None
    theme_color: str | None = None   # "#RRGGBB" 형식

    @field_validator('theme_color')
    @classmethod
    def valid_hex(cls, v):
        if v and not re.match(r'^#[0-9A-Fa-f]{6}$', v):
            raise ValueError('올바른 hex 색상 코드가 아닙니다 (예: #6750A4)')
        return v

    @field_validator('logo_url', 'banner_url')
    @classmethod
    def valid_url(cls, v):
        if v:
            from urllib.parse import urlparse
            parsed = urlparse(v)
            if parsed.scheme not in ('http', 'https') or not parsed.netloc:
                raise ValueError('올바르지 않은 URL입니다.')
        return v
```

- [ ] **Step 2: `main.py`에 `GET /clubs/{club_id}/profile` 추가**

```python
@app.get("/clubs/{club_id}/profile")
def get_club_profile(
    club_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """동아리 프로필 조회 — 인증 필요, 멤버십 무관"""
    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    # 플랜별 쿼터
    quota = {"free": 10240, "standard": 30720, "pro": 102400}.get(club.plan or "free", 10240)
    return {
        "club_id":            club.id,
        "name":               club.name,
        "plan":               club.plan or "free",
        "logo_url":           club.logo_url or "",
        "banner_url":         club.banner_url or "",
        "theme_color":        club.theme_color or "",
        "has_badge":          club.plan in ("standard", "pro"),
        "boost_credits_remaining": club.boost_credits or 0,
        "storage_used_mb":    club.storage_used_mb or 0,
        "storage_quota_mb":   quota + (club.storage_quota_extra_mb or 0),
    }
```

- [ ] **Step 3: `main.py`에 `PATCH /clubs/{club_id}/profile` 추가**

```python
@app.patch("/clubs/{club_id}/profile")
@limiter.limit("10/minute")
def update_club_profile(
    request: Request,
    club_id: int,
    req: ClubProfileUpdateRequest,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """동아리 프로필 수정 — super_admin만 가능"""
    me = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id,
        db_models.ClubMember.user_id == current_user.id,
    ).first()
    if not me or me.role != "super_admin":
        raise HTTPException(status_code=403, detail="회장만 수정할 수 있습니다.")

    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")

    # 로고는 무료 포함 전체 가능, 배너/컬러는 STANDARD+ 필요
    if (req.banner_url is not None or req.theme_color is not None):
        if club.plan not in ("standard", "pro"):
            raise HTTPException(status_code=403, detail="배너와 테마 컬러는 STANDARD 이상 구독이 필요합니다.")

    if req.logo_url   is not None: club.logo_url   = req.logo_url or None
    if req.banner_url is not None: club.banner_url = req.banner_url or None
    if req.theme_color is not None: club.theme_color = req.theme_color or None
    db.commit()
    return {"message": "동아리 프로필이 업데이트됐습니다."}
```

- [ ] **Step 4: 테스트**

```bash
# 1. 프로필 조회 (인증 필요)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/clubs/1/profile
# 기대: logo_url, plan 등 포함한 JSON

# 2. super_admin이 아닌 사용자가 PATCH 시도
curl -X PATCH -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"theme_color":"#FF0000"}' \
  http://localhost:8000/clubs/1/profile
# 기대: 403

# 3. 무료 플랜에서 배너 설정 시도
curl -X PATCH -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"banner_url":"https://example.com/banner.jpg"}' \
  http://localhost:8000/clubs/1/profile
# 기대: 403 (구독 필요)
```

- [ ] **Step 5: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add GET/PATCH /clubs/{id}/profile with plan-based permission"
```

---

### Task 6: 저장공간 쿼터 + presigned URL 개선

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `GET /upload/presigned`에 `club_id`, `file_size_mb` 파라미터 추가 및 쿼터 체크**

기존 `get_presigned_url` 함수 시그니처 변경:
```python
@app.get("/upload/presigned")
@limiter.limit("30/minute")
def get_presigned_url(
    request:      Request,
    filename:     str,
    content_type: str = "image/jpeg",
    club_id:      int | None = None,     # 동아리 업로드 시 필수
    file_size_mb: int = 0,               # 클라이언트가 보고하는 파일 크기 (MB)
    member: db_models.ClubMember = Depends(require_any_member),
    db: Session = Depends(get_db),
):
```

쿼터 체크 로직 (ALLOWED_CONTENT_TYPES 검사 후 추가):
```python
    # 쿼터 체크 (동아리 업로드인 경우)
    if club_id:
        club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
        if not club:
            raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
        if club.id != member.club_id:
            raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")
        quota_mb = {"free": 10240, "standard": 30720, "pro": 102400}.get(club.plan or "free", 10240)
        quota_mb += (club.storage_quota_extra_mb or 0)
        if (club.storage_used_mb or 0) + file_size_mb > quota_mb:
            raise HTTPException(status_code=413, detail="저장공간이 부족합니다. 구독을 업그레이드하거나 파일을 삭제해주세요.")
```

R2 경로 변경 (`key = ...` 부분):
```python
    if club_id:
        key = f"clubs/{club_id}/{uuid.uuid4()}/{safe_name}"
    else:
        key = f"posts/{uuid.uuid4()}/{safe_name}"
```

presign_requests 테이블에 기록 (presigned URL 반환 직전):
```python
    from datetime import timedelta
    pr = db_models.PresignRequest(
        key=key,
        club_id=club_id,
        user_id=member.user_id,
        file_size_mb=file_size_mb,
        expires_at=datetime.utcnow() + timedelta(minutes=5),
    )
    db.add(pr)
    db.commit()
```

- [ ] **Step 2: `POST /clubs/{club_id}/storage/report` 엔드포인트 추가**

```python
@app.post("/clubs/{club_id}/storage/report")
@limiter.limit("30/minute")
def report_storage(
    request: Request,
    club_id: int,
    body: dict,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    """업로드 완료 후 사용량 보고 — key로 presign_requests 검증"""
    key          = body.get("key", "")
    reported_mb  = body.get("added_mb", 0)

    # presign_requests에서 key 검증
    pr = db.query(db_models.PresignRequest).filter(
        db_models.PresignRequest.key == key,
        db_models.PresignRequest.user_id == member.user_id,
        db_models.PresignRequest.expires_at > datetime.utcnow(),
    ).first()
    if not pr:
        raise HTTPException(status_code=400, detail="유효하지 않은 업로드 요청입니다.")
    # IDOR 방어: presign_request가 현재 요청한 club_id의 것인지 확인
    if pr.club_id != club_id:
        raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")
    if abs(reported_mb - pr.file_size_mb) > 1:   # 1MB 오차 허용
        raise HTTPException(status_code=400, detail="파일 크기가 일치하지 않습니다.")

    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    club.storage_used_mb = (club.storage_used_mb or 0) + pr.file_size_mb

    # 사용한 presign_request 즉시 삭제 (재사용 방지)
    db.delete(pr)
    db.commit()
    return {"message": "사용량이 업데이트됐습니다.", "storage_used_mb": club.storage_used_mb}
```

- [ ] **Step 3: 테스트 — 쿼터 초과 시 413 확인**

```bash
# 무료 동아리에서 11000MB 업로드 시도 (10240MB 초과)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/upload/presigned?filename=test.jpg&content_type=image/jpeg&club_id=1&file_size_mb=11000"
# 기대: 413 저장공간 부족
```

- [ ] **Step 4: Commit**

```bash
git add backend/main.py
git commit -m "feat: add storage quota check and presign_requests validation"
```

---

### Task 7: 동아리 구독 검증 API + 웹훅

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 구독 검증 요청 모델 추가**

```python
class SubscriptionVerifyRequest(BaseModel):
    product_id:     str   # "stagemate_standard_monthly" 등
    transaction_id: str
    platform:       Literal["apple", "google"]
    receipt_data:   str   # base64 영수증 (Apple) 또는 purchase_token (Google)
    # ⚠️ expires_at은 클라이언트가 전달하지 않음 — 서버에서 purchased_at + 31일로 계산
    # 실제 영수증 검증 구현 후에는 Apple/Google API 응답의 expiresDate를 사용
```

- [ ] **Step 2: 플랜 매핑 헬퍼 추가**

`main.py` 상단에:
```python
PLAN_MAP = {
    "stagemate_standard_monthly": "standard",
    "stagemate_standard_early":   "standard",
    "stagemate_pro_monthly":      "pro",
    "stagemate_pro_early":        "pro",
    "stagemate_personal_monthly": "personal",  # Phase 2에서 사용
}
BOOST_CREDITS_MAP = {"standard": 1, "pro": 3, "free": 0}
```

- [ ] **Step 3: `POST /clubs/{club_id}/subscription/verify` 추가**

```python
@app.post("/clubs/{club_id}/subscription/verify")
@limiter.limit("5/minute")
def verify_club_subscription(
    request:  Request,
    club_id:  int,
    req:      SubscriptionVerifyRequest,
    db:       Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """동아리 인앱결제 영수증 검증 후 플랜 업데이트 (super_admin만)"""
    me = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id,
        db_models.ClubMember.user_id == current_user.id,
    ).first()
    if not me or me.role != "super_admin":
        raise HTTPException(status_code=403, detail="회장만 구독을 변경할 수 있습니다.")

    # 중복 transaction_id 방지
    dup = db.query(db_models.SubscriptionTransaction).filter(
        db_models.SubscriptionTransaction.transaction_id == req.transaction_id
    ).first()
    if dup:
        raise HTTPException(status_code=409, detail="이미 처리된 영수증입니다.")

    plan = PLAN_MAP.get(req.product_id)
    if not plan or plan == "personal":
        raise HTTPException(status_code=400, detail="올바르지 않은 동아리 구독 상품입니다.")

    # TODO: 실제 Apple/Google 영수증 검증 (프로덕션 배포 전 구현)
    # Apple: App Store Server API V2 JWS 검증 (signedTransactionInfo의 expiresDate 파싱)
    # Google: Google Play Developer API purchases.subscriptions.get
    # ⚠️ 현재는 영수증 형식만 확인 (개발/테스트용) — 프로덕션 전 실제 검증 필수
    if not req.receipt_data:
        raise HTTPException(status_code=400, detail="영수증 데이터가 없습니다.")

    # expires_at은 클라이언트를 신뢰하지 않고 서버에서 계산
    # 실제 검증 구현 후에는 Apple/Google 응답의 실제 만료일로 대체
    purchased_at = datetime.utcnow()
    expires_at = purchased_at + timedelta(days=31)

    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    club.plan = plan
    club.plan_expires_at = expires_at
    club.boost_credits = BOOST_CREDITS_MAP.get(plan, 0)

    txn = db_models.SubscriptionTransaction(
        club_id=club_id,
        user_id=current_user.id,
        product_id=req.product_id,
        transaction_id=req.transaction_id,
        platform=req.platform,
        purchased_at=purchased_at,
        expires_at=expires_at,
        status="active",
        raw_payload=req.receipt_data[:500],
    )
    db.add(txn)
    db.commit()
    return {"message": f"'{plan}' 플랜이 활성화됐습니다.", "plan": plan, "expires_at": expires_at.isoformat()}
```

- [ ] **Step 4: `GET /clubs/{club_id}/subscription` 추가**

```python
@app.get("/clubs/{club_id}/subscription")
def get_club_subscription(
    club_id: int,
    db: Session = Depends(get_db),
    current_user: db_models.User = Depends(get_current_user),
):
    """구독 상태 조회 — super_admin만"""
    me = db.query(db_models.ClubMember).filter(
        db_models.ClubMember.club_id == club_id,
        db_models.ClubMember.user_id == current_user.id,
    ).first()
    if not me or me.role != "super_admin":
        raise HTTPException(status_code=403, detail="회장만 조회할 수 있습니다.")

    club = db.query(db_models.Club).filter(db_models.Club.id == club_id).first()
    if not club:
        raise HTTPException(status_code=404, detail="동아리를 찾을 수 없습니다.")
    quota_mb = {"free": 10240, "standard": 30720, "pro": 102400}.get(club.plan or "free", 10240)
    quota_mb += (club.storage_quota_extra_mb or 0)
    return {
        "plan":               club.plan or "free",
        "plan_expires_at":    club.plan_expires_at.isoformat() if club.plan_expires_at else None,
        "storage_used_mb":    club.storage_used_mb or 0,
        "storage_quota_mb":   quota_mb,
        "boost_credits":      club.boost_credits or 0,
    }
```

- [ ] **Step 5: Apple/Google 웹훅 엔드포인트 추가**

`main.py` 상단 환경변수 섹션에 추가:
```python
# 웹훅 서명 검증 플래그 — Railway 환경변수로 설정
# ⚠️ 서명 검증 구현 전까지 "false"로 유지 (가짜 페이로드로 구독 조작 방지)
WEBHOOK_VERIFICATION_ENABLED = os.getenv("WEBHOOK_VERIFICATION_ENABLED", "false") == "true"
```

```python
@app.post("/webhooks/apple")
async def apple_webhook(request: Request, db: Session = Depends(get_db)):
    """Apple App Store Server Notifications V2"""
    # ⚠️ 서명 검증 미구현 시 DB 쓰기 차단 — 미검증 웹훅으로 구독 조작 방지
    if not WEBHOOK_VERIFICATION_ENABLED:
        logger.warning("Apple webhook received but WEBHOOK_VERIFICATION_ENABLED=false, skipping.")
        return {"status": "ok"}
    body = await request.body()
    # TODO: Apple JWS 서명 검증 (python-jose + Apple 루트 인증서)
    try:
        import json, base64
        payload = json.loads(body)
        signed_payload = payload.get("signedPayload", "")
        # JWS payload 파싱 (헤더.페이로드.서명)
        parts = signed_payload.split(".")
        if len(parts) >= 2:
            padded = parts[1] + "=" * (-len(parts[1]) % 4)
            data = json.loads(base64.urlsafe_b64decode(padded))
            notification_type = data.get("notificationType", "")
            product_id = data.get("data", {}).get("productId", "")
            transaction_id = data.get("data", {}).get("signedTransactionInfo", "")[:50]

            txn = db.query(db_models.SubscriptionTransaction).filter(
                db_models.SubscriptionTransaction.transaction_id == transaction_id
            ).first()
            if txn and notification_type in ("DID_RENEW", "SUBSCRIBED"):
                # 갱신: expires_at 연장
                _extend_subscription(txn, db)
            elif txn and notification_type in ("DID_FAIL_TO_RENEW", "EXPIRED", "REFUND"):
                _cancel_subscription(txn, db)
    except Exception as e:
        logger.error(f"Apple webhook error: {e}")
    return {"status": "ok"}

@app.post("/webhooks/google")
async def google_webhook(request: Request, db: Session = Depends(get_db)):
    """Google Play Real-time Developer Notifications"""
    if not WEBHOOK_VERIFICATION_ENABLED:
        logger.warning("Google webhook received but WEBHOOK_VERIFICATION_ENABLED=false, skipping.")
        return {"status": "ok"}
    body = await request.body()
    # TODO: Google Pub/Sub 서명 검증
    try:
        import json, base64
        payload = json.loads(body)
        msg_data = base64.b64decode(payload.get("message", {}).get("data", "")).decode()
        data = json.loads(msg_data)
        notification_type = data.get("subscriptionNotification", {}).get("notificationType", 0)
        purchase_token    = data.get("subscriptionNotification", {}).get("purchaseToken", "")
        txn = db.query(db_models.SubscriptionTransaction).filter(
            db_models.SubscriptionTransaction.transaction_id == purchase_token[:50]
        ).first()
        if txn:
            if notification_type in (4, 2):  # PURCHASED, RENEWED
                _extend_subscription(txn, db)
            elif notification_type in (3, 13):  # CANCELED, EXPIRED
                _cancel_subscription(txn, db)
    except Exception as e:
        logger.error(f"Google webhook error: {e}")
    return {"status": "ok"}

def _extend_subscription(txn: db_models.SubscriptionTransaction, db: Session):
    from datetime import timedelta
    if txn.club_id:
        club = db.query(db_models.Club).filter(db_models.Club.id == txn.club_id).first()
        if club:
            # ⚠️ +31일은 근사값 — 28/30일 월에서 드리프트 발생
            # 서명 검증 구현 후 Apple signedTransactionInfo.expiresDate,
            # Google subscriptionNotification.expiryTimeMillis로 대체 필요
            club.plan_expires_at = (club.plan_expires_at or datetime.utcnow()) + timedelta(days=31)
            db.commit()

def _cancel_subscription(txn: db_models.SubscriptionTransaction, db: Session):
    if txn.club_id:
        club = db.query(db_models.Club).filter(db_models.Club.id == txn.club_id).first()
        if club:
            club.plan = "free"
            club.plan_expires_at = None
            club.boost_credits = 0
    txn.status = "cancelled"
    db.commit()
```

- [ ] **Step 6: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add club subscription verify API and Apple/Google webhook handlers"
```

---

### Task 8: 홍보 부스트 API

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py`
- Modify: `C:/projects/performance-manager/backend/main.py`

- [ ] **Step 1: `models.py`에 BoostRequest 추가**

```python
class BoostRequest(BaseModel):
    pass  # 본문 없음, 인증 + club membership으로 충분
```

- [ ] **Step 2: `POST /posts/{post_id}/boost` 추가**

```python
@app.post("/posts/{post_id}/boost")
@limiter.limit("10/minute")
def boost_post(
    request: Request,
    post_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_any_member),
):
    """게시글 홍보 부스트 — 크레딧 차감, 24시간 상단 고정"""
    # super_admin만 부스트 가능
    if member.role != "super_admin":
        raise HTTPException(status_code=403, detail="동아리장만 홍보 부스트를 사용할 수 있습니다.")

    post = db.query(db_models.Post).filter(db_models.Post.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    # 클럽 경계 검증: 요청자의 동아리 게시글만 부스트 가능 (IDOR 방어)
    if post.club_id != member.club_id:
        raise HTTPException(status_code=403, detail="해당 동아리의 게시글이 아닙니다.")
    if not post.is_global:
        raise HTTPException(status_code=400, detail="전체 채널 게시글만 홍보 부스트할 수 있습니다.")
    if post.is_boosted:
        raise HTTPException(status_code=409, detail="이미 부스트 중인 게시글입니다.")

    # 크레딧 확인 (with_for_update로 동시 부스트 레이스 컨디션 방어)
    club = db.query(db_models.Club).filter(
        db_models.Club.id == member.club_id
    ).with_for_update().first()
    if not club or (club.boost_credits or 0) <= 0:
        raise HTTPException(status_code=402, detail="홍보 부스트 크레딧이 없습니다. STANDARD 이상 구독이 필요합니다.")

    from datetime import timedelta
    post.is_boosted = True
    post.boost_expires_at = datetime.utcnow() + timedelta(hours=24)
    club.boost_credits -= 1
    db.commit()
    return {"message": "홍보 부스트가 적용됐습니다. 24시간 동안 상단에 노출됩니다.", "credits_remaining": club.boost_credits}
```

- [ ] **Step 3: `GET /posts` 응답 정렬 수정 — 부스트 게시글 상단**

```python
# 기존: .order_by(db_models.Post.created_at.desc())
# 수정: 부스트 먼저, 이후 최신순
from sqlalchemy import desc, nulls_last
posts = query.order_by(
    desc(db_models.Post.is_boosted),
    nulls_last(desc(db_models.Post.boost_expires_at)),
    desc(db_models.Post.created_at),
).offset(offset).limit(limit).all()
```

응답에 `is_boosted` 필드 추가:
```python
result.append({
    ...
    "is_boosted": p.is_boosted or False,
    ...
})
```

- [ ] **Step 4: 테스트**

```bash
# 크레딧 없는 동아리에서 부스트 시도
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "X-Club-Id: 1" \
  http://localhost:8000/posts/1/boost
# 기대: 403 크레딧 없음
```

- [ ] **Step 5: Commit**

```bash
git add backend/models.py backend/main.py
git commit -m "feat: add post boost API with credit deduction and sorted GET /posts"
```

---

## Chunk 3: Flutter — 온보딩 + 동아리 꾸미기

### Task 9: ApiClient 신규 메서드

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`

- [ ] **Step 1: 동아리 프로필 관련 메서드 추가**

```dart
// 동아리 프로필 조회
static Future<Map<String, dynamic>> getClubProfile(int clubId) async {
  return await _get('/clubs/$clubId/profile');
}

// 동아리 프로필 수정 (logoUrl, bannerUrl, themeColor 중 비null만 전송)
static Future<void> updateClubProfile(int clubId, {
  String? logoUrl,
  String? bannerUrl,
  String? themeColor,
}) async {
  final body = <String, dynamic>{};
  if (logoUrl   != null) body['logo_url']    = logoUrl;
  if (bannerUrl != null) body['banner_url']  = bannerUrl;
  if (themeColor != null) body['theme_color'] = themeColor;
  await _patch('/clubs/$clubId/profile', body);
}

// 구독 상태 조회
static Future<Map<String, dynamic>> getClubSubscription(int clubId) async {
  return await _get('/clubs/$clubId/subscription');
}

// 구독 검증
// ⚠️ expiresAt 파라미터 없음 — 서버에서 purchased_at + 31일로 계산
static Future<Map<String, dynamic>> verifyClubSubscription(
  int clubId, {
  required String productId,
  required String transactionId,
  required String platform,
  required String receiptData,
}) async {
  return await _post('/clubs/$clubId/subscription/verify', {
    'product_id':     productId,
    'transaction_id': transactionId,
    'platform':       platform,
    'receipt_data':   receiptData,
  });
}

// 저장량 보고
static Future<void> reportStorage(int clubId, {
  required String key,
  required int addedMb,
}) async {
  await _post('/clubs/$clubId/storage/report', {
    'key': key,
    'added_mb': addedMb,
  });
}

// 게시글 부스트
static Future<Map<String, dynamic>> boostPost(int postId) async {
  return await _post('/posts/$postId/boost', {});
}
```

- [ ] **Step 2: presigned URL 메서드에 clubId, fileSizeMb 파라미터 추가**

```dart
static Future<Map<String, dynamic>> getPresignedUrl(
  String filename,
  String contentType, {
  int? clubId,
  int fileSizeMb = 0,
}) async {
  var uri = '$baseUrl/upload/presigned?filename=${Uri.encodeComponent(filename)}&content_type=${Uri.encodeComponent(contentType)}';
  if (clubId != null) uri += '&club_id=$clubId';
  if (fileSizeMb > 0) uri += '&file_size_mb=$fileSizeMb';
  return await _getUrl(uri);
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/api/api_client.dart
git commit -m "feat: add club profile/subscription/boost API client methods"
```

---

### Task 10: 2단계 온보딩 (동아리 생성)

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/club_onboarding_screen.dart`

- [ ] **Step 1: 상태 변수 추가**

```dart
int _step = 1;                    // 1 또는 2
XFile? _selectedLogo;
bool _isCreating = false;
String? _createdClubId;
String? _createdClubName;
String? _inviteCode;
```

- [ ] **Step 2: Step 1 화면 위젯 구현 (동아리 이름)**

```dart
Widget _buildStep1() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 스텝 인디케이터
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _stepDot(active: true),
        const SizedBox(width: 6),
        _stepDot(active: false),
      ]),
      const SizedBox(height: 32),
      // 추상 SVG 아이콘 (원 3개 겹침)
      Center(child: SizedBox(
        width: 64, height: 64,
        child: CustomPaint(painter: _GroupIconPainter()),
      )),
      const SizedBox(height: 20),
      const Text('동아리 이름을 정해주세요',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text('나중에 변경할 수 없어요',
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: '동아리 이름',
          hintText: '예) 댄스동아리 리듬',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _nameCtrl.text.trim().isEmpty ? null : () => setState(() => _step = 2),
        child: const Text('다음'),
      ),
    ],
  );
}
```

- [ ] **Step 3: Step 2 화면 위젯 구현 (동아리 사진)**

```dart
Widget _buildStep2() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _stepDot(active: true),
        const SizedBox(width: 6),
        _stepDot(active: true),
      ]),
      const SizedBox(height: 32),
      // 원형 사진 업로드 영역
      Center(
        child: GestureDetector(
          onTap: _pickLogo,
          child: CircleAvatar(
            radius: 44,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: _selectedLogo != null
                ? FileImage(File(_selectedLogo!.path)) : null,
            child: _selectedLogo == null
                ? CustomPaint(
                    size: const Size(36, 36),
                    painter: _CameraIconPainter(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : null,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('사진 추가',
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      Text('나중에 설정해도 돼요',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: _isCreating ? null : _createClub,
        child: _isCreating
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('동아리 만들기'),
      ),
      TextButton(
        onPressed: _isCreating ? null : _createClub,
        child: const Text('건너뛰기', style: TextStyle(color: Colors.grey)),
      ),
    ],
  );
}
```

- [ ] **Step 4: CustomPainter 아이콘 구현**

```dart
// 원 3개 겹침 (그룹 표현)
class _GroupIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final c = size.width / 2;
    paint.color = const Color(0xFF9575CD).withOpacity(0.7);
    canvas.drawCircle(Offset(c - 10, c - 4), 14, paint);
    paint.color = const Color(0xFF7E57C2).withOpacity(0.7);
    canvas.drawCircle(Offset(c + 10, c - 4), 14, paint);
    paint.color = const Color(0xFF6750A4).withOpacity(0.85);
    canvas.drawCircle(Offset(c, c + 8), 14, paint);
  }
  @override bool shouldRepaint(_) => false;
}

// 추상 카메라 (렌즈 구조)
class _CameraIconPainter extends CustomPainter {
  final Color color;
  const _CameraIconPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round;
    final fill   = Paint()..color = color.withOpacity(0.25)..style = PaintingStyle.fill;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.3, size.width, size.height * 0.65),
      const Radius.circular(6),
    );
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.63), size.width * 0.22, stroke);
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.63), size.width * 0.1,
        Paint()..color = color.withOpacity(0.4));
    final finder = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.33, 0, size.width * 0.22, size.height * 0.28),
      const Radius.circular(4),
    );
    canvas.drawRRect(finder, Paint()..color = color.withOpacity(0.5));
  }
  @override bool shouldRepaint(_) => false;
}
```

- [ ] **Step 5: `_createClub()` 메서드 — 동아리 생성 + 로고 업로드**

```dart
Future<void> _createClub() async {
  setState(() => _isCreating = true);
  try {
    final result = await ApiClient.createClub(_nameCtrl.text.trim());
    final clubId = result['club_id'] as int;

    // 로고 선택된 경우 R2 업로드
    if (_selectedLogo != null) {
      final file = File(_selectedLogo!.path);
      final fileSizeMb = (await file.length()) ~/ (1024 * 1024) + 1;
      final ext = _selectedLogo!.name.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final presigned = await ApiClient.getPresignedUrl(
        'logo$ext', ext == '.png' ? 'image/png' : 'image/jpeg',
        clubId: clubId, fileSizeMb: fileSizeMb,
      );
      final uploadUrl = presigned['upload_url'] as String;
      final publicUrl = presigned['public_url'] as String;
      final key       = presigned['key'] as String;
      final bytes = await file.readAsBytes();
      final ok = await _uploadFile(uploadUrl, bytes, ext == '.png' ? 'image/png' : 'image/jpeg');
      if (ok) {
        await ApiClient.updateClubProfile(clubId, logoUrl: publicUrl);
        await ApiClient.reportStorage(clubId, key: key, addedMb: fileSizeMb);
      }
    }

    setState(() {
      _step = 3;  // 완료 화면
      _createdClubId   = clubId.toString();
      _createdClubName = result['club_name'] as String;
      _inviteCode      = result['invite_code'] as String;
    });
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(e))),
    );
  } finally {
    setState(() => _isCreating = false);
  }
}
```

- [ ] **Step 6: 완료 화면 구현 (방사형 SVG + 초대코드)**

```dart
Widget _buildComplete() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(child: SizedBox(
        width: 72, height: 72,
        child: CustomPaint(painter: _StarburstPainter(
          color: Theme.of(context).colorScheme.primary,
        )),
      )),
      const SizedBox(height: 16),
      Text(_createdClubName ?? '',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text('동아리가 만들어졌어요',
        style: TextStyle(color: Colors.grey[600]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text('초대코드', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(_inviteCode ?? '',
            style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text('멤버에게 공유하세요', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: const Text('시작하기'),
      ),
    ],
  );
}
```

- [ ] **Step 7: build() 메서드에서 step 분기**

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(_step == 3 ? '완료' : '동아리 만들기 $_step/2'),
      automaticallyImplyLeading: _step == 1,
      leading: _step == 2 ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => _step = 1),
      ) : null,
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: _step == 1 ? _buildStep1()
           : _step == 2 ? _buildStep2()
           : _buildComplete(),
    ),
  );
}
```

- [ ] **Step 8: Commit**

```bash
git add lib/screens/club_onboarding_screen.dart lib/api/api_client.dart
git commit -m "feat: 2-step club onboarding with logo upload and abstract SVG icons"
```

---

## Chunk 4: Flutter — 구독 화면 + 인앱결제

### Task 11: pubspec.yaml에 in_app_purchase 추가

**Files:**
- Modify: `C:/projects/performance_manager/pubspec.yaml`
- Modify: `C:/projects/performance_manager/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: pubspec.yaml 의존성 추가**

```yaml
dependencies:
  in_app_purchase: ^3.2.0   # 인앱결제
```

- [ ] **Step 2: Flutter pub get**

```bash
cd C:/projects/performance_manager
flutter pub get
# 오류 없이 완료되면 성공
```

- [ ] **Step 3: AndroidManifest.xml BILLING 권한 확인**

`android/app/src/main/AndroidManifest.xml`에 아래가 없으면 추가:
```xml
<uses-permission android:name="com.android.vending.BILLING" />
```
(in_app_purchase 패키지가 자동 추가하는 경우가 많으나 명시적으로 확인)

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml
git commit -m "chore: add in_app_purchase dependency"
```

---

### Task 12: 구독 화면 (subscription_screen.dart)

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/subscription_screen.dart`

- [ ] **Step 1: 화면 뼈대 생성**

```dart
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../api/api_client.dart';

class ClubSubscriptionScreen extends StatefulWidget {
  final int clubId;
  const ClubSubscriptionScreen({super.key, required this.clubId});

  @override
  State<ClubSubscriptionScreen> createState() => _ClubSubscriptionScreenState();
}

class _ClubSubscriptionScreenState extends State<ClubSubscriptionScreen> {
  static const _standardId = 'stagemate_standard_monthly';
  static const _proId      = 'stagemate_pro_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  List<ProductDetails> _products = [];
  Map<String, dynamic> _subscription = {};
  bool _loading = true;
  String? _currentPlan;

  @override
  void initState() {
    super.initState();
    _load();
    InAppPurchase.instance.purchaseStream.listen(_onPurchaseUpdate);
  }
  ...
}
```

- [ ] **Step 2: 상품 로드 + 구독 상태 조회**

```dart
Future<void> _load() async {
  try {
    final sub = await ApiClient.getClubSubscription(widget.clubId);
    final available = await _iap.isAvailable();
    if (available) {
      final res = await _iap.queryProductDetails({_standardId, _proId});
      setState(() {
        _products      = res.productDetails;
        _subscription  = sub;
        _currentPlan   = sub['plan'] as String? ?? 'free';
        _loading       = false;
      });
    } else {
      setState(() { _loading = false; });
    }
  } catch (e) {
    setState(() { _loading = false; });
  }
}
```

- [ ] **Step 3: 구매 처리**

```dart
Future<void> _purchase(ProductDetails product) async {
  final param = PurchaseParam(productDetails: product);
  await _iap.buyNonConsumable(purchaseParam: param);
}

Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
  for (final p in purchases) {
    if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
      // 서버에 영수증 검증 요청
      try {
        await ApiClient.verifyClubSubscription(
          widget.clubId,
          productId:     p.productID,
          transactionId: p.purchaseID ?? '',
          platform:      Theme.of(context).platform == TargetPlatform.iOS ? 'apple' : 'google',
          receiptData:   p.verificationData.serverVerificationData,
          expiresAt:     DateTime.now().add(const Duration(days: 31)).toIso8601String(),
        );
        await _iap.completePurchase(p);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('구독이 활성화됐습니다!')),
          );
          _load();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
  }
}
```

- [ ] **Step 4: 3열 카드 UI 구현**

```dart
@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Scaffold(
    appBar: AppBar(
      title: const Text('동아리 구독'),
      backgroundColor: cs.primaryContainer,
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text('동아리를 더 돋보이게',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 6),
              Text('지금 구독하면 가격이 영구 고정됩니다',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _PlanCard(
                    title: 'FREE',
                    price: '₩0',
                    features: const ['저장공간 10GB', '대용량 영상 월 5개'],
                    isCurrent: _currentPlan == 'free',
                    isHighlighted: false,
                    onTap: null,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _PlanCard(
                    title: 'STANDARD',
                    price: '₩1,900',
                    features: const ['저장공간 30GB', '대용량 영상 무제한', '동아리 꾸미기', '홍보 부스트 월 1회'],
                    isCurrent: _currentPlan == 'standard',
                    isHighlighted: false,
                    onTap: _currentPlan == 'free'
                        ? () => _purchase(_products.firstWhere((p) => p.id == _standardId,
                              orElse: () => _products.first))
                        : null,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _PlanCard(
                    title: 'PRO ✦',
                    price: '₩4,900',
                    features: const ['저장공간 100GB', '대용량 영상 무제한', '동아리 꾸미기', '홍보 부스트 월 3회', '랭킹 우선 노출'],
                    isCurrent: _currentPlan == 'pro',
                    isHighlighted: true,
                    onTap: _currentPlan != 'pro'
                        ? () => _purchase(_products.firstWhere((p) => p.id == _proId,
                              orElse: () => _products.first))
                        : null,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              Text('인앱결제 · 언제든 해지 가능',
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ]),
          ),
  );
}
```

- [ ] **Step 5: `_PlanCard` 위젯**

```dart
class _PlanCard extends StatelessWidget {
  final String title, price;
  final List<String> features;
  final bool isCurrent, isHighlighted;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.title, required this.price,
    required this.features, required this.isCurrent,
    required this.isHighlighted, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isHighlighted ? cs.primary : cs.outlineVariant,
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: isHighlighted ? cs.primaryContainer.withOpacity(0.3) : null,
      ),
      child: Stack(children: [
        if (isHighlighted)
          Positioned(
            top: -1, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Text('추천', style: TextStyle(color: cs.onPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
            )),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          child: Column(children: [
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                color: cs.primary, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('/월', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            const Divider(height: 16),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(f, style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.75)),
                textAlign: TextAlign.center),
            )),
            const SizedBox(height: 10),
            if (isCurrent)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Text('현재 플랜', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              )
            else if (onTap != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('구독'),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 6: club_manage_screen.dart에서 구독 화면으로 이동하는 버튼 추가**

`club_manage_screen.dart`의 super_admin 전용 섹션에:
```dart
ListTile(
  leading: Icon(Icons.workspace_premium, color: colorScheme.primary),
  title: const Text('구독 및 꾸미기'),
  subtitle: const Text('로고, 배너, 부스트 관리'),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.push(context, MaterialPageRoute(
    builder: (_) => ClubSubscriptionScreen(clubId: currentClubId),
  )),
),
```

- [ ] **Step 7: Commit**

```bash
git add lib/screens/subscription_screen.dart lib/screens/club_manage_screen.dart
git commit -m "feat: add 3-column subscription screen with in-app purchase flow"
```

---

### Task 13: 피드 — 홍보 부스트 UI

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/feed_screen.dart`

- [ ] **Step 1: 게시글 카드에 부스트 버튼 추가**

게시글 작성자 본인 + 동아리 구독 있을 때만 버튼 표시:
```dart
// 게시글 카드 하단 액션 바에 추가
if (post['author_id'] == currentUserId)
  IconButton(
    icon: Icon(
      post['is_boosted'] == true ? Icons.rocket : Icons.rocket_launch_outlined,
      color: post['is_boosted'] == true
          ? Theme.of(context).colorScheme.primary
          : Colors.grey,
      size: 20,
    ),
    onPressed: post['is_boosted'] == true ? null : () => _boostPost(post['id'] as int),
    tooltip: post['is_boosted'] == true ? '부스트 중' : '홍보 부스트',
  ),
```

- [ ] **Step 2: `_boostPost()` 메서드 구현**

```dart
Future<void> _boostPost(int postId) async {
  try {
    final result = await ApiClient.boostPost(postId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] as String? ?? '부스트 적용됨'),
      ));
      _loadPosts();
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(e))),
    );
  }
}
```

- [ ] **Step 3: 부스트 게시글 상단 표시 (배지)**

```dart
// 게시글 카드 상단에 조건부 배지
if (post['is_boosted'] == true)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.rocket, size: 12, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 4),
      Text('홍보 중', style: TextStyle(fontSize: 11,
          color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
    ]),
  ),
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/feed_screen.dart
git commit -m "feat: add boost button and boosted post badge in feed"
```

---

## 10. 보류 사항 (동아리 구독)

- 구독 만료 알림 이메일
- 연간 구독 할인 옵션
- PRO 초과 저장 자동 반복 청구
- Apple/Google 실제 영수증 서버 검증 (프로덕션 배포 전 TODO 처리)
- iOS Xcode In-App Purchase capability 수동 설정 필요
