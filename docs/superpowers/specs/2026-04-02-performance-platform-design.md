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
- URL 입력 시 Video ID 추출 → `img.youtube.com/vi/{id}/hqdefault.jpg` 로 썸네일 즉시 미리보기
- 피드 카드에 썸네일 + 영상 제목 + 재생 시간 표시
- 카드 탭 → YouTube 앱 또는 브라우저로 이동 (인앱 재생 없음)
- 별도 API 키 불필요

### DB 변경
- `posts` 테이블에 `youtube_url VARCHAR(500) NULLABLE` 컬럼 추가

### 무료/유료 구분
- 무료: 완전 사용 가능 (진입 장벽 최소화)

---

## 기능 2: 공연 아카이브 탭

### 동작 방식
- 동아리 프로필에 **"공연 기록" 탭** 추가 (피드 · 멤버 탭 옆)
- 각 공연 기록 필드:
  - 공연 제목 (필수)
  - 공연 날짜 (필수)
  - YouTube URL (선택)
  - 설명 (선택, 셋리스트 등)
  - 네이티브 HD 영상 (유료 전용)
- 목록: 썸네일 카드 + 날짜 + 좋아요 수 + 조회수
- 챌린지에 제출한 공연은 "챌린지 제출" 뱃지 표시

### 공개 공유
- `stagemate.app/clubs/{club_id}` 경로로 외부 공개
- 로그인 없이 브라우저에서 열람 가능

### DB 변경
- `performances` 테이블 신규 생성:
  ```
  id, club_id, title, description,
  performance_date, youtube_url,
  native_video_url, view_count,
  created_at
  ```

### 무료/유료 구분
- **무료:** 최대 15개 저장, YouTube URL만 가능
- **유료(PRO):** 무제한 저장, 네이티브 HD 영상 직접 업로드

---

## 기능 3: 이달의 챌린지

### 동작 방식
- 매월 자동으로 챌린지 생성 (월 단위 초기화)
- 동아리 admin이 아카이브에서 대표 공연을 **챌린지에 제출**
- 앱 전체 유저가 좋아요로 투표
- 실시간 랭킹 화면 (D-day 카운트다운 + 참가 동아리 수)
- 월말 결과 발표: 1위 트로피 카드 + 링크/SNS 공유 버튼
- 1위 동아리 프로필에 "이달의 챔피언" 뱃지 부여

### DB 변경
- `challenges` 테이블 신규:
  ```
  id, year_month (YYYY-MM), is_active, created_at
  ```
- `challenge_entries` 테이블 신규:
  ```
  id, challenge_id, club_id, performance_id,
  likes_count, created_at
  ```

### 무료/유료 구분
- **무료:** 챌린지 참가 가능
- **유료(PRO):** 랭킹 페이지 우선 노출, 조회수·유입 경로 분석 데이터 제공

---

## 기능 4: 공개 웹 랭킹 페이지

### 동작 방식
- `stagemate.app/ranking`: 이달의 TOP 동아리 + 공연 영상 목록
  - 1위: 대형 카드 (썸네일 + 좋아요 + 조회수)
  - 2위~: 리스트 카드
  - 하단 "우리 동아리도 도전하세요 → 앱 받기" CTA
- `stagemate.app/clubs/{id}`: 동아리 공개 프로필 + 공연 아카이브 전체
- 로그인 불필요, 모바일 반응형

### 기술 구현
- FastAPI + Jinja2 HTML 템플릿으로 서빙
- 별도 프론트엔드 프레임워크 불필요
- 새 공개 API 엔드포인트:
  - `GET /public/ranking` — 이달의 챌린지 랭킹 (인증 불필요)
  - `GET /public/clubs/{club_id}` — 동아리 공개 프로필 + 아카이브 (인증 불필요)

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
- `feed_screen.dart`: YouTube 썸네일 카드 렌더링
- `performance_archive_screen.dart`: 신규 화면
- `challenge_screen.dart`: 신규 화면

### FastAPI 백엔드
- `posts` 테이블 마이그레이션 (youtube_url 추가)
- `performances`, `challenges`, `challenge_entries` 테이블 신규
- 공연 CRUD API, 챌린지 API, 공개 API 엔드포인트
- Jinja2 웹 페이지 (ranking, club profile)

### 의존성 추가 없음
- YouTube 썸네일: 외부 URL 직접 로드 (API 키 불필요)
- 웹 페이지: Jinja2는 FastAPI에 이미 포함

---

## 비고
- 앱 로고: 현재 초록색 연필+무대 아이콘 사용 (웹 페이지 헤더 포함)
- 네이티브 HD 영상 업로드는 기존 S3/Cloudflare 스토리지 연동 필요 (별도 검토)
- iOS 심사: 구독 복원 버튼 플랜과 별개로 이 기능은 심사 영향 없음
