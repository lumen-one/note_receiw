# NoteReview App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Android app that uses DeepSeek AI to quiz users on their Obsidian notes with SM-2 spaced repetition.

**Architecture:** Pure client-side Flutter app with Riverpod state management, Drift SQLite persistence, 3-tab bottom navigation (Home/Review/Settings). DeepSeek API called directly for question generation and chat.

**Tech Stack:** Flutter 3.x, Dart 3.x, Riverpod 2.x, Drift 2.x, GoRouter 14.x, Dio 5.x, WorkManager 0.5.x

---

## Prerequisites

- [ ] Flutter SDK installed and `flutter doctor` passes
- [ ] Android SDK with API 26+ available
- [ ] DeepSeek API key (https://platform.deepseek.com)

---

### Task 1: Create Flutter Project and Directory Structure

**Files:**
- Create: `phone_note_review/lib/main.dart`
- Create: `phone_note_review/pubspec.yaml`

- [ ] **Step 1: Create Flutter project**

```bash
flutter create --org com.noteview --project-name phone_note_review --platforms android .
```

- [ ] **Step 2: Verify project runs**

```bash
flutter build apk --debug
```
Expected: Build successful.

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p lib/core
mkdir -p lib/data/database/daos
mkdir -p lib/data/repositories
mkdir -p lib/services
mkdir -p lib/features/home/widgets
mkdir -p lib/features/vault/widgets
mkdir -p lib/features/review/widgets
mkdir -p lib/features/settings/widgets
mkdir -p lib/models
```

- [ ] **Step 4: Update pubspec.yaml with all dependencies**

Replace existing `pubspec.yaml` with:

```yaml
name: phone_note_review
description: AI-powered Obsidian note review app with spaced repetition.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.6.0

dependencies:
  flutter:
    sdk: flutter
  drift: ^2.22.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  path: ^1.9.0
  riverpod: ^2.6.0
  flutter_riverpod: ^2.6.0
  go_router: ^14.6.0
  dio: ^5.7.0
  flutter_secure_storage: ^9.2.0
  shared_preferences: ^2.3.0
  workmanager: ^0.5.2
  flutter_local_notifications: ^18.0.0
  permission_handler: ^11.3.0
  file_picker: ^8.1.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0
  intl: ^0.19.0
  collection: ^1.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.22.0
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.9.0
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 5: Run flutter pub get**

```bash
flutter pub get
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: initialize Flutter project with dependencies"
```

---

### Task 2: Core Constants and Theme

**Files:**
- Create: `lib/core/constants.dart`
- Create: `lib/core/theme.dart`

- [ ] **Step 1: Write constants.dart**

```dart
class AppConstants {
  static const String appName = 'NoteReview';
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String deepseekModel = 'deepseek-chat';
  static const int defaultQuestionCount = 5;
  static const int defaultNotifyHour = 20;
  static const int defaultNotifyMinute = 0;
  static const double defaultEaseFactor = 2.5;
  static const double minEaseFactor = 1.3;
  static const int apiTimeoutSeconds = 30;
  static const int maxRetries = 2;
}
```

- [ ] **Step 2: Write theme.dart**

```dart
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add core constants and theme"
```

---

### Task 3: Database Tables Definition (Drift)

**Files:**
- Create: `lib/data/database/tables.dart`
- Create: `lib/data/database/database.dart`

- [ ] **Step 1: Write tables.dart**

```dart
import 'package:drift/drift.dart';

class NoteFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().named('file_path')();
  TextColumn get fileName => text().named('file_name')();
  BoolColumn get addedManually =>
      boolean().named('added_manually').withDefault(const Constant(false))();
  BoolColumn get hasReviewTag =>
      boolean().named('has_review_tag').withDefault(const Constant(false))();
  BoolColumn get isActive =>
      boolean().named('is_active').withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();
}

class ReviewRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId =>
      integer().named('note_id').references(NoteFiles, #id, onDelete: KeyAction.cascade)();
  RealColumn get sm2Interval =>
      real().named('sm2_interval').withDefault(const Constant(1.0))();
  RealColumn get sm2EaseFactor =>
      real().named('sm2_ease_factor').withDefault(const Constant(2.5))();
  IntColumn get sm2Repetitions =>
      integer().named('sm2_repetitions').withDefault(const Constant(0))();
  DateTimeColumn get nextReviewDate =>
      dateTime().named('next_review_date')();
  DateTimeColumn get lastReviewDate =>
      dateTime().named('last_review_date').nullable()();
  IntColumn get lastScore =>
      integer().named('last_score').nullable()();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {noteId};
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionType => text().named('session_type')();
  IntColumn get noteId => integer().named('note_id').nullable()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
}

class AppState extends Table {
  IntColumn get id => integer()();
  DateTimeColumn get lastCheckTime => dateTime().named('last_check_time')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PromptTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get content => text()();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get uniqueKeys => {columns: {name}};
}
```

- [ ] **Step 2: Write database.dart**

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'database.g.dart';

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
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = p.join(dbFolder.path, 'note_review.db');
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
}
```

- [ ] **Step 3: Run drift code generation**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: `database.g.dart` generated. If errors, fix them.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add drift database schema"
```

---

### Task 4: Database DAOs

**Files:**
- Create: `lib/data/database/daos/note_dao.dart`
- Create: `lib/data/database/daos/review_dao.dart`
- Create: `lib/data/database/daos/chat_dao.dart`

- [ ] **Step 1: Write note_dao.dart** — extend AppDatabase with note-related queries

```dart
import 'package:drift/drift.dart';
import '../database.dart';

part 'note_dao.g.dart';

extension NoteDao on AppDatabase {
  Future<List<NoteFile>> allActiveNotes() =>
      (select(noteFiles)..where((t) => t.isActive.equals(true))).get();

  Future<List<NoteFile>> allNotes() => select(noteFiles).get();

  Future<NoteFile?> noteByPath(String filePath) =>
      (select(noteFiles)..where((t) => t.filePath.equals(filePath)))
          .getSingleOrNull();

  Future<NoteFile> upsertNote(
    String filePath,
    String fileName, {
    bool? addedManually,
    bool? hasReviewTag,
    bool? isActive,
  }) {
    final now = DateTime.now();
    final row = NoteFilesCompanion.insert(
      filePath: filePath,
      fileName: fileName,
      addedManually: Value(addedManually ?? false),
      hasReviewTag: Value(hasReviewTag ?? false),
      isActive: Value(isActive ?? true),
      createdAt: now,
      updatedAt: now,
    );
    return into(noteFiles).insertReturning(row, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateNoteActive(int id, bool isActive) {
    return (update(noteFiles)..where((t) => t.id.equals(id))).write(
      NoteFilesCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNote(int id) {
    return (delete(noteFiles)..where((t) => t.id.equals(id))).go();
  }
}

// Row class convenience aliases
typedef NoteFile = $NoteFilesTableTableRow;
```

