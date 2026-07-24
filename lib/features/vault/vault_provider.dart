import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/vault_service.dart';
import '../settings/settings_provider.dart';

final vaultServiceProvider = Provider<VaultService>((ref) => VaultService());

final vaultEntriesProvider = FutureProvider<List<VaultEntry>>((ref) async {
  final vaultPath = await ref.read(vaultPathProvider.future);
  if (vaultPath == null) return [];
  return ref.read(vaultServiceProvider).scanDirectory(vaultPath);
});

final vaultTreeProvider = FutureProvider<VaultTreeNode?>((ref) async {
  final vaultPath = await ref.read(vaultPathProvider.future);
  if (vaultPath == null) return null;
  return ref.read(vaultServiceProvider).scanTree(vaultPath);
});

final activeNoteIdsProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.read(databaseProvider);
  final notes = await db.allActiveNotes();
  return notes.map((n) => n.filePath).toSet();
});
