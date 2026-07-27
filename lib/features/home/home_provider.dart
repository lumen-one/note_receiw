import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../settings/settings_provider.dart';

final checkOverdueOnResumeProvider = Provider<void Function()>((ref) {
  return () async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    await db.updateLastCheckTime(now);
    ref.invalidate(overdueProvider);
  };
});

final overdueProvider = FutureProvider<OverdueInfo>((ref) async {
  final db = ref.read(databaseProvider);
  final now = DateTime.now();
  final records = await db.overdueNotes(now);
  return OverdueInfo(count: records.length, records: records);
});

final reviewHistory30Provider = FutureProvider<List<DailyReviewCount>>((ref) async {
  final db = ref.read(databaseProvider);
  final data = await db.reviewHistoryLast30Days();
  return data.reversed.toList();
});

class MonthKey {
  final int year;
  final int month;
  const MonthKey(this.year, this.month);

  @override
  bool operator ==(Object other) =>
      other is MonthKey && year == other.year && month == other.month;

  @override
  int get hashCode => year * 12 + month;
}

final reviewHistoryMonthProvider =
    FutureProvider.family<List<DailyReviewCount>, MonthKey>((ref, key) async {
  final db = ref.read(databaseProvider);
  return db.reviewHistoryForMonth(key.year, key.month);
});

final notesInMonthProvider =
    FutureProvider.family<List<JoinedRecord>, MonthKey>((ref, key) async {
  final db = ref.read(databaseProvider);
  return db.notesReviewedInMonth(key.year, key.month);
});

final notesOnDayProvider =
    FutureProvider.family<List<JoinedRecord>, DateTime>((ref, day) async {
  final db = ref.read(databaseProvider);
  return db.notesReviewedOnDay(day);
});

class OverdueInfo {
  final int count;
  final List<JoinedRecord> records;
  OverdueInfo({required this.count, required this.records});
}
