# StageMate 구독 시스템 설계 (동아리 + 개인)

**날짜**: 2026-03-28
**프로젝트**: StageMate (Flutter + FastAPI + PostgreSQL/Railway)
**범위**: 동아리 단위 구독 · 개인 구독 · 프로필 시스템 · 보안 강화 · 온보딩 개선

---

## 1. 개요

동아리 회비를 활용한 소액 정기 구독 모델을 도입한다. 동아리 간 시각적 차별화(꾸미기)와 기능 해금(업로드 무제한, 홍보 부스트)을 결합해 자연스러운 결제 유도를 목표로 한다. 결제 주체는 동아리장(super_admin)이며 혜택은 동아리 전체에 적용된다.

---

## 2. 요금제 구성

| 항목 | FREE | STANDARD | PRO |
|------|------|----------|-----|
| **월 요금** | ₩0 | ₩1,900 | ₩4,900 |
| **저장공간** | 10GB | 30GB | 100GB |
| **1GB 초과 영상** | 월 5개 | 무제한 | 무제한 |
| **동아리 로고 사진** | ✓ | ✓ | ✓ |
| **배너·포인트 컬러·인증 배지** | ✕ | ✓ | ✓ |
| **공연 홍보 부스트** | ✕ | 월 1회 | 월 3회 |
| **핫 랭킹 우선 노출** | ✕ | ✕ | ✓ |
| **초과 저장** | 업로드 차단 | 업로드 차단 | 소모성 1GB 추가 구매 |

### 가격 전략
- 얼리버드 그랜드파더링: App Store에 별도 제품 ID (`stagemate_standard_early`, `stagemate_pro_early`) 생성. 론칭 후 6개월간만 노출. 이후 신규는 일반 가격 제품 ID로만 구매 가능. `subscription_transactions` 테이블에 `product_id` 기록으로 구분.
- 인앱결제(Apple IAP / Google Play Billing) — 앱스토어 수수료 30% 적용

---

## 3. 기능 상세

### 3-1. 동아리 꾸미기

| 항목 | 플랜 | 설명 |
|------|------|------|
| 동아리 로고 | 전체(무료 포함) | 원형 아바타. super_admin만 변경 가능. image_picker → R2 업로드 후 URL만 PATCH |
| 배너 이미지 | STANDARD+ | 동아리 프로필 상단 와이드 이미지. super_admin만 변경 가능 |
| 포인트 컬러 | STANDARD+ | hex 코드 선택. super_admin만 변경 가능 |
| 인증 배지 | STANDARD+ | 동아리 이름 옆 ✦ 표시 |

> **주의**: `PATCH /clubs/{id}/profile`은 이미 R2에 업로드된 이미지의 URL 문자열과 hex 컬러값을 받는다. 파일 바이너리를 받지 않는다. 이미지 업로드는 기존 `GET /upload/presigned` 흐름을 그대로 사용한다.

### 3-2. 공연 홍보 부스트

- 게시글 작성 시 "홍보 부스트" 토글 노출 (크레딧 0이면 잠금 + 구독 유도 문구)
- 부스트된 게시글은 `GET /posts?is_global=true` 결과에서 `is_boosted=true` 게시글을 먼저 정렬 (`boost_expires_at DESC`, 이후 `created_at DESC`)
- 한 게시글에 중복 부스트 불가 (이미 부스트 중이면 409)
- 유효 시간 24시간. 만료 시 `is_boosted=false`로 자동 전환 (Railway cron)
- 월 1일 `boost_credits` 플랜별 값으로 초기화 (Railway cron)

### 3-3. 핫 랭킹 우선 노출 (PRO)

- 기존 `GET /clubs/hot-ranking` 점수 계산에 PRO 동아리 가중치 1.5배 적용
- 랭킹 화면에 PRO 배지(✦) 표시
- **이 엔드포인트는 변경 대상에 포함**

### 3-4. 저장공간 쿼터

**업데이트 방식**: 직접 업로드(presigned URL) 방식이라 서버가 파일을 보지 못한다. 따라서 업로드 완료 후 Flutter에서 `POST /clubs/{id}/storage/report` 호출 → 서버가 `storage_used_mb` 증가. 클라이언트가 보고하는 구조이므로 서버 측 quota 체크는 presigned URL 발급 시점에 수행한다.

