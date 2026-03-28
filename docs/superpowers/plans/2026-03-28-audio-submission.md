# 음원파일 제출 게시판 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 동아리 내 공연별 MP3 음원 제출 게시판을 구현한다 — 임원진이 공연을 생성하고, 팀장이 팀 음원(MP3)을 업로드/재제출하며, 임원진이 전체 제출 현황을 조회하고 앱 내에서 재생한다.

**Architecture:** 백엔드에 `performances` + `audio_submissions` 테이블 두 개를 추가하고, 기존 `require_admin` / `require_team_leader` 역할 의존성과 R2 presigned URL 업로드 흐름을 재사용한다. Flutter에서는 새 탭(`AudioSubmissionScreen`)을 홈 화면에 추가하고, `file_picker`로 MP3 선택, `audioplayers`로 앱 내 재생을 구현한다.

**Tech Stack:** FastAPI + SQLAlchemy + PostgreSQL (backend), Flutter + `file_picker ^6.0.0` + `audioplayers ^6.0.0` (frontend), Cloudflare R2 (스토리지)

---

## 파일 구조

### 신규 생성
| 파일 | 역할 |
|------|------|
| `lib/screens/audio_submission_screen.dart` | 음원 제출 탭 전체 UI (공연 목록, 제출 다이얼로그, 오디오 플레이어) |

### 수정
| 파일 | 변경 내용 |
|------|-----------|
| `backend/db_models.py` | `Performance`, `AudioSubmission` ORM 모델 추가 |
| `backend/models.py` | `PerformanceCreateRequest`, `AudioSubmissionRequest` Pydantic 모델 추가 |
| `backend/main.py` | 공연 CRUD 3개 + 제출 CRUD 4개 엔드포인트 추가 |
| `lib/api/api_client.dart` | 공연·제출 API 메서드 7개 추가 (주의: `getPresignedUrl`과 `reportStorage`는 이미 구현됨) |
| `pubspec.yaml` | `file_picker`, `audioplayers` 의존성 추가 |
| `lib/screens/home_screen.dart` | 음원 제출 탭 추가 (team_leader 이상) |

---

## Chunk 1: 백엔드

### Task 1: DB 모델 추가

**Files:**
- Modify: `C:/projects/performance-manager/backend/db_models.py` (파일 끝에 추가)

- [ ] **Step 1: db_models.py 파일 끝에 두 모델 추가**

```python
# ── 공연 테이블 ───────────────────────────────────
class Performance(Base):
    __tablename__ = "performances"

    id = Column(Integer, primary_key=True, index=True)
    club_id = Column(Integer, ForeignKey("clubs.id"), nullable=False)
    name = Column(String(100), nullable=False)
    performance_date = Column(String(10), nullable=True)   # "YYYY-MM-DD", 선택
    submission_deadline = Column(DateTime, nullable=True)  # 제출 마감일, 선택
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    submissions = relationship(
        "AudioSubmission", back_populates="performance",
        cascade="all, delete-orphan"
    )


# ── 음원 제출 테이블 ──────────────────────────────
class AudioSubmission(Base):
    __tablename__ = "audio_submissions"

    id = Column(Integer, primary_key=True, index=True)
    performance_id = Column(Integer, ForeignKey("performances.id"), nullable=False)
    club_id = Column(Integer, ForeignKey("clubs.id"), nullable=False)
    submitted_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    team_name = Column(String(50), nullable=False)
    song_title = Column(String(100), nullable=False)
    file_url = Column(String, nullable=False)       # R2 퍼블릭 URL
    file_size_mb = Column(Integer, nullable=False, default=0)
    submitted_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    performance = relationship("Performance", back_populates="submissions")
    submitter = relationship("User")

    # 팀장 한 명은 공연당 하나의 제출만 가능 (재제출 = UPDATE)
    __table_args__ = (
        UniqueConstraint("performance_id", "submitted_by", name="uq_audio_submission"),
    )
```

- [ ] **Step 2: 변경 확인**

```bash
cd C:/projects/performance-manager/backend
python -c "import db_models; print('Performance:', db_models.Performance.__tablename__); print('AudioSubmission:', db_models.AudioSubmission.__tablename__)"
```
Expected: `Performance: performances` + `AudioSubmission: audio_submissions` (오류 없음)

