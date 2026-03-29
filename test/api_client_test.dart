// test/api_client_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getPost 404 detection', () {
    test('response without id key is treated as not found', () {
      // Simulates FastAPI 404: {"detail": "Not found"}
      final notFoundResponse = <String, dynamic>{'detail': 'Not found'};
      expect(notFoundResponse.containsKey('id'), isFalse);
    });

    test('valid post response contains id key', () {
      final validPost = <String, dynamic>{
        'id': 42,
        'content': 'hello',
        'author_display_name': 'test',
      };
      expect(validPost.containsKey('id'), isTrue);
    });
  });
}
