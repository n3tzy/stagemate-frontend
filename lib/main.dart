import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/club_onboarding_screen.dart';
import 'api/api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const kakaoKey = String.fromEnvironment('KAKAO_APP_KEY');
  KakaoSdk.init(nativeAppKey: kakaoKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StageMate',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7DB96B), // 피스타치오 그린
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // UI 크롬(탭·버튼·레이블): ZenSerif (한글은 시스템 폰트 fallback)
        // 콘텐츠 제목: 아리따 부리 / 콘텐츠 본문: 이롭게 바탕체
        fontFamily: 'ZenSerif',
        textTheme: const TextTheme(
          // 화면 타이틀, 게시글 제목 등 헤드라인 → 아리따 부리
          displayLarge:   TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w700),
          displayMedium:  TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w700),
          displaySmall:   TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w600),
          headlineLarge:  TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w600),
          headlineSmall:  TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w600),
          titleLarge:     TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w600),
          titleMedium:    TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w400),
          titleSmall:     TextStyle(fontFamily: 'AritaBuri', fontWeight: FontWeight.w400),
          // 게시글 내용, 본문 텍스트 → 이롭게 바탕체
          bodyLarge:      TextStyle(fontFamily: 'IropkeBatang'),
          bodyMedium:     TextStyle(fontFamily: 'IropkeBatang'),
          bodySmall:      TextStyle(fontFamily: 'IropkeBatang'),
          // 버튼·칩·레이블 → ZenSerif (기본값 상속)
          labelLarge:     TextStyle(fontFamily: 'ZenSerif'),
          labelMedium:    TextStyle(fontFamily: 'ZenSerif'),
          labelSmall:     TextStyle(fontFamily: 'ZenSerif'),
        ),
      ),
      builder: (context, child) {
        // 시스템 글꼴 크기 설정을 그대로 존중 (iOS/Android 접근성)
        // 태블릿에서만 약간 확대하되, 최대 1.8배로 제한
        final width = MediaQuery.of(context).size.width;
        final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
        final responsiveScale = width >= 900 ? 1.3 : (width >= 600 ? 1.15 : 1.0);
        final combined = (responsiveScale * systemScale).clamp(0.8, 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(combined),
          ),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}

// 앱 시작 시 토큰 + 동아리 확인 화면
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _checkToken() async {
    await Future.delayed(const Duration(milliseconds: 300));

    // 1. 로컬 토큰 확인
    final token = await ApiClient.getToken();
    if (token == null) {
      _navigateTo(const LoginScreen());
      return;
    }

    // 2. 클라이언트 측 만료 체크 (서버 호출 없이 빠른 확인)
    if (ApiClient.isTokenExpired(token)) {
      await ApiClient.logout();
      _navigateTo(const LoginScreen());
      return;
    }

    // 3. 서버 측 실제 유효성 검증 (취소된 계정, 비밀번호 변경 등 대비)
    final isValid = await ApiClient.verifyToken();
    if (!isValid) {
      await ApiClient.logout();
      _navigateTo(const LoginScreen());
      return;
    }

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
      (selectedClub['club_id'] as num).toInt(),
      selectedClub['club_name'] as String,
      selectedClub['role'] as String,
    );

    _navigateTo(HomeScreen(
      displayName: displayName,
      role: selectedClub['role'] as String,
      clubName: selectedClub['club_name'] as String,
      clubs: clubs.cast<Map<String, dynamic>>(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 16),
            Text(
              'StageMate',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
