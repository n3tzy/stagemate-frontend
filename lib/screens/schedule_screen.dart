import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../utils/excel_exporter.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final List<Map<String, dynamic>> _songs = [];
  Map<String, dynamic>? _result;
  bool _isLoading = false;
  int _nextId = 1;

  // ── 시간 포맷 ──────────────────────────
  String _formatTime(double minutes) {
    final m = minutes.floor();
    final s = ((minutes - m) * 60).round();
    if (s == 0) return '$m분';
    return '$m분 ${s}초';
  }

  String _formatClock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // ── 멤버 랭킹 계산 ──────────────────────
  List<Map<String, dynamic>> _getMemberRanking() {
    final Map<String, List<String>> memberSongs = {};

    for (final song in _songs) {
      for (final member in song['members'] as List) {
        memberSongs.putIfAbsent(member.toString(), () => []);
        memberSongs[member.toString()]!.add(song['title'].toString());
      }
    }

    final sorted = memberSongs.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return sorted.take(5).map((e) => {
      'name': e.key,
      'songs': e.value,
      'count': e.value.length,
    }).toList();
  }

  // ── 시간 선택 바텀시트 ─────────────────────
  Future<void> _pickDuration({
    required BuildContext sheetCtx,
    required int initMin,
    required int initSec,
    required String label,
    required void Function(int m, int s) onPicked,
  }) async {
    int selMin = initMin;
    int selSec = initSec;
    await showModalBottomSheet(
      context: sheetCtx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bsCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            SizedBox(
              height: 180,
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.ms,
                initialTimerDuration: Duration(minutes: initMin, seconds: initSec),
                onTimerDurationChanged: (d) {
                  selMin = d.inMinutes;
                  selSec = d.inSeconds % 60;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    onPicked(selMin, selSec);
                    Navigator.pop(bsCtx);
                  },
                  child: const Text('확인'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 곡 추가 다이얼로그 ──────────────────
  Future<void> _showAddSongDialog() async {
    final titleController = TextEditingController();
    final membersController = TextEditingController();
    int durationMin = 4;
    int durationSec = 30;
    int introMin = 1;
    int introSec = 30;

    String fmtPick(int m, int s) => s == 0 ? '$m분' : '$m분 ${s}초';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('곡 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '곡 제목',
                    hintText: '예: Dynamite',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: membersController,
                  decoration: const InputDecoration(
                    labelText: '참여 멤버',
                    hintText: '쉼표로 구분: 민수, 지혜, 현아',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // ── 곡 길이 드럼롤 피커 ──
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await _pickDuration(
                      sheetCtx: ctx,
                      initMin: durationMin,
                      initSec: durationSec,
                      label: '곡 길이',
                      onPicked: (m, s) => setDialogState(() {
                        durationMin = m;
                        durationSec = s;
                      }),
                    );
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '곡 길이',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.expand_more),
                    ),
                    child: Text(
                      fmtPick(durationMin, durationSec),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── 무대 소개 시간 드럼롤 피커 ──
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await _pickDuration(
                      sheetCtx: ctx,
                      initMin: introMin,
                      initSec: introSec,
                      label: '무대 소개 시간',
                      onPicked: (m, s) => setDialogState(() {
                        introMin = m;
                        introSec = s;
                      }),
                    );
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '무대 소개 시간',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.expand_more),
                    ),
                    child: Text(
                      fmtPick(introMin, introSec),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                final membersRaw = membersController.text.trim();
                if (title.isEmpty || membersRaw.isEmpty) return;

                final duration = durationMin + durationSec / 60.0;
                final introTime = introMin + introSec / 60.0;

                final members = membersRaw
                    .split(',')
                    .map((m) => m.trim())
                    .where((m) => m.isNotEmpty)
                    .toList();

                setState(() {
                  _songs.add({
                    'id': _nextId++,
                    'title': title,
                    'members': members,
                    'duration': duration,
                    'intro_time': introTime,
                  });
                  _result = null;
                });
                Navigator.pop(dialogCtx);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 순서 최적화 API 호출 ────────────────
  Future<void> _optimize() async {
    if (_songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('곡을 먼저 추가해주세요!')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await ApiClient.createSchedule({
        'songs': _songs,
        'min_change_time': 7.0,
        'intro_time': 1.5,
      });
      setState(() => _result = result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 멤버 랭킹 위젯 ──────────────────────
  Widget _buildMemberRanking() {
    final ranking = _getMemberRanking();
    final colorScheme = Theme.of(context).colorScheme;
    final maxCount = ranking.isEmpty ? 1 : (ranking.first['count'] as int);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.emoji_events, size: 22, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  '출연 멤버 랭킹 (TOP ${ranking.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 랭킹 목록
            ...List.generate(ranking.length, (i) {
              final member = ranking[i];
              final count = member['count'] as int;
              final songs = (member['songs'] as List).join(' / ');
              final barRatio = maxCount == 0 ? 0.0 : count / maxCount;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이름 + 곡 수
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 14,
                          color: i == 0
                              ? Colors.amber
                              : i == 1
                                  ? Colors.grey.shade400
                                  : i == 2
                                      ? Colors.brown.shade300
                                      : colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          member['name'].toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count곡',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 진행 바
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: barRatio,
                        minHeight: 8,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          i == 0
                              ? Colors.amber
                              : i == 1
                                  ? Colors.blueGrey
                                  : i == 2
                                      ? Colors.brown.shade300
                                      : colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // 출연 곡 목록
                    Text(
                      songs,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── 메인 빌드 ───────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('무대 순서 최적화'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 곡 목록 섹션 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '곡 목록 (${_songs.length}곡)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                FilledButton.icon(
                  onPressed: _showAddSongDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('곡 추가'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 곡 목록
            if (_songs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.music_note,
                          size: 48, color: colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        '곡을 추가해주세요',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(_songs.length, (i) {
                final song = _songs[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(
                      song['title'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '👥 ${(song['members'] as List).join(', ')}\n'
                      '⏱ ${_formatTime((song['duration'] as num).toDouble())}'
                      '  |  소개 ${_formatTime((song['intro_time'] as num?)?.toDouble() ?? 1.5)}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: colorScheme.error,
                      onPressed: () {
                        setState(() {
                          _songs.removeAt(i);
                          _result = null;
                        });
                      },
                    ),
                  ),
                );
              }),

            // ── 멤버 랭킹 ──
            if (_songs.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildMemberRanking(),
            ],

            const SizedBox(height: 16),

            // ── 최적화 버튼 ──
            FilledButton.icon(
              onPressed: _isLoading ? null : _optimize,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? '계산 중...' : '순서 최적화하기'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            // ── 결과 섹션 ──
            if (_result != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // 결과 헤더
              Row(
                children: [
                  Icon(
                    _result!['is_valid'] ? Icons.check_circle : Icons.warning,
                    color: _result!['is_valid']
                        ? Colors.green
                        : colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _result!['is_valid']
                          ? '✅ 최적 순서 완성!'
                          : '⚠️ 일부 제약 조건 미충족',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _result!['is_valid']
                                ? Colors.green
                                : colorScheme.error,
                          ),
                    ),
                  ),
                  // 엑셀 다운로드 버튼
                  OutlinedButton.icon(
                    onPressed: () {
                      final path = ExcelExporter.exportSchedule(_result!);
                      if (path != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('💾 저장됐어요: ${path.split(Platform.pathSeparator).last}'),
                            duration: const Duration(seconds: 4),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('엑셀'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              // 총 공연 시간
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '총 공연 시간: ${_formatTime((_result!['total_time'] as num).toDouble())}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),

              // 경고 목록
              if ((_result!['warnings'] as List).isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '의상 교체 시간 부족 경고',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...(_result!['warnings'] as List).map(
                        (w) => Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.error.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            w.toString(),
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 타임라인
              Text(
                '무대 타임라인',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...(_result!['stages'] as List).map((stage) {
                final song = stage['song'];
                final members = (song['members'] as List).join(', ');
                final start = (stage['start_time'] as num).toDouble();
                final end = (stage['end_time'] as num).toDouble();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            child: Text('${stage['order']}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song['title'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                Text(
                                  '👥 $members',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_formatClock(start)} ~ ${_formatClock(end)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _formatTime(
                                    (song['duration'] as num).toDouble()),
                                style: TextStyle(
                                  color: colorScheme.outline,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
