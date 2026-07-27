import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'database.g.dart';

class JoinedRecord {
  final NoteFile note;
  final ReviewRecord? record;

  JoinedRecord({required this.note, this.record});
}

class DailyReviewCount {
  final DateTime date;
  final int count;

  DailyReviewCount({required this.date, required this.count});
}

@DriftDatabase(tables: [
  NoteFiles,
  ReviewRecords,
  ChatMessages,
  AppState,
  PromptTemplates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(appState).insert(AppStateCompanion.insert(
            id: Value(1),
            lastCheckTime: DateTime.now(),
          ));
        },
        onUpgrade: (m, from, to) async {
          if (from == 1) {
            await m.addColumn(noteFiles, noteFiles.tags);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'note_review.db'));
      return NativeDatabase.createInBackground(file);
    });
  }

  // --- AppState ---

  Future<DateTime> getLastCheckTime() async {
    final row = await (select(appState)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row?.lastCheckTime ?? DateTime.now();
  }

  Future<void> updateLastCheckTime(DateTime time) {
    return into(appState).insertReturning(
      AppStateCompanion(id: const Value(1), lastCheckTime: Value(time)),
      mode: InsertMode.insertOrReplace,
    );
  }

  // --- Prompt Templates ---

  Future<String?> getPromptTemplate(String name) async {
    final row = await (select(promptTemplates)
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    return row?.content;
  }

  Future<void> upsertPromptTemplate(String name, String content) {
    return into(promptTemplates).insertReturning(
      PromptTemplatesCompanion(name: Value(name), content: Value(content)),
      mode: InsertMode.insertOrReplace,
    );
  }

  // --- NoteFiles ---

  Future<List<NoteFile>> allActiveNotes() =>
      (select(noteFiles)..where((t) => t.isActive.equals(true))).get();

  Future<List<NoteFile>> allNotes() => select(noteFiles).get();

  Future<NoteFile?> noteByPath(String filePath) =>
      (select(noteFiles)..where((t) => t.filePath.equals(filePath)))
          .getSingleOrNull();

  Future<NoteFile> upsertNote({
    required String filePath,
    required String fileName,
    bool addedManually = false,
    bool hasReviewTag = false,
    bool isActive = true,
    String tags = '',
  }) async {
    final existing = await noteByPath(filePath);
    if (existing != null) {
      await (update(noteFiles)..where((t) => t.id.equals(existing.id))).write(
        NoteFilesCompanion(
          fileName: Value(fileName),
          addedManually: Value(addedManually),
          hasReviewTag: Value(hasReviewTag),
          isActive: Value(isActive),
          tags: Value(tags),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (await noteByPath(filePath))!;
    }
    return into(noteFiles).insertReturning(
      NoteFilesCompanion.insert(
        filePath: filePath,
        fileName: fileName,
        addedManually: Value(addedManually),
        hasReviewTag: Value(hasReviewTag),
        isActive: Value(isActive),
        tags: Value(tags),
      ),
    );
  }

  Future<void> updateNoteActive(int id, bool isActive) {
    return (update(noteFiles)..where((t) => t.id.equals(id))).write(
      NoteFilesCompanion(isActive: Value(isActive), updatedAt: Value(DateTime.now())),
    );
  }

  // --- ReviewRecords ---

  Future<ReviewRecord?> recordForNote(int noteId) =>
      (select(reviewRecords)..where((t) => t.noteId.equals(noteId)))
          .getSingleOrNull();

  Future<List<JoinedRecord>> overdueNotes(DateTime now) async {
    final activeNotes = await allActiveNotes();
    if (activeNotes.isEmpty) return [];

    final activeIds = activeNotes.map((n) => n.id).toList();
    final records = await (select(reviewRecords)
      ..where((t) => t.noteId.isIn(activeIds)))
      .get();

    final recordMap = {for (final r in records) r.noteId: r};

    final result = <JoinedRecord>[];
    for (final note in activeNotes) {
      final record = recordMap[note.id];
      if (record == null || !record.nextReviewDate.isAfter(now)) {
        result.add(JoinedRecord(note: note, record: record));
      }
    }

    result.sort((a, b) {
      final aDate = a.record?.nextReviewDate;
      final bDate = b.record?.nextReviewDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return -1;
      if (bDate == null) return 1;
      return aDate.compareTo(bDate);
    });

    return result;
  }

  Future<int> overdueCount(DateTime now) async {
    final activeNotes = await allActiveNotes();
    if (activeNotes.isEmpty) return 0;

    final activeIds = activeNotes.map((n) => n.id).toList();
    final records = await (select(reviewRecords)
      ..where((t) => t.noteId.isIn(activeIds)))
      .get();

    final recordMap = {for (final r in records) r.noteId: r};

    int count = 0;
    for (final note in activeNotes) {
      final record = recordMap[note.id];
      if (record == null || !record.nextReviewDate.isAfter(now)) {
        count++;
      }
    }
    return count;
  }

  Future<List<DailyReviewCount>> reviewHistoryLast30Days() async {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final start = DateTime(thirtyDaysAgo.year, thirtyDaysAgo.month, thirtyDaysAgo.day);

    final rows = await (select(reviewRecords)
          ..where((t) => t.lastReviewDate.isBiggerThanValue(start))
        ).get();

    final counts = <String, int>{};
    for (final row in rows) {
      if (row.lastReviewDate == null) continue;
      final date = row.lastReviewDate!;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final result = <DailyReviewCount>[];
    for (int i = 30; i >= 0; i--) {
      final day = start.add(Duration(days: i));
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      result.add(DailyReviewCount(date: day, count: counts[key] ?? 0));
    }
    return result;
  }

  Future<List<DailyReviewCount>> reviewHistoryForMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final rows = await (select(reviewRecords)
          ..where((t) => t.lastReviewDate.isBiggerOrEqualValue(start))
        ).get();

    final counts = <String, int>{};
    for (final row in rows) {
      if (row.lastReviewDate == null) continue;
      if (!row.lastReviewDate!.isBefore(end)) continue;
      final date = row.lastReviewDate!;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final result = <DailyReviewCount>[];
    final daysInMonth = end.subtract(const Duration(days: 1)).day;
    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      result.add(DailyReviewCount(date: day, count: counts[key] ?? 0));
    }
    return result;
  }

  Future<List<JoinedRecord>> _notesWithRecordsWhere(
      bool Function(ReviewRecord) filter) async {
    final activeNotes = await allActiveNotes();
    if (activeNotes.isEmpty) return [];
    final activeIds = activeNotes.map((n) => n.id).toList();
    final records = await (select(reviewRecords)
          ..where((t) => t.noteId.isIn(activeIds))
        ).get();
    final recordMap = {for (final r in records) r.noteId: r};
    final result = <JoinedRecord>[];
    for (final note in activeNotes) {
      final record = recordMap[note.id];
      if (record != null && filter(record)) {
        result.add(JoinedRecord(note: note, record: record));
      }
    }
    result.sort((a, b) => b.record!.lastReviewDate!.compareTo(a.record!.lastReviewDate!));
    return result;
  }

  Future<List<JoinedRecord>> notesReviewedOnDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _notesWithRecordsWhere((r) =>
        r.lastReviewDate != null &&
        !r.lastReviewDate!.isBefore(start) &&
        r.lastReviewDate!.isBefore(end));
  }

  Future<List<JoinedRecord>> notesReviewedInMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return _notesWithRecordsWhere((r) =>
        r.lastReviewDate != null &&
        !r.lastReviewDate!.isBefore(start) &&
        r.lastReviewDate!.isBefore(end));
  }

  Future<ReviewRecord> upsertRecord(ReviewRecordsCompanion data) {
    return into(reviewRecords).insertReturning(
      data,
      mode: InsertMode.insertOrReplace,
    );
  }

  // --- ChatMessages ---

  Future<List<ChatMessage>> messagesForSession(String sessionType, {int? noteId}) {
    final query = select(chatMessages)
      ..where((t) => t.sessionType.equals(sessionType))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (noteId != null) {
      query.where((t) => t.noteId.equals(noteId) | t.noteId.isNull());
    }
    return query.get();
  }

  Future<void> insertChatMessage({
    required String sessionType,
    int? noteId,
    required String role,
    required String content,
  }) {
    return into(chatMessages).insert(
      ChatMessagesCompanion.insert(
        sessionType: sessionType,
        noteId: Value(noteId),
        role: role,
        content: content,
      ),
    );
  }

  Future<void> clearSession(String sessionType) {
    return (delete(chatMessages)
          ..where((t) => t.sessionType.equals(sessionType)))
        .go();
  }

  Future<void> clearMessagesForNote(int noteId) {
    return (delete(chatMessages)
          ..where((t) => t.noteId.equals(noteId)))
        .go();
  }

  Future<List<ChatMessage>> allMessages() {
    return (select(chatMessages)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<ChatMessage>> messagesForNote(int noteId) {
    return (select(chatMessages)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
}
