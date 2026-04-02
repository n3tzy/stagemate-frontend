import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// YouTube URL에서 Video ID를 추출한다.
/// 지원 형식: youtu.be/{id}, youtube.com/watch?v={id}, youtube.com/shorts/{id}
String? extractYouTubeId(String url) {
  final patterns = [
    RegExp(r'youtu\.be/([^?&]+)'),
    RegExp(r'youtube\.com/watch\?v=([^&]+)'),
    RegExp(r'youtube\.com/shorts/([^?&]+)'),
    RegExp(r'youtube\.com/embed/([^?&]+)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

class YouTubeCard extends StatelessWidget {
  final String youtubeUrl;

  const YouTubeCard({super.key, required this.youtubeUrl});

  @override
  Widget build(BuildContext context) {
    final videoId = extractYouTubeId(youtubeUrl);
    // maxresdefault.jpg가 없는 영상은 HTTP 404 대신 120x90 회색 이미지를 반환한다.
    // Image.network의 errorBuilder가 이를 감지하지 못하므로, hqdefault.jpg 자동 폴백은
    // 불가능하다. 실패 시 플레이스홀더 아이콘 카드를 보여주는 것이 실용적인 대안이다.
    final thumbnailUrl = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg'
        : null;

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(youtubeUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 썸네일
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnailUrl != null
                  ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // 하단 레이블
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'YouTube에서 보기',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.open_in_new,
                      size: 14, color: Colors.grey.shade500),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade900,
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 48),
      ),
    );
  }
}
