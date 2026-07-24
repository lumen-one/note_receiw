import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reviewStateProvider.notifier).loadQuestions();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewStateProvider);
    final theme = Theme.of(context);

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('正在生成题目...')),
        body: const Center(child: CircularProgressIndicator()),
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
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (state.currentQuestionIndex + 1) / state.questions.length,
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
                      onScore: (score) {
                        ref
                            .read(reviewStateProvider.notifier)
                            .submitSelfScore(score);
                      },
                    ),
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
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.push('/review/chat'),
                            icon: const Icon(Icons.chat),
                            label: const Text('自由聊天'),
                          ),
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
    final item = stateNow.questions[stateNow.currentQuestionIndex];

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '你是一位和我一起学习的挚友。我们正在讨论以下笔记内容：\n${item.noteContent}',
      },
      {
        'role': 'assistant',
        'content': '题目：${item.question}\n\n评价：${item.evaluation ?? ""}',
      },
      {'role': 'user', 'content': '我的回答：${item.userAnswer ?? ""}'},
      ..._followUpMessages,
    ];

    try {
      final reply = await ref.read(aiServiceProvider).continueChat(messages: messages);
      setState(() {
        _followUpMessages.add({'role': 'assistant', 'content': reply});
      });
    } catch (e) {
      setState(() {
        _followUpMessages.add({
          'role': 'assistant',
          'content': '抱歉，请求失败：$e',
        });
      });
    }
  }
}
