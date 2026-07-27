import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class EvaluationView extends StatelessWidget {
  final String evaluation;
  final int? suggestedScore;
  final String? extension;
  final ValueChanged<int>? onScore;
  final int? selectedScore;

  const EvaluationView({
    super.key,
    required this.evaluation,
    this.suggestedScore,
    this.extension,
    this.onScore,
    this.selectedScore,
  });

  @override
  Widget build(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 20, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Text('AI 评价', style: theme.textTheme.labelMedium),
                    if (suggestedScore != null) ...[
                      const Spacer(),
                      Text('建议 $suggestedScore 分',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.tertiary,
                          )),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                MarkdownBody(data: evaluation, styleSheet: mdStyle, selectable: true),
                if (extension != null && extension!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('延伸思考',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  MarkdownBody(data: extension!, styleSheet: mdStyle, selectable: true),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (onScore != null) ...[
          Text('自评分数', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (i) {
              return _ScoreButton(
                score: i,
                isSelected: selectedScore == i,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onScore!(i);
                },
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  final int score;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScoreButton({
    required this.score,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.lime,
      Colors.lightGreen,
      Colors.green,
    ];
    final color = colors[score];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text('$score',
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                )),
            Text('分',
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontSize: 11,
                )),
          ],
        ),
      ),
    );
  }
}