Wait, Drift generates `$NoteFilesTableRow` or similar. Let me use `TypedResult` properly. Actually, Drift's generated row class depends on the table definition. Let me simplify and use proper Drift DAO patterns.

- [ ] **Step 1 (revised): Write note_dao.dart**

```dart
import 'package:drift/drift.dart';
import '../database.dart';

part 'note_dao.g.dart';

@driftAccessor
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

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
  }) async {
    final existing = await noteByPath(filePath);
    if (existing != null) {
      await update(noteFiles).replace(
        existing.copyWith(
          fileName: fileName,
          addedManually: addedManually,
          hasReviewTag: hasReviewTag,
          updatedAt: DateTime.now(),
        ),
      );
      return (await noteByPath(filePath))!;
    }
    return into(noteFiles).insertReturning(
      NoteFilesCompanion.insert(
        filePath: filePath,
        fileName: fileName,
        addedManually: addedManually,
        hasReviewTag: hasReviewTag,
        isActive: Value(isActive),
      ),
    );
  }

  Future<void> updateNoteActive(int id, bool isActive) {
    return (update(noteFiles)..where((t) => t.id.equals(id))).write(
      NoteFilesCompanion(isActive: Value(isActive), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> toggleNote(int id, bool active, {bool? addedManually}) async {
    final entry = NoteFilesCompanion(
      isActive: Value(active),
      addedManually: addedManually != null ? Value(addedManually) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    );
    await (update(noteFiles)..where((t) => t.id.equals(id))).write(entry);
  }
}
```

- [ ] **Step 2: Write review_dao.dart**

```dart
import 'package:drift/drift.dart';
import '../database.dart';

part 'review_dao.g.dart';

@driftAccessor
class ReviewDao extends DatabaseAccessor<AppDatabase> with _$ReviewDaoMixin {
  ReviewDao(super.db);

  Future<ReviewRecord?> recordForNote(int noteId) =>
      (select(reviewRecords)..where((t) => t.noteId.equals(noteId)))
          .getSingleOrNull();

  Future<List<JoinedRecord>> overdueNotes(DateTime lastCheck, DateTime now) {
    final query = select(reviewRecords).join([
      innerJoin(noteFiles, noteFiles.id.equalsExp(reviewRecords.noteId)),
    ]);
    query.where(
      reviewRecords.nextReviewDate.isBiggerThanValue(lastCheck) &
          reviewRecords.nextReviewDate.isSmallerOrEqualValue(now) &
          noteFiles.isActive.equals(true),
    );
    query.orderBy([OrderingTerm.asc(reviewRecords.nextReviewDate)]);
    return query.map((row) => JoinedRecord(
          note: row.readTable(noteFiles),
          record: row.readTable(reviewRecords),
        )).get();
  }

  Future<int> overdueCount(DateTime lastCheck, DateTime now) {
    final query = selectOnly(reviewRecords)
      ..join([
        innerJoin(noteFiles, noteFiles.id.equalsExp(reviewRecords.noteId)),
      ])
      ..where(
        reviewRecords.nextReviewDate.isBiggerThanValue(lastCheck) &
            reviewRecords.nextReviewDate.isSmallerOrEqualValue(now) &
            noteFiles.isActive.equals(true),
      );
    return query.map((r) => r.read(reviewRecords.id)).get().then((l) => l.length);
  }

  Future<ReviewRecord> upsertRecord(ReviewRecordsCompanion data) {
    return into(reviewRecords).insertReturning(
      data,
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> updateSm2State(ReviewRecord record) {
    return (update(reviewRecords)..where((t) => t.noteId.equals(record.noteId)))
        .write(ReviewRecordsCompanion(
      sm2Interval: Value(record.sm2Interval),
      sm2EaseFactor: Value(record.sm2EaseFactor),
      sm2Repetitions: Value(record.sm2Repetitions),
      nextReviewDate: Value(record.nextReviewDate),
      lastReviewDate: Value(record.lastReviewDate),
      lastScore: Value(record.lastScore),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

class JoinedRecord {
  final NoteFile note;
  final ReviewRecord record;
  JoinedRecord({required this.note, required this.record});
}
```

- [ ] **Step 3: Write chat_dao.dart**

```dart
import 'package:drift/drift.dart';
import '../database.dart';

part 'chat_dao.g.dart';

@driftAccessor
class ChatDao extends DatabaseAccessor<AppDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  Future<List<ChatMessage>> messagesForSession(String sessionType, {int? noteId}) {
    var query = select(chatMessages)
      ..where((t) => t.sessionType.equals(sessionType));
    if (noteId != null) {
      query = query..where((t) => t.noteId.equals(noteId) | t.noteId.isNull());
    } else {
      query = query..where((t) => t.noteId.isNull());
    }
    return query.orderBy([OrderingTerm.asc(chatMessages.createdAt)]).get();
  }

  Future<void> insertMessage({
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
}
```

- [ ] **Step 4: Verify AppState/PromptTemplate methods** — already written in Task 3, no extra code needed.

- [ ] **Step 5: Run code generation**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add database DAOs"
```

---

### Task 4.5: Settings Persistence (SharedPreferences)

**Files:**
- Create: `lib/data/settings_store.dart`

- [ ] **Step 1: Write settings_store.dart**

```dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _keyVaultPath = 'vault_path';
  static const _keyReviewCount = 'review_count';
  static const _keyNotifyHour = 'notify_hour';
  static const _keyNotifyMinute = 'notify_minute';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<String?> getVaultPath() async {
    final prefs = await _prefs;
    return prefs.getString(_keyVaultPath);
  }

  static Future<void> setVaultPath(String path) async {
    final prefs = await _prefs;
    await prefs.setString(_keyVaultPath, path);
  }

  static Future<int> getReviewCount() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyReviewCount) ?? 5;
  }

  static Future<void> setReviewCount(int count) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyReviewCount, count);
  }

  static Future<int> getNotifyHour() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyNotifyHour) ?? 20;
  }

  static Future<void> setNotifyHour(int hour) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyNotifyHour, hour);
  }

  static Future<int> getNotifyMinute() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyNotifyMinute) ?? 0;
  }

  static Future<void> setNotifyMinute(int minute) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyNotifyMinute, minute);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add SharedPreferences settings store"
