# 다중 동아리 지원 + 엑셀 다운로드 알림 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한 사용자가 여러 동아리를 앱바에서 바로 전환할 수 있게 하고, 엑셀 파일 저장 후 상태바 알림(탭하면 파일 열기)을 추가한다.

**Architecture:** HomeScreen에 `clubs` 리스트를 생성자로 전달하고, State 클래스에서 현재 동아리 정보를 관리한다. 동아리 2개 이상이면 앱바에 switcher 버튼이 표시되고, 탭 시 바텀시트에서 전환한다. 엑셀 알림은 `download_notification.dart`로 분리한다.

**Tech Stack:** Flutter (Dart), `flutter_local_notifications ^17.0.0`, `open_file ^3.3.2`, `flutter_secure_storage` (기존), FastAPI backend (변경 없음)

---

## Chunk 1: HomeScreen 생성자 확장 + 호출부 수정

### Task 1: HomeScreen에 `clubs` 파라미터 추가 + state 변수 도입

**Files:**
- Modify: `lib/screens/home_screen.dart:20-106`

- [ ] **Step 1: HomeScreen 위젯 생성자에 `clubs` 파라미터 추가**

  `home_screen.dart` line 20–32 (`HomeScreen` 클래스 선언부)를 다음과 같이 수정한다:

  ```dart
  class HomeScreen extends StatefulWidget {
    final String displayName;
    final String role;
    final String clubName;
    final List<Map<String, dynamic>> clubs; // 추가

    const HomeScreen({
      super.key,
      required this.displayName,
      required this.role,
      required this.clubName,
      required this.clubs, // 추가
    });

    @override
    State<HomeScreen> createState() => _HomeScreenState();
  }
  ```

- [ ] **Step 2: `_HomeScreenState`에 현재 동아리 상태 변수 추가**

  `_HomeScreenState` 클래스 상단 필드 선언부(기존 `int _currentIndex = 0;` 근처)에 추가:

  ```dart
  late String _currentRole;
  late String _currentClubName;
  late int _currentClubId;
  ```

- [ ] **Step 3: `initState()`에서 상태 변수 초기화 + async 초기화 메서드 추가**

  `initState()`는 sync여야 하므로, club_id 복원을 별도 async 메서드 `_initClub()`으로 분리한다.

  `_HomeScreenState` 클래스에 다음을 추가:

  ```dart
  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    _currentClubName = widget.clubName;
    _currentClubId = 0; // _initClub()에서 비동기로 확정
    _initClub();
    // 기존 initState 내용 유지 (FcmService.init, _loadUnreadCount 등)
  }

  Future<void> _initClub() async {
    // storage에서 마지막 사용 club_id를 읽어 widget.clubs와 대조
    final savedClubId = await ApiClient.getClubId();
    if (savedClubId != null && widget.clubs.isNotEmpty) {
      final matched = widget.clubs.firstWhere(
        (c) => (c['club_id'] as num).toInt() == savedClubId,
        orElse: () => widget.clubs[0],
      );
      if (mounted) {
        setState(() {
          _currentClubId = (matched['club_id'] as num).toInt();
          _currentClubName = matched['club_name'] as String;
          _currentRole = matched['role'] as String;
        });
      }
    } else if (widget.clubs.isNotEmpty) {
      final first = widget.clubs[0];
      if (mounted) {
        setState(() {
          _currentClubId = (first['club_id'] as num).toInt();
        });
      }
    }
  }
  ```

- [ ] **Step 4: `widget.role` → `_currentRole` 참조 교체**

  다음 위치를 모두 교체한다:

  | 위치 | 변경 전 | 변경 후 |
  |------|---------|---------|
  | line 88 | `widget.role == 'super_admin'` | `_currentRole == 'super_admin'` |
  | line 89 | `widget.role == 'admin'` | `_currentRole == 'admin'` |
  | line 92 | `widget.role == 'team_leader'` ... (3곳) | `_currentRole == 'team_leader'` 등 |
  | line 103 | `AudioSubmissionScreen(role: widget.role)` | `AudioSubmissionScreen(role: _currentRole)` |
  | line 145 | `switch (widget.role)` | `switch (_currentRole)` |
  | line 263 | `isCreator: widget.role == 'super_admin'` | `isCreator: _currentRole == 'super_admin'` |
  | line 265 | `role: widget.role` | `role: _currentRole` |

