import 'package:flutter/material.dart';
import '../../../data/database/database.dart';

void showOverdueNotesDialog(BuildContext context, List<JoinedRecord> records) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Text('待复习笔记（${records.length}）',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            itemCount: records.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final joined = records[index];
              final record = joined.record;
              final nextDate = record?.nextReviewDate;
              final lastScore = record?.lastScore;
              String subtitle;
              if (nextDate == null) {
                subtitle = '从未复习';
              } else {
                final diff = DateTime.now().difference(nextDate);
                if (diff.isNegative) {
                  subtitle = '${(-diff.inHours)} 小时后到期';
                } else {
                  subtitle = '已逾期 ${diff.inDays > 0 ? '${diff.inDays} 天 ' : ''}${diff.inHours % 24} 小时';
                }
              }
              return ListTile(
                leading: Icon(Icons.description_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(joined.note.fileName,
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(subtitle,
                    style: TextStyle(fontSize: 12,
                        color: Theme.of(context).colorScheme.error)),
                trailing: lastScore != null
                    ? Text('上次评分: $lastScore',
                        style: Theme.of(context).textTheme.bodySmall)
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
