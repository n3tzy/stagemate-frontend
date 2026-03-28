import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';

// ── 음원 제출 메인 탭 화면 ──────────────────────────
class AudioSubmissionScreen extends StatefulWidget {
  final String role;

  const AudioSubmissionScreen({super.key, required this.role});

  @override
  State<AudioSubmissionScreen> createState() => _AudioSubmissionScreenState();
}

class _AudioSubmissionScreenState extends State<AudioSubmissionScreen> {
  List<dynamic> _performances = [];
  bool _isLoading = false;
  int? _clubId;

  bool get _isAdmin =>
      widget.role == 'super_admin' || widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final id = await ApiClient.getClubId();
      if (id == null) return;
      final perfs = await ApiClient.getPerformances(id);
      if (mounted) {
        setState(() {
          _clubId = id;
          _performances = perfs;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreatePerformanceDialog() async {
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '공연명 *',
                hintText: '예: 2025 봄 축제',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  dateCtrl.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: '공연 날짜 (선택)',
                    hintText: '날짜를 선택하세요',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공연명을 입력해주세요.')),
        );
      }
      return;
    }
    if (_clubId == null) return;

    try {
      await ApiClient.createPerformance(
        _clubId!,
        name: name,
        performanceDate:
            dateCtrl.text.trim().isEmpty ? null : dateCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('공연이 등록됐습니다.'),
              backgroundColor: Colors.green,
            ),
          );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }

