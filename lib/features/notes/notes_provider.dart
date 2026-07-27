import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../settings/settings_provider.dart';

class NoteWithRecord {
  final NoteFile note;
  final ReviewRecord? record;
  final List<String> tags;

  NoteWithRecord({required this.note, this.record, required this.tags});
}

final notesWithRecordsProvider = FutureProvider<List<NoteWithRecord>>((ref) async {
  final db = ref.read(databaseProvider);
  final notes = await db.allActiveNotes();
  final result = <NoteWithRecord>[];
  for (final note in notes) {
    final record = await db.recordForNote(note.id);
    final tags = note.tags.isNotEmpty
        ? (jsonDecode(note.tags) as List).cast<String>()
        : <String>[];
    result.add(NoteWithRecord(note: note, record: record, tags: tags));
  }
  result.sort((a, b) {
    final aEase = a.record?.sm2EaseFactor ?? 2.5;
    final bEase = b.record?.sm2EaseFactor ?? 2.5;
    return aEase.compareTo(bEase);
  });
  return result;
});

final allTagsProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.read(databaseProvider);
  final notes = await db.allActiveNotes();
  final tagSet = <String>{};
  for (final note in notes) {
    if (note.tags.isEmpty) continue;
    try {
      final tags = jsonDecode(note.tags) as List;
      for (final t in tags) {
        tagSet.add(t as String);
      }
    } catch (_) {}
  }
  return tagSet.toList()..sort();
});
