import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../services/latex_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart';
import '../settings/settings_provider.dart';

class NoteDetailScreen extends ConsumerWidget {
  final int noteId;

  const NoteDetailScreen({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('笔记详情')),
      body: FutureBuilder(
        future: Future.wait([
          db.recordForNote(noteId),
          db.messagesForNote(noteId),
        ]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final record = snapshot.data![0] as ReviewRecord?;
          final allMessages = snapshot.data![1] as List<ChatMessage>;

          final sessions = _groupByDate(allMessages);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader(context, 'SM-2 复习状态'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _statusRow('熟练度系数', record?.sm2EaseFactor.toStringAsFixed(1) ?? '未复习'),
                      const Divider(),
                      _statusRow('当前间隔', record != null ? '${record.sm2Interval.toInt()} 天' : '-'),
                      const Divider(),
                      _statusRow('复习次数', '${record?.sm2Repetitions ?? 0} 次'),
                      const Divider(),
                      _statusRow('上次评分', record?.lastScore?.toString() ?? '-'),
                      const Divider(),
                      _statusRow('上次复习', record?.lastReviewDate != null
                          ? DateFormat('yyyy-MM-dd HH:mm').format(record!.lastReviewDate!)
                          : '从未'),
                      const Divider(),
                      _statusRow('下次复习', record?.nextReviewDate != null
                          ? DateFormat('yyyy-MM-dd HH:mm').format(record!.nextReviewDate)
                          : '-'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeader(context, '会话历史'),
              if (sessions.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text('暂无会话记录',
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                )
              else
                ...sessions.map((session) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.chat_bubble_outline,
                        color: theme.colorScheme.primary),
                    title: Text(
                      DateFormat('yyyy年M月d日').format(session.date),
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '${session.messages.length} 条消息',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showSessionDetail(
                      context, ref, session, noteId),
                  ),
                )),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('清除聊天记录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认清除'),
                        content: const Text('清除此笔记相关的所有聊天记录，操作不可恢复。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('清除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await db.clearMessagesForNote(noteId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('聊天记录已清除')),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_off),
                  label: const Text('解除监控笔记'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认解除监控'),
                        content: const Text('解除监控后，此笔记将不再参与复习和统计。笔记文件本身不会被修改。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('解除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await db.updateNoteActive(noteId, false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已解除监控')),
                        );
                        Navigator.of(context).pop();
                      }
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_MessageSession> _groupByDate(List<ChatMessage> messages) {
    final groups = <String, List<ChatMessage>>{};
    for (final msg in messages) {
      final key = DateFormat('yyyy-MM-dd').format(msg.createdAt);
      groups.putIfAbsent(key, () => []).add(msg);
    }
    final sessions = groups.entries.map((e) {
      final date = DateTime.parse(e.key);
      return _MessageSession(date: date, messages: e.value);
    }).toList();
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  void _showSessionDetail(
      BuildContext context, WidgetRef ref, _MessageSession session, int noteId) {
    final theme = Theme.of(context);
    final mdStyle = MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium,
      code: TextStyle(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Text(
                    DateFormat('M月d日').format(session.date),
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text('${session.messages.length} 条消息',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.push('/review/chat?notes=$noteId&session=review_$noteId');
                    },
                    icon: const Icon(Icons.chat, size: 16),
                    label: Text('继续对话', style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: session.messages.length,
                itemBuilder: (context, index) {
                  final msg = session.messages[index];
                  final isUser = msg.role == 'user';
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LaTeXMarkdown(
                            data: msg.content,
                            styleSheet: mdStyle,
                            selectable: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('HH:mm').format(msg.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}

class _MessageSession {
  final DateTime date;
  final List<ChatMessage> messages;

  _MessageSession({required this.date, required this.messages});
}
