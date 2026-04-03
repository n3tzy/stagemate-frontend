import 'package:flutter/material.dart';
import '../api/api_client.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  String _selectedDate = _todayString();
  Map<String, dynamic>? _bookingData;
  bool _isLoading = false;
  int? _myUserId;  // 현재 로그인한 유저 ID
  String _role = 'user';  // 예약 생성 권한 체크용

  // 모든 멤버 예약 가능
  bool get _canCreateBooking => _role.isNotEmpty;

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatClock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.getBookings(_selectedDate);
      setState(() => _bookingData = data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2027, 12, 31),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        _bookingData = null;
      });
      await _loadBookings();
    }
  }

  Future<void> _showAddBookingDialog() async {
    final teamController = TextEditingController();
    final noteController = TextEditingController();
    double startTime = 14.0;
    double endTime = 16.0;
    String selectedRoom = '동아리방';           // ← 드롭다운 기본값
    bool isExternal = false;                   // ← 외부 연습실 여부

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('예약 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 날짜 표시
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDate,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 팀 이름
                TextField(
                  controller: teamController,
                  style: const TextStyle(fontFamily: 'AritaBuri'),
                  decoration: const InputDecoration(
                    labelText: '팀 이름',
                    hintText: '예: 팀 블루',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ── 연습실 드롭다운 ──
                DropdownButtonFormField<String>(
                  value: selectedRoom,
                  decoration: const InputDecoration(
                    labelText: '연습실',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.meeting_room),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '동아리방',
                      child: Row(
                        children: [
                          Icon(Icons.home, size: 18),
                          SizedBox(width: 8),
                          Text('동아리방'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: '외부 연습실',
                      child: Row(
                        children: [
                          Icon(Icons.location_on, size: 18),
                          SizedBox(width: 8),
                          Text('외부 연습실'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setDialogState(() {
                      selectedRoom = val!;
                      isExternal = val == '외부 연습실';
                      // 외부 연습실 선택시 메모 힌트 안내
                      if (isExternal && noteController.text.isEmpty) {
                        noteController.text = '';
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),

                // 외부 연습실 선택시 안내 배너
                if (isExternal) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '아래 메모에 외부 연습실명을 기재해주세요\n예: 홍대 스튜디오A, OO댄스학원 등',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 시작 시간 슬라이더
                Text(
                  '시작 시간: ${_formatClock(startTime)}',
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
                      if (endTime <= startTime) {
                        endTime = startTime + 1.0;
                      }
                    });
                  },
                ),

                // 종료 시간 슬라이더
                Text(
                  '종료 시간: ${_formatClock(endTime)}',
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

                // 예약 시간 요약
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatClock(startTime)} ~ ${_formatClock(endTime)}'
                        '  (${(endTime - startTime).toStringAsFixed(1)}시간)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 메모
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: isExternal
                        ? '외부 연습실명 (필수)' // ← 외부 선택시 필수 표시
                        : '메모 (선택)',
                    hintText: isExternal
                        ? '예: 홍대 스튜디오A, OO댄스학원'
                        : '예: 안무 맞춰보기',
                    border: const OutlineInputBorder(),
                    // 외부 연습실일 때 강조
                    focusedBorder: isExternal
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(dialogContext).colorScheme.tertiary,
                              width: 2,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                final team = teamController.text.trim();
                final note = noteController.text.trim();

                if (team.isEmpty) return;

                // 외부 연습실인데 연습실명 미기재시 경고
                if (isExternal && note.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ 외부 연습실명을 메모에 기재해주세요!'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                final result = await ApiClient.createBooking({
                  'team_name': team,
                  'room_name': selectedRoom,
                  'date': _selectedDate,
                  'start_time': startTime,
                  'end_time': endTime,
                  'note': note,
                });

                if (result['success'] == true) {
                  Navigator.pop(dialogContext);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ 예약이 완료되었습니다!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  await _loadBookings();
                } else {
                  final conflicts =
                      (result['conflicts'] as List?)?.join('\n') ?? '';
                  showDialog(
                    context: dialogContext,
                    builder: (innerContext) => AlertDialog(
                      title: const Text('⚠️ 예약 충돌!'),
                      content: Text(conflicts),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(innerContext),
                          child: const Text('확인'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Text('예약'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBooking(int id, String teamName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('예약 취소'),
        content: Text('$teamName 의 예약을 취소할까요?'),
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
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiClient.deleteBooking(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('예약이 취소되었습니다.')),
          );
        }
        await _loadBookings();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('예약 취소에 실패했어요. ${friendlyError(e)}')),
          );
        }
      }
    }
  }

  Map<String, List<dynamic>> _groupByRoom(List<dynamic> bookings) {
    final Map<String, List<dynamic>> grouped = {};
    for (final b in bookings) {
      final room = b['room_name'].toString();
      grouped.putIfAbsent(room, () => []);
      grouped[room]!.add(b);
    }
    return grouped;
  }

  @override
  void initState() {
    super.initState();
    _loadMyInfo();
    _loadBookings();
  }

  Future<void> _loadMyInfo() async {
    final id = await ApiClient.getUserId();
    final role = await ApiClient.getRole();
    if (mounted) {
      setState(() {
        _myUserId = id;
        _role = role ?? 'user';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('연습실 예약'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  _selectedDate,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('날짜를 탭해서 변경'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            if (_canCreateBooking)
              FilledButton.icon(
                onPressed: _showAddBookingDialog,
                icon: const Icon(Icons.add),
                label: const Text('예약 추가하기'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadBookings,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBookingList(colorScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingList(ColorScheme colorScheme) {
    if (_bookingData == null) {
      return const Center(child: Text('날짜를 선택해주세요'));
    }
    final bookings = _bookingData!['bookings'] as List;
    final conflicts = _bookingData!['conflicts'] as List;

    if (bookings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.meeting_room, size: 56, color: colorScheme.outline),
                const SizedBox(height: 8),
                Text(
                  '$_selectedDate 예약 없음',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final grouped = _groupByRoom(bookings);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (conflicts.isNotEmpty) ...[
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
                  '⚠️ 예약 충돌 발생!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                ...conflicts.map((c) => Text(
                      c.toString(),
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        ...grouped.entries.map((entry) {
          final roomName = entry.key;
          final roomBookings = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    // 동아리방 vs 외부 연습실 아이콘 구분
                    Icon(
                      roomName == '동아리방'
                          ? Icons.home
                          : Icons.location_on,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      roomName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${roomBookings.length}건',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              ...roomBookings.map((b) {
                final startTime = (b['start_time'] as num).toDouble();
                final endTime = (b['end_time'] as num).toDouble();
                final duration = endTime - startTime;
                final note = b['note']?.toString() ?? '';
                final isExt = b['room_name'].toString() == '외부 연습실';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        // 외부 연습실은 다른 색으로 구분
                        color: isExt
                            ? colorScheme.tertiary
                            : colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    title: Text(
                      b['team_name'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${_formatClock(startTime)} ~ ${_formatClock(endTime)}'
                      '  (${duration.toStringAsFixed(1)}시간)'
                      '${note.isNotEmpty ? '\n📝 $note' : ''}',
                    ),
                    isThreeLine: note.isNotEmpty,
                    // 본인 예약일 때만 삭제 버튼 표시
                    trailing: (_myUserId != null &&
                            b['user_id'] != null &&
                            b['user_id'] == _myUserId)
                        ? IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            color: colorScheme.error,
                            tooltip: '내 예약 취소',
                            onPressed: () => _deleteBooking(
                              b['id'] as int,
                              b['team_name'].toString(),
                            ),
                          )
                        : null,
                  ),
                );
              }),
              const Divider(),
            ],
          );
        }),
      ],
    );
  }
}
