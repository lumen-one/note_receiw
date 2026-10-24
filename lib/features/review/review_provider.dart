import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../data/database/database.dart';
import '../../data/settings_store.dart';
import '../../services/ai_service.dart';
import '../../services/note_content.dart';
import '../../services/prompt_service.dart';
import '../../services/sm2_engine.dart';
import '../home/home_provider.dart';
import '../settings/settings_provider.dart';

class QuestionItem {
  final int noteId;
  final String fileName;
  final String question;
  final String expansion;
  final String noteContent;
  String? userAnswer;
  String? evaluation;
  int? suggestedScore;
  int? selfScore;
  String? extension;

  QuestionItem({
    required this.noteId,
    required this.fileName,
    required this.question,
    required this.expansion,
    required this.noteContent,
    this.userAnswer,
    this.evaluation,
    this.suggestedScore,
    this.selfScore,
    this.extension,
  });

  QuestionItem copyWith({
    String? userAnswer,
    String? evaluation,
    int? suggestedScore,
    int? selfScore,
    String? extension,
  }) {
    return QuestionItem(
      noteId: noteId,
      fileName: fileName,
      question: question,
      expansion: expansion,
      noteContent: noteContent,
      userAnswer: userAnswer ?? this.userAnswer,
      evaluation: evaluation ?? this.evaluation,
      suggestedScore: suggestedScore ?? this.suggestedScore,
      selfScore: selfScore ?? this.selfScore,
      extension: extension ?? this.extension,
    );
  }
}

enum ReviewPhase {
  loading,
  showingQuestions,
  answering,
  evaluating,
  chatting,
  complete,
  error
}

/// copyWith 的默认值哨兵。用它区分「不传这个字段」和「显式传 null 清空」——
/// 之前用 `x ?? this.x`，导致 errorMessage / statusMessage 一旦设置就永远清不掉。
const Object _unset = Object();

class ReviewState {
  final ReviewPhase phase;
  final List<QuestionItem> questions;
  final int currentQuestionIndex;
  final bool isLoading;
  final String? statusMessage;
  final String? errorMessage;
  final String? generatingText;

  /// 本次会话中出现的非致命问题（某篇读不到、某篇生成题数不足等）。
  final List<String> warnings;

  /// 本次会话没排进去、留到下次的逾期笔记数。
  final int remainingNoteCount;

  ReviewState({
    this.phase = ReviewPhase.loading,
    this.questions = const [],
    this.currentQuestionIndex = 0,
    this.isLoading = false,
    this.statusMessage,
    this.errorMessage,
    this.generatingText,
    this.warnings = const [],
    this.remainingNoteCount = 0,
  });

  ReviewState copyWith({
    ReviewPhase? phase,
    List<QuestionItem>? questions,
    int? currentQuestionIndex,
    bool? isLoading,
    int? remainingNoteCount,
    List<String>? warnings,
    Object? statusMessage = _unset,
    Object? errorMessage = _unset,
    Object? generatingText = _unset,
  }) {
    return ReviewState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isLoading: isLoading ?? this.isLoading,
      warnings: warnings ?? this.warnings,
      remainingNoteCount: remainingNoteCount ?? this.remainingNoteCount,
      statusMessage: identical(statusMessage, _unset)
          ? this.statusMessage
          : statusMessage as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      generatingText: identical(generatingText, _unset)
          ? this.generatingText
          : generatingText as String?,
    );
  }
}

final aiServiceProvider = Provider<AIService>((ref) => AIService());

final reviewStateProvider = StateNotifierProvider<ReviewNotifier, ReviewState>(
  (ref) => ReviewNotifier(ref),
);

class ReviewNotifier extends StateNotifier<ReviewState> {
  final Ref _ref;

  /// noteId -> {题目序号: 自评分数}。用序号做 key，重复点同一题的分数不会累加。
  final Map<int, Map<int, int>> _noteScores = {};
  final Map<int, ReviewRecord?> _originalRecords = {};
  final Set<int> _savedNotes = {};

  /// 用户在「还有题在生成」时点了下一题，先挂起这篇的 SM-2 记录，
  /// 等确认这篇的题真的答完（出现别的笔记的题或生成结束）再落库。
  int? _deferredSaveNoteId;

  /// 会话代号。每次重新开始 / 取消都自增，老协程发现代号对不上就安静退出，
  /// 避免两次生成同时往一个 notifier 里写状态。
  int _generation = 0;
  CancelToken? _cancelToken;
  bool _disposed = false;
  DateTime _lastPreviewAt = DateTime.fromMillisecondsSinceEpoch(0);