- [ ] **Step 3: 커밋**

```bash
git add backend/db_models.py
git commit -m "feat: add Performance and AudioSubmission ORM models"
```

---

### Task 2: Pydantic 요청 모델 추가

**Files:**
- Modify: `C:/projects/performance-manager/backend/models.py` (파일 끝에 추가)

- [ ] **Step 1: models.py 파일 끝에 추가**

```python
# ── 음원 제출 게시판 ──────────────────────────────

class PerformanceCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    performance_date: Optional[str] = Field(
        None, pattern=r'^\d{4}-\d{2}-\d{2}$',
        description="공연 날짜 YYYY-MM-DD (선택)"
    )
    submission_deadline: Optional[str] = Field(
        None,
        description="제출 마감일 ISO 8601 문자열 (선택), 예: 2025-09-01T23:59:00"
    )

    @field_validator('name')
    @classmethod
    def name_no_html(cls, v: str) -> str:
        if re.search(r'[<>"\'&]', v):
            raise ValueError('공연명에 특수문자(<, >, ", \', &)를 사용할 수 없습니다.')
        return v.strip()


class AudioSubmissionRequest(BaseModel):
    team_name: str = Field(..., min_length=1, max_length=50)
    song_title: str = Field(..., min_length=1, max_length=100)
    file_url: str = Field(..., min_length=1, max_length=2048)
    file_size_mb: int = Field(..., ge=0, le=200)  # 최대 200MB

    @field_validator('team_name', 'song_title')
    @classmethod
    def no_html(cls, v: str) -> str:
        if re.search(r'[<>"\'&]', v):
            raise ValueError('특수문자(<, >, ", \', &)를 사용할 수 없습니다.')
        return v.strip()

    @field_validator('file_url')
    @classmethod
    def validate_file_url(cls, v: str) -> str:
        if not re.match(r'^https?://', v):
            raise ValueError('file_url은 http:// 또는 https://로 시작해야 합니다.')
        if not v.lower().endswith('.mp3'):
            raise ValueError('MP3 파일만 허용됩니다.')
        return v
```

- [ ] **Step 2: 변경 확인**

```bash
python -c "from models import PerformanceCreateRequest, AudioSubmissionRequest; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: 커밋**

```bash
git add backend/models.py
git commit -m "feat: add PerformanceCreateRequest and AudioSubmissionRequest Pydantic models"
```

---

### Task 3: 공연 API 엔드포인트

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py`

main.py에서 `# ── 구독 / 플랜` 섹션 직전(또는 파일 끝 직전)에 아래 4개 엔드포인트를 추가한다.

- [ ] **Step 1: main.py 상단 imports 확인**

`models.py`에서 `PerformanceCreateRequest`와 `AudioSubmissionRequest`를 이미 import하는지 확인한다. main.py 첫 10줄에 `from models import` 구문이 있을 것이다. 해당 줄에 두 모델을 추가한다:

기존:
```python
from models import (
    ...
    BoostRequest,
)
```

추가:
```python
from models import (
    ...
    BoostRequest,
    PerformanceCreateRequest,
    AudioSubmissionRequest,
)
```

- [ ] **Step 2: 공연 엔드포인트 추가**

`GET /clubs/{club_id}/subscription` 엔드포인트 이후 적당한 위치에 추가:

