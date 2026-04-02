import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../widgets/youtube_card.dart';

class ChallengeScreen extends StatefulWidget {
  final bool isAdmin;
  final int clubId;

  const ChallengeScreen({
    super.key,
    required this.isAdmin,
    required this.clubId,
  });

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.getCurrentChallenge();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _toggleLike(int entryId) async {
    try {
      await ApiClient.toggleChallengeLike(entryId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _submit() async {
    // 아카이브 목록에서 선택
    final archives =
        await ApiClient.getPerformanceArchives(widget.clubId);
    if (!mounted || archives.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('먼저 공연 기록 탭에서 공연을 추가해주세요!')));
      }
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: archives.length,
        itemBuilder: (_, i) {
          final a = archives[i];
          return ListTile(
            title: Text(a['title'] as String),
            subtitle: Text(a['performance_date'] as String),
            onTap: () => Navigator.pop(ctx, a as Map<String, dynamic>),
          );
        },
      ),
    );
    if (selected == null) return;

    try {
      await ApiClient.submitChallengeEntry(selected['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('챌린지에 참가되었습니다!')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = (_data?['entries'] as List<dynamic>?) ?? [];
    final daysLeft = _data?['days_left'] as int? ?? 0;
    final entryCount = _data?['entry_count'] as int? ?? 0;
    final yearMonth = _data?['year_month'] as String? ?? '';
    final myClubId = _data?['my_club_id'] as int?;
    final isParticipating = entries.any(
        (e) => (e as Map)['club_id'] == myClubId);

    return Scaffold(
      appBar: AppBar(
        title: Text('$yearMonth 챌린지'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // D-day 배너
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('결과 발표까지',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12)),
                            Text('D-$daysLeft',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('참가 동아리',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12)),
                            Text('$entryCount개',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 참가 버튼 (admin + 미참가)
                  if (widget.isAdmin && !isParticipating)
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add_circle),
                      label: const Text('우리 동아리 영상 제출하기'),
                    ),
                  if (widget.isAdmin && isParticipating)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ApiClient.withdrawChallengeEntry();
                        await _load();
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('제출 취소'),
                    ),
                  const SizedBox(height: 16),

                  // 랭킹 목록
                  ...entries.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final entry = e.value as Map<String, dynamic>;
                    final liked = entry['my_liked'] as bool? ?? false;
                    final likesCount = entry['likes_count'] as int? ?? 0;
                    final youtubeUrl = entry['youtube_url'] as String?;
                    final isFirst = rank == 1;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: isFirst
                          ? RoundedRectangleBorder(
                              side: BorderSide(
                                  color: Colors.amber.shade600, width: 2),
                              borderRadius: BorderRadius.circular(12))
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Stack(
                                children: [
                                  YouTubeCard(youtubeUrl: youtubeUrl),
                                  if (isFirst)
                                    Positioned(
                                      top: 8, left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade600,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.workspace_premium,
                                                size: 14,
                                                color: Colors.white),
                                            SizedBox(width: 3),
                                            Text('1위',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isFirst
                                  ? Colors.amber.shade100
                                  : colorScheme.surfaceContainerHighest,
                              child: Text('$rank',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isFirst
                                          ? Colors.amber.shade800
                                          : null)),
                            ),
                            title: Text(
                                entry['club_name'] as String? ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                entry['archive_title'] as String? ?? ''),
                            trailing: GestureDetector(
                              onTap: () => _toggleLike(
                                  entry['entry_id'] as int),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: liked ? Colors.red : null,
                                    size: 22,
                                  ),
                                  Text('$likesCount',
                                      style:
                                          const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
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
}
