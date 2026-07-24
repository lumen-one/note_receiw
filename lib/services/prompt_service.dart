class PromptService {
  static const defaultGenerateQuestionPrompt = '''
你是一位和我一起学习的挚友。请阅读以下笔记内容，帮我查漏补缺：

1. 生成一道简答题，检验我对内容的理解
2. 根据笔记内容，拓展一个相关知识或概念，帮我开阔思路

笔记内容：
{note_content}

请按以下格式回复：
【题目】
(题目内容)

【拓展】
(拓展知识点或概念)
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

ParsedQuestion parseQuestionResponse(String response) {
  final questionMatch = RegExp(r'【题目】\s*([\s\S]*?)(?=【拓展】|$)').firstMatch(response);
  final expansionMatch = RegExp(r'【拓展】\s*([\s\S]*?)$').firstMatch(response);
  return ParsedQuestion(
    question: questionMatch?.group(1)?.trim() ?? '',
    expansion: expansionMatch?.group(1)?.trim() ?? '',
  );
}

ParsedResponse parseEvaluationResponse(String response) {
  final evalMatch = RegExp(r'【评价】\s*([\s\S]*?)(?=【建议评分】|$)').firstMatch(response);
  final scoreMatch = RegExp(r'【建议评分】\s*([\s\S]*?)(?=【延伸】|$)').firstMatch(response);
  final extMatch = RegExp(r'【延伸】\s*([\s\S]*?)$').firstMatch(response);
  final scoreText = scoreMatch?.group(1)?.trim();
  int? score;
  if (scoreText != null) {
    score = int.tryParse(RegExp(r'\d').firstMatch(scoreText)?.group(0) ?? '');
  }
  return ParsedResponse(
    evaluation: evalMatch?.group(1)?.trim() ?? '',
    suggestedScore: score,
    extension: extMatch?.group(1)?.trim() ?? '',
  );
}
