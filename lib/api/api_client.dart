import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';

// ── 예외 클래스 ──────────────────────────────────────
class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = '로그인이 만료되었습니다. 다시 로그인해주세요.']);
  @override
  String toString() => message;
}

class ServerException implements Exception {
  final String message;
  const ServerException([this.message = '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.']);
  @override
  String toString() => message;
}

/// 네트워크/연결 오류를 사용자 친화적인 메시지로 변환
String friendlyError(Object e) {
  final msg = e.toString();
  if (msg.contains('SocketException') ||
      msg.contains('ClientException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Connection refused') ||
      msg.contains('TimeoutException') ||
      msg.contains('Network is unreachable')) {
    return '서버에 연결을 실패했습니다. 다시 시도해 주세요.';
  }
  if (msg.contains('kakao') ||
      msg.contains('Kakao') ||
      msg.contains('invalid_request') ||
      msg.contains('bundleId') ||
      msg.contains('KakaoException') ||
      msg.contains('KakaoApiException') ||
      msg.contains('KakaoAuthException')) {
    return '카카오 로그인에 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
  }
  return '오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}

// ── API 클라이언트 ────────────────────────────────────
class ApiClient {
  /// 빌드 시 반드시 주입:
  ///   flutter run  --dart-define-from-file=dart_defines.json
  ///   flutter build apk --release --dart-define-from-file=dart_defines.json
  /// dart_defines.json 은 gitignore에 포함됨 (dart_defines.example.json 참고)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://skillful-unity-production-e922.up.railway.app',
  );


  static const _storage = FlutterSecureStorage(
    // iOS: 첫 잠금 해제 후 접근 가능, 기기 이전 시 복사 불가 (보안 강화)
    // first_unlock_this_device = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // Android: 암호화된 SharedPreferences 사용
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  static const _timeout = Duration(seconds: 30);

  // ── 토큰 유효성 (클라이언트 측) ──────────────────────
  /// JWT payload의 exp 클레임을 확인 (서버 호출 없이 빠른 체크)
  static bool isTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return true; // 파싱 실패 → 만료된 것으로 간주
    }
  }

  /// 서버에 GET /auth/me 요청으로 토큰 유효성 실제 확인
  static Future<bool> verifyToken() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        await saveAvatarUrl(data['avatar_url'] as String?);
        return true;
      }
      return false;
    } catch (_) {
      return false; // 네트워크 오류 / 타임아웃은 false 처리
    }
  }

  // ── 토큰 관리 ──────────────────────────────────────
  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'access_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'access_token');
  }

  // ── 유저 정보 관리 ────────────────────────────────
  static Future<void> saveUserInfo(String displayName, int userId) async {
    await _storage.write(key: 'display_name', value: displayName);
    await _storage.write(key: 'user_id', value: userId.toString());
  }

  static Future<void> saveAvatarUrl(String? url) async {
    if (url != null && url.isNotEmpty) {
      await _storage.write(key: 'avatar_url', value: url);
    } else {
      await _storage.delete(key: 'avatar_url');
    }
  }

  static Future<String?> getAvatarUrl() async {
    final v = await _storage.read(key: 'avatar_url');
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getDisplayName() async {
    return await _storage.read(key: 'display_name');
  }

  static Future<int?> getUserId() async {
    final id = await _storage.read(key: 'user_id');
    return id != null ? int.tryParse(id) : null;
  }

  // ── 동아리 정보 관리 ──────────────────────────────
  static Future<void> setClubInfo(int clubId, String clubName, String role) async {
    await _storage.write(key: 'club_id', value: clubId.toString());
    await _storage.write(key: 'club_name', value: clubName);
    await _storage.write(key: 'role', value: role);
  }

  static Future<int?> getClubId() async {
    final v = await _storage.read(key: 'club_id');
    return v != null ? int.tryParse(v) : null;
  }

  static Future<String?> getClubName() async {
    return await _storage.read(key: 'club_name');
  }

  static Future<String?> getRole() async {
    return await _storage.read(key: 'role');
  }

  static Future<void> logout() async {
    await _storage.deleteAll();
  }

  static Future<String?> getStoredValue(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> storeValue(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  // ── 공통 헤더 (토큰 + X-Club-Id 자동 포함) ──────────
  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    final clubId = await getClubId();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (clubId != null) 'X-Club-Id': clubId.toString(),
    };
  }

  /// X-Club-Id 없이 JWT만 포함하는 헤더 (동아리 목록 조회 등)
  static Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 공통 응답 처리: 타임아웃·5xx 예외 발생, 나머지는 JSON 반환
  static Map<String, dynamic> _parseResponse(http.Response response) {
    if (response.statusCode >= 500) {
      throw ServerException();
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ── 인증 API ────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String username,
    required String displayName,
    required String nickname,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'display_name': displayName,
        'nickname': nickname,
        'email': email,
        'password': password,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<bool> checkUsername(String username) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/check-username?username=${Uri.encodeComponent(username)}'),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    return data['available'] as bool;
  }

  static Future<bool> checkDisplayName(String displayName) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/check-displayname?display_name=${Uri.encodeComponent(displayName)}'),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    return data['available'] as bool;
  }

  static Future<bool> checkNickname(String nickname) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/check-nickname?nickname=${Uri.encodeComponent(nickname)}'),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    return data['available'] as bool;
  }

  static Future<bool> checkEmail(String email) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/check-email?email=${Uri.encodeComponent(email)}'),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    return data['available'] as bool;
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> kakaoLogin(String kakaoAccessToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/kakao'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': kakaoAccessToken}),
    ).timeout(_timeout);

    final data = _parseResponse(response);
    if (response.statusCode == 200) {
      await saveToken(data['access_token']);
      await saveUserInfo(data['display_name'], data['user_id']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      // URI 인코딩으로 특수문자 포함 비밀번호 안전 전송
      body: 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
    ).timeout(_timeout);

    final data = _parseResponse(response);
    if (response.statusCode == 200) {
      await saveToken(data['access_token']);
      await saveUserInfo(data['display_name'], data['user_id']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> getPost(int postId) async {
    final headers = await _headers();
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: headers,
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 동아리 API ────────────────────────────────
  static Future<Map<String, dynamic>> createClub(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs'),
      headers: await _authOnlyHeaders(),
      body: jsonEncode({'name': name}),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    if (response.statusCode == 200) {
      await setClubInfo(data['club_id'], data['club_name'], data['role']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> joinClub(String inviteCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/join'),
      headers: await _authOnlyHeaders(),
      body: jsonEncode({'invite_code': inviteCode}),
    ).timeout(_timeout);
    final data = _parseResponse(response);
    if (response.statusCode == 200) {
      await setClubInfo(data['club_id'], data['club_name'], data['role']);
    }
    return data;
  }

  static Future<List<dynamic>> getMyClubs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/my'),
      headers: await _authOnlyHeaders(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> getInviteCode(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/invite-code'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> regenerateInviteCode(int clubId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/invite-code/regenerate'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<List<dynamic>> getMembers(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/members'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> resetMemberPassword(
      int clubId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/members/$userId/reset-password'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> kickMember(int clubId, int userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clubs/$clubId/members/$userId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updateMemberRole(
      int clubId, int userId, String role) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/clubs/$clubId/members/$userId/role'),
      headers: await _headers(),
      body: jsonEncode({'role': role}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 무대 순서 최적화 ────────────────────────────
  static Future<Map<String, dynamic>> createSchedule(
      Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/schedule'),
      headers: await _headers(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 공지사항 ────────────────────────────────────
  static Future<List<dynamic>> getNotices() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notices'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> getNotice(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notices/$id'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> createNotice({
    required String title,
    required String content,
    List<String> mediaUrls = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notices'),
      headers: await _headers(),
      body: jsonEncode({'title': title, 'content': content, 'media_urls': mediaUrls}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updateNotice(
    int id, {
    required String title,
    required String content,
    List<String> mediaUrls = const [],
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notices/$id'),
      headers: await _headers(),
      body: jsonEncode({'title': title, 'content': content, 'media_urls': mediaUrls}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deleteNotice(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notices/$id'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 댓글 API ────────────────────────────────────
  static Future<List<dynamic>> getComments(int noticeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notices/$noticeId/comments'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> createComment(int noticeId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notices/$noticeId/comments'),
      headers: await _headers(),
      body: jsonEncode({'content': content}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deleteComment(int noticeId, int commentId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notices/$noticeId/comments/$commentId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 계정 관리 ──────────────────────────────────
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: await _authOnlyHeaders(),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deleteAccount({
    String? password,
    String? confirmText,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authOnlyHeaders(),
      body: jsonEncode({
        if (password != null) 'password': password,
        if (confirmText != null) 'confirm_text': confirmText,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 가능 시간 ──────────────────────────────────
  static Future<Map<String, dynamic>> saveAvailability({
    required String roomCode,
    required String day,
    required double startTime,
    required double endTime,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/availability'),
      headers: await _headers(),
      body: jsonEncode({
        'room_code': roomCode,
        'day': day,
        'start_time': startTime,
        'end_time': endTime,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> getAvailability(String roomCode) async {
    final response = await http.get(
      Uri.parse('$baseUrl/availability/$roomCode'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deleteAvailability(int slotId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/availability/$slotId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> getGroupSchedule(
      String roomCode, double durationNeeded) async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl/group-schedule/$roomCode?duration_needed=$durationNeeded'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 연습실 예약 ─────────────────────────────────
  static Future<Map<String, dynamic>> createBooking(
      Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/booking'),
      headers: await _headers(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> getBookings(String date) async {
    final response = await http.get(
      Uri.parse('$baseUrl/booking/$date'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deleteBooking(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/booking/$id'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 게시판 API ────────────────────────────────────
  static Future<List<dynamic>> getPosts({bool isGlobal = false, int offset = 0}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts?is_global=$isGlobal&offset=$offset&limit=20'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<List<dynamic>> searchPosts({
    required String q,
    required bool isGlobal,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/posts/search?q=${Uri.encodeQueryComponent(q)}&is_global=$isGlobal',
    );
    final response = await http.get(
      uri,
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createPost({
    required String content,
    List<String> mediaUrls = const [],
    bool isGlobal = false,
    bool isAnonymous = false,
    String? youtubeUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts'),
      headers: await _headers(),
      body: jsonEncode({
        'content': content,
        'media_urls': mediaUrls,
        'is_global': isGlobal,
        'is_anonymous': isAnonymous,
        if (youtubeUrl != null) 'youtube_url': youtubeUrl,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updateNickname(String nickname) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/nickname'),
      headers: await _headers(),
      body: jsonEncode({'nickname': nickname}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updateAvatarUrl(String avatarUrl) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/avatar'),
      headers: await _headers(),
      body: jsonEncode({'avatar_url': avatarUrl}),
    ).timeout(_timeout);
    final result = _parseResponse(response);
    await saveAvatarUrl(avatarUrl);
    return result;
  }

  static Future<Map<String, dynamic>> deletePost(int postId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> togglePostLike(int postId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/likes'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<List<dynamic>> getPostComments(int postId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> createPostComment(int postId, String content, {int? parentId}) async {
    final body = <String, dynamic>{'content': content};
    if (parentId != null) body['parent_id'] = parentId;
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updatePost(int postId, String content, {List<String> mediaUrls = const []}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: await _headers(),
      body: jsonEncode({'content': content, 'media_urls': mediaUrls}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updatePostComment(int postId, int commentId, String content) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId'),
      headers: await _headers(),
      body: jsonEncode({'content': content}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> reportPost(int postId, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/report'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> reportPostComment(int postId, int commentId, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId/report'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deletePostComment(int postId, int commentId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<List<dynamic>> getHotClubs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/hot-ranking'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> getMyActivity() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me/activity'),
      headers: await _authOnlyHeaders(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> getPresignedUrl(
    String filename,
    String contentType, {
    int? clubId,
    int fileSizeMb = 0,
  }) async {
    var url = '$baseUrl/upload/presigned?filename=${Uri.encodeComponent(filename)}&content_type=${Uri.encodeComponent(contentType)}&file_size_mb=$fileSizeMb';
    if (clubId != null) url += '&club_id=$clubId';
    final response = await http.get(
      Uri.parse(url),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('스토리지 용량이 초과되었습니다.');
    return _parseResponse(response);
  }

  // ── 아이디 찾기 ────────────────────────────────────
  static Future<Map<String, dynamic>> findId(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/find-id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 알림 ──────────────────────────────────────────
  static Future<Map<String, dynamic>> getNotifications() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: await _authOnlyHeaders(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> markNotificationsRead() async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: await _authOnlyHeaders(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> getClubProfile(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/profile'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode == 404) {
      throw Exception('동아리를 찾을 수 없습니다.');
    }
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> updateClubProfile(
    int clubId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/clubs/$clubId/profile'),
      headers: await _headers(),
      body: jsonEncode(data),
    ).timeout(_timeout);
    if (response.statusCode == 403) {
      throw Exception('권한이 없습니다.');
    }
    if (response.statusCode == 400) {
      // FastAPI returns {"detail": "..."} for 400 errors
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = body['detail'];
        if (detail is String) throw Exception(detail);
        if (detail is List && detail.isNotEmpty) {
          throw Exception((detail.first['msg'] as String?) ?? '잘못된 입력입니다.');
        }
      } catch (parseError) {
        if (parseError is Exception) rethrow;
      }
      throw Exception('잘못된 입력입니다.');
    }
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ── 구독 / 플랜 ──────────────────────────────────
  static Future<Map<String, dynamic>> getClubSubscription(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/subscription'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> verifyClubSubscription(
    int clubId, {
    required String productId,
    required String transactionId,
    required String platform,
    required String receiptData,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/subscription/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'product_id': productId,
        'transaction_id': transactionId,
        'platform': platform,
        'receipt_data': receiptData,
      }),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 409) throw Exception('이미 처리된 구매입니다.');
    if (response.statusCode == 400) {
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = body['detail'];
        if (detail is String) throw Exception(detail);
      } catch (e) {
        if (e is Exception) rethrow;
      }
      throw Exception('잘못된 요청입니다.');
    }
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Future<Map<String, dynamic>> reportStorage(
    int clubId,
    String key,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/storage/report'),
      headers: await _headers(),
      body: jsonEncode({'key': key}),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    return _parseResponse(response);
  }

  // ── 게시글 홍보(부스트) ──────────────────────────
  static Future<Map<String, dynamic>> boostPost(int postId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/boost'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 402) throw Exception('홍보 크레딧이 부족합니다.');
    if (response.statusCode == 409) throw Exception('이미 홍보 중인 게시글입니다.');
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ── 음원 제출 게시판 ──────────────────────────

  /// 응답 body에서 에러 메시지 추출 헬퍼
  static String _apiError(http.Response res, String fallback) {
    try {
      final b = jsonDecode(utf8.decode(res.bodyBytes));
      final d = b['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) {
        final first = d.first;
        return (first is Map ? first['msg']?.toString() : first.toString()) ?? fallback;
      }
    } catch (_) {}
    return '$fallback (${res.statusCode})';
  }

  static Future<List<dynamic>> getPerformances(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as List;
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '공연 목록을 불러오지 못했습니다'));
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
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '공연 등록에 실패했습니다'));
  }

  static Future<void> deletePerformance(int clubId, int perfId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 204) return;
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 404) throw Exception('공연을 찾을 수 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '공연 삭제에 실패했습니다'));
  }

  static Future<List<dynamic>> getSubmissions(int clubId, int perfId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId/submissions'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as List;
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '제출 목록을 불러오지 못했습니다'));
  }

  static Future<Map<String, dynamic>?> getMySubmission(
      int clubId, int perfId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performances/$perfId/submissions/mine'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body['submission'] as Map<String, dynamic>?;
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '내 제출 정보를 불러오지 못했습니다'));
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
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode == 404) throw Exception('공연을 찾을 수 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '음원 제출에 실패했습니다'));
  }

  static Future<void> deleteSubmission(
      int clubId, int perfId, int subId) async {
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/clubs/$clubId/performances/$perfId/submissions/$subId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 204) return;
    if (response.statusCode == 403) throw Exception('본인의 제출만 삭제할 수 있습니다.');
    if (response.statusCode == 404) throw Exception('제출을 찾을 수 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '제출 삭제에 실패했습니다'));
  }

  /// FCM 토큰을 백엔드에 등록/갱신. Fire-and-forget — 실패해도 무시.
  static Future<void> updateFcmToken(String token) async {
    try {
      await http.patch(
        Uri.parse('$baseUrl/users/me/fcm-token'),
        headers: await _authOnlyHeaders(),
        body: jsonEncode({'token': token}),
      ).timeout(_timeout);
    } catch (_) {
      // fire-and-forget
    }
  }

  static Future<Map<String, dynamic>> toggleCommentLike(
      int postId, int commentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId/like'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode == 403) throw Exception('권한이 없습니다.');
    if (response.statusCode >= 500) throw ServerException();
    throw Exception(_apiError(response, '좋아요 처리에 실패했습니다'));
  }

  // ── 공연 아카이브 API ─────────────────────────────────────
  static Future<List<dynamic>> getPerformanceArchives(int clubId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/clubs/$clubId/performance-archives'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createPerformanceArchive(
    int clubId, {
    required String title,
    required String performanceDate,
    String? description,
    String? youtubeUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/performance-archives'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'performance_date': performanceDate,
        if (description != null) 'description': description,
        if (youtubeUrl != null) 'youtube_url': youtubeUrl,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> toggleArchiveLike(
    int clubId,
    int archiveId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clubs/$clubId/performance-archives/$archiveId/like'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> updatePerformanceArchive(
    int clubId,
    int archiveId, {
    required String title,
    required String performanceDate,
    String? description,
    String? youtubeUrl,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/clubs/$clubId/performance-archives/$archiveId'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'performance_date': performanceDate,
        'description': description,
        'youtube_url': youtubeUrl,
      }),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> deletePerformanceArchive(
    int clubId,
    int archiveId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clubs/$clubId/performance-archives/$archiveId'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  // ── 챌린지 API ──────────────────────────────────────────
  static Future<Map<String, dynamic>> getCurrentChallenge() async {
    final response = await http.get(
      Uri.parse('$baseUrl/challenge/current'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode >= 500) throw ServerException();
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> submitChallengeEntry(int archiveId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/challenge/entries'),
      headers: await _headers(),
      body: jsonEncode({'archive_id': archiveId}),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> withdrawChallengeEntry() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/challenge/entries/mine'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }

  static Future<Map<String, dynamic>> toggleChallengeLike(int entryId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/challenge/entries/$entryId/like'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _parseResponse(response);
  }
}
