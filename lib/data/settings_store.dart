import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _keyVaultPath = 'vault_path';
  static const _keyReviewCount = 'review_count';
  static const _keySessionNoteLimit = 'session_note_limit';
  static const _keyIntervals = 'sm2_intervals';
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

  static Future<int> getSessionNoteLimit() async {
    final prefs = await _prefs;
    return prefs.getInt(_keySessionNoteLimit) ?? 3;
  }

  static Future<void> setSessionNoteLimit(int limit) async {
    final prefs = await _prefs;
    await prefs.setInt(_keySessionNoteLimit, limit);
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

  static Future<List<int>> getSm2Intervals() async {
    final prefs = await _prefs;
    final json = prefs.getString(_keyIntervals);
    if (json == null) return [1, 6, 15, 38, 95, 238];
    try {
      return (jsonDecode(json) as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return [1, 6, 15, 38, 95, 238];
    }
  }

  static Future<void> setSm2Intervals(List<int> intervals) async {
    final prefs = await _prefs;
    await prefs.setString(_keyIntervals, jsonEncode(intervals));
  }

  static Future<String> getModelName() async {
    final prefs = await _prefs;
    return prefs.getString('model_name') ?? 'deepseek-v4-flash';
  }

  static Future<void> setModelName(String name) async {
    final prefs = await _prefs;
    await prefs.setString('model_name', name);
  }

  static Future<void> resetSm2Intervals() async {
    final prefs = await _prefs;
    await prefs.remove(_keyIntervals);
  }
}