```python
# ════════════════════════════════════════════════
#  음원 제출 게시판 — 공연 관리
# ════════════════════════════════════════════════

@app.post("/clubs/{club_id}/performances")
def create_performance(
    club_id: int,
    req: PerformanceCreateRequest,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    """공연 생성 (임원진 이상)"""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    deadline = None
    if req.submission_deadline:
        try:
            from datetime import datetime as dt
            deadline = dt.fromisoformat(req.submission_deadline)
        except ValueError:
            raise HTTPException(status_code=400, detail="submission_deadline 형식이 올바르지 않습니다.")

    perf = db_models.Performance(
        club_id=club_id,
        name=req.name,
        performance_date=req.performance_date,
        submission_deadline=deadline,
        created_by=member.user_id,
    )
    db.add(perf)
    db.commit()
    db.refresh(perf)
    return {"id": perf.id, "message": "공연이 등록됐습니다."}


@app.get("/clubs/{club_id}/performances")
def list_performances(
    club_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_team_leader),
):
    """공연 목록 조회 (팀장 이상)"""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    perfs = (
        db.query(db_models.Performance)
        .filter(db_models.Performance.club_id == club_id)
        .order_by(db_models.Performance.created_at.desc())
        .all()
    )
    return [
        {
            "id": p.id,
            "name": p.name,
            "performance_date": p.performance_date,
            "submission_deadline": (
                p.submission_deadline.isoformat() if p.submission_deadline else None
            ),
            "submission_count": len(p.submissions),
            "created_at": p.created_at.strftime("%Y-%m-%d"),
        }
        for p in perfs
    ]


@app.delete("/clubs/{club_id}/performances/{perf_id}")
def delete_performance(
    club_id: int,
    perf_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    """공연 삭제 (임원진 이상, cascade로 음원 제출도 삭제)"""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    perf = db.query(db_models.Performance).filter(
        db_models.Performance.id == perf_id,
        db_models.Performance.club_id == club_id,
    ).first()
    if not perf:
        raise HTTPException(status_code=404, detail="공연을 찾을 수 없습니다.")

    db.delete(perf)
    db.commit()
    return {"message": "공연이 삭제됐습니다."}
```

- [ ] **Step 3: 서버 임포트 확인 (syntax check)**

```bash
cd C:/projects/performance-manager/backend
python -c "import main; print('syntax OK')"
```
Expected: `syntax OK`

- [ ] **Step 4: 커밋**

```bash
git add backend/main.py
git commit -m "feat: performance CRUD endpoints (임원진/팀장 권한)"
```

---

### Task 4: 음원 제출 API 엔드포인트

**Files:**
- Modify: `C:/projects/performance-manager/backend/main.py` (Task 3 추가 내용 이후)

- [ ] **Step 1: 음원 제출 엔드포인트 4개 추가**

```python
# ════════════════════════════════════════════════
#  음원 제출 게시판 — 제출 관리
# ════════════════════════════════════════════════

@app.post("/clubs/{club_id}/performances/{perf_id}/submissions")
def upsert_submission(
    club_id: int,
    perf_id: int,
    req: AudioSubmissionRequest,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_team_leader),
):
    """음원 제출 / 재제출 (팀장 이상). 같은 공연에 이미 제출했으면 덮어씀."""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    perf = db.query(db_models.Performance).filter(
        db_models.Performance.id == perf_id,
        db_models.Performance.club_id == club_id,
    ).first()
    if not perf:
        raise HTTPException(status_code=404, detail="공연을 찾을 수 없습니다.")

    existing = db.query(db_models.AudioSubmission).filter(
        db_models.AudioSubmission.performance_id == perf_id,
        db_models.AudioSubmission.submitted_by == member.user_id,
    ).first()

    if existing:
        # 덮어쓰기
        existing.team_name = req.team_name
        existing.song_title = req.song_title
        existing.file_url = req.file_url
        existing.file_size_mb = req.file_size_mb
        existing.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(existing)
        return {"id": existing.id, "message": "음원이 업데이트됐습니다."}
    else:
        sub = db_models.AudioSubmission(
            performance_id=perf_id,
            club_id=club_id,
            submitted_by=member.user_id,
            team_name=req.team_name,
            song_title=req.song_title,
            file_url=req.file_url,
            file_size_mb=req.file_size_mb,
        )
        db.add(sub)
        db.commit()
        db.refresh(sub)
        return {"id": sub.id, "message": "음원이 제출됐습니다."}


@app.get("/clubs/{club_id}/performances/{perf_id}/submissions")
def list_submissions(
    club_id: int,
    perf_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_admin),
):
    """모든 제출 목록 조회 (임원진 이상)"""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    subs = db.query(db_models.AudioSubmission).filter(
        db_models.AudioSubmission.performance_id == perf_id,
        db_models.AudioSubmission.club_id == club_id,
    ).order_by(db_models.AudioSubmission.updated_at.desc()).all()

    return [
        {
            "id": s.id,
            "team_name": s.team_name,
            "song_title": s.song_title,
            "file_url": s.file_url,
            "file_size_mb": s.file_size_mb,
            "submitter_name": s.submitter.display_name if s.submitter else "탈퇴한 사용자",
            "submitted_at": s.submitted_at.strftime("%Y-%m-%d %H:%M"),
            "updated_at": s.updated_at.strftime("%Y-%m-%d %H:%M") if s.updated_at else None,
        }
        for s in subs
    ]


@app.get("/clubs/{club_id}/performances/{perf_id}/submissions/mine")
def get_my_submission(
    club_id: int,
    perf_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_team_leader),
):
    """내 제출 현황 조회 (팀장 이상). 없으면 null 반환."""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    sub = db.query(db_models.AudioSubmission).filter(
        db_models.AudioSubmission.performance_id == perf_id,
        db_models.AudioSubmission.submitted_by == member.user_id,
    ).first()

    if not sub:
        return {"submission": None}

    return {
        "submission": {
            "id": sub.id,
            "team_name": sub.team_name,
            "song_title": sub.song_title,
            "file_url": sub.file_url,
            "file_size_mb": sub.file_size_mb,
            "updated_at": sub.updated_at.strftime("%Y-%m-%d %H:%M") if sub.updated_at else None,
        }
    }


@app.delete("/clubs/{club_id}/performances/{perf_id}/submissions/{sub_id}")
def delete_submission(
    club_id: int,
    perf_id: int,
    sub_id: int,
    db: Session = Depends(get_db),
    member: db_models.ClubMember = Depends(require_team_leader),
):
    """음원 제출 삭제 (본인만)"""
    if member.club_id != club_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    sub = db.query(db_models.AudioSubmission).filter(
        db_models.AudioSubmission.id == sub_id,
        db_models.AudioSubmission.performance_id == perf_id,
        db_models.AudioSubmission.club_id == club_id,
    ).first()
    if not sub:
        raise HTTPException(status_code=404, detail="제출을 찾을 수 없습니다.")
    if sub.submitted_by != member.user_id:
        raise HTTPException(status_code=403, detail="본인의 제출만 삭제할 수 있습니다.")

    db.delete(sub)
    db.commit()
    return {"message": "제출이 삭제됐습니다."}
```

