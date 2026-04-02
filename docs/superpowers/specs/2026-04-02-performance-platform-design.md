# StageMate 공연 플랫폼 기능 설계

**날짜:** 2026-04-02
**상태:** 승인됨
**목표:** 커뮤니티 활성화 → 고화질 영상 업로드 증가 → 결제 유도

---

## 개요

StageMate를 단순 동아리 관리 앱에서 **공연 인재 발굴 플랫폼**으로 확장한다. 4가지 기능이 하나의 결제 퍼널로 연결된다.

```
YouTube 링크 공유 → 아카이브 15개 한도 → 챌린지 경쟁 → 웹 노출 → 결제
```

---

## 기능 1: YouTube 링크 in 게시글

### 동작 방식
- 게시글 작성 화면에 **YouTube URL 입력 필드** 추가 (선택 사항)
- URL 입력 시 Video ID 추출 → `img.youtube.com/vi/{id}/maxresdefault.jpg` 로 썸네일 시도, 실패 시 `hqdefault.jpg` 폴백
- 피드 카드에 썸네일 + 영상 제목 표시 (YouTube 앱 이동)
- Flutter `Image.network errorBuilder`: 썸네일 로드 실패 또는 Video ID 유효하지 않으면 YouTube 아이콘 플레이스홀더 카드 표시
- 탭 → YouTube 앱 또는 브라우저로 이동 (인앱 재생 없음)
- 별도 API 키 불필요

### DB 변경
- `posts` 테이블에 `youtube_url VARCHAR(500) NULLABLE` 컬럼 추가 (`_run_migrations()`에서 ALTER TABLE)

### 무료/유료 구분
- 무료: 완전 사용 가능 (진입 장벽 최소화)

---

## 기능 2: 공연 아카이브 탭

> **주의:** 백엔드에 `performances` 테이블이 오디오 제출 기능용으로 이미 존재함. 신규 테이블 이름은 `performance_archives`로 구분한다.

### 동작 방식
- 동아리 프로필에 **"공연 기록" 탭** 추가 (피드 · 멤버 탭 옆)
- 각 공연 기록 필드:
  - 공연 제목 (필수)
  - 공연 날짜 (필수)
  - YouTube URL (선택)
  - 설명 (선택, 셋리스트 등)
  - 네이티브 HD 영상 URL (유료 전용)
- 목록: 썸네일 카드 + 날짜 + 좋아요 수 + 조회수
- 챌린지에 제출한 공연은 "챌린지 제출" 뱃지 표시

### 좋아요
- `performance_archive_likes` 테이블로 관리 (기존 `PostLike` 패턴과 동일)
  ```
  id, archive_id (FK performance_archives.id), user_id (FK users.id), created_at
  UNIQUE CONSTRAINT on (archive_id, user_id)
  ```
- 아카이브 카드의 좋아요 수는 이 테이블 COUNT로 산출

### 공개 공유
- `stagemate.app/clubs/{club_id}` 경로로 외부 공개
- 로그인 없이 브라우저에서 열람 가능

### 15개 한도 적용
- `POST /clubs/{club_id}/performance-archives` 엔드포인트에서:
  - `club.plan == 'free'` 이고 해당 club의 `performance_archives` 행 수 >= 15이면 **HTTP 403** 반환
  - 응답 body: `{"detail": "무료 플랜은 최대 15개까지 저장할 수 있어요. 무제한은 PRO 플랜으로 업그레이드하세요."}`

### DB 변경
- `performance_archives` 테이블 신규 생성:
  ```
  id, club_id (FK), title, description,
  performance_date (DATE), youtube_url,
  native_video_url, view_count (INT DEFAULT 0),
  created_at
  ```
- `performance_archive_likes` 테이블 신규 생성 (위 참조)

### 무료/유료 구분
- **무료:** 최대 15개 저장, YouTube URL만 가능
- **유료(PRO):** 무제한 저장, 네이티브 HD 영상 직접 업로드

---

## 기능 3: 이달의 챌린지

### 동작 방식
- **월별 챌린지 자동 생성:** lazy creation 방식. 챌린지 관련 GET 요청 수신 시 현재 `year_month`에 해당하는 행이 없으면 자동 생성. 별도 스케줄러 불필요.
- 동아리 admin이 아카이브에서 대표 공연을 **챌린지에 제출** (동아리당 1개 제한)
- 앱 전체 유저가 좋아요로 투표 (1인 1표, 중복 불가)
- 실시간 랭킹 화면 (D-day 카운트다운 + 참가 동아리 수)
- 월말(매월 1일 이후 이전 달 챌린지 접근 시) `is_active = false` lazy 처리
- 결과 발표: 1위 트로피 카드 + 링크/SNS 공유 버튼
- 1위 동아리 프로필에 "이달의 챔피언" 뱃지 부여

### 투표 중복 방지
- `challenge_entry_likes` 테이블로 관리:
  ```
  id, entry_id (FK challenge_entries.id), user_id (FK users.id), created_at
  UNIQUE CONSTRAINT on (entry_id, user_id)
  ```