```

---

### Task 5: SM-2 Algorithm Engine

**Files:**
- Create: `lib/services/sm2_engine.dart`

- [ ] **Step 1: Write sm2_engine.dart**

```dart
import 'package:intl/intl.dart';

class Sm2Result {
  final double interval;
  final double easeFactor;
  final int repetitions;
  final DateTime nextReviewDate;

  Sm2Result({
    required this.interval,
    required this.easeFactor,
    required this.repetitions,
    required this.nextReviewDate,
  });
}

class Sm2Engine {
  static Sm2Result calculate({
    required int quality,
    required double currentInterval,
    required double currentEaseFactor,
    required int currentRepetitions,
  }) {
    double newInterval;
    int newRepetitions;
    double newEaseFactor;

    if (quality >= 3) {
      if (currentRepetitions == 0) {
        newInterval = 1;
      } else if (currentRepetitions == 1) {
        newInterval = 6;
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
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add SM-2 algorithm engine"
```

---

### Task 6: Secure Storage Service

**Files:**
- Create: `lib/data/secure_storage.dart`

- [ ] **Step 1: Write secure_storage.dart**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _keyApiKey = 'deepseek_api_key';
  final FlutterSecureStorage _storage;

  SecureStorageService() : _storage = const FlutterSecureStorage();

  Future<String?> getApiKey() => _storage.read(key: _keyApiKey);

  Future<void> setApiKey(String key) =>
      _storage.write(key: _keyApiKey, value: key);

  Future<void> deleteApiKey() => _storage.delete(key: _keyApiKey);
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add secure storage for API key"
```

---

### Task 7: AI Service (DeepSeek API)

**Files:**
- Create: `lib/services/ai_service.dart`
- Create: `lib/services/prompt_service.dart`

- [ ] **Step 1: Write prompt_service.dart**

```dart
class PromptService {
  static const defaultGenerateQuestionPrompt = '''
你是一位和我一起学习的挚友。请阅读以下笔记内容，帮我查漏补缺：

1. 生成一道简答题，检验我对内容的理解
2. 根据笔记内容，拓展一个相关知识或概念，帮我开阔思路

笔记内容：
{note_content}

请按以下格式回复：
【题目】
(题目内容)

【拓展】
(拓展知识点或概念)
''';

  static const defaultEvaluateAnswerPrompt = '''
你是和我一起学习的挚友。以下是笔记、你出的题和我的回答。

笔记：
{note_content}

题目：
{question}

我的回答：
{user_answer}

请：
1. 温和地评价我的回答，指出遗漏的关键点
2. 建议评分 0-5 分（0=完全错误, 5=完全正确且完整）
3. 提出一个延伸问题，引导我深入思考

请按以下格式回复：
【评价】
(评价内容)

【建议评分】
(0-5 的整数)

【延伸】
(延伸问题)
''';

  static String render(String template, Map<String, String> variables) {
    var result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

class ParsedResponse {
  final String evaluation;
  final int? suggestedScore;
  final String extension;

  ParsedResponse({
    required this.evaluation,
    this.suggestedScore,
    required this.extension,
  });
}

class ParsedQuestion {
  final String question;
  final String expansion;

  ParsedQuestion({required this.question, required this.expansion});
}

ParsedQuestion parseQuestionResponse(String response) {
  final questionMatch = RegExp(r'【题目】\s*([\s\S]*?)(?=【拓展】|$)').firstMatch(response);
  final expansionMatch = RegExp(r'【拓展】\s*([\s\S]*?)$').firstMatch(response);
  return ParsedQuestion(
    question: questionMatch?.group(1)?.trim() ?? '',
    expansion: expansionMatch?.group(1)?.trim() ?? '',
  );
}

ParsedResponse parseEvaluationResponse(String response) {
  final evalMatch = RegExp(r'【评价】\s*([\s\S]*?)(?=【建议评分】|$)').firstMatch(response);
  final scoreMatch = RegExp(r'【建议评分】\s*([\s\S]*?)(?=【延伸】|$)').firstMatch(response);
  final extMatch = RegExp(r'【延伸】\s*([\s\S]*?)$').firstMatch(response);
  final scoreText = scoreMatch?.group(1)?.trim();
  int? score;
  if (scoreText != null) {
    score = int.tryParse(RegExp(r'\d').firstMatch(scoreText)?.group(0) ?? '');
  }
  return ParsedResponse(
    evaluation: evalMatch?.group(1)?.trim() ?? '',
    suggestedScore: score,
    extension: extMatch?.group(1)?.trim() ?? '',
  );
}
```

- [ ] **Step 2: Write ai_service.dart**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AIService {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  AIService()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.deepseek.com/v1',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        )),
        _secureStorage = const FlutterSecureStorage();

  Future<String> _getApiKey() async {
    final key = await _secureStorage.read(key: 'deepseek_api_key');
    if (key == null || key.isEmpty) {
      throw Exception('请先在设置中配置 DeepSeek API Key');
    }
    return key;
  }

  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    List<Map<String, String>> history = const [],
    int maxRetries = 2,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history,
      {'role': 'user', 'content': userMessage},
    ];

    Exception? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final apiKey = await _getApiKey();
        final response = await _dio.post(
          '/chat/completions',
          data: {
            'model': 'deepseek-chat',
            'messages': messages,
            'temperature': 0.7,
            'max_tokens': 2048,
          },
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
          ),
        );
        return response.data['choices'][0]['message']['content'] as String;
      } on DioException catch (e) {
        lastError = e;
        if (attempt == maxRetries) break;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('AI 请求失败: ${lastError.toString()}');
  }

  Future<String> continueChat({
    required List<Map<String, String>> messages,
    int maxRetries = 2,
  }) async {
    Exception? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final apiKey = await _getApiKey();
        final response = await _dio.post(
          '/chat/completions',
          data: {
            'model': 'deepseek-chat',
            'messages': messages,
            'temperature': 0.7,
            'max_tokens': 2048,
          },
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
          ),
        );
        return response.data['choices'][0]['message']['content'] as String;
      } on DioException catch (e) {
        lastError = e;
        if (attempt == maxRetries) break;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('AI 请求失败: ${lastError.toString()}');
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add AI service and prompt engine"
```

---

### Task 8: Vault Service (File Scanning)

**Files:**
- Create: `lib/services/vault_service.dart`

- [ ] **Step 1: Write vault_service.dart**

```dart
import 'dart:io';

class VaultEntry {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;

  VaultEntry({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    required this.hasReviewTag,
  });
}

class VaultService {
  Future<List<VaultEntry>> scanDirectory(String rootPath) async {
    final entries = <VaultEntry>[];
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) return entries;

    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        final relativePath =
            entity.path.substring(rootPath.length).replaceAll('\\', '/');
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        final content = await entity.readAsString();
        final hasReviewTag = content.contains('#review');
        entries.add(VaultEntry(
          name: entity.path.split('/').last,
          relativePath: relativePath.toString(),
          absolutePath: entity.path,
          isDirectory: false,
          hasReviewTag: hasReviewTag,
        ));
      }
    }
    return entries;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add vault file scanning service"
```

---

### Task 9: Notification Service

**Files:**
- Create: `lib/services/notification_service.dart`

- [ ] **Step 1: Write notification_service.dart**

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Will be implemented in Task 9 - initialization
    return true;
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static void _onNotificationTap(NotificationResponse response) {
    // Handled via payload in router
  }

  static Future<void> showReviewNotification(int count) async {
    const androidDetails = AndroidNotificationDetails(
      'review_channel',
      '复习提醒',
      channelDescription: '笔记复习提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      0,
      '复习时间到',
      '你有 $count 篇笔记需要复习',
      details,
      payload: '/review',
    );
  }

  static Future<void> schedulePeriodicCheck() async {
    await Workmanager().registerPeriodicTask(
      'review_check',
      'checkForOverdueReviews',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add notification and workmanager service"
```

---

### Task 10: Riverpod Providers — Settings & Database

**Files:**
- Create: `lib/features/settings/settings_provider.dart`

- [ ] **Step 1: Write settings_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/secure_storage.dart';
import '../../data/settings_store.dart';
import '../../services/prompt_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final apiKeyProvider = FutureProvider<String?>((ref) async {
  return ref.read(secureStorageProvider).getApiKey();
});