- [ ] **Step 2: syntax check**

```bash
python -c "import main; print('syntax OK')"
```
Expected: `syntax OK`

- [ ] **Step 3: 커밋**

```bash
git add backend/main.py
git commit -m "feat: audio submission CRUD endpoints (upsert/list/mine/delete)"
```

---

## Chunk 2: Flutter 의존성 & ApiClient

### Task 5: pubspec.yaml 의존성 추가

**Files:**
- Modify: `C:/projects/performance_manager/pubspec.yaml`

- [ ] **Step 1: 두 패키지 추가**

`in_app_purchase: ^3.2.0` 아래에 추가:

```yaml
  in_app_purchase: ^3.2.0
  file_picker: ^6.0.0       # MP3 파일 선택
  audioplayers: ^6.0.0      # 앱 내 오디오 재생
```

- [ ] **Step 2: pub get**

```bash
cd C:/projects/performance_manager
flutter pub get
```
Expected: `Got dependencies!` (오류 없음)

- [ ] **Step 3: Android 권한 확인**

`android/app/src/main/AndroidManifest.xml`에 아래 권한이 없으면 추가:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<!-- Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
```

- [ ] **Step 4: 커밋**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml
git commit -m "feat: add file_picker and audioplayers dependencies"
```

---

### Task 6: ApiClient 메서드 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/api/api_client.dart`

> **전제**: `getPresignedUrl(filename, contentType, {int? clubId, int fileSizeMb = 0})` 와 `reportStorage(int clubId, String key)` 는 이전 Task 9 (구독/스토리지 작업)에서 이미 구현되어 있다. 아래 7개 메서드만 추가한다.

`boostPost` 메서드 끝(`}`) 직전에 아래를 추가 (클래스 닫는 `}` 전):

- [ ] **Step 1: 8개 메서드 추가**

