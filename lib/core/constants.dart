class AppConstants {
  static const String appName = 'NoteReview';
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String deepseekModel = 'deepseek-v4-flash';
  static const int defaultQuestionCount = 5;
  static const int defaultNotifyHour = 20;
  static const int defaultNotifyMinute = 0;
  static const double defaultEaseFactor = 2.5;
  static const double minEaseFactor = 1.3;
  static const int apiTimeoutSeconds = 30;
  static const int maxRetries = 2;

  /// 单次复习最多处理的笔记篇数，避免一次把整库逾期笔记全跑一遍。
  static const int defaultSessionNoteLimit = 3;
  static const int maxSessionNoteLimit = 10;

  /// 送进 prompt 的笔记内容上限（字符）。超过就截断并在界面上提示。
  static const int maxNoteCharsForPrompt = 6000;
  static const int maxNoteCharsForChat = 2000;

  /// 每道题的输出预算（token），用于按题目数量估算 max_tokens。
  static const int tokensPerQuestion = 500;
  static const int minMaxTokens = 1200;
  static const int maxMaxTokens = 8192;

  /// 流式生成时预览文本只保留末尾这么多字符，避免每帧都渲染整段长文。
  static const int streamPreviewTailChars = 600;
}
