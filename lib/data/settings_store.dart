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