final vaultPathProvider = FutureProvider<String?>((ref) async {
  return SettingsStore.getVaultPath();
});

final generatePromptProvider = FutureProvider<String>((ref) async {
  final db = ref.read(databaseProvider);
  final saved = await db.getPromptTemplate('generate_question');
  return saved ?? PromptService.defaultGenerateQuestionPrompt;
});

final evaluatePromptProvider = FutureProvider<String>((ref) async {
  final db = ref.read(databaseProvider);
  final saved = await db.getPromptTemplate('evaluate_answer');
  return saved ?? PromptService.defaultEvaluateAnswerPrompt;
});

final reviewCountProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getReviewCount();
});

final notifyHourProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getNotifyHour();
});

final notifyMinuteProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getNotifyMinute();
});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add Riverpod settings and database providers"
```

---

### Task 11: Riverpod Providers — Vault

**Files:**
- Create: `lib/features/vault/vault_provider.dart`

- [ ] **Step 1: Write vault_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/database/daos/note_dao.dart';
import '../../services/vault_service.dart';
import '../settings/settings_provider.dart';

final vaultServiceProvider = Provider<VaultService>((ref) => VaultService());

final vaultEntriesProvider = FutureProvider<List<VaultEntry>>((ref) async {
  final vaultPath = await ref.read(vaultPathProvider.future);
  if (vaultPath == null) return [];
  return ref.read(vaultServiceProvider).scanDirectory(vaultPath);
});

final activeNoteIdsProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = NoteDao(db);
  final notes = await dao.allActiveNotes();
  return notes.map((n) => n.filePath).toSet();
});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add vault Riverpod providers"
```

---

### Task 12: Riverpod Providers — Review

**Files:**
- Create: `lib/features/review/review_provider.dart`

- [ ] **Step 1: Write review_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/database/daos/review_dao.dart';
import '../../data/database/daos/chat_dao.dart';
import '../../services/sm2_engine.dart';
import '../../services/ai_service.dart';
import '../../services/prompt_service.dart';
import '../../services/vault_service.dart';
import '../settings/settings_provider.dart';
import 'dart:io';

// Model classes for review session state

class QuestionItem {
  final int noteId;
  final String fileName;
  final String question;
  final String expansion;
  final String noteContent;
  String? userAnswer;
  String? evaluation;
  int? suggestedScore;
  int? selfScore;
  String? extension;

  QuestionItem({
    required this.noteId,
    required this.fileName,
    required this.question,
    required this.expansion,
    required this.noteContent,
    this.userAnswer,
    this.evaluation,
    this.suggestedScore,
    this.selfScore,
    this.extension,
  });

  QuestionItem copyWith({
    String? userAnswer,
    String? evaluation,
    int? suggestedScore,
    int? selfScore,
    String? extension,
  }) {
    return QuestionItem(
      noteId: noteId,
      fileName: fileName,
      question: question,
      expansion: expansion,
      noteContent: noteContent,
      userAnswer: userAnswer ?? this.userAnswer,
      evaluation: evaluation ?? this.evaluation,
      suggestedScore: suggestedScore ?? this.suggestedScore,
      selfScore: selfScore ?? this.selfScore,
      extension: extension ?? this.extension,
    );
  }
}

enum ReviewPhase { loading, showingQuestions, answering, evaluating, chatting, complete }

class ReviewState {
  final ReviewPhase phase;
  final List<QuestionItem> questions;
  final int currentQuestionIndex;
  final bool isLoading;

  ReviewState({
    this.phase = ReviewPhase.loading,
    this.questions = const [],
    this.currentQuestionIndex = 0,
    this.isLoading = false,
  });

  ReviewState copyWith({
    ReviewPhase? phase,
    List<QuestionItem>? questions,
    int? currentQuestionIndex,
    bool? isLoading,
  }) {
    return ReviewState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class OverdueInfo {
  final int count;
  final List<JoinedRecord> records;

  OverdueInfo({required this.count, required this.records});
}

final overdueProvider = FutureProvider<OverdueInfo>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = ReviewDao(db);
  final lastCheck = await db.getLastCheckTime();
  final now = DateTime.now();
  final records = await dao.overdueNotes(lastCheck, now);
  return OverdueInfo(count: records.length, records: records);
});

final reviewStateProvider = StateNotifierProvider<ReviewNotifier, ReviewState>(
  (ref) => ReviewNotifier(ref),
);

class ReviewNotifier extends StateNotifier<ReviewState> {
  final Ref _ref;

  ReviewNotifier(this._ref) : super(ReviewState());

