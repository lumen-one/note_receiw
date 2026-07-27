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

final reviewHistoryProvider = FutureProvider<List<DailyReviewCount>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.reviewHistoryLast30Days();
});

class OverdueInfo {
  final int count;
  final List<JoinedRecord> records;
  OverdueInfo({required this.count, required this.records});
}