```dart
  // ── 음원 제출 게시판 ──────────────────────────
  static Future<List<dynamic>> getPerformances(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as List;
  }

  static Future<Map<String, dynamic>> createPerformance(
    int clubId, {
    required String name,
    String? performanceDate,
    String? submissionDeadline,
  }) async {
    final body = <String, dynamic>{'name': name};
    if (performanceDate != null) body['performance_date'] = performanceDate;
    if (submissionDeadline != null) body['submission_deadline'] = submissionDeadline;
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/performances'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<void> deletePerformance(int clubId, int perfId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 404) throw Exception('공연을 찾을 수 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
  }

  static Future<List<dynamic>> getSubmissions(int clubId, int perfId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId/submissions'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as List;
  }

  static Future<Map<String, dynamic>?> getMySubmission(
      int clubId, int perfId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId/submissions/mine'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return body['submission'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> submitAudio(
    int clubId,
    int perfId, {
    required String teamName,
    required String songTitle,
    required String fileUrl,
    required int fileSizeMb,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId/submissions'),
      headers: await _headers(),
      body: jsonEncode({
        'team_name': teamName,
        'song_title': songTitle,
        'file_url': fileUrl,
        'file_size_mb': fileSizeMb,
      }),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 404) throw Exception('공연을 찾을 수 없습니다.');
    if (response.statusCode == 400) {
      try {
        final b = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = b['detail'];
        if (detail is String) throw Exception(detail);
        if (detail is List && detail.isNotEmpty) {
          throw Exception((detail.first['msg'] as String?) ?? '잘못된 입력입니다.');
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
      throw Exception('잘못된 입력입니다.');
    }
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<void> deleteSubmission(
      int clubId, int perfId, int subId) async {
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/clubs/$clubId/performances/$perfId/submissions/$subId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('본인의 제출만 삭제할 수 있습니다.');
    if (response.statusCode == 404) throw Exception('제출을 찾을 수 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
  }
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze lib/api/api_client.dart
```
Expected: 오류 없음

- [ ] **Step 3: 커밋**

```bash
git add lib/api/api_client.dart
git commit -m "feat: ApiClient audio submission methods"
```

---

## Chunk 3: Flutter 화면

### Task 7: audio_submission_screen.dart 생성

**Files:**
- Create: `C:/projects/performance_manager/lib/screens/audio_submission_screen.dart`

이 파일 하나에 모든 UI를 담는다. 4개의 위젯 클래스로 구성:
1. `AudioSubmissionScreen` — 탭 루트, 공연 목록
2. `_PerformanceCard` — 공연 카드 (역할별 다른 액션)
3. `_AdminSubmissionSheet` — 임원진용 전체 제출 목록 바텀시트 (오디오 플레이어 포함)
4. `_TeamLeaderSubmitSheet` — 팀장용 제출/재제출 바텀시트

- [ ] **Step 1: 파일 생성**