**서버 측 size 검증**: 클라이언트 조작 방지를 위해, presigned URL 발급 시 `{ key, file_size_mb }` 쌍을 서버 DB(`presign_requests` 임시 테이블 또는 Redis)에 5분간 저장. `storage/report` 호출 시 `key`로 조회해 사전 등록된 `file_size_mb`로만 증가를 허용. 등록 없는 key나 값 불일치는 400 반환.

**쿼터 체크 흐름**:
1. Flutter가 `GET /upload/presigned?filename=X&content_type=Y&club_id=Z&file_size_mb=N` 호출
2. 서버가 현재 `storage_used_mb + N > 플랜 쿼터`이면 403 반환
3. 통과 시 presigned URL 발급, 경로: `clubs/{club_id}/{uuid}/{safe_filename}`
4. 업로드 성공 시 Flutter가 `POST /clubs/{id}/storage/report { "added_mb": N }` 호출

**초과 처리 (PRO)**:
- `stagemate_storage_1gb` 소모성 인앱결제로 1GB 추가 (영수증 검증 후 `storage_quota_extra_mb += 1024`)
- 영구 추가 (만료 없음)

**플랜별 기본 쿼터**:
- FREE: 10,240MB / STANDARD: 30,720MB / PRO: 102,400MB

### 3-5. 구독 만료 처리

Railway에 별도 cron 서비스를 `railway.toml`에 정의:
```toml
[[services]]
name = "cron"
startCommand = "python cron.py"

[[services.cronJobs]]
schedule  = "0 2 * * *"   # 매일 02:00 UTC
command   = "python cron.py expire"

[[services.cronJobs]]
schedule  = "0 0 1 * *"   # 매월 1일 00:00 UTC
command   = "python cron.py reset_boosts"

[[services.cronJobs]]
schedule  = "*/30 * * * *"  # 30분마다: 만료된 부스트 게시글 해제
command   = "python cron.py expire_boosts"

[[services.cronJobs]]
schedule  = "*/10 * * * *"  # 10분마다: presign_requests 만료 행 삭제
command   = "python cron.py cleanup_presign"
```

**`presign_requests` 테이블** (Redis 대신 DB 사용):
```sql
CREATE TABLE presign_requests (
    key         VARCHAR PRIMARY KEY,   -- R2 object key
    club_id     INTEGER,               -- 동아리 업로드시 (nullable)
    user_id     INTEGER NOT NULL,
    file_size_mb INTEGER NOT NULL,
    expires_at  TIMESTAMP NOT NULL     -- NOW() + 5분
);
```
10분 cron으로 만료 행 정리. Railway 무료 플랜에서 Redis 불필요.

`cron.py` 역할:
- `expire`: `clubs.plan_expires_at < NOW()` → `plan='free'`, `plan_expires_at=NULL`, `boost_credits=0` / `users.personal_plan_expires_at < NOW()` → `personal_plan='free'`, `personal_plan_expires_at=NULL`
- `reset_boosts`: 플랜별 크레딧 값으로 `boost_credits` 초기화 (free=0, standard=1, pro=3)
- `expire_boosts`: `boost_expires_at < NOW()` 인 게시글 `is_boosted=false` 처리
- `cleanup_presign`: `presign_requests` 테이블에서 `expires_at < NOW()` 행 삭제 (5분 TTL)

**Apple/Google 서버-to-서버 알림**:
- Apple: App Store Server Notifications V2 endpoint `POST /webhooks/apple`
- Google: Google Play Developer Notifications endpoint `POST /webhooks/google`
- **서명 검증 필수**: Apple은 JWS 서명 검증 (`python-jwt` + Apple 루트 인증서), Google은 RTDN Pub/Sub 메시지의 서명 검증. 미검증 시 누구나 가짜 구독 활성화 가능.
- 웹훅 payload의 `product_id` 기준으로 동아리/개인 플랜 구분:
  - `stagemate_standard_*` / `stagemate_pro_*` → `clubs.plan_expires_at` 업데이트
  - `stagemate_personal_*` → `users.personal_plan_expires_at` 업데이트
- 구독 갱신 성공 시 해당 테이블 `expires_at` 연장. 취소/환불 시 즉시 다운그레이드.
- 웹훅 payload는 `subscription_transactions`에 기록

---

## 4. 온보딩 플로우 개선 (동아리 생성)

### Step 1 — 동아리 이름
- 기존 이름 입력 폼 유지
- 하단 스텝 인디케이터 추가 (●○)
- 추상 SVG 아이콘 (원 3개 겹침)

