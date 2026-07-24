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
  Set<Column> get primaryKey => {noteId};
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
  Set<Column> get primaryKey => {id};
}

class PromptTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get content => text()();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();
}
