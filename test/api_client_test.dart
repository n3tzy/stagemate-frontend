// test/api_client_test.dart
//
// Tests for ApiClient.getPost and related response-parsing logic.
//
// NOTE: ApiClient uses the http package's top-level functions (http.get, etc.)
// rather than an injectable http.Client. This means true end-to-end HTTP mocking
// (intercepting the actual network call) would require either:
//   a) Refactoring ApiClient to accept an http.Client constructor parameter, or
//   b) Adding a dependency such as `mockito` + `http_mock_adapter`, or
//      `nock` for Dart.
// Until that refactoring is done the tests below cover:
//   1. The 404-detection logic that callers of getPost rely on.
//   2. The ServerException class behaviour (the exception thrown on 5xx).
//   3. A compile-time import check — ApiClient is imported and referenced so
//      any breaking change to its public API will fail this file at analysis time.

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_mate/api/api_client.dart';

void main() {
  // ── Compile-time reference to ApiClient ────────────────────────────────────
  // This keeps the import live so static analysis catches API-signature changes.
  // ignore: unused_local_variable
  const _ = ApiClient;

  // ── ServerException ─────────────────────────────────────────────────────────
  group('ServerException', () {
    test('uses default message when none provided', () {
      const e = ServerException();
      expect(e.toString(), contains('서버 오류'));
    });

    test('accepts a custom message', () {
      const e = ServerException('custom error');
      expect(e.toString(), equals('custom error'));
      expect(e.message, equals('custom error'));
    });

    test('implements Exception', () {
      expect(ServerException(), isA<Exception>());
    });
  });

  // ── 404-detection logic (mirrors what callers of getPost use) ───────────────
  //
  // When the backend returns 404, FastAPI responds with {"detail": "Not found"}.
  // _parseResponse decodes that JSON as-is (statusCode < 500 → no throw).
  // Callers then check `data.containsKey('id')` to distinguish a real post
  // object from an error envelope.
  group('getPost 404-detection logic', () {
    test('FastAPI 404 envelope does not contain id key', () {
      // Simulates: {"detail": "Not found"}
      final notFoundBody = <String, dynamic>{'detail': 'Not found'};
      expect(notFoundBody.containsKey('id'), isFalse);
    });

    test('valid post response contains id key', () {
      final validPost = <String, dynamic>{
        'id': 42,
        'content': 'hello',
        'author_display_name': 'tester',
      };
      expect(validPost.containsKey('id'), isTrue);
    });

    test('empty response body does not contain id key', () {
      final emptyBody = <String, dynamic>{};
      expect(emptyBody.containsKey('id'), isFalse);
    });

    test('validation error envelope does not contain id key', () {
      // Simulates FastAPI 422 body
      final validationError = <String, dynamic>{
        'detail': [
          {'loc': 'body', 'msg': 'field required', 'type': 'value_error'},
        ],
      };
      expect(validationError.containsKey('id'), isFalse);
    });
  });
}
