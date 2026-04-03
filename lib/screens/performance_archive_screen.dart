import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../widgets/youtube_card.dart';

class PerformanceArchiveScreen extends StatefulWidget {
  final int clubId;
  final bool isAdmin;

  const PerformanceArchiveScreen({
    super.key,
    required this.clubId,
    required this.isAdmin,
  });

  @override
  State<PerformanceArchiveScreen> createState() =>
      _PerformanceArchiveScreenState();
}

class _PerformanceArchiveScreenState extends State<PerformanceArchiveScreen> {
  List<dynamic> _archives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.getPerformanceArchives(widget.clubId);
      if (mounted) setState(() { _archives = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _toggleLike(dynamic archive) async {
    try {
      await ApiClient.toggleArchiveLike(
        widget.clubId, archive['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _delete(int archiveId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공연 기록 삭제'),
        content: const Text('이 공연 기록을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.deletePerformanceArchive(widget.clubId, archiveId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _openAdd() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArchiveAddScreen(clubId: widget.clubId),
        fullscreenDialog: true,
      ),
    ).then((_) => _load());
  }

  void _openEdit(Map<String, dynamic> archive) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArchiveAddScreen(
          clubId: widget.clubId,
          existingArchive: archive,
        ),
        fullscreenDialog: true,
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('공연 기록'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openAdd,
              tooltip: '공연 기록 추가',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _archives.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined,
                              size: 56, color: colorScheme.outline),
                          const SizedBox(height: 8),
                          Text('등록된 공연 기록이 없어요',
                              style: TextStyle(color: colorScheme.outline)),
                          if (widget.isAdmin) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _openAdd,
                              icon: const Icon(Icons.add),
                              label: const Text('첫 공연 기록 추가하기'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _archives.length,
                      itemBuilder: (context, i) {
                        final a = _archives[i];
                        final youtubeUrl = a['youtube_url'] as String?;
                        final liked = a['my_liked'] as bool? ?? false;
                        final likesCount = a['likes_count'] as int? ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: YouTubeCard(youtubeUrl: youtubeUrl),
                                ),
                              ListTile(
                                title: Text(a['title'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(a['performance_date'] as String? ?? ''),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        liked ? Icons.favorite : Icons.favorite_border,
                                        color: liked ? Colors.red : null,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleLike(a),
                                    ),
                                    Text('$likesCount',
                                        style: const TextStyle(fontSize: 12)),
                                    if (widget.isAdmin)
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined,
                                            color: colorScheme.primary, size: 20),
                                        onPressed: () => _openEdit(a),
                                      ),
                                    if (widget.isAdmin)
                                      IconButton(
                                        icon: Icon(Icons.delete_outline,
                                            color: colorScheme.error, size: 20),
                                        onPressed: () =>
                                            _delete(a['id'] as int),
                                      ),
                                  ],
                                ),
                              ),
                              if ((a['description'] as String?)?.isNotEmpty ?? false)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Text(a['description'] as String,
                                      style: TextStyle(
                                                                                    color: colorScheme.onSurfaceVariant,
                                          fontSize: 13)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ── 공연 기록 추가 화면 ────────────────────────────────────────
class _ArchiveAddScreen extends StatefulWidget {
  final int clubId;
  final Map<String, dynamic>? existingArchive; // null = add mode, non-null = edit mode
  const _ArchiveAddScreen({required this.clubId, this.existingArchive});

  @override
  State<_ArchiveAddScreen> createState() => _ArchiveAddScreenState();
}

class _ArchiveAddScreenState extends State<_ArchiveAddScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _youtubeCtrl;
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _youtubeCtrl = TextEditingController();
    if (widget.existingArchive != null) {
      final a = widget.existingArchive!;
      _titleCtrl.text = a['title'] as String? ?? '';
      _descCtrl.text = a['description'] as String? ?? '';
      _youtubeCtrl.text = a['youtube_url'] as String? ?? '';
      // Parse date from 'YYYY-MM-DD' string
      final dateStr = a['performance_date'] as String? ?? '';
      if (dateStr.isNotEmpty) {
        try {
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            _selectedDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    try {
      if (widget.existingArchive != null) {
        // Edit mode
        await ApiClient.updatePerformanceArchive(
          widget.clubId,
          widget.existingArchive!['id'] as int,
          title: _titleCtrl.text.trim(),
          performanceDate: dateStr,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          youtubeUrl: _youtubeCtrl.text.trim().isEmpty ? null : _youtubeCtrl.text.trim(),
        );
      } else {
        // Add mode
        await ApiClient.createPerformanceArchive(
          widget.clubId,
          title: _titleCtrl.text.trim(),
          performanceDate: dateStr,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          youtubeUrl: _youtubeCtrl.text.trim().isEmpty ? null : _youtubeCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingArchive != null ? '공연 기록 수정' : '공연 기록 추가'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '공연 제목 *',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '공연 날짜 *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text('${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _youtubeCtrl,
              decoration: const InputDecoration(
                labelText: 'YouTube URL (선택)',
                prefixIcon: Icon(Icons.link, color: Colors.red),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_youtubeCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              YouTubeCard(youtubeUrl: _youtubeCtrl.text.trim()),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '설명 (선택, 셋리스트 등)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              maxLength: 1000,
            ),
          ],
        ),
      ),
    );
  }
}
