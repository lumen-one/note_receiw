import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart';
import '../settings/settings_provider.dart';
import '../notes/note_detail_screen.dart';
import 'home_provider.dart';
import '../review/widgets/overdue_notes_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedMonthOffset = 0;
  int? _expanded30DayIdx;
  List<JoinedRecord>? _expanded30DayNotes;
  bool _loading30DayNotes = false;

  int? _expandedMonthBarIdx;
  List<JoinedRecord>? _expandedMonthDayNotes;
  bool _loadingMonthDayNotes = false;

  DateTime get _selectedMonth =>
      DateTime(DateTime.now().year, DateTime.now().month + _selectedMonthOffset, 1);

  List<DateTime> get _months {
    final now = DateTime.now();
    return List.generate(7, (i) => DateTime(now.year, now.month - 5 + i, 1));
  }

  @override
  Widget build(BuildContext context) {
    final overdueAsync = ref.watch(overdueProvider);
    final vaultPathAsync = ref.watch(vaultPathProvider);
    final history30Async = ref.watch(reviewHistory30Provider);
    final hasVaultPath = vaultPathAsync.valueOrNull != null;

    final selectedMonth = _selectedMonth;
    final monthKey = MonthKey(selectedMonth.year, selectedMonth.month);
    final monthHistoryAsync = ref.watch(reviewHistoryMonthProvider(monthKey));
    final monthNotesAsync = ref.watch(notesInMonthProvider(monthKey));

    return Scaffold(
      appBar: AppBar(title: const Text('NoteReview')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverdueCard(context, overdueAsync),
          const SizedBox(height: 24),
          if (!hasVaultPath)
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('去设置笔记路径'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          if (hasVaultPath) ...[
            FilledButton.icon(
              onPressed: () => context.push('/vault-browser'),
              icon: const Icon(Icons.folder_open),
              label: const Text('管理笔记'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/review'),
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('开始复习'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/notes'),
              icon: const Icon(Icons.list_alt),
              label: const Text('已监控笔记'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 24),
            Text('遗忘曲线概览', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _build30DayCurve(context, history30Async),
            const SizedBox(height: 24),
            Text('按月查看', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildMonthScroller(context),
            const SizedBox(height: 8),
            _buildMonthlyCurve(context, monthHistoryAsync, monthNotesAsync, selectedMonth),
          ],
        ],
      ),
    );
  }

  Widget _buildOverdueCard(BuildContext context, AsyncValue<OverdueInfo> overdueAsync) {
    final theme = Theme.of(context);
    final overdueInfo = overdueAsync.valueOrNull;
    final overdueCount = overdueInfo?.count ?? 0;

    return Card(
      child: GestureDetector(
        onTap: overdueCount > 0 && overdueInfo != null
            ? () => showOverdueNotesDialog(context, overdueInfo.records)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              _buildStatCircle(
                value: overdueCount,
                label: '待复习',
                color: overdueCount > 0 ? theme.colorScheme.error : theme.colorScheme.primary,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overdueInfo == null
                          ? '加载中...'
                          : overdueCount > 0
                              ? '有笔记需要复习'
                              : '暂无待复习笔记',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      overdueCount > 0 ? '点击查看详情' : '所有笔记已复习完毕',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build30DayCurve(BuildContext context, AsyncValue<List<DailyReviewCount>> historyAsync) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('近30天', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            historyAsync.when(
              data: (history) {
                final maxCount = history.fold(0, (p, c) => c.count > p ? c.count : p);
                final maxY = maxCount < 3 ? 3.0 : maxCount.toDouble();
                return Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchCallback: (event, response) {
                              if (event is FlTapUpEvent && response?.spot != null) {
                                final idx = response!.spot!.touchedBarGroupIndex;
                                _onTap30DayBar(idx, history);
                              }
                            },
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final day = history[group.x.toInt()];
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
                                  return Text('${value.toInt()}',
                                      style: const TextStyle(fontSize: 10));
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: history.asMap().entries.map((entry) {
                            final isSelected = _expanded30DayIdx == entry.key;
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value.count.toDouble(),
                                  color: entry.value.count > 0
                                      ? (isSelected
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.primary)
                                      : theme.colorScheme.surfaceContainerHighest,
                                  width: 6,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (_expanded30DayIdx != null)
                      _buildExpandedNotes(
                        _expanded30DayNotes,
                        _loading30DayNotes,
                        () => setState(() => _expanded30DayIdx = null),
                      ),
                  ],
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
          ],
        ),
      ),
    );
  }

  void _onTap30DayBar(int idx, List<DailyReviewCount> history) {
    if (idx < 0 || idx >= history.length) return;
    if (_expanded30DayIdx == idx) {
      setState(() => _expanded30DayIdx = null);
      return;
    }
    setState(() {
      _expanded30DayIdx = idx;
      _loading30DayNotes = true;
      _expanded30DayNotes = null;
    });
    final day = history[idx].date;
    ref.read(databaseProvider).notesReviewedOnDay(day).then((notes) {
      if (mounted) {
        setState(() {
          _expanded30DayNotes = notes;
          _loading30DayNotes = false;
        });
      }
    });
  }

  Widget _buildMonthScroller(BuildContext context) {
    final months = _months;
    final selected = _selectedMonth;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        itemBuilder: (ctx, idx) {
          final m = months[idx];
          final isSelected = m.year == selected.year && m.month == selected.month;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                DateFormat('yyyy/MM').format(m),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  final now = DateTime.now();
                  _selectedMonthOffset =
                      (m.year - now.year) * 12 + (m.month - now.month);
                  _expandedMonthBarIdx = null;
                  _expandedMonthDayNotes = null;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthlyCurve(
    BuildContext context,
    AsyncValue<List<DailyReviewCount>> historyAsync,
    AsyncValue<List<JoinedRecord>> notesAsync,
    DateTime selectedMonth,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy年M月').format(selectedMonth),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            historyAsync.when(
              data: (history) {
                final maxCount = history.fold(0, (p, c) => c.count > p ? c.count : p);
                final maxY = maxCount < 3 ? 3.0 : maxCount.toDouble();
                return Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchCallback: (event, response) {
                              if (event is FlTapUpEvent && response?.spot != null) {
                                final idx = response!.spot!.touchedBarGroupIndex;
                                _onTapMonthBar(idx, history, selectedMonth);
                              }
                            },
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final day = history[group.x.toInt()];
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
                                  if ((idx + 1) % 5 != 0 && idx != history.length - 1) return const SizedBox();
                                  final day = history[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${day.date.day}日',
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
                                  return Text('${value.toInt()}',
                                      style: const TextStyle(fontSize: 10));
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: history.asMap().entries.map((entry) {
                            final isSelected = _expandedMonthBarIdx == entry.key;
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value.count.toDouble(),
                                  color: entry.value.count > 0
                                      ? (isSelected
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.secondary)
                                      : theme.colorScheme.surfaceContainerHighest,
                                  width: 8,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _expandedMonthBarIdx != null
                          ? '${_expandedMonthBarIdx! + 1}日 复习笔记'
                          : '当月复习笔记',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    if (_expandedMonthBarIdx != null)
                      _buildExpandedNotes(_expandedMonthDayNotes, _loadingMonthDayNotes, () {
                        setState(() => _expandedMonthBarIdx = null);
                      })
                    else
                      notesAsync.when(
                        data: (notes) => _buildNoteList(notes, null),
                        loading: () => const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(child: Text('加载失败: $e')),
                        ),
                      ),
                  ],
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
          ],
        ),
      ),
    );
  }

  void _onTapMonthBar(int idx, List<DailyReviewCount> history, DateTime month) {
    if (idx < 0 || idx >= history.length) return;
    if (_expandedMonthBarIdx == idx) {
      setState(() => _expandedMonthBarIdx = null);
      return;
    }
    setState(() {
      _expandedMonthBarIdx = idx;
      _loadingMonthDayNotes = true;
      _expandedMonthDayNotes = null;
    });
    final day = DateTime(month.year, month.month, idx + 1);
    ref.read(databaseProvider).notesReviewedOnDay(day).then((notes) {
      if (mounted) {
        setState(() {
          _expandedMonthDayNotes = notes;
          _loadingMonthDayNotes = false;
        });
      }
    });
  }

  Widget _buildExpandedNotes(
    List<JoinedRecord>? notes,
    bool loading,
    VoidCallback onClose,
  ) {
    final theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (notes == null || notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text('暂无复习记录', style: theme.textTheme.bodySmall),
        ),
      );
    }
    return _buildNoteList(notes, onClose);
  }

  Widget _buildNoteList(List<JoinedRecord> notes, VoidCallback? onClose) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (onClose != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ...notes.map((jr) => Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            title: Text(jr.note.fileName,
                style: const TextStyle(fontSize: 14)),
            subtitle: jr.record?.lastScore != null
                ? Text('评分: ${jr.record!.lastScore}',
                    style: theme.textTheme.bodySmall)
                : null,
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => NoteDetailScreen(noteId: jr.note.id),
                ),
              );
            },
          ),
        )),
      ],
    );
  }

  Widget _buildStatCircle({
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
