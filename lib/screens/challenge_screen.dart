import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
    final myRank = myClubId != null && entries.isNotEmpty
        ? entries.indexWhere((e) => (e as Map)['club_id'] == myClubId) + 1
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('$yearMonth 챌린지'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share(
              'StageMate 공연 랭킹을 확인해보세요! 🎵\nhttps://stagemate.netzy.dev/ranking',
              subject: 'StageMate 공연 랭킹',
            ),
            tooltip: '랭킹 공유',
          ),
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
                          children: [
                            Text('내 동아리',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12)),
                            Text(myRank > 0 ? '$myRank위' : '-',
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
                  if (entries.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, idx) {
                        final rank = idx + 1;
                        final entry = entries[idx] as Map<String, dynamic>;
                        final liked = entry['my_liked'] as bool? ?? false;
                        final likesCount = entry['likes_count'] as int? ?? 0;
                        final youtubeUrl = entry['youtube_url'] as String?;
                        final isFirst = rank == 1;
                        final videoId = youtubeUrl != null ? extractYouTubeId(youtubeUrl) : null;

                        return Card(
                          shape: isFirst
                              ? RoundedRectangleBorder(
                                  side: BorderSide(color: Colors.amber.shade600, width: 2),
                                  borderRadius: BorderRadius.circular(12))
                              : null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: youtubeUrl != null
                                ? () => launchUrl(Uri.parse(youtubeUrl),
                                    mode: LaunchMode.externalApplication)
                                : null,
                            onLongPress: () {
                              final clubId = entry['club_id'];
                              final clubName = entry['club_name'] as String? ?? '';
                              final url = 'https://stagemate.netzy.dev/clubs/$clubId/public';
                              showModalBottomSheet(
                                context: context,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.link),
                                        title: Text(clubName),
                                        subtitle: Text(url, style: const TextStyle(fontSize: 11)),
                                      ),
                                      const Divider(height: 1),
                                      ListTile(
                                        leading: const Icon(Icons.copy),
                                        title: const Text('링크 복사'),
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: url));
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('링크가 복사되었습니다!')),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.share_outlined),
                                        title: const Text('공유하기'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Share.share(url, subject: '$clubName 공연 기록');
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 썸네일
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                        child: videoId != null
                                            ? Image.network(
                                                'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  color: const Color(0xFF1a1a2e),
                                                  child: const Icon(Icons.play_circle_outline,
                                                      color: Colors.white54, size: 36),
                                                ),
                                              )
                                            : Container(
                                                color: const Color(0xFF1a1a2e),
                                                child: const Icon(Icons.music_note,
                                                    color: Colors.white54, size: 36),
                                              ),
                                      ),
                                      // 순위 배지
                                      Positioned(
                                        top: 6, left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isFirst ? Colors.amber.shade600 : Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isFirst) ...[
                                                const Icon(Icons.workspace_premium,
                                                    size: 12, color: Colors.white),
                                                const SizedBox(width: 2),
                                              ],
                                              Text('$rank위',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 정보
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry['club_name'] as String? ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry['archive_title'] as String? ?? '',
                                              style: const TextStyle(
                                                  fontSize: 11, color: Colors.grey),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _toggleLike(entry['entry_id'] as int),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  liked ? Icons.favorite : Icons.favorite_border,
                                                  color: liked ? Colors.red : Colors.grey,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 2),
                                                Text('$likesCount',
                                                    style: const TextStyle(fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
