# NoteReview App 功能增强 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add folder tree + search to vault browser, @mention notes in chat (counts as review), forgetting curve chart, dark mode auto-follow, and custom SM-2 intervals.

**Architecture:** All changes are Dart-only (no DB migration). Vault service adopts recursive tree building. Chat screen adds @-autocomplete overlay and on-end SM-2 batch update. Home screen adds fl_chart bar chart. Settings adds interval list editor.

**Tech Stack:** Flutter 3.x, Dart 3.x, fl_chart ^0.69.0

---

### Task 1: Dark Mode Auto-Follow System

**Files:**
- Modify: `lib/app.dart:61-67`

- [ ] **Step 1: Add ThemeMode.system to MaterialApp.router**

```dart
// In lib/app.dart, the NoteReviewApp build method:
return MaterialApp.router(
  title: 'NoteReview',
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ThemeMode.system,  // ← add this line
  routerConfig: router,
  debugShowCheckedModeBanner: false,
);
```

Also add the import if not present (it's in `package:flutter/material.dart` which is already imported).

- [ ] **Step 2: Verify**

```bash
dart analyze lib/app.dart
```
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: auto-follow system dark mode via ThemeMode.system"
```

---

### Task 2: Custom SM-2 Intervals in Settings

**Files:**
- Modify: `lib/data/settings_store.dart`
- Modify: `lib/services/sm2_engine.dart`
- Modify: `lib/features/settings/settings_provider.dart`
- Modify: `lib/features/settings/settings_screen.dart`

- [ ] **Step 1: Add interval storage to SettingsStore**

Add to `lib/data/settings_store.dart`:

```dart
import 'dart:convert';

// Add inside class SettingsStore:
static const _keyIntervals = 'sm2_intervals';

static Future<List<int>> getSm2Intervals() async {
  final prefs = await _prefs;
  final json = prefs.getString(_keyIntervals);
  if (json == null) return [1, 6, 15, 38, 95, 238];
  return (jsonDecode(json) as List).cast<int>();
}

static Future<void> setSm2Intervals(List<int> intervals) async {
  final prefs = await _prefs;
  await prefs.setString(_keyIntervals, jsonEncode(intervals));
}

static Future<void> resetSm2Intervals() async {
  final prefs = await _prefs;
  await prefs.remove(_keyIntervals);
}
```

- [ ] **Step 2: Update Sm2Engine to accept custom intervals**

In `lib/services/sm2_engine.dart`, modify `calculate`:

```dart
static Sm2Result calculate({
  required int quality,
  required double currentInterval,
  required double currentEaseFactor,
  required int currentRepetitions,
  List<int>? customIntervals,
}) {
  double newInterval;
  int newRepetitions;
  double newEaseFactor;

  if (quality >= 3) {
    if (currentRepetitions == 0) {
      newInterval = (customIntervals != null && customIntervals.length > 0)
          ? customIntervals[0].toDouble()
          : 1;
    } else if (currentRepetitions == 1) {
      newInterval = (customIntervals != null && customIntervals.length > 1)
          ? customIntervals[1].toDouble()
          : 6;
    } else if (customIntervals != null && currentRepetitions < customIntervals.length) {
      newInterval = customIntervals[currentRepetitions].toDouble();
    } else {
      newInterval = (currentInterval * currentEaseFactor).roundToDouble();
    }
    newRepetitions = currentRepetitions + 1;
  } else {
    newInterval = 1;
    newRepetitions = 0;
  }

  newEaseFactor = currentEaseFactor +
      (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
  if (newEaseFactor < 1.3) newEaseFactor = 1.3;

  final today = DateTime.now();
  final dayStart = DateTime(today.year, today.month, today.day);
  final nextReviewDate = dayStart.add(Duration(days: newInterval.toInt()));

  return Sm2Result(
    interval: newInterval,
    easeFactor: newEaseFactor,
    repetitions: newRepetitions,
    nextReviewDate: nextReviewDate,
  );
}
```

- [ ] **Step 3: Add sm2IntervalsProvider to settings_provider.dart**

Add to `lib/features/settings/settings_provider.dart`:

```dart
final sm2IntervalsProvider = FutureProvider<List<int>>((ref) async {
  return SettingsStore.getSm2Intervals();
});
```

- [ ] **Step 4: Add interval editor UI to settings_screen.dart**

In `lib/features/settings/settings_screen.dart`, add a new state field `_intervals` and a new section after "复习设置":

```dart
// Add state:
List<int> _intervals = [1, 6, 15, 38, 95, 238];

// In _loadSettings():
final intervals = await SettingsStore.getSm2Intervals();
_intervals = intervals;

// New method:
Future<void> _setIntervals(List<int> intervals) async {
  await SettingsStore.setSm2Intervals(intervals);
  setState(() => _intervals = intervals);
  ref.invalidate(sm2IntervalsProvider);
}

// New section in build(), after the "复习设置" card:
_sectionHeader('遗忘曲线间隔'),
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._intervals.asMap().entries.map((entry) {
          final i = entry.key;
          final val = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('第${i + 1}次: ', style: const TextStyle(fontSize: 14)),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: TextEditingController(text: '$val'),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (text) {
                      final n = int.tryParse(text);
                      if (n != null && n > 0) {
                        final copy = List<int>.from(_intervals);
                        copy[i] = n;
                        _setIntervals(copy);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('天'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: _intervals.length > 1
                      ? () => _setIntervals(List<int>.from(_intervals)..removeAt(i))
                      : null,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _setIntervals([..._intervals, 30]),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加间隔'),
        ),
        TextButton(
          onPressed: () => _setIntervals([1, 6, 15, 38, 95, 238]),
          child: const Text('恢复默认'),
        ),
      ],
    ),
  ),
),
```

- [ ] **Step 5: Verify**

```bash
dart analyze lib/data/settings_store.dart lib/services/sm2_engine.dart
```
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: custom SM-2 intervals in settings"
```

---

### Task 3: Vault Tree Data Structure

**Files:**
- Modify: `lib/services/vault_service.dart`
- Modify: `lib/features/vault/vault_provider.dart`

- [ ] **Step 1: Add VaultTreeNode class and tree scanning to vault_service.dart**

Add to `lib/services/vault_service.dart`:

```dart
class VaultTreeNode {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;
  final List<VaultTreeNode> children;
  final int fileCount; // total .md files in subtree (only for directories)

  VaultTreeNode({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.hasReviewTag = false,
    this.children = const [],
    this.fileCount = 0,
  });
}
```

Add a new method to `VaultService`:

```dart
Future<VaultTreeNode> scanTree(String rootPath) async {
  final rootDir = Directory(rootPath);
  return _buildNode(rootDir, rootPath, '');
}

Future<VaultTreeNode> _buildNode(Directory dir, String rootPath, String relativeParent) async {
  final name = dir.path.split('/').last;
  final relativePath = relativeParent.isEmpty ? name : '$relativeParent/$name';
  final children = <VaultTreeNode>[];
  int fileCount = 0;

  await for (final entity in dir.list()) {
    if (entity is Directory) {
      final child = await _buildNode(entity, rootPath, relativePath);
      fileCount += child.fileCount;
      children.add(child);
    } else if (entity is File && entity.path.endsWith('.md')) {
      final content = await entity.readAsString();
      final hasReviewTag = content.contains('#review');
      final fileRelative = entity.path.substring(rootPath.length + 1);
      children.add(VaultTreeNode(
        name: entity.path.split('/').last,
        relativePath: fileRelative,
        absolutePath: entity.path,
        isDirectory: false,
        hasReviewTag: hasReviewTag,
      ));
      fileCount++;
    }
  }

  // Sort: directories first, then files, alphabetically
  children.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.compareTo(b.name);
  });

  return VaultTreeNode(
    name: name,
    relativePath: relativePath,
    absolutePath: dir.path,
    isDirectory: true,
    children: children,
    fileCount: fileCount,
  );
}

List<VaultEntry> flattenTree(VaultTreeNode node) {
  final result = <VaultEntry>[];
  _flatten(node, result);
  return result;
}

void _flatten(VaultTreeNode node, List<VaultEntry> result) {
  if (!node.isDirectory) {
    result.add(VaultEntry(
      name: node.name,
      relativePath: node.relativePath,
      absolutePath: node.absolutePath,
      isDirectory: false,
      hasReviewTag: node.hasReviewTag,
    ));
  }
  for (final child in node.children) {
    _flatten(child, result);
  }
}
```

Keep the existing `scanDirectory` method for backward compatibility (it can delegate to flattenTree now):

```dart
Future<List<VaultEntry>> scanDirectory(String rootPath) async {
  final tree = await scanTree(rootPath);
  return flattenTree(tree);
}
```

- [ ] **Step 2: Add vaultTreeProvider to vault_provider.dart**

Add to `lib/features/vault/vault_provider.dart`:

```dart
final vaultTreeProvider = FutureProvider<VaultTreeNode?>((ref) async {
  final vaultPath = await ref.read(vaultPathProvider.future);
  if (vaultPath == null) return null;
  return ref.read(vaultServiceProvider).scanTree(vaultPath);
});
```

- [ ] **Step 3: Verify**

```bash
dart analyze lib/services/vault_service.dart lib/features/vault/vault_provider.dart
```
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: vault tree scanning data structure"
```

---

### Task 4: Vault Browser Tree UI + Search

**Files:**
- Rewrite: `lib/features/vault/vault_browser_screen.dart`

- [ ] **Step 1: Rewrite vault_browser_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/vault_service.dart';
import '../../services/permission_service.dart';
import '../settings/settings_provider.dart';
import 'vault_provider.dart';
import 'widgets/note_tile.dart';

class VaultBrowserScreen extends ConsumerStatefulWidget {
  const VaultBrowserScreen({super.key});

  @override
  ConsumerState<VaultBrowserScreen> createState() => _VaultBrowserScreenState();
}

class _VaultBrowserScreenState extends ConsumerState<VaultBrowserScreen> {
  List<VaultEntry> _allEntries = [];
  VaultTreeNode? _tree;
  Map<String, bool> _activeStates = {};
  bool _loading = true;
  bool _permissionDenied = false;
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final hasPermission = await PermissionService.requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _loading = false;
          _permissionDenied = true;
        });
        PermissionService.showPermissionSettingsDialog(context);
      }
      return;
    }

    final vaultPath = await ref.read(vaultPathProvider.future);
    if (vaultPath == null) {
      setState(() => _loading = false);
      return;
    }

    final service = ref.read(vaultServiceProvider);
    final tree = await service.scanTree(vaultPath);
    final allEntries = service.flattenTree(tree);
    final db = ref.read(databaseProvider);
    final activeNotes = await db.allActiveNotes();
    final activePaths = activeNotes.map((n) => n.filePath).toSet();

    final states = <String, bool>{};
    for (final entry in allEntries) {
      if (entry.hasReviewTag && !activePaths.contains(entry.relativePath)) {
        await db.upsertNote(
          filePath: entry.relativePath,
          fileName: entry.name,
          hasReviewTag: true,
        );
        states[entry.relativePath] = true;
      } else {
        states[entry.relativePath] = activePaths.contains(entry.relativePath);
      }
    }

    if (mounted) {
      setState(() {
        _tree = tree;
        _allEntries = allEntries;
        _activeStates = states;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String path, bool active) async {
    final db = ref.read(databaseProvider);
    final entry = _allEntries.firstWhere((e) => e.relativePath == path);
    await db.upsertNote(
      filePath: entry.relativePath,
      fileName: entry.name,
      addedManually: active,
      hasReviewTag: entry.hasReviewTag,
      isActive: active,
    );
    setState(() => _activeStates[path] = active);
  }

  List<VaultEntry> _filteredEntries() {
    if (_searchQuery.isEmpty) return _allEntries;
    final q = _searchQuery.toLowerCase();
    return _allEntries
        .where((e) => e.name.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildTree(VaultTreeNode node) {
    if (_isSearching) {
      final filtered = _filteredEntries();
      if (filtered.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.search_off, size: 48,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('未找到匹配 "$_searchQuery" 的笔记'),
              ],
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final entry = filtered[index];
          return NoteTile(
            name: entry.name,
            path: entry.relativePath,
            hasReviewTag: entry.hasReviewTag,
            isActive: _activeStates[entry.relativePath] ?? false,
            onToggle: (active) => _toggle(entry.relativePath, active),
          );
        },
      );
    }

    return _buildNode(node);
  }

  Widget _buildNode(VaultTreeNode node) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: node.children.map((child) {
        if (child.isDirectory) {
          return _buildFolderTile(child);
        } else {
          return NoteTile(
            name: child.name,
            path: child.relativePath,
            hasReviewTag: child.hasReviewTag,
            isActive: _activeStates[child.relativePath] ?? false,
            onToggle: (active) => _toggle(child.relativePath, active),
          );
        }
      }).toList(),
    );
  }

  Widget _buildFolderTile(VaultTreeNode folder) {
    final isActive = folder.children.any((c) =>
        !c.isDirectory && (_activeStates[c.relativePath] ?? false));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          isActive ? Icons.folder_special : Icons.folder,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Text(folder.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${folder.fileCount} 篇笔记',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.only(left: 16),
        children: folder.children.map((child) {
          if (child.isDirectory) {
            return _buildFolderTile(child);
          }
          return NoteTile(
            name: child.name,
            path: child.relativePath,
            hasReviewTag: child.hasReviewTag,
            isActive: _activeStates[child.relativePath] ?? false,
            onToggle: (active) => _toggle(child.relativePath, active),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理笔记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off, size: 64,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 16),
                        const Text('无法访问存储权限'),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () => PermissionService
                              .showPermissionSettingsDialog(context),
                          child: const Text('授予权限'),
                        ),
                      ],
                    ),
                  ),
                )
              : _tree == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description_outlined, size: 64,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 16),
                            const Text('该文件夹中没有找到 .md 文件'),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => _load(),
                              child: const Text('重新扫描'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '搜索笔记...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _isSearching = false;
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                                _isSearching = value.isNotEmpty;
                              });
                            },
                          ),
                        ),
                        Expanded(child: _buildTree(_tree!)),
                      ],
                    ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
dart analyze lib/features/vault/vault_browser_screen.dart
```
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: vault browser tree view with search"
```

---

### Task 5: Forgetting Curve Chart on Home Screen

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/data/database/database.dart`
- Modify: `lib/features/home/home_provider.dart`
- Modify: `lib/features/home/home_screen.dart`

- [ ] **Step 1: Add fl_chart dependency**

In `pubspec.yaml`, add under `dependencies:`:

```yaml
  fl_chart: ^0.69.0
```

Run:

```bash
flutter pub get
```
Expected: Success.

- [ ] **Step 2: Add review history query to AppDatabase**

Add to `lib/data/database/database.dart`:

```dart
class DailyReviewCount {
  final DateTime date;
  final int count;

  DailyReviewCount({required this.date, required this.count});
}

// Add inside AppDatabase:
Future<List<DailyReviewCount>> reviewHistoryLast30Days() async {
  final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
  final start = DateTime(thirtyDaysAgo.year, thirtyDaysAgo.month, thirtyDaysAgo.day);

  final rows = await (select(reviewRecords)
        ..where((t) => t.lastReviewDate.isBiggerThanValue(start))
      ).get();

  final Map<String, int> counts = {};
  for (final row in rows) {
    if (row.lastReviewDate == null) continue;
    final key = '${row.lastReviewDate!.year}-${row.lastReviewDate!.month.toString().padLeft(2, '0')}-${row.lastReviewDate!.day.toString().padLeft(2, '0')}';
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final result = <DailyReviewCount>[];
  for (int i = 29; i >= 0; i--) {
    final day = start.add(Duration(days: i));
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    result.add(DailyReviewCount(date: day, count: counts[key] ?? 0));
  }
  return result;
}
```

- [ ] **Step 3: Add reviewHistoryProvider to home_provider.dart**

Add to `lib/features/home/home_provider.dart`:

```dart
final reviewHistoryProvider = FutureProvider<List<DailyReviewCount>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.reviewHistoryLast30Days();
});
```

- [ ] **Step 4: Add chart widget to home_screen.dart**

Replace the "遗忘曲线概览" section in `lib/features/home/home_screen.dart`:

```dart
// At top of file, add imports:
import 'package:fl_chart/fl_chart.dart';
import 'data/database/database.dart';

// Replace the "遗忘曲线概览" text and "即将支持" placeholder with:
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
                      // Show label every 7 days
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
```

- [ ] **Step 5: Build check**

```bash
cd /mnt/c/Users/zzz/Desktop/phone_note_receiw/phone_note_reviewIDET && dart analyze lib/data/database/database.dart lib/features/home/
```
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: forgetting curve chart on home screen"
```

---

### Task 6: @ Mention Chat with Note Autocomplete

**Files:**
- Rewrite: `lib/features/review/chat_screen.dart`
- Modify: `lib/features/review/review_provider.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Add @ mention autocomplete to chat_screen.dart**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../services/ai_service.dart';
import '../settings/settings_provider.dart';
import 'review_provider.dart';
import 'widgets/chat_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String sessionType;
  final String? initialNoteIds; // comma-separated note IDs

  const ChatScreen({
    super.key,
    required this.sessionType,
    this.initialNoteIds,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  List<NoteFile> _allNotes = [];
  List<NoteFile> _activeNotes = [];
  bool _showSuggestions = false;
  String _mentionQuery = '';
  int _mentionCursorPos = -1;
  final Set<int> _mentionedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final db = ref.read(databaseProvider);
    final all = await db.allNotes();
    final active = await db.allActiveNotes();
    setState(() {
      _allNotes = all;
      _activeNotes = active;
    });

    // If initialNoteIds provided, pre-add them
    if (widget.initialNoteIds != null && widget.initialNoteIds!.isNotEmpty) {
      final ids = widget.initialNoteIds!
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .where((id) => id != null)
          .cast<int>()
          .toList();
      setState(() {
        _mentionedNoteIds.addAll(ids);
      });
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      setState(() => _showSuggestions = false);
      return;
    }

    final cursorPos = sel.baseOffset;
    // Find the last @ before cursor
    final beforeCursor = text.substring(0, cursorPos);
    final atIdx = beforeCursor.lastIndexOf('@');

    if (atIdx >= 0 && (atIdx == 0 || beforeCursor[atIdx - 1] == ' ' || beforeCursor[atIdx - 1] == '\n')) {
      final query = beforeCursor.substring(atIdx + 1);
      // Don't show suggestions if there's a space after @
      if (!query.contains(' ')) {
        setState(() {
          _showSuggestions = true;
          _mentionQuery = query;
          _mentionCursorPos = atIdx;
        });
        return;
      }
    }

    setState(() => _showSuggestions = false);
  }

  List<NoteFile> _filteredNotes() {
    final q = _mentionQuery.toLowerCase();
    // Show active notes first, sorted by match
    final active = _activeNotes
        .where((n) => n.fileName.toLowerCase().contains(q))
        .toList();
    final inactive = _allNotes
        .where((n) => !_activeNotes.any((a) => a.id == n.id))
        .where((n) => n.fileName.toLowerCase().contains(q))
        .toList();
    return [...active, ...inactive];
  }

  void _selectNote(NoteFile note) {
    final text = _controller.text;
    final before = text.substring(0, _mentionCursorPos);
    final after = text.substring(_mentionCursorPos + 1 + _mentionQuery.length);
    _controller.text = '$before@${note.fileName} $after';
    _controller.selection = TextSelection.collapsed(
      offset: _mentionCursorPos + note.fileName.length + 2,
    );
    setState(() {
      _showSuggestions = false;
      _mentionedNoteIds.add(note.id);
    });
  }

  String _buildContextPrompt() {
    if (_mentionedNoteIds.isEmpty) {
      return '你是一位和我一起学习的挚友。我们可以自由讨论任何话题，包括笔记中的知识。';
    }

    final vaultPath = ref.read(vaultPathProvider).valueOrNull;
    final notes = _allNotes.where((n) => _mentionedNoteIds.contains(n.id)).toList();
    final contextParts = <String>[];
    for (final note in notes) {
      final filePath = vaultPath != null ? '$vaultPath/${note.filePath}' : '';
      String content = '';
      if (filePath.isNotEmpty) {
        try {
          final file = File(filePath);
          if (file.existsSync()) {
            final full = file.readAsStringSync();
            content = full.length > 2000 ? '${full.substring(0, 2000)}\n\n...(截断)' : full;
          }
        } catch (_) {}
      }
      contextParts.add('- ${note.fileName}（来自 ${note.filePath}）：\n$content');
    }

    return '你是一位和我一起学习的挚友。用户可以 @ 笔记名来引用笔记内容。'
        '当前会话引用的笔记：\n${contextParts.join('\n\n')}'
        '\n\n请基于以上笔记内容进行讨论。';
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': content});
      _loading = true;
    });
    _controller.clear();

    try {
      final aiService = ref.read(aiServiceProvider);
      final systemPrompt = _buildContextPrompt();
      final fullMessages = [
        {'role': 'system', 'content': systemPrompt},
        ..._messages,
      ];

      final reply = await aiService.continueChat(messages: fullMessages);
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '抱歉，请求失败：$e',
        });
      });
    } finally {
      setState(() => _loading = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endChat() async {
    if (_mentionedNoteIds.isEmpty) return;

    final db = ref.read(databaseProvider);
    final activeMentioned = _activeNotes
        .where((n) => _mentionedNoteIds.contains(n.id))
        .toList();

    if (activeMentioned.isEmpty) return;

    int updated = 0;
    for (final note in activeMentioned) {
      final existing = await db.recordForNote(note.id);
      final result = Sm2Engine.calculate(
        quality: 3,
        currentInterval: existing?.sm2Interval ?? 1.0,
        currentEaseFactor: existing?.sm2EaseFactor ?? 2.5,
        currentRepetitions: existing?.sm2Repetitions ?? 0,
      );
      await db.upsertRecord(ReviewRecordsCompanion.insert(
        noteId: Value(note.id),
        sm2Interval: Value(result.interval),
        sm2EaseFactor: Value(result.easeFactor),
        sm2Repetitions: Value(result.repetitions),
        nextReviewDate: result.nextReviewDate,
        lastReviewDate: Value(DateTime.now()),
        lastScore: const Value(3),
      ));
      updated++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已通过聊天复习 $updated 篇笔记')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _showSuggestions ? _filteredNotes() : <NoteFile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionType == 'free_chat' ? '自由聊天' : '追问'),
        actions: [
          if (_mentionedNoteIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_mentionedNoteIds.length} 篇笔记',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '结束聊天并记录复习',
              onPressed: _endChat,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      '开始和你的学习挚友聊天吧\n在输入框中输入 @ 引用笔记',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _loading) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final msg = _messages[index];
                      return ChatBubble(
                        content: msg['content'] ?? '',
                        isUser: msg['role'] == 'user',
                      );
                    },
                  ),
          ),
          if (suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 16),
                itemBuilder: (context, index) {
                  final note = suggestions[index];
                  final isActive = _activeNotes.any((n) => n.id == note.id);
                  final isAlreadyMentioned = _mentionedNoteIds.contains(note.id);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isActive ? Icons.description : Icons.description_outlined,
                      size: 20,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(note.fileName, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      isActive
                          ? (isAlreadyMentioned ? '已引用 · 已监控' : '已监控')
                          : '未监控',
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? null : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => _selectNote(note),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: _activeNotes.isEmpty
                          ? '暂无监控笔记，@ 无法引用'
                          : '输入消息...（@引用笔记）',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Update app.dart to pass initialNoteIds**

Modify the router in `lib/app.dart`:

```dart
// Change the /review/chat route:
GoRoute(
  path: '/review/chat',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (context, state) {
    final notes = state.uri.queryParameters['notes'];
    return ChatScreen(
      sessionType: 'free_chat',
      initialNoteIds: notes,
    );
  },
),
```

- [ ] **Step 3: Verify**

```bash
dart analyze lib/features/review/chat_screen.dart lib/app.dart
```
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: @ mention notes in chat with context + review on end"
```

---

### Task 7: Update AGENTS.md

**Files:**
- Modify: `/mnt/c/Users/zzz/Desktop/phone_note_receiw/phone_note_reviewIDET/AGENTS.md`

- [ ] **Step 1: Mark completed TODOs and update known issues**

In `AGENTS.md`, update:

```markdown
## 已知问题 / 待修复
1. **workmanager 本地补丁** — `packages/workmanager/` 是对 0.5.2 的 Kotlin patch，后续应升级到官方新版
2. **FilePicker 路径** — settings_screen 的 `_resolvePath()` 处理 content URI 转真实路径，实测可能需调整
3. ~~遗忘曲线概览 — 首页的「遗忘曲线概览」区域未实现，显示「即将支持」~~ ✅ 已实现 fl_chart 图表
4. **Drift 编译** — 改数据库表后必须跑 `dart run build_runner build --delete-conflicting-outputs`
5. **Android 编译标志** — 当前需 `--android-skip-build-dependency-validation`，因为 Gradle/AGP/Kotlin 版本匹配问题

## 遗留 TODO
- [x] 首页遗忘曲线可视化图表
- [x] 自由聊天上下文携带用户笔记库（通过 @ 笔记名实现）
- [ ] workmanager 升级到官方兼容版本
- [x] 暗色主题自动跟随系统
- [x] 设置中遗忘曲线间隔自定义
- [x] VaultBrowser 文件夹树展示 + 搜索
- [x] 自由聊天 @ 引用笔记，聊天代替复习
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "docs: update AGENTS.md with completed features"
```

---

### Self-Review Checklist

1. **Spec coverage:** Every section from the design doc maps to at least one task:
   - ThemeMode.system → Task 1
   - Custom intervals → Task 2
   - Vault tree data → Task 3
   - Vault tree UI + search → Task 4
   - Forgetting curve chart → Task 5
   - @ mention chat + context + review linkage → Task 6
   - AGENTS.md update → Task 7
2. **Placeholder scan:** No TBD, TODO, or incomplete code.
3. **Type consistency:** `VaultTreeNode`/`VaultEntry`, `Sm2Result`/`DailyReviewCount` all consistent.