  Future<void> loadQuestions() async {
    state = state.copyWith(isLoading: true, phase: ReviewPhase.loading);

    final db = _ref.read(databaseProvider);
    final reviewDao = ReviewDao(db);
    final noteDao = NoteDao(db);
    final aiService = _ref.read(aiServiceProvider);
    final generatePrompt = await _ref.read(generatePromptProvider.future);
    final vaultPath = await _ref.read(vaultPathProvider.future);

    final lastCheck = await db.getLastCheckTime();
    final overdue = await reviewDao.overdueNotes(lastCheck, DateTime.now());

    final count = _ref.read(reviewCountProvider).valueOrNull ?? 5;
    final selected = overdue.take(count).toList();

    final items = <QuestionItem>[];
    for (final joined in selected) {
      final filePath = '${vaultPath ?? ""}/${joined.note.filePath}';
      final file = File(filePath);
      String noteContent = '';
      if (await file.exists()) {
        noteContent = await file.readAsString();
      }

      final prompt = PromptService.render(generatePrompt, {
        'note_content': noteContent,
      });

      final response = await aiService.chat(
        systemPrompt: '你是一位帮助我学习的挚友。',
        userMessage: prompt,
      );

      final parsed = parseQuestionResponse(response);
      items.add(QuestionItem(
        noteId: joined.note.id,
        fileName: joined.note.fileName,
        question: parsed.question,
        expansion: parsed.expansion,
        noteContent: noteContent,
      ));
    }

    state = state.copyWith(
      questions: items,
      currentQuestionIndex: 0,
      phase: items.isEmpty ? ReviewPhase.complete : ReviewPhase.showingQuestions,
      isLoading: false,
    );
  }

  Future<void> submitAnswer(String answer) async {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(userAnswer: answer);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions, phase: ReviewPhase.evaluating, isLoading: true);

    final aiService = _ref.read(aiServiceProvider);
    final evaluatePrompt = await _ref.read(evaluatePromptProvider.future);
    final noteContent = item.noteContent;

    final prompt = PromptService.render(evaluatePrompt, {
      'note_content': noteContent,
      'question': item.question,
      'user_answer': answer,
    });

    final response = await aiService.chat(
      systemPrompt: '你是一位帮助我学习的挚友。',
      userMessage: prompt,
    );

    final parsed = parseEvaluationResponse(response);
    final updated = item.copyWith(
      evaluation: parsed.evaluation,
      suggestedScore: parsed.suggestedScore,
      extension: parsed.extension,
    );
    final newQuestions2 = List<QuestionItem>.from(state.questions);
    newQuestions2[idx] = updated;
    state = state.copyWith(
      questions: newQuestions2,
      phase: ReviewPhase.evaluating,
      isLoading: false,
    );
  }

  Future<void> submitSelfScore(int score) async {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(selfScore: score);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions);

    final db = _ref.read(databaseProvider);
    final reviewDao = ReviewDao(db);
    final existing = await reviewDao.recordForNote(item.noteId);

    final result = Sm2Engine.calculate(
      quality: score,
      currentInterval: existing?.sm2Interval ?? 1.0,
      currentEaseFactor: existing?.sm2EaseFactor ?? 2.5,
      currentRepetitions: existing?.sm2Repetitions ?? 0,
    );

    await reviewDao.upsertRecord(ReviewRecordsCompanion.insert(
      noteId: item.noteId,
      sm2Interval: Value(result.interval),
      sm2EaseFactor: Value(result.easeFactor),
      sm2Repetitions: Value(result.repetitions),
      nextReviewDate: result.nextReviewDate,
      lastReviewDate: Value(DateTime.now()),
      lastScore: Value(score),
    ));
  }

  void nextQuestion() {
    if (state.currentQuestionIndex < state.questions.length - 1) {
      state = state.copyWith(
        currentQuestionIndex: state.currentQuestionIndex + 1,
        phase: ReviewPhase.showingQuestions,
      );
    } else {
      state = state.copyWith(phase: ReviewPhase.complete);
    }
  }

  void enterChatMode() {
    state = state.copyWith(phase: ReviewPhase.chatting);
  }

  void reset() {
    state = ReviewState();
  }
}

final aiServiceProvider = Provider<AIService>((ref) => AIService());
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add review Riverpod providers and state"
```

---

### Task 13: App Entry Point with GoRouter

**Files:**
- Create: `lib/main.dart`
- Create: `lib/app.dart`

- [ ] **Step 1: Write main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await NotificationService.schedulePeriodicCheck();
  runApp(const ProviderScope(child: NoteReviewApp()));
}
```

- [ ] **Step 2: Write app.dart**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/vault/vault_browser_screen.dart';
import 'features/review/review_session_screen.dart';
import 'features/review/chat_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) => const ReviewScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/vault-browser',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const VaultBrowserScreen(),
    ),
    GoRoute(
      path: '/review/start',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReviewSessionScreen(),
    ),
    GoRoute(
      path: '/review/chat',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ChatScreen(sessionType: 'free_chat'),
    ),
  ],
);

class NoteReviewApp extends StatelessWidget {
  const NoteReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NoteReview',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int currentIndex;
    if (location.startsWith('/review')) {
      currentIndex = 1;
    } else if (location.startsWith('/settings')) {
      currentIndex = 2;
    } else {
      currentIndex = 0;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/review');
            case 2:
              context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add app entry point, GoRouter, and bottom navigation shell"
```

---

### Task 14: HomeScreen

**Files:**
- Create: `lib/features/home/home_screen.dart`
- Create: `lib/features/home/widgets/stats_card.dart`
- Create: `lib/features/home/widgets/overdue_badge.dart`

- [ ] **Step 1: Write home_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../review/review_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueProvider);
    final overdueCount = overdueAsync.valueOrNull?.count ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteReview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '管理笔记',
            onPressed: () => context.push('/vault-browser'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
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
                            overdueCount > 0 ? '有笔记需要复习' : '暂无待复习笔记',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            overdueCount > 0
                                ? '点击下方复习标签开始'
                                : '去设置添加笔记文件夹',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '遗忘曲线概览',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Text(
                  '即将支持',
                  style: Theme.of(context).textTheme.bodyMedium,
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
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add HomeScreen with overdue stats"
```

---

### Task 15: VaultBrowserScreen

**Files:**
- Create: `lib/features/vault/vault_browser_screen.dart`
- Create: `lib/features/vault/widgets/file_tree.dart`
- Create: `lib/features/vault/widgets/note_tile.dart`

- [ ] **Step 1: Write vault_browser_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/database/daos/note_dao.dart';
import '../../services/vault_service.dart';
import '../settings/settings_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vaultPath = await ref.read(vaultPathProvider.future);
    if (vaultPath == null) {
      setState(() => _loading = false);
      return;
    }
    final service = ref.read(vaultServiceProvider);
    final entries = await service.scanDirectory(vaultPath);
    final db = ref.read(databaseProvider);
    final dao = NoteDao(db);
    final activeNotes = await dao.allActiveNotes();
    final activePaths = activeNotes.map((n) => n.filePath).toSet();

    final states = <String, bool>{};
    for (final entry in entries) {
      final existing = activeNotes.where((n) => n.filePath == entry.relativePath);
      if (entry.hasReviewTag && existing.isEmpty) {
        await dao.upsertNote(
          filePath: entry.relativePath,
          fileName: entry.name,
          hasReviewTag: true,
        );
        states[entry.relativePath] = true;
      } else if (existing.isNotEmpty) {
        states[entry.relativePath] = existing.first.isActive;
      } else {
        states[entry.relativePath] = false;
      }
    }

    setState(() {
      _entries = entries;
      _activeStates = states;
      _loading = false;
    });
  }