### Step 2 — 동아리 사진 (선택)
- 원형 아바타 영역 탭 → image_picker 실행 → R2 업로드 → `POST /clubs` body에 `logo_url` 포함 또는 완료 후 `PATCH /clubs/{id}/profile` 호출
- "건너뛰기" 버튼으로 생략 가능
- 아이콘: 추상 카메라 SVG (렌즈 구조), 이모지 미사용

### 완료 화면
- 추상 방사형 SVG 일러스트 (원 + 8방향 선)
- 동아리 이름 + 초대코드 표시
- 이모지 미사용

---

## 5. 데이터 모델 변경

### clubs 테이블 추가 컬럼
```sql
logo_url            VARCHAR          -- 동아리 로고 URL (모든 플랜)
banner_url          VARCHAR          -- 배너 이미지 URL (STANDARD+)
theme_color         VARCHAR(7)       -- hex 포인트 컬러 (STANDARD+)
plan                VARCHAR(20) DEFAULT 'free'   -- 'free' | 'standard' | 'pro'
plan_expires_at     TIMESTAMP        -- NULL = 무료 또는 해지됨
storage_used_mb     BIGINT DEFAULT 0 -- 현재 사용량 (MB). BIGINT 사용 (100GB = 102400MB)
storage_quota_extra_mb BIGINT DEFAULT 0 -- PRO 초과 추가 구매분 (MB)
boost_credits       INTEGER DEFAULT 0 -- 남은 홍보 부스트 횟수
```

### posts 테이블 추가 컬럼
```sql
is_boosted          BOOLEAN DEFAULT FALSE
boost_expires_at    TIMESTAMP
```

### subscription_transactions 테이블 (신규)
```sql
CREATE TABLE subscription_transactions (
    id                  SERIAL PRIMARY KEY,
    club_id             INTEGER REFERENCES clubs(id),          -- 개인 구독 시 NULL
    user_id             INTEGER NOT NULL REFERENCES users(id),  -- 결제한 super_admin
    product_id          VARCHAR NOT NULL,       -- 'stagemate_pro_monthly' 등
    transaction_id      VARCHAR UNIQUE NOT NULL, -- 중복 영수증 방지
    platform            VARCHAR(10) NOT NULL,   -- 'apple' | 'google'
    purchased_at        TIMESTAMP NOT NULL,
    expires_at          TIMESTAMP,
    status              VARCHAR(20) DEFAULT 'active', -- 'active' | 'cancelled' | 'refunded'
    raw_payload         TEXT,                  -- 원본 웹훅 payload
    created_at          TIMESTAMP DEFAULT NOW()
);
```

---

## 6. 백엔드 API

| Method | Endpoint | 설명 | 변경 여부 |
|--------|----------|------|-----------|
| GET | `/clubs/{id}/profile` | 동아리 프로필 조회 (인증 필요, 멤버십 무관 열람 가능). 응답: `{ club_id, name, plan, logo_url, banner_url, theme_color, has_badge, boost_credits_remaining }` | 신규 |
| PATCH | `/clubs/{id}/profile` | 로고URL·배너URL·컬러 업데이트 (super_admin) | 신규 |
| GET | `/clubs/{id}/subscription` | 구독 상태·사용량·크레딧 조회 | 신규 |
| POST | `/clubs/{id}/subscription/verify` | 동아리 인앱결제 영수증 검증 + 플랜 업데이트 (club plan만) | 신규 |
| POST | `/users/me/subscription/verify` | 개인 인앱결제 영수증 검증 + `personal_plan` 업데이트 | 신규 |
| POST | `/clubs/{id}/storage/report` | 업로드 완료 후 사용량 보고 | 신규 |
| POST | `/posts/{id}/boost` | 홍보 부스트 적용 (크레딧 차감) | 신규 |
| POST | `/webhooks/apple` | Apple 서버 알림 수신 | 신규 |
| POST | `/webhooks/google` | Google 서버 알림 수신 | 신규 |
| GET | `/upload/presigned` | `club_id`, `file_size_mb` 파라미터 추가 + 쿼터 체크 + 경로 변경 | **수정** |
| GET | `/clubs/hot-ranking` | PRO 가중치 1.5배 적용 | **수정** |
| GET | `/posts` | `is_boosted` 게시글 상단 정렬 | **수정** |

---

## 7. Flutter 화면 변경

