import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../home/home_provider.dart';
import 'chat_history_provider.dart';
import 'widgets/overdue_notes_dialog.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueProvider);
    final historyAsync = ref.watch(chatHistoryProvider);
    final overdueCount = overdueAsync.valueOrNull?.count ?? 0;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('复习')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                if (overdueCount > 0) ...[
                  Card(
                    child: GestureDetector(
                      onTap: () => showOverdueNotesDialog(
                          context, overdueAsync.valueOrNull!.records),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.error.withAlpha(25),
                                border: Border.all(
                                  color: theme.colorScheme.error,
                                  width: 3,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$overdueCount',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text('待复习',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('有笔记需要复习',
                                      style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('点击查看详情',
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push('/review/start'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始复习'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text('历史聊天',
                    style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
                const SizedBox(height: 8),
                historyAsync.when(
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('暂无聊天记录\n在自由聊天中与 AI 交流后记录将出现在这里',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: sessions.map((session) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.chat_bubble_outline,
                              color: theme.colorScheme.primary),
                          title: Text(
                            DateFormat('M月d日').format(session.date),
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            '${session.messages.length} 条消息 · ${session.messages.last.content.length > 30 ? "${session.messages.last.content.substring(0, 30)}..." : session.messages.last.content}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                                            trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showSessionDetail(context, ref, session),
                        ),
                      )).toList(),
                    );
                  },
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('加载失败: $e'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/review/chat'),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('随便聊聊'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionDetail(BuildContext context, WidgetRef ref, ChatSession session) {
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
                      context.push('/review/chat');
                    },
                    icon: const Icon(Icons.chat, size: 16),
                    label: const Text('继续对话', style: TextStyle(fontSize: 13)),
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
                          MarkdownBody(
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
}
