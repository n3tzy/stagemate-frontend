import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '../api/api_client.dart';
import 'club_onboarding_screen.dart';
import 'home_screen.dart';

// ── 공통 입력 검증 헬퍼 ────────────────────────────────
bool isValidUsername(String v) => RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(v);

bool isStrongPassword(String v) =>
    v.length >= 8 &&
    v.contains(RegExp(r'[A-Z]')) &&
    v.contains(RegExp(r'[a-z]')) &&
    v.contains(RegExp(r'\d'));


// ── 로그인 화면 ────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _showFindIdDialog() async {
    final emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        bool isSending = false;
        return StatefulBuilder(
          builder: (ctx, setDs) => AlertDialog(
            title: const Text('아이디 찾기'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('가입 시 등록한 이메일 주소를 입력하면\n아이디를 발송해 드립니다.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) return;
                        setDs(() => isSending = true);
                        try {
                          await ApiClient.findId(email);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('이메일을 확인하세요. 아이디를 발송했습니다.'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        } catch (e) {
                          setDs(() => isSending = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(friendlyError(e))),
                          );
                        }
                      },
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('발송'),
              ),
            ],
          ),
        );
      },
    );
    emailController.dispose();
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        bool isSending = false;
        return StatefulBuilder(
          builder: (ctx, setDs) => AlertDialog(
            title: const Text('비밀번호 재설정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('가입 시 등록한 이메일 주소를 입력하면\n임시 비밀번호를 발송해 드립니다.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) return;
                        setDs(() => isSending = true);
                        try {
                          await ApiClient.forgotPassword(email);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '이메일을 확인하세요. 임시 비밀번호가 발송됐습니다.',
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        } catch (e) {
                          setDs(() => isSending = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(friendlyError(e))),
                          );
                        }
                      },
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('발송'),
              ),
            ],
          ),
        );
      },
    );
    emailController.dispose();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // 클라이언트 측 입력 검증
    if (username.isEmpty || password.isEmpty) {
      _showError('아이디와 비밀번호를 입력해주세요.');
      return;
    }
    if (username.length < 3) {
      _showError('아이디는 3자 이상이어야 합니다.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.login(
        username: username,
        password: password,
      );

      if (!mounted) return;

      if (data.containsKey('access_token')) {
        // 내가 속한 동아리 확인
        final clubs = await ApiClient.getMyClubs();
        if (!mounted) return;

        if (clubs.isEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ClubOnboardingScreen()),
          );
        } else {
          // 동아리 1개 이상 → 첫 번째 자동 선택
          final club = clubs[0];
          await ApiClient.setClubInfo(
            club['club_id'],
            club['club_name'],
            club['role'],
          );
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                displayName: data['display_name'],
                role: club['role'],
                clubName: club['club_name'],
              ),
            ),
          );
        }
      } else {
        _showError(data['detail'] ?? '로그인 실패');
      }
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _kakaoLogin() async {
    setState(() => _isLoading = true);
    try {
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      final data = await ApiClient.kakaoLogin(token.accessToken);
      if (!mounted) return;

      if (data.containsKey('access_token')) {
        final clubs = await ApiClient.getMyClubs();
        if (!mounted) return;

        if (clubs.isEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ClubOnboardingScreen()),
          );
        } else {
          final club = clubs[0];
          await ApiClient.setClubInfo(club['club_id'], club['club_name'], club['role']);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                displayName: data['display_name'],
                role: club['role'],
                clubName: club['club_name'],
              ),
            ),
          );
        }
      } else {
        _showError('카카오 로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // 사용자가 직접 취소한 경우 에러 메시지 표시 안 함
      if (msg.contains('canceled') || msg.contains('cancel') || msg.contains('user_cancelled') ||
          msg.contains('webauthnticationsession error 1') || msg.contains('error 1')) {
        return;
      }
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.theater_comedy_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'StageMate',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '동아리 공연의 든든한 파트너',
                style: TextStyle(color: colorScheme.outline),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '아이디',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _login,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('로그인', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Divider(color: colorScheme.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('또는', style: TextStyle(color: colorScheme.outline, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: colorScheme.outlineVariant)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _kakaoLogin,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF191919),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'K  카카오로 시작하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _showFindIdDialog(),
                    child: Text(
                      '아이디 찾기',
                      style: TextStyle(color: colorScheme.outline, fontSize: 13),
                    ),
                  ),
                  Text('|', style: TextStyle(color: colorScheme.outlineVariant, fontSize: 13)),
                  TextButton(
                    onPressed: () => _showForgotPasswordDialog(),
                    child: Text(
                      '비밀번호 찾기',
                      style: TextStyle(color: colorScheme.outline, fontSize: 13),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen()),
                  );
                },
                child: const Text('계정이 없으신가요? 회원가입'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ── 회원가입 화면 ─────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _displayNameFocus = FocusNode();
  final _nicknameFocus = FocusNode();
  final _emailFocus = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool? _usernameAvailable;
  bool? _displayNameAvailable;
  bool? _nicknameAvailable;
  bool? _emailAvailable;

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(() {
      if (!_usernameFocus.hasFocus) {
        final v = _usernameController.text.trim();
        if (v.isNotEmpty) _checkUsername(v);
      }
    });
    _displayNameFocus.addListener(() {
      if (!_displayNameFocus.hasFocus) {
        final v = _displayNameController.text.trim();
        if (v.isNotEmpty) _checkDisplayName(v);
      }
    });
    _nicknameFocus.addListener(() {
      if (!_nicknameFocus.hasFocus) {
        final v = _nicknameController.text.trim();
        if (v.isNotEmpty) _checkNickname(v);
      }
    });
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) {
        final v = _emailController.text.trim();
        if (v.isNotEmpty) _checkEmail(v);
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameFocus.dispose();
    _displayNameFocus.dispose();
    _nicknameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _checkUsername(String value) async {
    if (!isValidUsername(value)) return;
    try {
      final available = await ApiClient.checkUsername(value);
      if (mounted) setState(() => _usernameAvailable = available);
    } catch (_) {}
  }

  Future<void> _checkDisplayName(String value) async {
    try {
      final available = await ApiClient.checkDisplayName(value);
      if (mounted) setState(() => _displayNameAvailable = available);
    } catch (_) {}
  }

  Future<void> _checkNickname(String value) async {
    if (value.length < 2 || value.length > 20) return;
    try {
      final available = await ApiClient.checkNickname(value);
      if (mounted) setState(() => _nicknameAvailable = available);
    } catch (_) {}
  }

  Future<void> _checkEmail(String value) async {
    if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(value)) return;
    try {
      final available = await ApiClient.checkEmail(value);
      if (mounted) setState(() => _emailAvailable = available);
    } catch (_) {}
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    // 클라이언트 측 입력 검증 (서버와 동일 기준)
    if (username.isEmpty || displayName.isEmpty || nickname.isEmpty ||
        email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showError('모든 항목을 입력해주세요.');
      return;
    }
    if (_usernameAvailable == false) {
      _showError('이미 사용 중인 아이디입니다.');
      return;
    }
    if (_displayNameAvailable == false) {
      _showError('이미 사용 중인 닉네임입니다.');
      return;
    }
    if (_nicknameAvailable == false) {
      _showError('이미 사용 중인 커뮤니티 닉네임입니다.');
      return;
    }
    if (nickname.length < 2 || nickname.length > 20) {
      _showError('커뮤니티 닉네임은 2~20자여야 합니다.');
      return;
    }
    if (_emailAvailable == false) {
      _showError('이미 사용 중인 이메일입니다.');
      return;
    }
    if (!isValidUsername(username)) {
      _showError('아이디는 영문·숫자·언더스코어(_)만 사용 가능하며, 3~20자여야 합니다.');
      return;
    }
    if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      _showError('올바른 이메일 형식을 입력해주세요.');
      return;
    }
    if (!isStrongPassword(password)) {
      _showError('비밀번호는 최소 8자 이상, 대문자·소문자·숫자를 각 1개 이상 포함해야 합니다.');
      return;
    }
    if (password != confirm) {
      _showError('비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.register(
        username: username,
        displayName: displayName,
        nickname: nickname,
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (data.containsKey('user_id')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? '회원가입 완료!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        _showError(data['detail'] ?? '회원가입 실패');
      }
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _usernameAvailable = null),
                decoration: InputDecoration(
                  labelText: '아이디',
                  hintText: '영문/숫자/_ 조합, 3~20자',
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                  suffixIcon: _usernameAvailable == null
                      ? null
                      : _usernameAvailable!
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                _usernameController.clear();
                                setState(() => _usernameAvailable = null);
                              },
                            ),
                  errorText: _usernameAvailable == false ? '이미 사용 중인 아이디입니다.' : null,
                  helperText: _usernameAvailable == true ? '사용 가능한 아이디입니다.' : null,
                  helperStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _displayNameController,
                focusNode: _displayNameFocus,
                onChanged: (_) => setState(() => _displayNameAvailable = null),
                decoration: InputDecoration(
                  labelText: '닉네임',
                  hintText: '앱에 표시될 이름',
                  prefixIcon: const Icon(Icons.badge),
                  border: const OutlineInputBorder(),
                  suffixIcon: _displayNameAvailable == null
                      ? null
                      : _displayNameAvailable!
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                _displayNameController.clear();
                                setState(() => _displayNameAvailable = null);
                              },
                            ),
                  errorText: _displayNameAvailable == false ? '이미 사용 중인 닉네임입니다.' : null,
                  helperText: _displayNameAvailable == true ? '사용 가능한 닉네임입니다.' : null,
                  helperStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nicknameController,
                focusNode: _nicknameFocus,
                onChanged: (_) => setState(() => _nicknameAvailable = null),
                decoration: InputDecoration(
                  labelText: '닉네임 (커뮤니티 표시명)',
                  hintText: '전체 채널에서 표시될 닉네임, 2~20자',
                  prefixIcon: const Icon(Icons.public),
                  border: const OutlineInputBorder(),
                  suffixIcon: _nicknameAvailable == null
                      ? null
                      : _nicknameAvailable!
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                _nicknameController.clear();
                                setState(() => _nicknameAvailable = null);
                              },
                            ),
                  errorText: _nicknameAvailable == false ? '이미 사용 중인 커뮤니티 닉네임입니다.' : null,
                  helperText: _nicknameAvailable == true ? '사용 가능한 커뮤니티 닉네임입니다.' : null,
                  helperStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _emailAvailable = null),
                decoration: InputDecoration(
                  labelText: '이메일',
                  hintText: '비밀번호 재설정에 사용됩니다',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: _emailAvailable == null
                      ? null
                      : _emailAvailable!
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                _emailController.clear();
                                setState(() => _emailAvailable = null);
                              },
                            ),
                  errorText: _emailAvailable == false ? '이미 사용 중인 이메일입니다.' : null,
                  helperText: _emailAvailable == true ? '사용 가능한 이메일입니다.' : null,
                  helperStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '비밀번호 확인',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                onSubmitted: (_) => _register(),
              ),
              const SizedBox(height: 8),
              // 비밀번호 강도 안내
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '비밀번호: 8자 이상, 대문자·소문자·숫자 각 1개 이상\n이메일은 비밀번호 분실 시 재설정에 사용됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _register,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('가입하기', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