  Future<void> _toggle(String path, bool active) async {
    final db = ref.read(databaseProvider);
    final dao = NoteDao(db);
    final entry = _entries.firstWhere((e) => e.relativePath == path);
    await dao.upsertNote(
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
          : _entries.isEmpty
              ? const Center(child: Text('未找到笔记\n请先在设置中配置 Vault 路径'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return NoteTile(
                      name: entry.name,
                      path: entry.relativePath,
                      hasReviewTag: entry.hasReviewTag,
                      isActive: _activeStates[entry.relativePath] ?? false,
                      onToggle: (active) => _toggle(entry.relativePath, active),
                    );
                  },
                ),
    );
  }
}
```

- [ ] **Step 2: Write note_tile.dart**

```dart
import 'package:flutter/material.dart';

class NoteTile extends StatelessWidget {
  final String name;
  final String path;
  final bool hasReviewTag;
  final bool isActive;
  final ValueChanged<bool> onToggle;

  const NoteTile({
    super.key,
    required this.name,
    required this.path,
    required this.hasReviewTag,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        secondary: Icon(
          hasReviewTag ? Icons.label : Icons.description_outlined,
          color: hasReviewTag
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        value: isActive,
        onChanged: onToggle,
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add VaultBrowserScreen with note toggling"
```

---

### Task 16: ReviewScreen (Tab Page)

**Files:**
- Create: `lib/features/review/review_screen.dart`

- [ ] **Step 1: Write review_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../home/home_provider.dart';
import '../../data/database/database.dart';
import 'review_provider.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('复习')),
      body: overdueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (info) {
          if (info.count == 0) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('暂无待复习笔记',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.push('/review/chat'),
                    icon: const Icon(Icons.chat),
                    label: const Text('随便聊聊'),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          '${info.count}',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text('篇笔记需要复习',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('基于遗忘曲线，这些笔记已进入复习周期',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await ref.read(databaseProvider).updateLastCheckTime(DateTime.now());
                    if (context.mounted) {
                      context.push('/review/start');
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始复习'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/review/chat'),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('自由聊天'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add ReviewScreen tab page"
```

---

### Task 17: ReviewSessionScreen

**Files:**
- Create: `lib/features/review/review_session_screen.dart`
- Create: `lib/features/review/widgets/question_card.dart`
- Create: `lib/features/review/widgets/evaluation_view.dart`

- [ ] **Step 1: Write review_session_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'review_provider.dart';
import 'widgets/question_card.dart';
import 'widgets/evaluation_view.dart';
import 'widgets/chat_bubble.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  final _answerController = TextEditingController();
  bool _showFollowUpChat = false;
  List<Map<String, String>> _followUpMessages = [];

  Stream<ReviewState> get _stateStream =>
      ref.watch(reviewStateProvider.select((s) => s)).asStream().asBroadcastStream();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reviewStateProvider.notifier).loadQuestions();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewStateProvider);
    final theme = Theme.of(context);

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('正在生成题目...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习')),
        body: const Center(child: Text('暂无待复习笔记')),
      );
    }

    final question = state.questions[state.currentQuestionIndex];
    final progress =
        '${state.currentQuestionIndex + 1} / ${state.questions.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 - 第 $progress 题'),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (state.currentQuestionIndex + 1) / state.questions.length,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(question.fileName,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 12),
                  // Question phase
                  if (state.phase == ReviewPhase.showingQuestions ||
                      state.phase == ReviewPhase.answering)
                    QuestionCard(
                      question: question.question,
                      expansion: question.expansion,
                      answerController: _answerController,
                      onSubmit: () {
                        final answer = _answerController.text.trim();
                        if (answer.isNotEmpty) {
                          ref
                              .read(reviewStateProvider.notifier)
                              .submitAnswer(answer);
                        }
                      },
                    ),

                  // Evaluation phase
                  if (state.phase == ReviewPhase.evaluating &&
                      question.evaluation != null)
                    EvaluationView(
                      evaluation: question.evaluation!,
                      suggestedScore: question.suggestedScore,
                      extension: question.extension,
                      onScore: (score) {
                        ref
                            .read(reviewStateProvider.notifier)
                            .submitSelfScore(score);
                      },
                    ),

                  // Follow-up chat
                  if (_showFollowUpChat) ...[
                    const Divider(height: 32),
                    Text('追问',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._followUpMessages
                        .map((m) => ChatBubble(
                              content: m['content'] ?? '',
                              isUser: m['role'] == 'user',
                            )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _answerController,
                            decoration: const InputDecoration(
                              hintText: '继续追问...',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () => _sendFollowUp(),
                        ),
                      ],
                    ),
                  ],

                  // Actions after evaluation
                  if (state.phase == ReviewPhase.evaluating &&
                      question.selfScore != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _showFollowUpChat = true);
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('追问'),
                        ),
                        FilledButton(
                          onPressed: () {
                            _answerController.clear();
                            setState(() {
                              _showFollowUpChat = false;
                              _followUpMessages = [];
                            });
                            ref
                                .read(reviewStateProvider.notifier)
                                .nextQuestion();
                          },
                          child: Text(
                            state.currentQuestionIndex <
                                    state.questions.length - 1
                                ? '下一题'
                                : '完成复习',
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Complete
                  if (state.phase == ReviewPhase.complete) ...[
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.celebration,
                              size: 64, color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('复习完成！', style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.push('/review/chat'),
                            icon: const Icon(Icons.chat),
                            label: const Text('自由聊天'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFollowUp() async {
    final content = _answerController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _followUpMessages.add({'role': 'user', 'content': content});
    });
    _answerController.clear();

    final aiService = ref.read(aiServiceProvider);
    final state = ref.read(reviewStateProvider);
    final item = state.questions[state.currentQuestionIndex];

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '你是一位和我一起学习的挚友。我们正在讨论以下笔记内容：\n${item.noteContent}',
      },
      {
        'role': 'assistant',
        'content': '题目：${item.question}\n\n评价：${item.evaluation ?? ""}',
      },
      {'role': 'user', 'content': '我的回答：${item.userAnswer ?? ""}'},
      ..._followUpMessages,
    ];

    try {
      final reply = await aiService.continueChat(messages: messages);
      setState(() {
        _followUpMessages.add({'role': 'assistant', 'content': reply});
      });
    } catch (e) {
      setState(() {
        _followUpMessages.add({
          'role': 'assistant',
          'content': '抱歉，请求失败：$e',
        });
      });
    }
  }
}
```

- [ ] **Step 2: Write question_card.dart**

```dart
import 'package:flutter/material.dart';