```dart
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';

// ── 음원 제출 메인 탭 화면 ──────────────────────────
class AudioSubmissionScreen extends StatefulWidget {
  final String role; // 'super_admin' | 'admin' | 'team_leader'

  const AudioSubmissionScreen({super.key, required this.role});

  @override
  State<AudioSubmissionScreen> createState() => _AudioSubmissionScreenState();
}

class _AudioSubmissionScreenState extends State<AudioSubmissionScreen> {
  List<dynamic> _performances = [];
  bool _isLoading = false;
  int? _clubId;

  bool get _isAdmin =>
      widget.role == 'super_admin' || widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final id = await ApiClient.getClubId();
      if (id == null) return;
      final perfs = await ApiClient.getPerformances(id);
      if (mounted) {
        setState(() {
          _clubId = id;
          _performances = perfs;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreatePerformanceDialog() async {
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '공연명 *',
                hintText: '예: 2025 봄 축제',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(
                labelText: '공연 날짜 (선택)',
                hintText: 'YYYY-MM-DD',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty || _clubId == null) return;

    try {
      await ApiClient.createPerformance(
        _clubId!,
        name: name,
        performanceDate: dateCtrl.text.trim().isEmpty ? null : dateCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공연이 등록됐습니다.'),
            backgroundColor: Colors.green,
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePerformance(dynamic perf) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 삭제'),
        content: Text(
          '\'${perf['name']}\' 공연과 모든 제출 파일을 삭제할까요?\n이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.deletePerformance(_clubId!, perf['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공연이 삭제됐습니다.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openPerformance(dynamic perf) {
    if (_clubId == null) return;
    if (_isAdmin) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _AdminSubmissionSheet(
          clubId: _clubId!,
          perf: perf,
          onChanged: _load,
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _TeamLeaderSubmitSheet(
          clubId: _clubId!,
          perf: perf,
          onChanged: _load,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('음원 제출'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _performances.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_off,
                              size: 56, color: colorScheme.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            _isAdmin
                                ? '등록된 공연이 없습니다.\n+ 버튼으로 추가하세요.'
                                : '등록된 공연이 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _performances.length,
                      itemBuilder: (_, i) => _PerformanceCard(
                        perf: _performances[i],
                        isAdmin: _isAdmin,
                        onTap: () => _openPerformance(_performances[i]),
                        onDelete: _isAdmin
                            ? () => _deletePerformance(_performances[i])
                            : null,
                      ),
                    ),
            ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreatePerformanceDialog,
              icon: const Icon(Icons.add),
              label: const Text('공연 추가'),
            )
          : null,
    );
  }
}


// ── 공연 카드 ────────────────────────────────────
class _PerformanceCard extends StatelessWidget {
  final dynamic perf;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PerformanceCard({
    required this.perf,
    required this.isAdmin,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = perf['submission_count'] as int? ?? 0;
    final date = perf['performance_date'] as String?;
    final deadline = perf['submission_deadline'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.library_music,
                    color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perf['name'] as String? ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.event,
                              size: 13, color: colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            date,
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ],
                    if (deadline != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 13, color: Colors.orange.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '마감: ${deadline.length > 10 ? deadline.substring(0, 10) : deadline}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade600),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count팀 제출',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Text(
                        '탭하여 제출하기',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.outline),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: colorScheme.error),
                  onPressed: onDelete,
                  tooltip: '삭제',
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}


// ── 임원진 제출 목록 바텀시트 ─────────────────────
class _AdminSubmissionSheet extends StatefulWidget {
  final int clubId;
  final dynamic perf;
  final VoidCallback onChanged;

  const _AdminSubmissionSheet({
    required this.clubId,
    required this.perf,
    required this.onChanged,
  });

  @override
  State<_AdminSubmissionSheet> createState() => _AdminSubmissionSheetState();
}

class _AdminSubmissionSheetState extends State<_AdminSubmissionSheet> {
  List<dynamic> _submissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final subs = await ApiClient.getSubmissions(
          widget.clubId, widget.perf['id'] as int);
      if (mounted) setState(() => _submissions = subs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // 핸들바
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.library_music),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.perf['name'] as String? ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${_submissions.length}팀 제출',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // 제출 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _submissions.isEmpty
                    ? Center(
                        child: Text(
                          '아직 제출된 음원이 없습니다.',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _submissions.length,
                        itemBuilder: (_, i) => _SubmissionTile(
                          sub: _submissions[i],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}


// ── 제출 항목 (플레이어 포함) ─────────────────────
class _SubmissionTile extends StatefulWidget {
  final dynamic sub;
  const _SubmissionTile({required this.sub});

  @override
  State<_SubmissionTile> createState() => _SubmissionTileState();
}

class _SubmissionTileState extends State<_SubmissionTile> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isExpanded = false;

  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playerState = s);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      final url = widget.sub['file_url'] as String;
      if (_playerState == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(url));
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaying = _playerState == PlayerState.playing;
    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.music_note,
                        size: 18,
                        color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sub['song_title'] as String? ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${widget.sub['team_name']} · ${widget.sub['submitter_name']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      isPlaying ? Icons.pause_circle : Icons.play_circle,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                    tooltip: isPlaying ? '일시정지' : '재생',
                  ),
                ],
              ),
              if (_isExpanded || isPlaying || _position > Duration.zero) ...[
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: _duration.inSeconds > 0
                        ? (v) {
                            final pos = Duration(
                                seconds:
                                    (v * _duration.inSeconds).round());
                            _player.seek(pos);
                          }
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.outline),
                    ),
                    Text(
                      _duration > Duration.zero
                          ? _formatDuration(_duration)
                          : '--:--',
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '업데이트: ${widget.sub['updated_at'] ?? widget.sub['submitted_at']}',
                  style:
                      TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


// ── 팀장 제출/재제출 바텀시트 ─────────────────────
class _TeamLeaderSubmitSheet extends StatefulWidget {
  final int clubId;
  final dynamic perf;
  final VoidCallback onChanged;

  const _TeamLeaderSubmitSheet({
    required this.clubId,
    required this.perf,
    required this.onChanged,
  });

  @override
  State<_TeamLeaderSubmitSheet> createState() =>
      _TeamLeaderSubmitSheetState();
}

class _TeamLeaderSubmitSheetState extends State<_TeamLeaderSubmitSheet> {
  Map<String, dynamic>? _mySubmission;
  bool _isLoading = true;
  bool _isUploading = false;
  String _uploadStatus = '';

  final _teamNameCtrl = TextEditingController();
  final _songTitleCtrl = TextEditingController();

  // 현재 제출의 오디오 플레이어
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.onPlayerStateChanged
          .listen((s) { if (mounted) setState(() => _playerState = s); }),
      _player.onPositionChanged
          .listen((p) { if (mounted) setState(() => _position = p); }),
      _player.onDurationChanged
          .listen((d) { if (mounted) setState(() => _duration = d); }),
    ];
    _load();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _songTitleCtrl.dispose();
    for (final s in _subs) s.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final sub = await ApiClient.getMySubmission(
          widget.clubId, widget.perf['id'] as int);
      if (mounted) {
        setState(() => _mySubmission = sub);
        if (sub != null) {
          _teamNameCtrl.text = sub['team_name'] as String? ?? '';
          _songTitleCtrl.text = sub['song_title'] as String? ?? '';
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndSubmit() async {
    // 1. MP3 파일 선택
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;

    final teamName = _teamNameCtrl.text.trim();
    final songTitle = _songTitleCtrl.text.trim();

    if (teamName.isEmpty || songTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀명과 곡 제목을 입력해주세요.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '파일 업로드 중...';
    });

    try {
      final file = File(picked.path!);
      final fileSize = await file.length();
      final fileSizeMb = (fileSize / (1024 * 1024)).ceil();

      if (fileSizeMb > 200) {
        throw Exception('파일이 너무 큽니다. 최대 200MB까지 업로드할 수 있어요.');
      }

      // 2. Presigned URL 획득 (MP3, club storage)
      final presigned = await ApiClient.getPresignedUrl(
        picked.name,
        'audio/mpeg',
        clubId: widget.clubId,
        fileSizeMb: fileSizeMb,
      );

      final uploadUrl = presigned['upload_url'] as String;
      final publicUrl = presigned['public_url'] as String;
      final storageKey = presigned['key'] as String;

      // 3. R2에 직접 업로드 (PUT)
      setState(() => _uploadStatus = 'R2에 업로드 중...');
      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'audio/mpeg'},
        body: bytes,
      );
      if (uploadResponse.statusCode != 200 &&
          uploadResponse.statusCode != 204) {
        throw Exception('파일 업로드 실패 (${uploadResponse.statusCode})');
      }

      // 4. 스토리지 사용량 신고
      setState(() => _uploadStatus = '처리 중...');
      await ApiClient.reportStorage(widget.clubId, storageKey);

      // 5. 음원 제출 API 호출
      await ApiClient.submitAudio(
        widget.clubId,
        widget.perf['id'] as int,
        teamName: teamName,
        songTitle: songTitle,
        fileUrl: publicUrl,
        fileSizeMb: fileSizeMb,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('음원이 제출됐습니다! 🎵'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onChanged();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteSubmission() async {
    if (_mySubmission == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제출 삭제'),
        content: const Text('제출한 음원을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.deleteSubmission(
        widget.clubId,
        widget.perf['id'] as int,
        _mySubmission!['id'] as int,
      );
      if (mounted) {
        setState(() => _mySubmission = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제출이 삭제됐습니다.')),
        );
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_mySubmission == null) return;
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else if (_playerState == PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(_mySubmission!['file_url'] as String));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 핸들바
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 공연명
              Text(
                widget.perf['name'] as String? ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '음원 제출',
                style: TextStyle(color: colorScheme.outline, fontSize: 13),
              ),
              const Divider(height: 24),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // 현재 제출 현황
                if (_mySubmission != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16, color: Colors.green.shade600),
                            const SizedBox(width: 6),
                            const Text(
                              '제출 완료',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _mySubmission!['updated_at'] ??
                                  _mySubmission!['submitted_at'] ??
                                  '',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '🎵 ${_mySubmission!['song_title']}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '팀: ${_mySubmission!['team_name']}',
                          style: TextStyle(
                              fontSize: 12, color: colorScheme.outline),
                        ),
                        const SizedBox(height: 10),
                        // 미니 플레이어
                        Row(
                          children: [
                            IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                _playerState == PlayerState.playing
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                size: 36,
                                color: colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                              enabledThumbRadius: 5),
                                    ),
                                    child: Slider(
                                      value: (_duration.inSeconds > 0
                                              ? _position.inSeconds /
                                                  _duration.inSeconds
                                              : 0.0)
                                          .clamp(0.0, 1.0),
                                      onChanged: _duration.inSeconds > 0
                                          ? (v) {
                                              _player.seek(Duration(
                                                  seconds: (v *
                                                          _duration
                                                              .inSeconds)
                                                      .round()));
                                            }
                                          : null,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_fmt(_position),
                                          style: const TextStyle(
                                              fontSize: 10)),
                                      Text(
                                          _duration > Duration.zero
                                              ? _fmt(_duration)
                                              : '--:--',
                                          style: const TextStyle(
                                              fontSize: 10)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: colorScheme.error, size: 20),
                              onPressed: _deleteSubmission,
                              tooltip: '제출 삭제',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '재제출',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  const Text(
                    '아직 제출하지 않았습니다.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                ],

                // 팀명, 곡 제목 입력
                TextField(
                  controller: _teamNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '팀명 *',
                    hintText: '예: A팀',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _songTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: '곡 제목 *',
                    hintText: '예: 불꽃놀이',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(height: 20),

                if (_isUploading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _uploadStatus,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                FilledButton.icon(
                  onPressed: _isUploading ? null : _pickAndSubmit,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_mySubmission != null ? '재제출 (MP3)' : 'MP3 파일 선택 & 제출'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'MP3 파일만 허용 · 최대 200MB',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze lib/screens/audio_submission_screen.dart
```
Expected: 오류 없음

