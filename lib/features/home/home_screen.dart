import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../settings/settings_provider.dart';
import 'home_provider.dart';
import '../review/widgets/overdue_notes_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueProvider);
    final vaultPathAsync = ref.watch(vaultPathProvider);
    final overdueCount = overdueAsync.valueOrNull?.count ?? 0;
    final hasVaultPath = vaultPathAsync.valueOrNull != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteReview'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: GestureDetector(
                onTap: overdueCount > 0 && overdueAsync.valueOrNull != null
                    ? () => showOverdueNotesDialog(context, overdueAsync.valueOrNull!.records)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      _buildStatCircle(
                        context,
                        value: overdueCount,
                        label: '待复习',
                        color: overdueCount > 0
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              !hasVaultPath
                                  ? '尚未设置笔记路径'
                                  : overdueCount > 0
                                      ? '有笔记需要复习'
                                      : '暂无待复习笔记',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              !hasVaultPath
                                  ? '点击下方设置按钮选择 Obsidian 笔记文件夹'
                                  : overdueCount > 0
                                      ? '点击查看详情'
                                      : '去管理笔记中添加笔记',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!hasVaultPath)
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('去设置笔记路径'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            if (hasVaultPath) ...[
              FilledButton.icon(
                onPressed: () => context.push('/vault-browser'),
                icon: const Icon(Icons.folder_open),
                label: const Text('管理笔记'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/review'),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('开始复习'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/notes'),
                icon: const Icon(Icons.list_alt),
                label: const Text('已监控笔记'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              '遗忘曲线概览',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ref.watch(reviewHistoryProvider).when(
                  data: (history) {
                    final maxCount = history.fold(0, (p, c) => c.count > p ? c.count : p);
                    final maxY = maxCount < 3 ? 3 : maxCount;
                    return SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY.toDouble(),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final day = history[groupIndex];
                                return BarTooltipItem(
                                  '${day.date.month}/${day.date.day}\n${day.count}篇',
                                  const TextStyle(color: Colors.white, fontSize: 12),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= history.length) return const SizedBox();
                                  if (idx % 7 != 0) return const SizedBox();
                                  final day = history[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${day.date.month}/${day.date.day}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                                reservedSize: 20,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const SizedBox();
                                  return Text(
                                    '${value.toInt()}',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: history.asMap().entries.map((entry) {
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value.count.toDouble(),
                                  color: entry.value.count > 0
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  width: 6,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SizedBox(
                    height: 180,
                    child: Center(child: Text('加载失败: $e')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle(
    BuildContext context, {
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(25),
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
