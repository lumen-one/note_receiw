import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import 'notes_provider.dart';
import 'note_detail_screen.dart';

class MonitoredNotesScreen extends ConsumerStatefulWidget {
  const MonitoredNotesScreen({super.key});

  @override
  ConsumerState<MonitoredNotesScreen> createState() => _MonitoredNotesScreenState();
}

class _MonitoredNotesScreenState extends ConsumerState<MonitoredNotesScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _selectedTags = {};
  String _sortBy = 'ease';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<NoteWithRecord> _filter(List<NoteWithRecord> items) {
    var result = items;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((n) => n.note.fileName.toLowerCase().contains(q)).toList();
    }

    if (_selectedTags.isNotEmpty) {
      result = result.where((n) =>
        n.tags.any((t) => _selectedTags.contains(t))
      ).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesWithRecordsProvider);
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('已监控笔记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索笔记...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          tagsAsync.when(
            data: (tags) => tags.isEmpty
                ? const SizedBox()
                : SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: tags.map((tag) {
                        final selected = _selectedTags.contains(tag);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(tag),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) { _selectedTags.add(tag); }
                                else { _selectedTags.remove(tag); }
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
            loading: () => const SizedBox(height: 44),
            error: (_, __) => const SizedBox(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('排序: ', style: TextStyle(fontSize: 13)),
                ChoiceChip(
                  label: const Text('熟练度', style: TextStyle(fontSize: 13)),
                  selected: _sortBy == 'ease',
                  onSelected: (_) => setState(() => _sortBy = 'ease'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('下次复习', style: TextStyle(fontSize: 13)),
                  selected: _sortBy == 'next',
                  onSelected: (_) => setState(() => _sortBy = 'next'),
                ),
              ],
            ),
          ),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                final filtered = _filter(notes);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty || _selectedTags.isNotEmpty
                              ? '无匹配笔记'
                              : '暂无已监控笔记',
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final record = item.record;
                    final isOverdue = record?.nextReviewDate != null
                        ? record!.nextReviewDate.isBefore(DateTime.now())
                        : false;
                    final dueDays = record?.nextReviewDate != null
                        ? record!.nextReviewDate.difference(DateTime.now()).inDays
                        : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(item.note.fileName, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.note.filePath,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            if (item.tags.isNotEmpty)
                              Wrap(
                                spacing: 4,
                                children: item.tags.map((t) => Chip(
                                  label: Text(t, style: const TextStyle(fontSize: 11)),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                )).toList(),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _infoChip(
                                  '熟练度: ${record != null ? record.sm2EaseFactor.toStringAsFixed(1) : "未复习"}',
                                ),
                                const SizedBox(width: 8),
                                _infoChip(
                                  '间隔: ${record != null ? "${record.sm2Interval.toInt()}天" : "-"}',
                                ),
                                const SizedBox(width: 8),
                                _infoChip(
                                  isOverdue
                                      ? '已逾期'
                                      : dueDays != null
                                          ? '${dueDays}天后'
                                          : '无记录',
                                  isOverdue
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: item.tags.isNotEmpty,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => NoteDetailScreen(noteId: item.note.id),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text, [Color? color]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withAlpha(25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