| 파일 | 변경 내용 |
|------|-----------|
| `club_onboarding_screen.dart` | 2단계 플로우, 사진 업로드 Step 추가 |
| `club_manage_screen.dart` | 동아리 꾸미기 섹션 (로고·배너·컬러) 추가 |
| `subscription_screen.dart` | **신규**: 3열 카드 요금제 페이지 + 인앱결제 연동 |
| `feed_screen.dart` | 홍보 부스트 토글 + 잠금 상태 UI |
| `home_screen.dart` | 동아리 프로필 헤더에 배너·배지·컬러 적용 |
| `api_client.dart` | 신규 API 메서드 추가 |

---

## 8. 결제 구현 (인앱결제)

### pubspec.yaml 추가
```yaml
in_app_purchase: ^3.2.0
```

### iOS 추가 설정 (Xcode 필요)
- Xcode > Signing & Capabilities > "+ Capability" > **In-App Purchase** 추가
- App Store Connect에서 구독 상품 등록 후 심사 통과 필요

### Android 추가 설정
- Google Play Console > 앱 내 상품 등록
- `AndroidManifest.xml`에 `BILLING` 권한 추가 (in_app_purchase 패키지가 자동 처리)

### 제품 ID
| ID | 설명 |
|----|------|
| `stagemate_standard_monthly` | 일반 STANDARD 월정기구독 |
| `stagemate_pro_monthly` | 일반 PRO 월정기구독 |
| `stagemate_standard_early` | 얼리버드 STANDARD (론칭 후 6개월) |
| `stagemate_pro_early` | 얼리버드 PRO (론칭 후 6개월) |
| `stagemate_storage_1gb` | PRO 추가 저장 1GB (소모성) |

### 영수증 서버 검증
- Apple: App Store Server API V2 JWS (`GET /inApps/v2/history/{transactionId}`) — 구 `verifyReceipt` 엔드포인트는 deprecated, 사용 금지
- Google: Google Play Developer API (`purchases.subscriptions.get`)
- `transaction_id` 중복 확인으로 리플레이 어택 방지

---

## 9. 구현 순서

1. DB 마이그레이션 (clubs 컬럼 추가, subscription_transactions 테이블 신규)
2. `railway.toml` cron 서비스 및 `cron.py` 작성
3. 백엔드 API — 프로필 · 구독 · 저장량 보고
4. 백엔드 API — 부스트 + posts 정렬 변경 + 랭킹 가중치
5. 백엔드 웹훅 (Apple/Google)
6. `GET /upload/presigned` 경로 + 쿼터 체크 수정
7. Flutter `pubspec.yaml` + iOS/Android 결제 설정
8. Flutter 온보딩 개선 (2단계)
9. Flutter 동아리 꾸미기 UI
10. Flutter 구독 화면 + 인앱결제 연동
11. Flutter 홍보 부스트 UI + 홈 배너/배지 적용

---

---

## 10. 보류 사항 (동아리 구독)

- 구독 만료 알림 이메일
- 연간 구독 할인 옵션
- PRO 초과 저장 자동 반복 청구

---

## 11. 개인 구독 (Personal Plan)

### 11-1. 요금제

| 항목 | 무료 | PERSONAL ₩2,900/월 |
|------|------|---------------------|
| 개인 프로필 페이지 | 기본 정보만 | ✓ 풀 프로필 |
| 개인 아카이브 (영상·사진) | ✕ | ✓ 무제한 업로드 |
| 닉네임 효과 (컬러·그라데이션) | ✕ | ✓ |
| 개인 배너 이미지 | ✕ | ✓ |
| 개인 테마 컬러 | ✕ | ✓ |
| 자기소개 + 인스타 링크 | ✕ | ✓ |
| 인앱결제 제품 ID | — | `stagemate_personal_monthly` |

### 11-2. 개인 프로필 페이지

- URL 구조: 앱 내 딥링크 `/profile/{user_id}`
- 구성:
  - 상단: 배너 이미지 (PERSONAL만) + 원형 아바타 + 닉네임 + 효과
  - 자기소개 텍스트 (최대 150자)
  - 인스타그램 링크 (외부 브라우저 오픈)
  - 아카이브 탭: 개인 업로드 영상·사진 그리드
- 비구독자는 아바타·닉네임·자기소개만 표시, 아카이브 탭 잠금

### 11-3. 프로필 카드 팝업

- 게시글·댓글의 아바타 또는 닉네임 탭 → 바텀시트 팝업 형태
- 표시 내용: 아바타, 닉네임(+효과), 자기소개 한 줄, "프로필 보기" 버튼
- 프로필 보기 → 전체 프로필 페이지로 이동

