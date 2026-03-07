import 'package:flutter/material.dart';
import '../api/api_client.dart';

class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  List<dynamic> _notices = [];
  bool _isLoading = false;
  String _role = 'user';
  String _myDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient.getRole(),
        ApiClient.getDisplayName(),
        ApiClient.getNotices(),
      ]);
      setState(() {
        _role = (results[0] as String?) ?? 'user';
        _myDisplayName = (results[1] as String?) ?? '';
        _notices = results[2] as List;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 공지사항 작성 다이얼로그 (admin만)
  Future<void> _showWriteDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공지사항 작성'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 2026 봄 공연 무대 순서 확정',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    hintText: '공지 내용을 입력하세요',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final content = contentController.text.trim();
              if (title.isEmpty || content.isEmpty) return;

              final result = await ApiClient.createNotice(
                title: title,
                content: content,
              );
              Navigator.pop(dialogContext);

              if (result.containsKey('id')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ 공지사항이 등록됐습니다!'),
                    backgroundColor: Colors.green,
                  ),
                );
                await _loadData();
              }
            },
            child: const Text('등록'),
          ),
        ],
      ),
    );
  }

  // 공지사항 상세 보기
  Future<void> _showDetail(int id) async {
    final notice = await ApiClient.getNotice(id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(notice['title']),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 작성자 / 날짜
                Row(
                  children: [
                    Icon(Icons.person,
                        size: 14,
                        color: Theme.of(dialogContext).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      '${notice['author']}  ·  ${notice['created_at']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(dialogContext).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                // 내용
                Text(
                  notice['content'],
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // 회장: 모든 공지 삭제 가능 / 임원진: 본인 작성 공지만 삭제 가능
          if (_role == 'super_admin' ||
              (_role == 'admin' && notice['author'] == _myDisplayName))
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ApiClient.deleteNotice(id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('삭제됐습니다.')),
                );
                await _loadData();
              },
              child: Text(
                '삭제',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📢 공지사항'),
        backgroundColor: colorScheme.primaryContainer,
        // admin / super_admin만 작성 버튼 표시
        actions: [
          if (_role == 'admin' || _role == 'super_admin')
            FilledButton.icon(
              onPressed: _showWriteDialog,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('작성'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign,
                          size: 56, color: colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        '등록된 공지사항이 없어요',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                      if (_role == 'admin' || _role == 'super_admin') ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _showWriteDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('첫 공지사항 작성하기'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notices.length,
                    itemBuilder: (context, i) {
                      final notice = _notices[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${_notices.length - i}',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            notice['title'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${notice['author']}  ·  ${notice['created_at']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showDetail(notice['id']),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
