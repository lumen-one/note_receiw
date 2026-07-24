import 'package:flutter/material.dart';

class EvaluationView extends StatelessWidget {
  final String evaluation;
  final int? suggestedScore;
  final String? extension;
  final ValueChanged<int>? onScore;

  const EvaluationView({
    super.key,
    required this.evaluation,
    this.suggestedScore,
    this.extension,
    this.onScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Text(evaluation, style: theme.textTheme.bodyMedium),
                if (extension != null && extension!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('延伸思考',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(extension!, style: theme.textTheme.bodyMedium),
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
              return _ScoreButton(score: i, onTap: () => onScore!(i));
            }),
          ),
        ],
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  final int score;
  final VoidCallback onTap;

  const _ScoreButton({required this.score, required this.onTap});

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors[score].withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors[score]),
        ),
        child: Column(
          children: [
            Text('$score', style: TextStyle(color: colors[score], fontWeight: FontWeight.bold, fontSize: 18)),
            Text('分', style: TextStyle(color: colors[score], fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
