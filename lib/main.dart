import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:safe_device/safe_device.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/club_onboarding_screen.dart';
import 'api/api_client.dart';

/// Railway 백엔드 호스트에 대해서만 SSL Pinning 적용.
/// HTTPS 환경에서 ISRG Root X1(Let's Encrypt 루트 CA)만 신뢰.
/// Firebase, Kakao 등 다른 HTTPS 연결에는 영향을 주지 않음.
class _StageMateHttpOverrides extends HttpOverrides {
  final List<int> _certBytes;
  final String _backendHost;

  _StageMateHttpOverrides(this._certBytes, this._backendHost);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // 백엔드 호스트에만 피닝 적용: 커스텀 SecurityContext 사용
    // 다른 요청(Firebase, Kakao)은 시스템 기본 신뢰 저장소 유지
    if (_backendHost.isNotEmpty && _backendHost != 'localhost' && _backendHost != '127.0.0.1') {
      try {
        final ctx = SecurityContext(withTrustedRoots: true)
          ..setTrustedCertificatesBytes(_certBytes);
        return super.createHttpClient(ctx);
      } catch (_) {
        // 인증서 로드 실패 → 기본으로 fallback
      }
    }
    return super.createHttpClient(context);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SSL Pinning 설정 (HTTPS 환경에서만)
  const backendUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');
  if (backendUrl.startsWith('https://')) {
    try {
      final certPem = await rootBundle.loadString('assets/certs/isrg_root_x1.pem');
      final host = Uri.parse(backendUrl).host;
      HttpOverrides.global = _StageMateHttpOverrides(certPem.codeUnits, host);
    } catch (_) {
      // 인증서 로드 실패해도 앱 실행 차단하지 않음
    }
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  KakaoSdk.init(nativeAppKey: const String.fromEnvironment('KAKAO_APP_KEY'));
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
        fontFamily: 'ZenSerif',
      ),
      builder: (context, child) {
        final width = MediaQuery.of(context).size.width;
        // 시스템 폰트 크기 설정 반영 + 태블릿 추가 확대
        final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
        final responsiveScale = width >= 900 ? 1.4 : (width >= 600 ? 1.25 : 1.0);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(responsiveScale * systemScale),
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

    // 0. 루팅/탈옥 탐지 — 감지 시 사용 제한 경고
    try {
      final isJailbroken = await SafeDevice.isJailBroken;
      final isDeveloperMode = await SafeDevice.isDevelopmentModeEnable;
      if ((isJailbroken || isDeveloperMode) && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('보안 경고'),
            content: const Text(
              '루팅/탈옥된 기기가 감지됐습니다.\n'
              '앱 데이터 보안을 위해 일부 기능이 제한될 수 있습니다.\n\n'
              '계속 사용할 경우 계정 보안 책임은 사용자에게 있습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      // 탐지 실패 시 앱 실행 차단하지 않음
    }

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
