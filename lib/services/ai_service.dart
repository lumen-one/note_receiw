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
        if (e.response != null) {
          final detail = e.response!.data;
          lastError = Exception('${e.message}: $detail');
        }
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
        if (e.response != null) {
          final detail = e.response!.data;
          lastError = Exception('${e.message}: $detail');
        }
        if (attempt == maxRetries) break;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('AI 请求失败: ${lastError.toString()}');
  }
}