class QuestionCard extends StatelessWidget {
  final String question;
  final String expansion;
  final TextEditingController answerController;
  final VoidCallback onSubmit;

  const QuestionCard({
    super.key,
    required this.question,
    required this.expansion,
    required this.answerController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('题目', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(question, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('拓展知识', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(expansion, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: answerController,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: '输入你的回答...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.send),
          label: const Text('提交回答'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Write evaluation_view.dart**

```dart
import 'package:flutter/material.dart';

class EvaluationView extends StatelessWidget {
  final String evaluation;
  final int? suggestedScore;
  final String? extension;
  final ValueChanged<int>? onScore;

  const EvaluationView({
    super.key,
    required this.evaluation,
    this.suggestedScore,
    this.extension,
    this.onScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 20, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Text('AI 评价', style: theme.textTheme.labelMedium),
                    if (suggestedScore != null) ...[
                      const Spacer(),
                      Text('建议 $suggestedScore 分',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.tertiary,
                          )),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(evaluation, style: theme.textTheme.bodyMedium),
                if (extension != null && extension!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('延伸思考',
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(extension!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (onScore != null) ...[
          Text('自评分数', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (i) {
              return _ScoreButton(score: i, onTap: () => onScore!(i));
            }),
          ),
        ],
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  final int score;
  final VoidCallback onTap;

  const _ScoreButton({required this.score, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.lime,
      Colors.lightGreen,
      Colors.green,
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors[score].withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors[score]),
        ),
        child: Column(
          children: [
            Text('$score', style: TextStyle(color: colors[score], fontWeight: FontWeight.bold, fontSize: 18)),
            Text('分', style: TextStyle(color: colors[score], fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create chat_bubble.dart if not exists**

```bash
mkdir -p lib/features/review/widgets
```

Write `lib/features/review/widgets/chat_bubble.dart`:

```dart
import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;

  const ChatBubble({super.key, required this.content, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Text(content, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add full review session with question, evaluation, and scoring"
```

---

### Task 18: ChatScreen (Free Chat)

**Files:**
- Create: `lib/features/review/chat_screen.dart`

- [ ] **Step 1: Write chat_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_service.dart';
import 'widgets/chat_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String sessionType;
  const ChatScreen({super.key, required this.sessionType});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

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
      final fullMessages = [
        {'role': 'system', 'content': '你是一位和我一起学习的挚友。我们可以自由讨论任何话题，包括笔记中的知识。'},
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionType == 'free_chat' ? '自由聊天' : '追问'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      '开始和你的学习挚友聊天吧',
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add free chat and follow-up chat screens"
```

---

### Task 19: SettingsScreen

**Files:**
- Create: `lib/features/settings/settings_screen.dart`
- Create: `lib/features/settings/widgets/prompt_editor.dart`

- [ ] **Step 1: Write settings_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/database/database.dart';
import '../../data/secure_storage.dart';
import '../../data/settings_store.dart';
import '../../services/prompt_service.dart';
import '../settings/settings_provider.dart';
import 'widgets/prompt_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  String? _vaultPath;
  int _reviewCount = 5;
  int _notifyHour = 20;
  int _notifyMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = SecureStorageService();
    final key = await storage.getApiKey();
    _apiKeyController.text = key ?? '';

    final vaultPath = await SettingsStore.getVaultPath();
    final reviewCount = await SettingsStore.getReviewCount();
    final notifyHour = await SettingsStore.getNotifyHour();
    final notifyMinute = await SettingsStore.getNotifyMinute();
    setState(() {
      _vaultPath = vaultPath;
      _reviewCount = reviewCount;
      _notifyHour = notifyHour;
      _notifyMinute = notifyMinute;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveVaultPath(String path) async {
    await SettingsStore.setVaultPath(path);
    setState(() => _vaultPath = path);
  }

  Future<void> _setReviewCount(int count) async {
    await SettingsStore.setReviewCount(count);
    setState(() => _reviewCount = count);
    ref.invalidate(reviewCountProvider);
  }

  Future<void> _setNotifyTime(int hour, int minute) async {
    await SettingsStore.setNotifyHour(hour);
    await SettingsStore.setNotifyMinute(minute);
    setState(() {
      _notifyHour = hour;
      _notifyMinute = minute;
    });
    ref.invalidate(notifyHourProvider);
    ref.invalidate(notifyMinuteProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('AI 配置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'DeepSeek API Key',
                      hintText: 'sk-...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final storage = SecureStorageService();
                      await storage.setApiKey(_apiKeyController.text.trim());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API Key 已保存')),
                        );
                      }
                    },
                    child: const Text('保存 API Key'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('Obsidian Vault'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _vaultPath ?? '未设置',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath();
                      if (result != null) {
                        await _saveVaultPath(result);
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择笔记文件夹'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('Prompt 模板'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.quiz),
                    title: const Text('出题 Prompt'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final prompt = await ref.read(generatePromptProvider.future);
                      if (context.mounted) {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (ctx) => PromptEditorPage(
                              title: '出题 Prompt',
                              initialContent: prompt,
                            ),
                          ),
                        );
                        if (result != null) {
                          final db = ref.read(databaseProvider);
                          await db.upsertPromptTemplate('generate_question', result);
                          ref.invalidate(generatePromptProvider);
                        }
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.rate_review),
                    title: const Text('评价 Prompt'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final prompt = await ref.read(evaluatePromptProvider.future);
                      if (context.mounted) {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (ctx) => PromptEditorPage(
                              title: '评价 Prompt',
                              initialContent: prompt,
                            ),
                          ),
                        );
                        if (result != null) {
                          final db = ref.read(databaseProvider);
                          await db.upsertPromptTemplate('evaluate_answer', result);
                          ref.invalidate(evaluatePromptProvider);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('通知设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('每日提醒时间'),
                subtitle: Text(
                  '$_notifyHour:${_notifyMinute.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: _notifyHour, minute: _notifyMinute),
                  );
                  if (time != null) {
                    await _setNotifyTime(time.hour, time.minute);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('复习设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('每次复习题数'),
                  const Spacer(),
                  IconButton(
                    onPressed: _reviewCount > 1
                        ? () => _setReviewCount(_reviewCount - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    '$_reviewCount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    onPressed: _reviewCount < 10
                        ? () => _setReviewCount(_reviewCount + 1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write prompt_editor.dart**

```dart
import 'package:flutter/material.dart';

class PromptEditorPage extends StatefulWidget {
  final String title;
  final String initialContent;

  const PromptEditorPage({
    super.key,
    required this.title,
    required this.initialContent,
  });

  @override
  State<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<PromptEditorPage> {
  late final TextEditingController _controller;
  bool _modified = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() {
      if (!_modified && _controller.text != widget.initialContent) {
        setState(() => _modified = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _modified
                ? () => Navigator.of(context).pop(_controller.text)
                : null,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '在此编辑 Prompt 模板...\n可使用 {note_content}, {question}, {user_answer} 等占位符',
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add SettingsScreen with API key, vault path, prompts, and notifications"
```

---

### Task 20: Background Task Implementation (WorkManager Callback Logic)

**Files:**
- Modify: `lib/services/notification_service.dart`

- [ ] **Step 1: Update callbackDispatcher in notification_service.dart**

Replace the `callbackDispatcher` function body with functional logic:

```dart
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import '../data/database/database.dart';
import '../data/database/daos/review_dao.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'checkForOverdueReviews') {
      try {
        final dbFolder = await getApplicationDocumentsDirectory();
        final file = p.join(dbFolder.path, 'note_review.db');
        final db = AppDatabase.forTesting(NativeDatabase(File(file)));

        final lastCheck = await db.getLastCheckTime();
        final now = DateTime.now();

        final reviewDao = ReviewDao(db);
        final count = await reviewDao.overdueCount(lastCheck, now);

        if (count > 0) {
          const androidDetails = AndroidNotificationDetails(
            'review_channel',
            '复习提醒',
            channelDescription: '笔记复习提醒',
            importance: Importance.high,
            priority: Priority.high,
          );
          const details = NotificationDetails(android: androidDetails);

          final notifications = FlutterLocalNotificationsPlugin();
          await notifications.initialize(
            const InitializationSettings(android: androidDetails),
          );
          await notifications.show(
            0,
            '复习时间到',
            '你有 $count 篇笔记需要复习',
            details,
            payload: '/review',
          );
        }

        await db.close();
      } catch (e) {
        // Silently fail in background
      }
    }
    return true;
  });
}
```

Note: This requires updating the AppDatabase to support `forTesting`. Add this factory constructor to `database.dart`:

```dart
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: implement WorkManager background overdue check"
```

---

### Task 21: Overdue Detection on App Resume

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/features/home/home_provider.dart`

- [ ] **Step 1: Add WidgetsBindingObserver to main.dart**

Update `main.dart` to check overdue on resume:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await NotificationService.schedulePeriodicCheck();
  runApp(const ProviderScope(child: NoteReviewApp()));
}
```

- [ ] **Step 2: Create home_provider.dart with overdue check logic**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/database/daos/review_dao.dart';
import '../settings/settings_provider.dart';

final checkOverdueOnResumeProvider = Provider<void Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    await db.updateLastCheckTime(now);
    ref.invalidate(overdueProvider);
  };
});

// Re-export overdueProvider for convenience
final overdueProvider = FutureProvider<OverdueInfo>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = ReviewDao(db);
  final lastCheck = await db.getLastCheckTime();
  final now = DateTime.now();
  final records = await dao.overdueNotes(lastCheck, now);
  return OverdueInfo(count: records.length, records: records);
});

class OverdueInfo {
  final int count;
  final List<JoinedRecord> records;
  OverdueInfo({required this.count, required this.records});
}
```

- [ ] **Step 3: Trigger overdue check in AppShell**

Add `WidgetsBindingObserver` to AppShell in `app.dart`:

```dart
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkOverdueOnResumeProvider)();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(checkOverdueOnResumeProvider)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int currentIndex;
    if (location.startsWith('/review')) {
      currentIndex = 1;
    } else if (location.startsWith('/settings')) {
      currentIndex = 2;
    } else {
      currentIndex = 0;
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/review');
            case 2:
              context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add overdue detection on app resume"
```

---

### Task 22: Fix Imports and Resolve Compilation Issues

**Files:**
- Modify: Various files with import issues

- [ ] **Step 1: Run build and fix issues**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze
```

Fix all analysis warnings and errors. Common issues:
- DAO generation: ensure `@DriftAccessor` annotation is correct
- Provider type consistency
- Missing imports
- Deprecated API usage

- [ ] **Step 2: Fix review_provider.dart to remove duplicate overdueProvider**

`review_provider.dart` and `home_provider.dart` both define `OverdueInfo` and `overdueProvider`. Consolidate into `home_provider.dart` and import from review files.

- [ ] **Step 3: Run full analysis again until clean**

```bash
flutter analyze
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "fix: resolve all compilation and analysis issues"
```

---

### Task 23: Android Configuration (Permissions & WorkManager)

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle`

- [ ] **Step 1: Update AndroidManifest.xml — add permissions**

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>

    <application
        android:label="NoteReview"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:requestLegacyExternalStorage="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="...">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- [ ] **Step 2: Update build.gradle — ensure minSdk is 26**

In `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 26
        ...
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: configure Android permissions and minSdk"
```

---

### Task 24: Final Integration — Build and Test

- [ ] **Step 1: Run flutter analyze**

```bash
flutter analyze
```
Expected: No issues.

- [ ] **Step 2: Run build**

```bash
flutter build apk --debug
```
Expected: APK built successfully.

- [ ] **Step 3: Verify key files exist**

```bash
ls -la lib/main.dart lib/app.dart lib/core/theme.dart lib/data/database/database.dart lib/services/sm2_engine.dart lib/services/ai_service.dart lib/features/
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: final integration and build verification"
```

---

### Post-Implementation Checklist

- [ ] DeepSeek API Key configured in Settings
- [ ] Obsidian vault folder selected in Settings
- [ ] Notes with `#review` tag auto-detected
- [ ] Manual note selection working in VaultBrowser
- [ ] Review session generates questions and evaluates answers
- [ ] SM-2 algorithm updates intervals correctly
- [ ] Follow-up chat works after each question
- [ ] Free chat works independently
- [ ] Notifications fire at configured time (when overdue)
- [ ] App detects overdue notes on resume after being killed
- [ ] API errors show user-friendly messages with retry