- [ ] **Step 5: `widget.clubName` → `_currentClubName` 교체**

  | 위치 | 변경 전 | 변경 후 |
  |------|---------|---------|
  | line 264 | `clubName: widget.clubName` | `clubName: _currentClubName` |
  | line 858 | `widget.clubName` (앱바 subtitle 텍스트) | `_currentClubName` |

- [ ] **Step 6: `flutter analyze`로 컴파일 오류 확인**

  ```bash
  cd C:/projects/performance_manager && flutter analyze lib/screens/home_screen.dart
  ```
  Expected: `No issues found!` (또는 `clubs:` 인자 누락 오류만 — 다음 task에서 수정)

---

### Task 2: HomeScreen 호출부 5곳에 `clubs:` 전달

**Files:**
- Modify: `lib/main.dart:82-124`
- Modify: `lib/screens/login_screen.dart:215-260, 275-300`
- Modify: `lib/screens/club_onboarding_screen.dart:395-438, 680-725`

- [ ] **Step 1: `login_screen.dart` — 일반 로그인 (line 244)**

  이미 `clubs` 변수가 있으므로 `HomeScreen(...)` 호출에 `clubs: clubs.cast<Map<String,dynamic>>()` 추가:

  ```dart
  builder: (_) => HomeScreen(
    displayName: data['display_name'],
    role: club['role'],
    clubName: club['club_name'],
    clubs: clubs.cast<Map<String, dynamic>>(),  // 추가
  ),
  ```

- [ ] **Step 2: `login_screen.dart` — 카카오 로그인 (line 291)**

  동일하게 `clubs: clubs.cast<Map<String, dynamic>>()` 추가.

- [ ] **Step 3: `club_onboarding_screen.dart` — 동아리 생성 후 (line 431)**

  이 경로는 방금 동아리를 생성한 직후라 `getMyClubs()`를 호출해야 한다:

  ```dart
  // showWelcomeDialog 이후, Navigator.pushAndRemoveUntil 이전에 추가
  final myClubs = await ApiClient.getMyClubs();
  if (!mounted) return;

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => HomeScreen(
        displayName: displayName,
        role: 'super_admin',
        clubName: _createdClub!['club_name'],
        clubs: myClubs.cast<Map<String, dynamic>>(),  // 추가
      ),
    ),
    (route) => false,
  );
  ```

- [ ] **Step 4: `club_onboarding_screen.dart` — 동아리 참가 후 (line 718)**

  동일하게 `getMyClubs()` 호출 후 전달:

  ```dart
  final myClubs = await ApiClient.getMyClubs();
  if (!mounted) return;

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => HomeScreen(
        displayName: displayName,
        role: data['role'],
        clubName: data['club_name'],
        clubs: myClubs.cast<Map<String, dynamic>>(),  // 추가
      ),
    ),
    (route) => false,
  );
  ```

- [ ] **Step 5: `main.dart` — SplashScreen `_checkToken()` 전면 교체**

  기존 step 4 (storage에서 clubId/role/clubName 읽는 분기 전체)를 `getMyClubs()` 기반으로 교체한다.
  기존 코드 (line 107–123):

  ```dart
  // 기존 — 제거
  final displayName = await ApiClient.getDisplayName();
  final role = await ApiClient.getRole();
  final clubName = await ApiClient.getClubName();
  final clubId = await ApiClient.getClubId();

  if (clubId != null && role != null && ...) {
    _navigateTo(HomeScreen(displayName: ..., role: ..., clubName: ...));
  } else {
    _navigateTo(const ClubOnboardingScreen());
  }
  ```

  교체 후:

  ```dart
  // 4. 서버에서 내 동아리 목록 조회
  final displayName = await ApiClient.getDisplayName() ?? '';
  List<dynamic> clubs;
  try {
    clubs = await ApiClient.getMyClubs();
  } catch (_) {
    clubs = [];
  }

  if (clubs.isEmpty) {
    _navigateTo(const ClubOnboardingScreen());
    return;
  }

  // 마지막 사용 동아리 복원
  final savedClubId = await ApiClient.getClubId();
  Map<String, dynamic> selectedClub;
  if (savedClubId != null) {
    selectedClub = clubs.firstWhere(
      (c) => c['club_id'] == savedClubId,
      orElse: () => clubs[0],
    ) as Map<String, dynamic>;
  } else {
    selectedClub = clubs[0] as Map<String, dynamic>;
  }

  await ApiClient.setClubInfo(
    selectedClub['club_id'],
    selectedClub['club_name'],
    selectedClub['role'],
  );

  _navigateTo(HomeScreen(
    displayName: displayName,
    role: selectedClub['role'],
    clubName: selectedClub['club_name'],
    clubs: clubs.cast<Map<String, dynamic>>(),
  ));
  ```

