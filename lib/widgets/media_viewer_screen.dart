import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

// ── 슬라이드 미디어 뷰어 ──────────────────────────────
class MediaViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const MediaViewerScreen({super.key, required this.urls, required this.initialIndex});

  static bool isVideo(String u) {
    final l = u.toLowerCase();
    return l.contains('.mp4') || l.contains('.mov') ||
           l.contains('.avi') || l.contains('.webm');
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final url = widget.urls[_currentIndex];
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('다운로드 중...'),
      duration: Duration(seconds: 60),
    ));
    try {
      final response = await http.get(Uri.parse(url));
      final ext = url.split('.').last.split('?').first.toLowerCase();
      final isVideo = ['mp4', 'mov', 'webm', 'avi'].contains(ext);
      if (isVideo) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${Directory.systemTemp.path}/dl_$ts.$ext');
        await tempFile.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(tempFile.path);
        await tempFile.delete();
      } else {
        await Gal.putImageBytes(response.bodyBytes);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('갤러리에 저장되었습니다!'),
        backgroundColor: Colors.green,
      ));
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('다운로드에 실패했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        // n / total 표시
        title: widget.urls.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              )
            : null,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: _download,
            tooltip: '저장',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return MediaViewerScreen.isVideo(url)
              ? VideoPage(url: url, isActive: i == _currentIndex)
              : PhotoPage(url: url);
        },
      ),
    );
  }
}

// ── 사진 페이지 (핀치 줌) ─────────────────────────────
class PhotoPage extends StatelessWidget {
  final String url;
  const PhotoPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(color: Colors.white)),
          errorBuilder: (_, __, ___) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 64),
              SizedBox(height: 8),
              Text('이미지를 불러올 수 없어요', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 영상 페이지 ───────────────────────────────────────
class VideoPage extends StatefulWidget {
  final String url;
  final bool isActive;
  const VideoPage({super.key, required this.url, required this.isActive});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        if (widget.isActive) _ctrl.play();
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didUpdateWidget(VideoPage old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      widget.isActive ? _ctrl.play() : _ctrl.pause();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text('영상을 불러올 수 없어요', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _ctrl.value.aspectRatio,
          child: VideoPlayer(_ctrl),
        ),
        const SizedBox(height: 8),
        VideoProgressIndicator(
          _ctrl,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.white,
            bufferedColor: Colors.white30,
            backgroundColor: Colors.white12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_ctrl.value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(_fmt(_ctrl.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play(),
          icon: Icon(
            _ctrl.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
            size: 56,
          ),
        ),
      ],
    );
  }
}