### 11-4. 아카이브 콘텐츠

- 개인 업로드 영상·사진 (R2 저장, 경로: `profiles/{user_id}/{uuid}/{filename}`)
- 타 유저가 방문해 좋아요·댓글 가능
- 댓글은 별도 `archive_comments` 테이블 사용 (Section 13 참조)
- 아카이브 아이템 삭제: DB 레코드 삭제 + R2 오브젝트 삭제를 **동일 핸들러 내 원자적으로** 처리. 소유권(`archive_item.user_id == current_user.id`) 확인 후 R2 삭제 진행. 두 작업은 반드시 같은 함수 안에서 실행해 부분 실패 방지.
- 저장 용량: PERSONAL 구독자 무제한. R2 비용은 초기 수용 후 사용량 증가 시 별도 쿼터 도입 검토 (현재는 비용 감수 결정으로 명시적으로 기록).

### 11-5. 닉네임 효과

| 효과 | 설명 |
|------|------|
| 단색 | hex 컬러로 닉네임 텍스트 색상 변경 |
| 그라데이션 | 시작·끝 컬러 두 가지 지정 |
| 볼드+컬러 | 굵게 + 컬러 조합 |

- 효과 미리보기 UI 제공 (색상 피커 + 실시간 미리보기)
- 무료 유저는 기본 텍스트 색(흰/검) 고정

---

## 12. 닉네임 필수화 및 실명 보호

### 12-1. 회원가입 변경

- 기존: `display_name` 입력 → 닉네임은 선택사항
- 변경: 회원가입 시 `nickname` 필수 입력, `display_name`(실명)은 유지하되 동아리 내부 전용
- `nickname`: 전체 커뮤니티(global channel) 표시명
- `display_name`: 동아리 내부 피드·멤버 목록에서만 사용

### 12-2. 실명 노출 차단 (보안)

**전체 채널(global) 게시글·댓글 API 응답에서 `display_name` 완전 제거**

현재 취약점:
- `GET /posts?is_global=true` 응답에 `author` 필드가 `post_author_name`(닉네임) 또는 `display_name`(실명) 혼재
- `GET /posts/{id}/comments` 응답에 `author: display_name` 노출 가능

패치 방향:
- 전체 채널 게시글: `author = post_author_name` (닉네임 or "익명"). `display_name` 폴백 금지
- 전체 채널 댓글: `author = commenter.nickname`. `nickname`이 없으면 업로드 차단(닉네임 필수화 이후엔 항상 존재)
- 동아리 내부 게시글·댓글: `author = display_name` 그대로 유지
- API 응답에서 `author_id` 노출은 유지하되, `GET /users/{user_id}/profile` 응답에 `display_name` 필드를 **명시적으로 포함 금지**. 응답 스키마에 없는 필드는 직렬화 시 제외. (Section 14 프로필 API 응답 정의 참조)

### 12-3. 권한 검증 강화 (신규 API 전반)

모든 신규 엔드포인트에 아래 검증 레이어를 반드시 포함:

| 검증 항목 | 방법 |
|-----------|------|
| 인증 여부 | `get_current_user` 의존성 (JWT 필수) |
| 탈퇴 계정 차단 | `get_current_user` 내 `deleted_at` 체크 (기존 패치 적용) |
| 아카이브 수정·삭제 | `archive_item.user_id == current_user.id` 확인 |
| 프로필 수정 | `user_id == current_user.id` 확인 (타인 프로필 수정 불가) |
| 구독 검증 | presigned URL 발급·아카이브 업로드 전 `user.personal_plan == 'personal'` 확인 |
| Rate limit | 프로필 수정 5/minute, 아카이브 업로드 20/minute, 댓글 30/minute. 기존 `slowapi` 라이브러리(현재 코드베이스에 적용됨) 동일하게 사용 |

---

## 13. 데이터 모델 추가 (개인 구독)

### users 테이블 추가 컬럼
```sql
nickname_color      VARCHAR(7)        -- 닉네임 단색 hex (PERSONAL+)
nickname_color2     VARCHAR(7)        -- 그라데이션 끝 색 (PERSONAL+, nullable)
nickname_bold       BOOLEAN DEFAULT FALSE
personal_banner_url VARCHAR
personal_theme_color VARCHAR(7)
bio                 VARCHAR(150)      -- 자기소개
instagram_id        VARCHAR(50)       -- @ 제외 순수 ID
personal_plan       VARCHAR(20) DEFAULT 'free'  -- 'free' | 'personal'
personal_plan_expires_at TIMESTAMP
```