- [ ] **Step 6: `flutter analyze`로 전체 컴파일 오류 없는지 확인**

  ```bash
  cd C:/projects/performance_manager && flutter analyze
  ```
  Expected: `No issues found!`

- [ ] **Step 7: Commit**

  ```bash
  cd C:/projects/performance_manager
  git add lib/screens/home_screen.dart lib/main.dart lib/screens/login_screen.dart lib/screens/club_onboarding_screen.dart
  git commit -m "feat: pass clubs list to HomeScreen, migrate role/club state to local vars"
  ```

---

## Chunk 2: 동아리 switcher UI

### Task 3: 앱바 switcher 버튼 + `_ClubSwitcherSheet`

**Files:**
- Modify: `lib/screens/home_screen.dart` (앱바 영역 + 파일 하단에 위젯 추가)

- [ ] **Step 1: 역할 레이블 헬퍼 함수 추가**

  `_HomeScreenState` 클래스 내 아무 곳(예: `_roleBadgeColor` 근처)에 추가:

  ```dart
  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin': return '회장';
      case 'admin':       return '임원진';
      case 'team_leader': return '팀장';
      default:            return '멤버';
    }
  }
  ```

- [ ] **Step 2: 앱바 동아리 이름 부분을 조건부 switcher로 교체**

  `build()` 메서드의 앱바 내 `Column` 부분 (현재 'StageMate' + `_currentClubName` 텍스트):

  ```dart
  // 기존 Column children의 두 번째 Text(_currentClubName)를 아래로 교체
  if (widget.clubs.length >= 2)
    GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => _ClubSwitcherSheet(
            clubs: widget.clubs,
            currentClubId: _currentClubId,
            onSelect: (club) async {
              await ApiClient.setClubInfo(
                (club['club_id'] as num).toInt(),
                club['club_name'] as String,
                club['role'] as String,
              );
              setState(() {
                _currentClubId = (club['club_id'] as num).toInt();
                _currentClubName = club['club_name'] as String;
                _currentRole = club['role'] as String;
              });
            },
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, size: 12, color: Colors.white70),
          const SizedBox(width: 3),
          Text(
            '$_currentClubName · ${_roleLabel(_currentRole)}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onPrimaryContainer.withOpacity(0.85),
            ),
          ),
          const Icon(Icons.expand_more, size: 13, color: Colors.white70),
        ],
      ),
    )
  else
    Text(
      _currentClubName,
      style: TextStyle(
        fontSize: 11,
        color: colorScheme.onPrimaryContainer.withOpacity(0.7),
      ),
    ),
  ```

- [ ] **Step 3: `_ClubSwitcherSheet` 위젯을 파일 하단에 추가**

  `home_screen.dart` 맨 아래(마지막 `}` 전)에 추가:

  ```dart
  class _ClubSwitcherSheet extends StatelessWidget {
    final List<Map<String, dynamic>> clubs;
    final int currentClubId;
    final Future<void> Function(Map<String, dynamic> club) onSelect;

    const _ClubSwitcherSheet({
      required this.clubs,
      required this.currentClubId,
      required this.onSelect,
    });

    String _roleLabel(String role) {
      switch (role) {
        case 'super_admin': return '회장';
        case 'admin':       return '임원진';
        case 'team_leader': return '팀장';
        default:            return '멤버';
      }
    }

    @override
    Widget build(BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('동아리 선택',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('입장할 동아리를 선택하세요',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 14),
              ...clubs.map((club) {
                final isSelected = (club['club_id'] as num).toInt() == currentClubId;
                return GestureDetector(
                  onTap: isSelected
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await onSelect(club);
                        },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : Colors.grey[50],
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.grey[200]!,
                        width: isSelected ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : Colors.grey[400],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.theater_comedy,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                club['club_name'] as String,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _roleLabel(club['role'] as String),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isSelected
                                          ? colorScheme.primary
                                          : Colors.grey,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isSelected ? Icons.check : Icons.chevron_right,
                          color: isSelected
                              ? colorScheme.primary
                              : Colors.grey,
                        ),
                      ],
                    ),
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

- [ ] **Step 4: `flutter analyze` 실행**

  ```bash
  cd C:/projects/performance_manager && flutter analyze lib/screens/home_screen.dart
  ```
  Expected: `No issues found!`

- [ ] **Step 5: Commit**

  ```bash
  cd C:/projects/performance_manager
  git add lib/screens/home_screen.dart
  git commit -m "feat: add club switcher button in app bar with bottom sheet"
  ```

---

## Chunk 3: 엑셀 다운로드 시스템 알림

### Task 4: 패키지 추가 + `download_notification.dart` 신규 생성

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/utils/download_notification.dart`
- Modify: `lib/utils/excel_save_io.dart`