- `challenge_entries`에 `likes_count` 컬럼 없음. 좋아요 수는 랭킹 조회 시 `challenge_entry_likes` COUNT로 산출 (캐시 컬럼 미사용)

### 챌린지 상태 규칙
- `challenges` 테이블에 `UNIQUE CONSTRAINT on (year_month)`
- `is_active = true`: 해당 월 진행 중, 제출·투표 모두 가능
- `is_active = false`: 이전 달 챌린지, 결과 조회만 가능, 제출·투표 불가
- 상태 전환: 새 월 챌린지 lazy 생성 시 `UPDATE challenges SET is_active = false WHERE year_month < current_month` (직전 월뿐 아니라 모든 이전 월 일괄 비활성화)

### DB 변경
- `challenges` 테이블 신규:
  ```
  id, year_month VARCHAR(7) (YYYY-MM), is_active BOOLEAN DEFAULT TRUE, created_at
  UNIQUE CONSTRAINT on (year_month)
  ```
- `challenge_entries` 테이블 신규:
  ```
  id, challenge_id (FK), club_id (FK),
  archive_id (FK performance_archives.id) NOT NULL,
  created_at
  UNIQUE CONSTRAINT on (challenge_id, club_id)
  ```
  - `archive_id NOT NULL`: 아카이브 공연 없이는 챌린지 제출 불가

### view_count 증가 시점
- `GET /clubs/{club_id}/performance-archives/{archive_id}` (상세 조회) 호출 시 `view_count += 1`
- 목록 조회(`GET /clubs/{club_id}/performance-archives`)에서는 증가하지 않음
- `challenge_entry_likes` 테이블 신규 (위 참조)

### 무료/유료 구분
- **무료:** 챌린지 참가 및 투표 가능
- **유료(PRO):** 랭킹 페이지 우선 노출, 조회수·유입 경로 분석 데이터 제공

---

## 기능 4: 공개 웹 랭킹 페이지

### 동작 방식
- `stagemate.app/ranking`: 이달의 TOP 동아리 + 공연 영상 목록
  - 1위: 대형 카드 (썸네일 + 좋아요 + 조회수)
  - 2위~: 리스트 카드
  - 하단 "우리 동아리도 도전하세요 → 앱 받기" CTA
- `stagemate.app/clubs/{club_id}`: 동아리 공개 프로필 + 공연 아카이브 전체
- 로그인 불필요, 모바일 반응형

### 기술 구현
- FastAPI + Jinja2 HTML 템플릿으로 서빙
- **의존성 확인 필요:** `requirements.txt`에 `jinja2`와 `aiofiles` 명시적 추가 필요 (FastAPI minimal install에 미포함)
- 새 공개 API 엔드포인트 (인증 없음):
  - `GET /public/ranking` — 이달의 챌린지 랭킹
  - `GET /public/clubs/{club_id}` — 동아리 공개 프로필 + 아카이브
- 웹 페이지 라우트:
  - `GET /ranking` — HTML 응답
  - `GET /clubs/{club_id}` — HTML 응답

### 배포 사전 조건
- **커스텀 도메인 설정 필요:** Railway 대시보드에서 `stagemate.app` 커스텀 도메인 추가 + DNS A 레코드 설정 후에야 외부 공개 가능
- 현재 백엔드 URL (`skillful-unity-production-e922.up.railway.app`)로는 테스트 가능하나 최종 배포 전 도메인 설정 완료 필요

### 무료/유료 구분
- **유료(PRO):** 랭킹 페이지 상단 우선 노출

---

## 결제 퍼널 흐름

| 단계 | 트리거 | 결제 훅 |
|------|--------|---------|
| 1 | YouTube 링크로 영상 공유 시작 | 무료, 활동 유도 |
| 2 | 아카이브 15개 소진 | "무제한 업그레이드 →" 안내 |
| 3 | 챌린지에서 경쟁 심화 | 조회수 분석·우선 노출 욕구 |
| 4 | 웹 랭킹 노출로 외부 발견 | HD 업로드·브랜딩 강화 욕구 |

---

## 구현 범위 요약

### Flutter 앱
- `post_create_screen.dart`: YouTube URL 필드 추가
- `feed_screen.dart`: YouTube 썸네일 카드 렌더링 (errorBuilder 포함)
- `performance_archive_screen.dart`: 신규 화면
- `challenge_screen.dart`: 신규 화면

### FastAPI 백엔드
- `requirements.txt`: `jinja2`, `aiofiles` 추가
- `posts` 테이블 마이그레이션 (youtube_url 추가)
- `performance_archives`, `performance_archive_likes`, `challenges`, `challenge_entries`, `challenge_entry_likes` 테이블 신규
- 공연 CRUD API, 챌린지 API, 공개 API 엔드포인트
- Jinja2 웹 페이지 (ranking, club profile)

### 비고
- 앱 로고: 초록색 연필+무대 아이콘 사용 (웹 페이지 헤더 포함)
- 네이티브 HD 영상 업로드는 S3/Cloudflare 스토리지 연동 필요 (별도 검토)
- 커스텀 도메인(`stagemate.app`) Railway 설정은 런칭 전 완료 필요
