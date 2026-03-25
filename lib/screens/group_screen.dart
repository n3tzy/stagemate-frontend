import 'package:flutter/material.dart';
import '../api/api_client.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _roomCodeController = TextEditingController();
  double _durationNeeded = 2.0;

  // DB에서 불러온 데이터
  // { '민수': [ {'id':1,'day':'화','start':14.0,'end':20.0} ] }
  Map<String, List<dynamic>> _memberSlots = {};
  String _myDisplayName = '';
  int? _myUserId;

  Map<String, dynamic>? _result;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<String> _days = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _loadMyInfo();
  }

  // 내 정보 불러오기
  Future<void> _loadMyInfo() async {
    final name = await ApiClient.getDisplayName();
    final id = await ApiClient.getUserId();
    setState(() {
      _myDisplayName = name ?? '';
      _myUserId = id;
    });
    await _loadAvailability();
  }

  // 방 코드의 가능 시간 불러오기
  Future<void> _loadAvailability() async {
    if (_roomCodeController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.getAvailability(
        _roomCodeController.text.trim(),
      );
      setState(() {
        _memberSlots = Map<String, List<dynamic>>.from(
          (data['members'] as Map).map(
            (key, value) => MapEntry(key, List<dynamic>.from(value)),
          ),
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatClock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _slotLabel(dynamic slot) {
    return '${slot['day']}  ${_formatClock((slot['start'] as num).toDouble())}'
        '~${_formatClock((slot['end'] as num).toDouble())}';
  }

  // 내 가능 시간 추가 다이얼로그
  Future<void> _showAddSlotDialog() async {
    int selectedDayIndex = 0;
    double startTime = 14.0;
    double endTime = 18.0;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedDay = _days[selectedDayIndex];
          return AlertDialog(
            title: Text('내 가능 시간 추가\n($_myDisplayName)'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '방 코드: ${_roomCodeController.text.trim()}',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 요일 선택
                    Text(
                      '요일 선택',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(_days.length, (i) {
                        final isSelected = selectedDayIndex == i;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedDayIndex = i);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Theme.of(ctx)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _days[i],
                              style: TextStyle(
                                color: isSelected
                                    ? Theme.of(ctx).colorScheme.onPrimary
                                    : Theme.of(ctx).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),

                    // 시작 시간
                    Text(
                      '시작: ${_formatClock(startTime)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: startTime,
                      min: 6.0,
                      max: 23.0,
                      divisions: 34,
                      label: _formatClock(startTime),
                      onChanged: (val) {
                        setDialogState(() {
                          startTime = val;
                          if (endTime <= startTime) endTime = startTime + 1.0;
                        });
                      },
                    ),

                    // 종료 시간
                    Text(
                      '종료: ${_formatClock(endTime)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: endTime,
                      min: 6.5,
                      max: 24.0,
                      divisions: 35,
                      label: _formatClock(endTime),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val > startTime) endTime = val;
                        });
                      },
                    ),

                    // 시간 요약
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '$selectedDay  ${_formatClock(startTime)}'
                            '~${_formatClock(endTime)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
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
                  setState(() => _isSaving = true);
                  try {
                    final result = await ApiClient.saveAvailability(
                      roomCode: _roomCodeController.text.trim(),
                      day: _days[selectedDayIndex],
                      startTime: startTime,
                      endTime: endTime,
                    );
                    // 서버가 성공 응답(message 포함)인지 확인
                    if (!result.containsKey('message')) {
                      throw Exception(
                        result['detail']?.toString() ?? '저장에 실패했습니다.',
                      );
                    }
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ 저장됐습니다!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    await _loadAvailability(); // 새로고침
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('저장 실패: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 내 슬롯 삭제 (본인것만)
  Future<void> _deleteSlot(int slotId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 시간대를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiClient.deleteAvailability(slotId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제됐습니다.')),
        );
        await _loadAvailability();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  // 공통 시간 찾기
  Future<void> _findCommonSlots() async {
    if (_memberSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가능 시간을 먼저 등록해주세요!')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await ApiClient.getGroupSchedule(
        _roomCodeController.text.trim(),
        _durationNeeded,
      );
      setState(() => _result = result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 스케줄 조율'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          // 새로고침
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAvailability,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 방 설정 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '방 설정',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _roomCodeController,
                            decoration: const InputDecoration(
                              labelText: '방 코드',
                              hintText: '예: DANCE2026',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.tag),
                              suffixIcon: Tooltip(
                                message: '방 코드는 팀 단위 코드예요.\n같은 팀원끼리 동일한 코드를 입력하면\n팀 스케줄을 함께 조율할 수 있어요.',
                                triggerMode: TooltipTriggerMode.tap,
                                showDuration: Duration(seconds: 5),
                                child: Icon(Icons.info_outline),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _loadAvailability,
                          child: const Text('조회'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '필요 연습 시간: ${_durationNeeded.toStringAsFixed(1)}시간',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: _durationNeeded,
                      min: 0.5,
                      max: 6.0,
                      divisions: 11,
                      label: '${_durationNeeded.toStringAsFixed(1)}시간',
                      onChanged: (val) {
                        setState(() {
                          _durationNeeded = val;
                          _result = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── 내 가능 시간 추가 버튼 ──
            FilledButton.icon(
              onPressed: _isSaving ? null : _showAddSlotDialog,
              icon: const Icon(Icons.add),
              label: Text('내 가능 시간 추가 ($_myDisplayName)'),
            ),
            const SizedBox(height: 16),

            // ── 멤버별 가능 시간 목록 ──
            Text(
              '멤버 가능 시간 (${_memberSlots.length}명 등록)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_memberSlots.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.group_add,
                          size: 48, color: colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        '아직 등록된 가능 시간이 없어요\n내 가능 시간을 추가해보세요!',
                        style: TextStyle(color: colorScheme.outline),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._memberSlots.entries.map((entry) {
                final memberName = entry.key;
                final slots = entry.value;
                final isMe = memberName == _myDisplayName;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  // 내 카드는 강조
                  color: isMe
                      ? colorScheme.primaryContainer.withOpacity(0.3)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 멤버 이름
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isMe
                                  ? colorScheme.primary
                                  : colorScheme.secondaryContainer,
                              child: Text(
                                memberName[0],
                                style: TextStyle(
                                  color: isMe
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              memberName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '나',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              '${slots.length}개',
                              style: TextStyle(
                                color: colorScheme.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 슬롯 목록
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: slots.map((slot) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? colorScheme.primaryContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _slotLabel(slot),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isMe
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                  // 내 슬롯만 삭제 버튼 표시
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () =>
                                          _deleteSlot(slot['id'] as int),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 16),

            // ── 공통 시간 찾기 버튼 ──
            FilledButton.icon(
              onPressed: _isLoading ? null : _findCommonSlots,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isLoading ? '찾는 중...' : '✨ 공통 시간 찾기'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            // ── 결과 섹션 ──
            if (_result != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // best_slot
              if (_result!['best_slot'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('🏆', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 8),
                          Text(
                            '최적 추천 시간',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _slotLabel(_result!['best_slot']),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '참여 가능: ${(_result!['best_slot']['available_members'] as List).join(', ')}',
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 전원 가능
              if ((_result!['common_slots'] as List).isNotEmpty) ...[
                Text(
                  '✅ 전원 가능 시간 (${(_result!['common_slots'] as List).length}개)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                ),
                const SizedBox(height: 8),
                ...(_result!['common_slots'] as List).map((slot) {
                  final members =
                      (slot['available_members'] as List).join(', ');
                  final duration =
                      (slot['end'] as num) - (slot['start'] as num);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: const Text('✅'),
                      ),
                      title: Text(
                        _slotLabel(slot),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('👥 $members'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${duration.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // 부분 가능
              if ((_result!['partial_slots'] as List).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '🔶 일부 가능 시간 (${(_result!['partial_slots'] as List).length}개)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                ),
                const SizedBox(height: 8),
                ...(_result!['partial_slots'] as List).map((slot) {
                  final members =
                      (slot['available_members'] as List).join(', ');
                  final duration =
                      (slot['end'] as num) - (slot['start'] as num);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        child: const Text('🔶'),
                      ),
                      title: Text(
                        _slotLabel(slot),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('👥 $members'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${duration.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // 결과 없음
              if ((_result!['common_slots'] as List).isEmpty &&
                  (_result!['partial_slots'] as List).isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '😢 공통 가능 시간이 없어요.\n멤버들의 가능 시간을 다시 확인해주세요!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
