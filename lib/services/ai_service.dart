import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/settings_store.dart';

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

  Future<String> _getModelName() async {
    return SettingsStore.getModelName();
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
        final model = await _getModelName();
        final response = await _dio.post(
          '/chat/completions',
          data: {
            'model': model,
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

  Stream<String> chatStream({
    required String systemPrompt,
    required String userMessage,
    List<Map<String, String>> history = const [],
  }) async* {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history,
      {'role': 'user', 'content': userMessage},
    ];

    final apiKey = await _getApiKey();
    final model = await _getModelName();

    final response = await _dio.post<ResponseBody>(
      '/chat/completions',
      data: {
        'model': model,
        'messages': messages,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 2048,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
        responseType: ResponseType.stream,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw Exception('AI 返回为空');
    }

    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices[0] as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // skip malformed SSE lines
      }
    }
  }

  Future<String> continueChat({
    required List<Map<String, String>> messages,
    int maxRetries = 2,
  }) async {
    Exception? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final apiKey = await _getApiKey();
        final model = await _getModelName();
        final response = await _dio.post(
          '/chat/completions',
          data: {
            'model': model,
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

  Stream<String> continueChatStream({
    required List<Map<String, String>> messages,
  }) async* {
    final apiKey = await _getApiKey();
    final model = await _getModelName();

    final response = await _dio.post<ResponseBody>(
      '/chat/completions',
      data: {
        'model': model,
        'messages': messages,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 2048,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
        responseType: ResponseType.stream,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw Exception('AI 返回为空');
    }

    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices[0] as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // skip malformed SSE lines
      }
    }
  }
}
