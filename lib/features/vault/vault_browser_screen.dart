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
  List<VaultEntry> _entries = [];
  Map<String, bool> _activeStates = {};
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    final entries = await service.scanDirectory(vaultPath);
    final db = ref.read(databaseProvider);
    final activeNotes = await db.allActiveNotes();
    final activePaths = activeNotes.map((n) => n.filePath).toSet();

    final states = <String, bool>{};
    for (final entry in entries) {
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
        _entries = entries;
        _activeStates = states;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String path, bool active) async {
    final db = ref.read(databaseProvider);
    final entry = _entries.firstWhere((e) => e.relativePath == path);
    await db.upsertNote(
      filePath: entry.relativePath,
      fileName: entry.name,
      addedManually: active,
      hasReviewTag: entry.hasReviewTag,
      isActive: active,
    );
    setState(() => _activeStates[path] = active);
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
              : _entries.isEmpty
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
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return NoteTile(
                          name: entry.name,
                          path: entry.relativePath,
                          hasReviewTag: entry.hasReviewTag,
                          isActive:
                              _activeStates[entry.relativePath] ?? false,
                          onToggle: (active) =>
                              _toggle(entry.relativePath, active),
                        );
                      },
                    ),
    );
  }
}
