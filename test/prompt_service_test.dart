import 'package:flutter_test/flutter_test.dart';
import 'package:phone_note_review/services/prompt_service.dart';

void main() {
  group('parseCompletedQuestions（流式）', () {
    test('还没出现下一个题目标记时，最后一块不交出去', () {
      const partial = '【题目1】\n什么是梯度消失？\n【拓展1】\n连乘';
      expect(parseCompletedQuestions(partial), isEmpty);
    });

    test('被下一个标记闭合后才交出去，且拓展不为空', () {
      const text = '【题目1】\n什么是梯度消失？\n【拓展1】\n连乘导致梯度趋零\n\n'
          '【题目2】\n什么是残差连接？\n【拓展2】\n恒等映射';
      final streaming = parseCompletedQuestions(text);
      expect(streaming, hasLength(1));
      expect(streaming.first.question, '什么是梯度消失？');
      expect(streaming.first.expansion, '连乘导致梯度趋零');

      final finished = parseCompletedQuestions(text, isFinal: true);
      expect(finished, hasLength(2));
      expect(finished.last.question, '什么是残差连接？');
      expect(finished.last.expansion, '恒等映射');
    });

    test('流结束前最后一块的拓展是半句，也要整块等流结束才交', () {
      const text = '【题目1】\nA\n【拓展1】\nB\n【题目2】\nC\n【拓展2】\nD 写到一';
      final streaming = parseCompletedQuestions(text);
      expect(streaming.map((q) => q.expansion), ['B']);

      final finished = parseCompletedQuestions(text, isFinal: true);
      expect(finished.map((q) => q.expansion), ['B', 'D 写到一']);
    });

    test('兼容无编号的【题目】/【拓展】', () {
      const text = '【题目】\n单题\n【拓展】\n补充';
      final parsed = parseCompletedQuestions(text, isFinal: true);
      expect(parsed, hasLength(1));
      expect(parsed.single.question, '单题');
      expect(parsed.single.expansion, '补充');
    });

    test('多行题目与空行不会串到下一题', () {
      const text = '【题目1】\n第一行\n第二行\n\n【拓展1】\n拓展一\n\n'
          '【题目2】\n另一个问题\n\n【拓展2】\n拓展二';
      final parsed = parseCompletedQuestions(text, isFinal: true);
      expect(parsed, hasLength(2));
      expect(parsed.first.question, '第一行\n第二行');
      expect(parsed.first.expansion, '拓展一');
      expect(parsed.last.question, '另一个问题');
    });

    test('模型只给出题目忘了拓展时，题目仍然可用', () {
      const text = '【题目1】\n问题一\n【题目2】\n问题二\n【拓展2】\n拓展二';
      final parsed = parseCompletedQuestions(text, isFinal: true);
      expect(parsed, hasLength(2));
      expect(parsed.first.question, '问题一');
      expect(parsed.first.expansion, '');
    });

    test('完全不合格式时返回空，交给兜底解析', () {
      expect(parseCompletedQuestions('这里没有任何标记', isFinal: true), isEmpty);
    });

    test('parseMultipleQuestions 等价于 isFinal 版本', () {
      const text = '【题目1】\nA\n【拓展1】\nB';
      expect(parseMultipleQuestions(text).single.question, 'A');
    });
  });

  group('parseSingleQuestion', () {
    test('提取单个题目与拓展', () {
      final parsed = parseSingleQuestion('【题目】\n问题\n【拓展】\n拓展');
      expect(parsed.question, '问题');
      expect(parsed.expansion, '拓展');
    });
  });

  group('parseEvaluationResponse', () {
    test('正常三段', () {
      final r = parseEvaluationResponse(
        '【评价】\n答得不错\n\n【建议评分】\n4\n\n【延伸】\n还能怎么优化？',
      );
      expect(r.evaluation, '答得不错');
      expect(r.suggestedScore, 4);
      expect(r.extension, '还能怎么优化？');
    });

    test('评分被写成「满分 5 分」这类描述时不误判成 5', () {
      final r = parseEvaluationResponse(
        '【评价】\n一般\n【建议评分】\n3（满分 5 分）\n【延伸】\n随便问问',
      );
      expect(r.suggestedScore, 3);
    });

    test('评分越界（10）不会读成 1', () {
      final r = parseEvaluationResponse('【评价】\n好\n【建议评分】\n10\n【延伸】\nx');
      // 只认 0-5，读不到就是 null，由用户自己选分
      expect(r.suggestedScore, isNull);
    });

    test('缺少分段时给出空串而不是抛异常', () {
      final r = parseEvaluationResponse('随便一段话');
      expect(r.evaluation, '');
      expect(r.suggestedScore, isNull);
      expect(r.extension, '');
    });
  });

  group('PromptService.render', () {
    test('替换全部占位符', () {
      final out = PromptService.render(
        '共 {count} 题，内容：{note_content}',
        {'count': '3', 'note_content': '笔记'},
      );
      expect(out, '共 3 题，内容：笔记');
    });

    test('自定义模板里没有的变量不影响结果', () {
      final out = PromptService.render(
        '内容 {note_content}',
        {'note_content': 'X', 'count': '5'},
      );
      expect(out, '内容 X');
    });
  });
}