- [ ] **Step 1: `pubspec.yaml`에 패키지 추가**

  `dependencies:` 섹션에 추가:

  ```yaml
  flutter_local_notifications: ^17.0.0
  open_file: ^3.3.2
  ```

- [ ] **Step 2: 패키지 설치**

  ```bash
  cd C:/projects/performance_manager && flutter pub get
  ```
  Expected: `Got dependencies!`

- [ ] **Step 3: `lib/utils/download_notification.dart` 신규 작성**

  ```dart
  import 'dart:io';
  import 'package:flutter_local_notifications/flutter_local_notifications.dart';
  import 'package:open_file/open_file.dart';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initDownloadNotifications() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          OpenFile.open(payload);
        }
      },
    );
    _initialized = true;
  }

  Future<void> showDownloadNotification({
    required String filePath,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) return; // iOS는 no-op
    await initDownloadNotifications();

    // Android 13+ 런타임 권한 요청
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    const androidDetails = AndroidNotificationDetails(
      'downloads',
      '다운로드',
      channelDescription: '파일 다운로드 완료 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      0,
      '다운로드 완료',
      fileName,
      details,
      payload: filePath,
    );
  }
  ```

- [ ] **Step 4: `excel_save_io.dart`에서 알림 호출 추가**

  파일 저장 성공 후 `return filePath;` 직전에 알림 호출을 추가한다:

  ```dart
  import 'download_notification.dart'; // 파일 상단에 import 추가

  // saveExcelFile 함수 내 File(filePath).writeAsBytesSync(bytes); 다음 줄:
  File(filePath).writeAsBytesSync(bytes);

  // 알림 표시 (비동기, 실패해도 무시)
  showDownloadNotification(
    filePath: filePath,
    fileName: fileName,
  ).catchError((_) {});

  return filePath;
  ```

- [ ] **Step 5: `flutter analyze` 실행**

  ```bash
  cd C:/projects/performance_manager && flutter analyze lib/utils/
  ```
  Expected: `No issues found!`

- [ ] **Step 6: Android manifest POST_NOTIFICATIONS 선언 확인**

  `flutter pub get` 후 다음 명령으로 merged manifest에 `POST_NOTIFICATIONS`가 있는지 확인:

  ```bash
  grep -r "POST_NOTIFICATIONS" C:/projects/performance_manager/android/
  ```

  결과가 없으면 `android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 바로 아래에 추가:

  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  ```

- [ ] **Step 7: Commit**

  ```bash
  cd C:/projects/performance_manager
  git add pubspec.yaml pubspec.lock lib/utils/download_notification.dart lib/utils/excel_save_io.dart android/app/src/main/AndroidManifest.xml
  git commit -m "feat: show system notification after excel download with open file action"
  ```

---

## 수동 검증 체크리스트

구현 완료 후 실기기(Android)에서 확인:

- [ ] **다중 동아리 — SplashScreen**: 앱 재시작 시 마지막 사용 동아리로 진입하는지 확인
- [ ] **다중 동아리 — 단일 동아리 사용자**: switcher 버튼이 표시되지 않고 동아리명만 표시되는지 확인
- [ ] **다중 동아리 — 전환**: 바텀시트에서 다른 동아리 선택 시 앱바가 즉시 업데이트되는지 확인
- [ ] **다중 동아리 — 탭 유지**: 피드 탭에서 동아리 전환 후 피드 탭이 유지되는지 확인
- [ ] **다중 동아리 — 권한 반영**: 전환 후 역할에 맞는 탭(무대순서, 음원제출 등)이 맞게 표시/숨김 되는지 확인
- [ ] **엑셀 — 알림**: 무대순서 화면에서 엑셀 내보내기 후 상태바에 알림이 표시되는지 확인
- [ ] **엑셀 — 파일 열기**: 알림 탭 후 Excel 또는 Google Sheets로 파일이 열리는지 확인
