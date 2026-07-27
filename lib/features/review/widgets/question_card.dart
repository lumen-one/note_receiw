import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../services/latex_markdown.dart';

class QuestionCard extends StatelessWidget {
  final String question;
  final String expansion;
  final TextEditingController answerController;
  final VoidCallback onSubmit;

  const QuestionCard({
    super.key,
    required this.question,
    required this.expansion,
    required this.answerController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mdStyle = MarkdownStyleSheet(
      p: theme.textTheme.bodyLarge,
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
    final mdStyleSmall = MarkdownStyleSheet(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('题目', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                LaTeXMarkdown(data: question, styleSheet: mdStyle, selectable: true),
              ],
            ),
          ),
        ),
        if (expansion.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('拓展知识', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 8),
                  LaTeXMarkdown(data: expansion, styleSheet: mdStyleSmall, selectable: true),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: answerController,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: '输入你的回答...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.send),
          label: const Text('提交回答'),
        ),
      ],
    );
  }
}
