import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';
import '../data/settings_store.dart';

/// 主动取消（用户退页 / 重开会话）时抛出，调用方据此静默收尾，不当成错误展示。
class OperationCancelled implements Exception {
  const OperationCancelled();

  @override
  String toString() => '已取消';
}

class AIService {
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  AIService()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConstants.deepseekBaseUrl,
          connectTimeout: const Duration(seconds: AppConstants.apiTimeoutSeconds),
          receiveTimeout: const Duration(seconds: AppConstants.apiTimeoutSeconds),
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

  /// 把底层异常翻译成能直接给用户看的一句话。
  static String describeError(Object error) {
    if (error is OperationCancelled) return '已取消';
    if (error is! DioException) {
      return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    }
    if (CancelToken.isCancel(error)) return '已取消';
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败';
      default:
        break;
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'API Key 无效或已过期';
    if (status == 402) return '账户余额不足';
    if (status == 429) return '请求过于频繁，稍后再试';
    if (status != null && status >= 500) return '服务端错误（$status）';
    if (status != null) return '请求失败（$status）';
    return error.message ?? '请求失败';
  }

  static bool _isCancelled(Object error) =>
      error is DioException && CancelToken.isCancel(error);

  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    List<Map<String, String>> history = const [],
    int maxTokens = 2048,
    int maxRetries = AppConstants.maxRetries,
    CancelToken? cancelToken,
  }) {
    return _complete(
      <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': userMessage},
      ],
      maxTokens: maxTokens,
      maxRetries: maxRetries,
      cancelToken: cancelToken,
    );
  }

  Future<String> continueChat({
    required List<Map<String, String>> messages,
    int maxTokens = 2048,
    int maxRetries = AppConstants.maxRetries,
    CancelToken? cancelToken,
  }) {
    return _complete(
      messages,
      maxTokens: maxTokens,
      maxRetries: maxRetries,
      cancelToken: cancelToken,
    );
  }

  Future<String> _complete(
    List<Map<String, String>> messages, {
    required int maxTokens,
    required int maxRetries,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) throw const OperationCancelled();
      try {
        final apiKey = await _getApiKey();
        final model = await _getModelName();
        final response = await _dio.post(
          '/chat/completions',
          data: {
            'model': model,
            'messages': messages,
            'temperature': 0.7,
            'max_tokens': maxTokens,
          },
          options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
          cancelToken: cancelToken,
        );
        return response.data['choices'][0]['message']['content'] as String;
      } catch (e) {
        // 配置问题与主动取消都不值得重试
        if (e is OperationCancelled || _isCancelled(e)) rethrow;
        if (e.toString().contains('API Key')) rethrow;
        lastError = e;
        if (attempt == maxRetries) break;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception(describeError(lastError ?? '未知错误'));
  }

  Stream<String> chatStream({
    required String systemPrompt,
    required String userMessage,
    List<Map<String, String>> history = const [],
    int maxTokens = 2048,
    CancelToken? cancelToken,
    void Function(String? finishReason)? onFinish,
  }) {
    return _stream(
      <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': userMessage},
      ],
      maxTokens: maxTokens,
      cancelToken: cancelToken,
      onFinish: onFinish,
    );
  }

  Stream<String> continueChatStream({
    required List<Map<String, String>> messages,
    int maxTokens = 2048,
    CancelToken? cancelToken,
    void Function(String? finishReason)? onFinish,
  }) {
    return _stream(
      messages,
      maxTokens: maxTokens,
      cancelToken: cancelToken,
      onFinish: onFinish,
    );
  }

  /// 共用一条 SSE 管道。[onFinish] 在流正常结束或被取消时都会回调，
  /// 带上最后一次收到的 `finish_reason`（`length` 表示被 max_tokens 截断）。
  Stream<String> _stream(
    List<Map<String, String>> messages, {
    required int maxTokens,
    CancelToken? cancelToken,
    void Function(String? finishReason)? onFinish,
  }) async* {
    final apiKey = await _getApiKey();
    final model = await _getModelName();

    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'stream': true,
          'temperature': 0.7,
          'max_tokens': maxTokens,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
    } catch (e) {
      if (e is OperationCancelled || _isCancelled(e)) {
        throw const OperationCancelled();
      }
      throw Exception(describeError(e));
    }

    final body = response.data;
    if (body == null) {
      throw Exception('AI 返回为空');
    }

    String? finishReason;
    try {
      await for (final line in body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final choice = choices[0] as Map<String, dynamic>;
          final reason = choice['finish_reason'] as String?;
          if (reason != null) finishReason = reason;
          final delta = choice['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // 跳过格式不完整的 SSE 行
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const OperationCancelled();
      throw Exception(describeError(e));
    } finally {
      onFinish?.call(finishReason);
    }
  }
}
