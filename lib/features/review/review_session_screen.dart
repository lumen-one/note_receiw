import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../settings/settings_provider.dart';
import 'review_provider.dart';
import 'widgets/question_card.dart';
import 'widgets/evaluation_view.dart';
import 'widgets/chat_bubble.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  final _answerController = TextEditingController();
  bool _showFollowUpChat = false;
  List<Map<String, String>> _followUpMessages = [];
  ReviewNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier = ref.read(reviewStateProvider.notifier);
      _notifier!.loadQuestions();
    });
  }

  @override
  void dispose() {
    // 离开页面就中断后台流，避免生成还在往已卸载的状态里写
    _notifier?.stopGeneration();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewStateProvider);
    final theme = Theme.of(context);

    if (state.questions.isEmpty && state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('正在生成题目...')),
        body: Column(
          children: [
            const LinearProgressIndicator(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      if (state.statusMessage != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          state.statusMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (state.generatingText != null &&
                          state.generatingText!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            state.generatingText!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.phase == ReviewPhase.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text('出错了', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  state.errorMessage ?? '未知错误',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.read(reviewStateProvider.notifier).loadQuestions(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习')),
        body: const Center(child: Text('暂无待复习笔记')),
      );
    }

    final question = state.questions[state.currentQuestionIndex];
    final progress =
        '${state.currentQuestionIndex + 1} / ${state.questions.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 - 第 $progress 题'),
        actions: [
          if (state.phase == ReviewPhase.showingQuestions ||
              state.phase == ReviewPhase.answering)
            TextButton.icon(
              onPressed: () => ref
                  .read(reviewStateProvider.notifier)
                  .skipToScoring(),
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('跳过'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (state.isLoading)
            const LinearProgressIndicator()
          else
            LinearProgressIndicator(
              value: (state.currentQuestionIndex + 1) / state.questions.length,
            ),
          if (state.isLoading && state.questions.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.tertiaryContainer,
              child: Row(
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.statusMessage ?? '正在生成更多题目...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          if (state.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16,
                        color: theme.colorScheme.onErrorContainer),
                    onPressed: () =>
                        ref.read(reviewStateProvider.notifier).clearError(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: '关闭提示',
                  ),
                ],
              ),
            ),
          if (state.phase != ReviewPhase.complete && state.warnings.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                state.warnings.last,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(question.fileName,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 12),
                  if (state.phase == ReviewPhase.showingQuestions ||
                      state.phase == ReviewPhase.answering)
                    QuestionCard(
                      question: question.question,
                      expansion: question.expansion,
                      answerController: _answerController,
                      onSubmit: () {
                        final answer = _answerController.text.trim();
                        if (answer.isNotEmpty) {
                          ref
                              .read(reviewStateProvider.notifier)
                              .submitAnswer(answer);
                        }
                      },
                    ),
                  if (state.phase == ReviewPhase.evaluating &&
                      question.evaluation != null)
                    EvaluationView(
                      evaluation: question.evaluation!,
                      suggestedScore: question.suggestedScore,
                      extension: question.extension,
                      selectedScore: question.selfScore,
                      onScore: (score) {
                        ref
                            .read(reviewStateProvider.notifier)
                            .submitSelfScore(score);
                      },
                    ),
                  if (state.phase == ReviewPhase.loading && state.questions.isNotEmpty) ...[
                    const SizedBox(height: 48),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('正在生成下一题...',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                        ],
                      ),
                    ),
                  ],
                  if (_showFollowUpChat) ...[
                    const Divider(height: 32),
                    Text('追问',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._followUpMessages
                        .map((m) => ChatBubble(
                              content: m['content'] ?? '',
                              isUser: m['role'] == 'user',
                            )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _answerController,
                            decoration: const InputDecoration(
                              hintText: '继续追问...',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () => _sendFollowUp(),
                        ),
                      ],
                    ),
                  ],
                  if (state.phase == ReviewPhase.evaluating &&
                      question.selfScore != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _showFollowUpChat = true);
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('追问'),
                        ),
                        FilledButton(
                          onPressed: () {
                            _answerController.clear();
                            setState(() {
                              _showFollowUpChat = false;
                              _followUpMessages = [];
                            });
                            ref
                                .read(reviewStateProvider.notifier)
                                .nextQuestion();
                          },
                          child: Text(
                            state.currentQuestionIndex <
                                    state.questions.length - 1
                                ? '下一题'
                                : state.isLoading
                                    ? '等待生成中...'
                                    : '完成复习',
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (state.phase == ReviewPhase.complete) ...[
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.celebration,
                              size: 64, color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('复习完成！', style: theme.textTheme.headlineSmall),
                          if (state.remainingNoteCount > 0) ...[
                            const SizedBox(height: 12),
                            Text(
                              '还有 ${state.remainingNoteCount} 篇逾期笔记，留到下一次',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.push('/review/chat'),
                            icon: const Icon(Icons.chat),
                            label: const Text('自由聊天'),
                          ),
                          if (state.warnings.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            Card(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('本次提示',
                                        style: theme.textTheme.labelMedium),
                                    const SizedBox(height: 8),
                                    for (final warning in state.warnings)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '· $warning',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFollowUp() async {
    final content = _answerController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _followUpMessages.add({'role': 'user', 'content': content});
    });
    _answerController.clear();

    final stateNow = ref.read(reviewStateProvider);
    if (stateNow.questions.isEmpty) return;
    final index =
        stateNow.currentQuestionIndex.clamp(0, stateNow.questions.length - 1).toInt();
    final item = stateNow.questions[index];
    final db = ref.read(databaseProvider);

    await db.insertChatMessage(
      sessionType: 'review_${item.noteId}',
      noteId: item.noteId,
      role: 'user',
      content: content,
    );

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '你是一位和我一起学习的挚友。我们正在讨论以下笔记内容：\n${item.noteContent}',
      },
      {
        'role': 'assistant',
        'content': '题目：${item.question}\n\n评价：${item.evaluation ?? ""}\n\n延伸思考：${item.extension ?? ""}',
      },
      {'role': 'user', 'content': '我的回答：${item.userAnswer ?? ""}'},
      ..._followUpMessages,
    ];

    try {
      final reply = await ref.read(aiServiceProvider).continueChat(messages: messages);
      if (!mounted) return;
      setState(() {
        _followUpMessages.add({'role': 'assistant', 'content': reply});
      });
      await db.insertChatMessage(
        sessionType: 'review_${item.noteId}',
        noteId: item.noteId,
        role: 'assistant',
        content: reply,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followUpMessages.add({
          'role': 'assistant',
          'content': '抱歉，请求失败：${AIService.describeError(e)}',
        });
      });
    }
  }
}
