import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../../data/database/database.dart';
import '../../services/vault_service.dart';
import '../../services/permission_service.dart';
import '../settings/settings_provider.dart';
import '../home/home_provider.dart';
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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
        final note = await db.upsertNote(
          filePath: entry.relativePath,
          fileName: entry.name,
          hasReviewTag: true,
        );
        final existing = await db.recordForNote(note.id);
        if (existing == null) {
          await db.upsertRecord(ReviewRecordsCompanion.insert(
            noteId: Value(note.id),
            nextReviewDate: DateTime.now(),
          ));
        }
        ref.invalidate(overdueProvider);
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
    final note = await db.upsertNote(
      filePath: entry.relativePath,
      fileName: entry.name,
      addedManually: active,
      hasReviewTag: entry.hasReviewTag,
      isActive: active,
    );
    if (active) {
      final existing = await db.recordForNote(note.id);
      if (existing == null) {
        await db.upsertRecord(ReviewRecordsCompanion.insert(
          noteId: Value(note.id),
          nextReviewDate: DateTime.now(),
        ));
      }
      ref.invalidate(overdueProvider);
    }
    if (mounted) {
      setState(() => _activeStates[path] = active);
    }
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

    final children = node.children;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final child = children[index];
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
      },
    );
  }

  Widget _buildFolderTile(VaultTreeNode folder) {
    final hasActiveChild = folder.children.any((c) =>
        !c.isDirectory && (_activeStates[c.relativePath] ?? false));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ExpansionTile(
        leading: Icon(
          hasActiveChild ? Icons.folder_special : Icons.folder,
          color: hasActiveChild
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
              : _tree == null || _tree!.fileCount == 0
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
                                        _debounce?.cancel();
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
                              _debounce?.cancel();
                              _debounce = Timer(const Duration(milliseconds: 200), () {
                                if (mounted) {
                                  setState(() {
                                    _searchQuery = value;
                                    _isSearching = value.isNotEmpty;
                                  });
                                }
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