  ReviewNotifier(this._ref) : super(ReviewState());

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelToken?.cancel('notifier disposed');
    super.dispose();
  }

  void _emit(ReviewState next) {
    if (_disposed || !mounted) return;
    state = next;
  }

  // --- 会话生命周期 ---

  /// 用户离开复习页时调用：中断后台流，保留已经拿到的题目。
  void stopGeneration() {
    _generation++;
    _cancelToken?.cancel('session left');
    _cancelToken = null;
    if (!_disposed && mounted && state.isLoading) {
      _emit(state.copyWith(isLoading: false, generatingText: null));
    }
  }

  void clearError() {
    if (_disposed || !mounted) return;
    final next = state.copyWith(errorMessage: null);
    if (next.phase == ReviewPhase.error) {
      _emit(next.copyWith(
        phase: next.questions.isEmpty
            ? ReviewPhase.complete
            : ReviewPhase.showingQuestions,
      ));
      return;
    }
    _emit(next);
  }

  void reset() {
    _generation++;
    _cancelToken?.cancel('reset');
    _cancelToken = null;
    _noteScores.clear();
    _originalRecords.clear();
    _savedNotes.clear();
    _deferredSaveNoteId = null;
    _emit(ReviewState());
  }

  // --- 生成题目 ---

  Future<void> loadQuestions() async {
    final generation = ++_generation;
    _cancelToken?.cancel('restart');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    _noteScores.clear();
    _originalRecords.clear();
    _savedNotes.clear();
    _deferredSaveNoteId = null;

    _emit(ReviewState(
      phase: ReviewPhase.loading,
      isLoading: true,
      statusMessage: '正在读取待复习笔记...',
    ));

    bool stale() =>
        _disposed || generation != _generation || cancelToken.isCancelled;

    try {
      final db = _ref.read(databaseProvider);
      final aiService = _ref.read(aiServiceProvider);
      final generatePrompt = await _ref.read(generatePromptProvider.future);
      final vaultPath = await _ref.read(vaultPathProvider.future);
      final questionsPerNote = await _ref.read(reviewCountProvider.future);
      final noteLimit = await _ref.read(sessionNoteLimitProvider.future);
      if (stale()) return;

      final overdue = await db.overdueNotes(DateTime.now());
      if (stale()) return;

      final limit = noteLimit < 1 ? 1 : noteLimit;
      final sessionNotes = overdue.take(limit).toList();
      final remaining = overdue.length - sessionNotes.length;

      if (sessionNotes.isEmpty) {
        _emit(state.copyWith(
          phase: ReviewPhase.complete,
          isLoading: false,
          statusMessage: null,
          generatingText: null,
          remainingNoteCount: 0,
        ));
        return;
      }
      _emit(state.copyWith(remainingNoteCount: remaining));

      final items = <QuestionItem>[];
      final warnings = <String>[];

      for (var i = 0; i < sessionNotes.length; i++) {
        if (stale()) return;
        final joined = sessionNotes[i];
        _originalRecords[joined.note.id] = joined.record;
        _noteScores[joined.note.id] = <int, int>{};

        _emit(state.copyWith(
          statusMessage: '正在为「${joined.note.fileName}」生成题目'
              '（${i + 1}/${sessionNotes.length}）',
          generatingText: '',
        ));

        final content =
            await NoteContentLoader.load(vaultPath, joined.note.filePath);
        if (stale()) return;

        if (content.isEmpty) {
          warnings.add('「${joined.note.fileName}」读不到内容，已跳过');
          _emit(state.copyWith(warnings: List<String>.from(warnings)));
          continue;
        }
        if (content.truncated) {
          warnings.add('「${joined.note.fileName}」过长，'
              '只发了前 ${AppConstants.maxNoteCharsForPrompt} 字');
        }

        final prompt = PromptService.render(generatePrompt, {
          'note_content': content.text,
          'count': questionsPerNote.toString(),
        });

        final buffer = StringBuffer();
        var emitted = 0;
        String? finishReason;
        String? generationError;

        try {
          await for (final token in aiService.chatStream(
            systemPrompt: '你是一位帮助我学习的挚友。',
            userMessage: prompt,
            maxTokens: _tokenBudget(questionsPerNote),
            cancelToken: cancelToken,
            onFinish: (reason) => finishReason = reason,
          )) {
            if (stale()) return;
            buffer.write(token);

            final parsed = parseCompletedQuestions(buffer.toString());
            if (parsed.length > emitted) {
              for (var k = emitted; k < parsed.length; k++) {
                items.add(_toItem(joined.note, parsed[k], content.text));
              }
              emitted = parsed.length;
              _emitQuestions(items);
            } else {
              _emitPreview(buffer.toString());
            }
          }
        } on OperationCancelled {
          return;
        } catch (e) {
          if (stale()) return;
          generationError = AIService.describeError(e);
        }

        if (stale()) return;

        if (generationError != null) {
          warnings.add('「${joined.note.fileName}」生成失败：$generationError');
        } else {
          var finalList = parseCompletedQuestions(
            buffer.toString(),
            isFinal: true,
          );
          if (finalList.isEmpty) {
            final single = parseSingleQuestion(buffer.toString());
            if (single.question.isNotEmpty) finalList = [single];
          }

          // 流式阶段交出去的题目已经定型（块一旦被下一个标记闭合，内容就不再变），
          // 这里只补齐最后一块，并用完整结果校正题目与拓展文本。
          final baseIndex = items.length - emitted;
          for (var k = 0; k < finalList.length; k++) {
            final idx = baseIndex + k;
            if (idx >= 0 && idx < items.length) {
              final old = items[idx];
              items[idx] = QuestionItem(
                noteId: old.noteId,
                fileName: old.fileName,
                question: finalList[k].question.isEmpty
                    ? old.question
                    : finalList[k].question,
                expansion: finalList[k].expansion.isEmpty
                    ? old.expansion
                    : finalList[k].expansion,
                noteContent: old.noteContent,
              );
            } else {
              items.add(_toItem(joined.note, finalList[k], content.text));
            }
          }
          emitted = finalList.length;
          _emitQuestions(items);

          if (finalList.length < questionsPerNote) {
            final hitLimit = finishReason == 'length';
            warnings.add('「${joined.note.fileName}」只生成 '
                '${finalList.length}/$questionsPerNote 题'
                '${hitLimit ? '（输出被长度上限截断）' : ''}');
          }
        }

        if (warnings.isNotEmpty) {
          _emit(state.copyWith(warnings: List<String>.from(warnings)));
        }

        final sessionType = 'review_${joined.note.id}';
        final contentBuffer = StringBuffer();
        for (var k = 0; k < emitted; k++) {
          final index = items.length - emitted + k;
          if (index < 0 || index >= items.length) continue;
          final item = items[index];
          contentBuffer.writeln('【题目${k + 1}】\n${item.question}\n\n'
              '【拓展${k + 1}】\n${item.expansion}');
          if (k < emitted - 1) contentBuffer.writeln();
        }
        if (contentBuffer.isNotEmpty) {
          await db.insertChatMessage(
            sessionType: sessionType,
            noteId: joined.note.id,
            role: 'assistant',
            content: contentBuffer.toString(),
          );
        }
      }

      if (stale()) return;

      if (items.isEmpty) {
        _emit(state.copyWith(
          phase: ReviewPhase.error,
          isLoading: false,
          statusMessage: null,
          generatingText: null,
          warnings: List<String>.from(warnings),
          errorMessage: warnings.isEmpty
              ? '没有生成任何题目，请检查 API Key 与网络后重试'
              : warnings.first,
        ));
        return;
      }

      // 生成结束，挂起的那篇笔记可以落库了
      final deferred = _deferredSaveNoteId;
      if (deferred != null) {
        _deferredSaveNoteId = null;
        await _saveNoteRecord(deferred);
        if (stale()) return;
      }

      // 用户按「下一题」时如果正在等生成，phase 会是 loading；
      // 生成已经结束，不能再停在 loading 上，否则界面永久转圈。
      final nextPhase = state.phase == ReviewPhase.loading
          ? ReviewPhase.complete
          : state.phase;

      _emit(state.copyWith(
        questions: _mergeWithState(items),
        currentQuestionIndex: _clampIndex(state.currentQuestionIndex, items.length),
        phase: nextPhase,
        isLoading: false,
        statusMessage: null,
        generatingText: null,
        warnings: List<String>.from(warnings),
      ));
    } catch (e) {
      if (stale()) return;
      _emit(state.copyWith(
        phase: ReviewPhase.error,
        isLoading: false,
        statusMessage: null,
        generatingText: null,
        errorMessage: '生成题目失败：${AIService.describeError(e)}',
      ));
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  /// 新题目到达时的状态推进。
  ///
  /// phase 为 loading 表示用户在等下一题（当前这批已经答完），此时推进一格；
  /// 其余情况用户正在答题，只更新列表，不动他正在看的那一题。
  void _emitQuestions(List<QuestionItem> items) {
    if (items.isEmpty) return;
    final snapshot = _mergeWithState(items);

    if (state.phase == ReviewPhase.loading) {
      final nextIndex = state.questions.isEmpty
          ? 0
          : _clampIndex(state.currentQuestionIndex + 1, snapshot.length);

      // 新题不属于等待中的那篇笔记，说明这篇答完了，可以落 SM-2
      final deferred = _deferredSaveNoteId;
      if (deferred != null &&
          nextIndex < snapshot.length &&
          snapshot[nextIndex].noteId != deferred) {
        _deferredSaveNoteId = null;
        unawaited(_saveNoteRecord(deferred));
      }

      _emit(state.copyWith(
        questions: snapshot,
        currentQuestionIndex: nextIndex,
        phase: ReviewPhase.showingQuestions,
        generatingText: null,
        statusMessage: null,
      ));
      return;
    }

    _emit(state.copyWith(
      questions: snapshot,
      currentQuestionIndex:
          _clampIndex(state.currentQuestionIndex, snapshot.length),
    ));
  }

  /// 把新一批题目与当前状态合并。
  ///
  /// 生成还在跑的时候用户已经在答题了，新题到达时如果直接用新列表替换，
  /// 已经写进去的作答、评价、自评分会被冲掉。这里按「笔记 + 题干」对齐，
  /// 保留旧条目上的作答结果，只用新条目补题目与拓展文本。
  List<QuestionItem> _mergeWithState(List<QuestionItem> fresh) {
    final current = state.questions;
    final merged = <QuestionItem>[];
    for (var i = 0; i < fresh.length; i++) {
      final next = fresh[i];
      if (i < current.length &&
          current[i].noteId == next.noteId &&
          current[i].question == next.question) {
        final prev = current[i];
        merged.add(QuestionItem(
          noteId: next.noteId,
          fileName: next.fileName,
          question: next.question.isEmpty ? prev.question : next.question,
          expansion: next.expansion.isEmpty ? prev.expansion : next.expansion,
          noteContent:
              next.noteContent.isEmpty ? prev.noteContent : next.noteContent,
          userAnswer: prev.userAnswer,
          evaluation: prev.evaluation,
          suggestedScore: prev.suggestedScore,
          selfScore: prev.selfScore,
          extension: prev.extension,
        ));
        continue;
      }
      merged.add(next);
    }
    return merged;
  }

  /// 流式预览只保留末尾一段，否则每来一个 token 都要渲染整篇长文。
  void _emitPreview(String text) {
    final now = DateTime.now();
    if (now.difference(_lastPreviewAt).inMilliseconds < 80) return;
    _lastPreviewAt = now;

    const tail = AppConstants.streamPreviewTailChars;
    final preview = text.length <= tail ? text : '...${text.substring(text.length - tail)}';
    _emit(state.copyWith(generatingText: preview));
  }

  QuestionItem _toItem(
    NoteFile note,
    ParsedQuestion parsed,
    String noteContent,
  ) {
    return QuestionItem(
      noteId: note.id,
      fileName: note.fileName,
      question: parsed.question,
      expansion: parsed.expansion,
      noteContent: noteContent,
    );
  }

  int _clampIndex(int index, int length) {
    if (length <= 0) return 0;
    if (index < 0) return 0;
    if (index >= length) return length - 1;
    return index;
  }

  int _tokenBudget(int questionCount) {
    final budget = 900 + questionCount * AppConstants.tokensPerQuestion;
    if (budget < AppConstants.minMaxTokens) return AppConstants.minMaxTokens;
    if (budget > AppConstants.maxMaxTokens) return AppConstants.maxMaxTokens;
    return budget;
  }

  // --- 作答与评价 ---

  Future<void> submitAnswer(String answer) async {
    if (state.questions.isEmpty) return;
    final idx = _clampIndex(state.currentQuestionIndex, state.questions.length);
    final item = state.questions[idx].copyWith(userAnswer: answer);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    _emit(state.copyWith(
      questions: newQuestions,
      isLoading: true,
      errorMessage: null,
    ));

    try {
      final db = _ref.read(databaseProvider);
      final aiService = _ref.read(aiServiceProvider);
      final evaluatePrompt = await _ref.read(evaluatePromptProvider.future);

      await db.insertChatMessage(
        sessionType: 'review_${item.noteId}',
        noteId: item.noteId,
        role: 'user',
        content: answer,
      );

      final prompt = PromptService.render(evaluatePrompt, {
        'note_content': item.noteContent,
        'question': item.question,
        'user_answer': answer,
      });

      final response = await aiService.chat(
        systemPrompt: '你是一位帮助我学习的挚友。',
        userMessage: prompt,
      );
      if (_disposed || !mounted) return;

      final parsed = parseEvaluationResponse(response);
      final updated = item.copyWith(
        evaluation: parsed.evaluation,
        suggestedScore: parsed.suggestedScore,
        extension: parsed.extension,
      );
      final merged = List<QuestionItem>.from(state.questions);
      if (idx < merged.length) merged[idx] = updated;

      _emit(state.copyWith(
        questions: merged,
        phase: ReviewPhase.evaluating,
        isLoading: false,
      ));

      await db.insertChatMessage(
        sessionType: 'review_${item.noteId}',
        noteId: item.noteId,
        role: 'assistant',
        content: '【评价】\n${parsed.evaluation}\n\n'
            '【建议评分】\n${parsed.suggestedScore ?? ''}\n\n'
            '【延伸】\n${parsed.extension}',
      );
    } catch (e) {
      if (_disposed || !mounted) return;
      _emit(state.copyWith(
        isLoading: false,
        errorMessage: '评价失败：${AIService.describeError(e)}',
      ));
    }
  }

  void skipToScoring() {
    if (state.questions.isEmpty) return;
    final idx = _clampIndex(state.currentQuestionIndex, state.questions.length);
    final item = state.questions[idx].copyWith(
      userAnswer: '(跳过作答)',
      evaluation: '已跳过',
    );
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    _emit(state.copyWith(
      questions: newQuestions,
      phase: ReviewPhase.evaluating,
      errorMessage: null,
    ));
  }

  void submitSelfScore(int score) {
    if (state.questions.isEmpty) return;
    final idx = _clampIndex(state.currentQuestionIndex, state.questions.length);
    final item = state.questions[idx].copyWith(selfScore: score);
    _noteScores[item.noteId]?[idx] = score;
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    _emit(state.copyWith(questions: newQuestions));
  }

  Future<void> _saveNoteRecord(int noteId) async {
    if (_savedNotes.contains(noteId)) return;
    final scores = _noteScores[noteId];
    if (scores == null || scores.isEmpty) return;
    _savedNotes.add(noteId);

    final avgScore =
        (scores.values.reduce((a, b) => a + b) / scores.length).round();
    final clampedScore = avgScore.clamp(0, 5).toInt();
    final db = _ref.read(databaseProvider);
    final existing = _originalRecords[noteId];
    final customIntervals = await SettingsStore.getSm2Intervals();

    final result = Sm2Engine.calculate(
      quality: clampedScore,
      currentInterval: existing?.sm2Interval ?? 1.0,
      currentEaseFactor: existing?.sm2EaseFactor ?? 2.5,
      currentRepetitions: existing?.sm2Repetitions ?? 0,
      customIntervals: customIntervals,
    );

    await db.upsertRecord(ReviewRecordsCompanion.insert(
      noteId: Value(noteId),
      sm2Interval: Value(result.interval),
      sm2EaseFactor: Value(result.easeFactor),
      sm2Repetitions: Value(result.repetitions),
      nextReviewDate: result.nextReviewDate,
      lastReviewDate: Value(DateTime.now()),
      lastScore: Value(clampedScore),
    ));
  }

  Future<void> nextQuestion() async {
    if (state.questions.isEmpty) return;
    final idx = _clampIndex(state.currentQuestionIndex, state.questions.length);
    final currentId = state.questions[idx].noteId;

    if (idx < state.questions.length - 1) {
      // 同一篇笔记的题要答完再平均，切换笔记时才落一次 SM-2 记录
      if (state.questions[idx + 1].noteId != currentId) {
        await _saveNoteRecord(currentId);
      }
      _emit(state.copyWith(
        currentQuestionIndex: idx + 1,
        phase: ReviewPhase.showingQuestions,
        errorMessage: null,
      ));
      return;
    }

    if (state.isLoading) {
      // 还在生成：不确定这篇后面还有没有题，先挂起，
      // 避免用半截的平均分落 SM-2 记录
      _deferredSaveNoteId = currentId;
      _emit(state.copyWith(phase: ReviewPhase.loading, errorMessage: null));
      return;
    }

    await _saveNoteRecord(currentId);
    _ref.invalidate(overdueProvider);
    _emit(state.copyWith(phase: ReviewPhase.complete, errorMessage: null));
  }

  void enterChatMode() {
    _emit(state.copyWith(phase: ReviewPhase.chatting));
  }
}
