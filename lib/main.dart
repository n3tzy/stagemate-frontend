import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/club_onboarding_screen.dart';
import 'api/api_client.dart';

void main() {
  KakaoSdk.init(nativeAppKey: 'KAKAO_KEY_REDACTED');
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
      ),
      builder: (context, child) {
        final width = MediaQuery.of(context).size.width;
        // 태블릿(600px 이상)은 텍스트 1.25배, 대형 태블릿(900px 이상)은 1.4배
        final textScale = width >= 900 ? 1.4 : (width >= 600 ? 1.25 : 1.0);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
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

    // 4. 토큰 유효 — 저장된 사용자 정보 확인
    final displayName = await ApiClient.getDisplayName();
    final role = await ApiClient.getRole();
    final clubName = await ApiClient.getClubName();
    final clubId = await ApiClient.getClubId();

    if (clubId != null && role != null && clubName != null && displayName != null) {
      // 토큰 + 동아리 정보 모두 있으면 홈으로
      _navigateTo(HomeScreen(
        displayName: displayName,
        role: role,
        clubName: clubName,
      ));
    } else {
      // 토큰은 있지만 동아리 미선택 → 온보딩
      _navigateTo(const ClubOnboardingScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎭', style: TextStyle(fontSize: 60)),
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
