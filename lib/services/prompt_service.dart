class PromptService {
  static const defaultGenerateQuestionPrompt = '''
你是一位和我一起学习的挚友。请阅读以下笔记内容，帮我查漏补缺：

1. 生成 {count} 道简答题，检验我对内容的理解
2. 每道题后附上一个拓展知识或概念

笔记内容：
{note_content}

请按以下格式回复（共 {count} 组）：
【题目1】
(第1题)
【拓展1】
(拓展1)

【题目2】
(第2题)
【拓展2】
(拓展2)
……
''';

  static const defaultEvaluateAnswerPrompt = '''
你是和我一起学习的挚友。以下是笔记、你出的题和我的回答。

笔记：
{note_content}

题目：
{question}

我的回答：
{user_answer}

请：
1. 温和地评价我的回答，指出遗漏的关键点
2. 建议评分 0-5 分（0=完全错误, 5=完全正确且完整）
3. 提出一个延伸问题，引导我深入思考

请按以下格式回复：
【评价】
(评价内容)

【建议评分】
(0-5 的整数)

【延伸】
(延伸问题)
''';

  static String render(String template, Map<String, String> variables) {
    var result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

class ParsedResponse {
  final String evaluation;
  final int? suggestedScore;
  final String extension;

  ParsedResponse({
    required this.evaluation,
    this.suggestedScore,
    required this.extension,
  });
}

class ParsedQuestion {
  final String question;
  final String expansion;

  ParsedQuestion({required this.question, required this.expansion});
}

/// 题目块起始标记，兼容 `【题目1】`、`【题目】`、`【题目 2】`。
final RegExp _questionMarker = RegExp(r'【\s*题目\s*\d*\s*】');

/// 拓展块起始标记，连同正文一起吃掉。
final RegExp _expansionMarker = RegExp(r'【\s*拓展\s*\d*\s*】\s*([\s\S]*)$');

/// 解析流式输出中**已经闭合**的题目块。
///
/// 一个题目块只有在后面出现了下一个 `【题目N】` 标记（或整条流结束）时才算写完，
/// 否则最后一块随时可能继续增长。早期实现直接按 `【题目N】` 切分，会把还没写完的
/// 拓展当成空串捕获，只能事后靠数组下标偏移去补，这是几个 bug 的共同根源。
///
/// [isFinal] 为 true 表示流已结束，最后一块也视作闭合。
List<ParsedQuestion> parseCompletedQuestions(
  String response, {
  bool isFinal = false,
}) {
  final markers = _questionMarker.allMatches(response).toList();
  if (markers.isEmpty) return const [];

  final result = <ParsedQuestion>[];
  for (var i = 0; i < markers.length; i++) {
    final isLast = i == markers.length - 1;
    if (isLast && !isFinal) break;

    final start = markers[i].end;
    final end = isLast ? response.length : markers[i + 1].start;
    final block = response.substring(start, end).trim();
    if (block.isEmpty) continue;

    final expansionMatch = _expansionMarker.firstMatch(block);
    if (expansionMatch == null) {
      // 拓展还没开始写，但题目本身已被下一个标记闭合
      result.add(ParsedQuestion(question: block, expansion: ''));
      continue;
    }

    final question = block.substring(0, expansionMatch.start).trim();
    if (question.isEmpty) continue;
    result.add(ParsedQuestion(
      question: question,
      expansion: expansionMatch.group(1)?.trim() ?? '',
    ));
  }
  return result;
}

/// 兼容旧调用：整条响应已完整时直接取全部题目块。
List<ParsedQuestion> parseMultipleQuestions(String response) =>
    parseCompletedQuestions(response, isFinal: true);

/// 兜底：模型没按编号格式输出时，取单个 `【题目】…【拓展】` 结构。
ParsedQuestion parseSingleQuestion(String response) {
  final questionMatch = RegExp(r'【\s*题目\s*\d*\s*】\s*([\s\S]*?)(?=【\s*拓展|$)')
      .firstMatch(response);
  final expansionMatch =
      RegExp(r'【\s*拓展\s*\d*\s*】\s*([\s\S]*)$').firstMatch(response);
  return ParsedQuestion(
    question: questionMatch?.group(1)?.trim() ?? '',
    expansion: expansionMatch?.group(1)?.trim() ?? '',
  );
}

ParsedResponse parseEvaluationResponse(String response) {
  final evalMatch =
      RegExp(r'【\s*评价\s*】\s*([\s\S]*?)(?=【\s*建议评分|$)').firstMatch(response);
  final scoreMatch =
      RegExp(r'【\s*建议评分\s*】\s*([\s\S]*?)(?=【\s*延伸|$)').firstMatch(response);
  final extMatch = RegExp(r'【\s*延伸\s*】\s*([\s\S]*)$').firstMatch(response);

  int? score;
  final scoreText = scoreMatch?.group(1)?.trim();
  if (scoreText != null) {
    // 取第一个数字，只在 0-5 内采信；避免把「10」读成 1 或把「满分 5 分」读成 5
    final numberMatch = RegExp(r'\d+').firstMatch(scoreText);
    if (numberMatch != null) {
      final value = int.tryParse(numberMatch.group(0)!);
      if (value != null && value >= 0 && value <= 5) score = value;
    }
  }

  return ParsedResponse(
    evaluation: evalMatch?.group(1)?.trim() ?? '',
    suggestedScore: score,
    extension: extMatch?.group(1)?.trim() ?? '',
  );
}
