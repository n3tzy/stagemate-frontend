import 'package:flutter/material.dart';
import '../api/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiClient.getNotifications();
      await ApiClient.markNotificationsRead();
      if (mounted) {
        setState(() {
          _notifications = (data['notifications'] as List?) ?? [];
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: const Text('알림'),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _load,
              child: Text(
                '모두 읽음',
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_outlined,
                        size: 56,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '새 알림이 없어요',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: colorScheme.outlineVariant),
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      final isRead = n['is_read'] as bool? ?? true;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.primaryContainer,
                          child: Icon(
                            Icons.chat_bubble_outline,
                            size: 20,
                            color: isRead
                                ? colorScheme.outline
                                : colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          n['message'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          n['created_at'] ?? '',
                          style: TextStyle(fontSize: 12, color: colorScheme.outline),
                        ),
                        tileColor: isRead
                            ? null
                            : colorScheme.primaryContainer.withValues(alpha: 0.3),
                      );
                    },
                  ),
                ),
    );
  }
}