### archive_items 테이블 (신규)
```sql
CREATE TABLE archive_items (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    media_url   VARCHAR NOT NULL,
    media_type  VARCHAR(10) NOT NULL,  -- 'image' | 'video'
    caption     VARCHAR(500),
    like_count  INTEGER DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);
```

### archive_comments 테이블 (신규)
```sql
CREATE TABLE archive_comments (
    id              SERIAL PRIMARY KEY,
    archive_item_id INTEGER NOT NULL REFERENCES archive_items(id) ON DELETE CASCADE,
    author_id       INTEGER NOT NULL REFERENCES users(id),
    content         VARCHAR(500) NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);
```

### archive_likes 테이블 (신규)
```sql
CREATE TABLE archive_likes (
    archive_item_id INTEGER NOT NULL REFERENCES archive_items(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    PRIMARY KEY (archive_item_id, user_id)
);
```

---

## 14. 추가 API (개인 구독)

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/users/{user_id}/profile` | 공개 프로필 조회. 응답: `{ nickname, avatar_url, bio, instagram_id, nickname_style, personal_banner_url, personal_theme_color, is_personal_subscriber }` |
| PATCH | `/users/me/profile` | 내 프로필 수정 (bio, instagram_id, 닉네임 효과 등). 본인만 가능 |
| GET | `/users/{user_id}/archive` | 아카이브 목록 조회. 비구독자는 빈 배열 + `locked: true` |
| POST | `/users/me/archive` | 아카이브 아이템 업로드 (PERSONAL 구독 확인 후 presigned URL 발급) |
| DELETE | `/users/me/archive/{item_id}` | 본인 아카이브 삭제 (R2 오브젝트도 삭제) |
| POST | `/archive/{item_id}/likes` | 좋아요 토글 |
| GET | `/archive/{item_id}/comments` | 댓글 목록 |
| POST | `/archive/{item_id}/comments` | 댓글 작성 |
| DELETE | `/archive/{item_id}/comments/{comment_id}` | 댓글 삭제 (본인만) |
| POST | `/users/me/subscription/verify` | 개인 인앱결제 영수증 검증. `personal_plan`, `personal_plan_expires_at` 업데이트 |

---

## 15. Flutter 추가 화면 (개인 구독)

| 파일 | 변경 내용 |
|------|-----------|
| `profile_screen.dart` | 신규: 개인 프로필 풀 페이지 (배너, 아바타, 닉네임, bio, 인스타, 아카이브 그리드) |
| `profile_card_widget.dart` | 신규: 바텀시트 프로필 카드 팝업 |
| `archive_upload_screen.dart` | 신규: 아카이브 영상/사진 업로드 |
| `personal_subscription_screen.dart` | 신규: 개인 구독 요금제 카드 |
| `nickname_style_screen.dart` | 신규: 닉네임 효과 선택 + 미리보기 |
| `register_screen.dart` | 닉네임 필수 입력 추가 |
| `feed_screen.dart` | 게시글·댓글 아바타/닉네임 탭 → 프로필 카드 팝업 연결 |

---

## 16. 구현 순서 (전체 통합)

### Phase 1 — 기반 (보안 + DB)
1. DB 마이그레이션 전체 (clubs + users + 신규 테이블)
2. 닉네임 필수화 + 실명 노출 차단 (API 응답 패치)
3. 신규 API 권한 검증 레이어 표준화

### Phase 2 — 동아리 구독
4. `railway.toml` cron + `cron.py`
5. 동아리 프로필·구독·저장량·부스트 API
6. `GET /upload/presigned` 쿼터 체크 + 경로 변경
7. Flutter 온보딩 2단계 + 동아리 꾸미기 + 구독 화면

### Phase 3 — 개인 구독
8. 개인 프로필 API + 아카이브 API
9. Apple/Google 웹훅 (동아리·개인 통합 처리)
10. Flutter 프로필 페이지 + 카드 팝업 + 아카이브
11. Flutter 닉네임 효과 + 개인 구독 화면

### Phase 4 — 랭킹·부스트
12. 핫 랭킹 PRO 가중치 + 부스트 정렬

---

## 17. 보류 사항 (개인 구독)

- 구독 만료 알림 이메일 (개인)
- 연간 구독 할인 옵션 (개인)
- 아카이브 아이템 신고 기능
- 개인 아카이브 저장 쿼터 (현재 무제한, 추후 비용 증가 시 도입)