  Future<void> _deletePerformance(dynamic perf) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 삭제'),
        content: Text(
          '\'${perf['name']}\' 공연과 모든 제출 파일을 삭제할까요?\n이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.deletePerformance(_clubId!, perf['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공연이 삭제됐습니다.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openPerformance(dynamic perf) {
    if (_clubId == null) return;
    if (_isAdmin) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _AdminSubmissionSheet(
          clubId: _clubId!,
          perf: perf,
          onChanged: _load,
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _TeamLeaderSubmitSheet(
          clubId: _clubId!,
          perf: perf,
          onChanged: _load,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('음원 제출'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _performances.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_off,
                              size: 56,
                              color: colorScheme.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            _isAdmin
                                ? '등록된 공연이 없습니다.\n+ 버튼으로 추가하세요.'
                                : '등록된 공연이 없습니다.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _performances.length,
                      itemBuilder: (_, i) => _PerformanceCard(
                        perf: _performances[i],
                        isAdmin: _isAdmin,
                        onTap: () => _openPerformance(_performances[i]),
                        onDelete: _isAdmin
                            ? () => _deletePerformance(_performances[i])
                            : null,
                      ),
                    ),
            ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreatePerformanceDialog,
              icon: const Icon(Icons.add),
              label: const Text('공연 추가'),
            )
          : null,
    );
  }
}

// ── 공연 카드 ────────────────────────────────────
class _PerformanceCard extends StatelessWidget {
  final dynamic perf;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PerformanceCard({
    required this.perf,
    required this.isAdmin,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = perf['submission_count'] as int? ?? 0;
    final date = perf['performance_date'] as String?;
    final deadline = perf['submission_deadline'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.library_music,
                    color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perf['name'] as String? ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.event,
                              size: 13, color: colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            date,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ],
                    if (deadline != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 13,
                              color: Colors.orange.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '마감: ${deadline.length > 10 ? deadline.substring(0, 10) : deadline}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade600),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count팀 제출',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Text(
                        '탭하여 제출하기',
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: colorScheme.error),
                  onPressed: onDelete,
                  tooltip: '삭제',
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 임원진 제출 목록 바텀시트 ─────────────────────
class _AdminSubmissionSheet extends StatefulWidget {
  final int clubId;
  final dynamic perf;
  final VoidCallback onChanged;

  const _AdminSubmissionSheet({
    required this.clubId,
    required this.perf,
    required this.onChanged,
  });

  @override
  State<_AdminSubmissionSheet> createState() =>
      _AdminSubmissionSheetState();
}

class _AdminSubmissionSheetState extends State<_AdminSubmissionSheet> {
  List<dynamic> _submissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final subs = await ApiClient.getSubmissions(
          widget.clubId, widget.perf['id'] as int);
      if (mounted) setState(() => _submissions = subs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.library_music),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.perf['name'] as String? ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${_submissions.length}팀 제출',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _submissions.isEmpty
                    ? Center(
                        child: Text(
                          '아직 제출된 음원이 없습니다.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _submissions.length,
                        itemBuilder: (_, i) =>
                            _SubmissionTile(sub: _submissions[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── 제출 항목 (플레이어 포함) ─────────────────────
class _SubmissionTile extends StatefulWidget {
  final dynamic sub;
  const _SubmissionTile({required this.sub});

  @override
  State<_SubmissionTile> createState() => _SubmissionTileState();
}

class _SubmissionTileState extends State<_SubmissionTile> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isExpanded = false;

  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playerState = s);
      }),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      } else {
        final url = widget.sub['file_url'] as String;
        if (_playerState == PlayerState.paused) {
          await _player.resume();
        } else {
          await _player.play(UrlSource(url));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('재생 오류: ${friendlyError(e)}')),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaying = _playerState == PlayerState.playing;
    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.music_note,
                        size: 18,
                        color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sub['song_title'] as String? ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${widget.sub['team_name']} · ${widget.sub['submitter_name']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      size: 36,
                      color: colorScheme.primary,
                    ),
                    tooltip: isPlaying ? '일시정지' : '재생',
                  ),
                ],
              ),
              if (_isExpanded ||
                  isPlaying ||
                  _position > Duration.zero) ...[
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: _duration.inSeconds > 0
                        ? (v) {
                            final pos = Duration(
                                seconds:
                                    (v * _duration.inSeconds).round());
                            _player.seek(pos);
                          }
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.outline),
                    ),
                    Text(
                      _duration > Duration.zero
                          ? _formatDuration(_duration)
                          : '--:--',
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '업데이트: ${widget.sub['updated_at'] ?? widget.sub['submitted_at']}',
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 팀장 제출/재제출 바텀시트 ─────────────────────
class _TeamLeaderSubmitSheet extends StatefulWidget {
  final int clubId;
  final dynamic perf;
  final VoidCallback onChanged;

  const _TeamLeaderSubmitSheet({
    required this.clubId,
    required this.perf,
    required this.onChanged,
  });

  @override
  State<_TeamLeaderSubmitSheet> createState() =>
      _TeamLeaderSubmitSheetState();
}

class _TeamLeaderSubmitSheetState
    extends State<_TeamLeaderSubmitSheet> {
  Map<String, dynamic>? _mySubmission;
  bool _isLoading = true;
  bool _isUploading = false;
  String _uploadStatus = '';

  final _teamNameCtrl = TextEditingController();
  final _songTitleCtrl = TextEditingController();

  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.onPlayerStateChanged.listen(
          (s) { if (mounted) setState(() => _playerState = s); }),
      _player.onPositionChanged.listen(
          (p) { if (mounted) setState(() => _position = p); }),
      _player.onDurationChanged.listen(
          (d) { if (mounted) setState(() => _duration = d); }),
    ];
    _load();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _songTitleCtrl.dispose();
    for (final s in _subs) s.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final sub = await ApiClient.getMySubmission(
          widget.clubId, widget.perf['id'] as int);
      if (mounted) {
        setState(() => _mySubmission = sub);
        if (sub != null) {
          _teamNameCtrl.text = sub['team_name'] as String? ?? '';
          _songTitleCtrl.text = sub['song_title'] as String? ?? '';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndSubmit() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;

    final teamName = _teamNameCtrl.text.trim();
    final songTitle = _songTitleCtrl.text.trim();

    if (teamName.isEmpty || songTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀명과 곡 제목을 입력해주세요.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isUploading = true;
      _uploadStatus = '파일 업로드 중...';
    });

    try {
      final file = File(picked.path!);
      final fileSize = await file.length();
      final fileSizeMb = (fileSize / (1024 * 1024)).ceil();

      if (fileSizeMb > 200) {
        throw Exception('파일이 너무 큽니다. 최대 200MB까지 업로드할 수 있어요.');
      }

      final presigned = await ApiClient.getPresignedUrl(
        picked.name,
        'audio/mpeg',
        clubId: widget.clubId,
        fileSizeMb: fileSizeMb,
      );

      final uploadUrl = presigned['upload_url'] as String;
      final publicUrl = presigned['public_url'] as String;
      final storageKey = presigned['key'] as String;

      setState(() => _uploadStatus = '파일 업로드 중...');
      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'audio/mpeg'},
        body: bytes,
      );
      if (uploadResponse.statusCode != 200 &&
          uploadResponse.statusCode != 204) {
        throw Exception('파일 업로드 실패 (${uploadResponse.statusCode})');
      }

      setState(() => _uploadStatus = '처리 중...');
      await ApiClient.reportStorage(widget.clubId, storageKey);

      await ApiClient.submitAudio(
        widget.clubId,
        widget.perf['id'] as int,
        teamName: teamName,
        songTitle: songTitle,
        fileUrl: publicUrl,
        fileSizeMb: fileSizeMb,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('음원이 제출됐습니다! 🎵'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onChanged();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteSubmission() async {
    if (_mySubmission == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제출 삭제'),
        content: const Text('제출한 음원을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.deleteSubmission(
        widget.clubId,
        widget.perf['id'] as int,
        _mySubmission!['id'] as int,
      );
      if (mounted) {
        setState(() => _mySubmission = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제출이 삭제됐습니다.')),
        );
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_mySubmission == null) return;
    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      } else if (_playerState == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(
            UrlSource(_mySubmission!['file_url'] as String));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('재생 오류: ${friendlyError(e)}')),
        );
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.perf['name'] as String? ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '음원 제출',
                style: TextStyle(
                    color: colorScheme.outline, fontSize: 13),
              ),
              const Divider(height: 24),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_mySubmission != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16,
                                color: Colors.green.shade600),
                            const SizedBox(width: 6),
                            const Text(
                              '제출 완료',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _mySubmission!['updated_at'] ??
                                  _mySubmission!['submitted_at'] ??
                                  '',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '🎵 ${_mySubmission!['song_title']}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '팀: ${_mySubmission!['team_name']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                _playerState == PlayerState.playing
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                size: 36,
                                color: colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context)
                                        .copyWith(
                                      trackHeight: 3,
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                              enabledThumbRadius: 5),
                                    ),
                                    child: Slider(
                                      value: (_duration.inSeconds > 0
                                              ? _position.inSeconds /
                                                  _duration.inSeconds
                                              : 0.0)
                                          .clamp(0.0, 1.0),
                                      onChanged: _duration.inSeconds >
                                              0
                                          ? (v) {
                                              _player.seek(Duration(
                                                  seconds: (v *
                                                          _duration
                                                              .inSeconds)
                                                      .round()));
                                            }
                                          : null,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_fmt(_position),
                                          style: const TextStyle(
                                              fontSize: 10)),
                                      Text(
                                          _duration > Duration.zero
                                              ? _fmt(_duration)
                                              : '--:--',
                                          style: const TextStyle(
                                              fontSize: 10)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: colorScheme.error, size: 20),
                              onPressed: _deleteSubmission,
                              tooltip: '제출 삭제',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '재제출',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  const Text(
                    '아직 제출하지 않았습니다.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _teamNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '팀명 *',
                    hintText: '예: A팀',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _songTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: '곡 제목 *',
                    hintText: '예: 불꽃놀이',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(height: 20),

                if (_isUploading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _uploadStatus,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                FilledButton.icon(
                  onPressed: _isUploading ? null : _pickAndSubmit,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_mySubmission != null
                      ? '재제출 (MP3)'
                      : 'MP3 파일 선택 & 제출'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'MP3 파일만 허용 · 최대 200MB',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
