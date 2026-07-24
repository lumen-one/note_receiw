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
