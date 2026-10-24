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

final sessionNoteLimitProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getSessionNoteLimit();
});

final notifyHourProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getNotifyHour();
});

final notifyMinuteProvider = FutureProvider<int>((ref) async {
  return SettingsStore.getNotifyMinute();
});

final sm2IntervalsProvider = FutureProvider<List<int>>((ref) async {
  return SettingsStore.getSm2Intervals();
});

final modelNameProvider = FutureProvider<String>((ref) async {
  return SettingsStore.getModelName();
});