- [ ] **Step 3: 커밋**

```bash
git add lib/screens/audio_submission_screen.dart
git commit -m "feat: AudioSubmissionScreen with player, upload, admin/teamleader views"
```

---

### Task 8: home_screen.dart에 탭 추가

**Files:**
- Modify: `C:/projects/performance_manager/lib/screens/home_screen.dart`

- [ ] **Step 1: import 추가**

파일 상단 import 목록에 추가:
```dart
import 'audio_submission_screen.dart';
```

- [ ] **Step 2: 권한 헬퍼 추가**

`_canManageClub` 다음 줄에:
```dart
  bool get _canSubmitAudio => widget.role != 'user';  // team_leader 이상
```

- [ ] **Step 3: `_screens` 리스트에 탭 추가**

`_screens` getter에서 `BookingScreen()` 다음, `ClubManageScreen()` 앞에 추가:
```dart
      if (_canSubmitAudio)
        AudioSubmissionScreen(role: widget.role),
```

- [ ] **Step 4: `_destinations` 리스트에 탭 추가**

`_destinations` getter에서 `연습실 예약` NavigationDestination 다음, `동아리 관리` 앞에 추가:
```dart
      if (_canSubmitAudio)
        const NavigationDestination(
          icon: Icon(Icons.audio_file),
          label: '음원 제출',
        ),
```

- [ ] **Step 5: flutter analyze**

```bash
flutter analyze lib/screens/home_screen.dart
```
Expected: 오류 없음

- [ ] **Step 6: 커밋**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add 음원 제출 tab to home screen (team_leader+)"
```

---

## 검증 방법

### 백엔드 검증
1. `python -c "import main"` → syntax 오류 없음
2. Railway 배포 후 `/docs` (Swagger UI)에서 공연 생성 → 성공
3. 팀장 토큰으로 음원 제출 → 성공, 재제출 시 덮어쓰기 확인
4. 일반 멤버로 `GET /clubs/{id}/performances` 시도 → 403

### Flutter 검증
1. `flutter analyze` → 오류 없음
2. team_leader 계정으로 로그인 → "음원 제출" 탭 표시됨
3. 일반 멤버 계정으로 로그인 → 탭 없음
4. MP3 파일 선택 → 업로드 진행 표시 → 제출 완료 스낵바
5. 동일 공연 재제출 → 기존 내용 덮어씌움
6. 임원진으로 로그인 → 제출 바텀시트에서 모든 팀 목록 + 재생 버튼 작동
