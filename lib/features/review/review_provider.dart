import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/settings_store.dart';
import '../../services/sm2_engine.dart';
import '../../services/ai_service.dart';
import '../../services/prompt_service.dart';
import '../settings/settings_provider.dart';
import '../home/home_provider.dart';

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

enum ReviewPhase { loading, showingQuestions, answering, evaluating, chatting, complete, error }

class ReviewState {
  final ReviewPhase phase;
  final List<QuestionItem> questions;
  final int currentQuestionIndex;
  final bool isLoading;
  final String? statusMessage;
  final String? errorMessage;
  final String? generatingText;

  ReviewState({
    this.phase = ReviewPhase.loading,
    this.questions = const [],
    this.currentQuestionIndex = 0,
    this.isLoading = false,
    this.statusMessage,
    this.errorMessage,
    this.generatingText,
  });

  ReviewState copyWith({
    ReviewPhase? phase,
    List<QuestionItem>? questions,
    int? currentQuestionIndex,
    bool? isLoading,
    String? statusMessage,
    String? errorMessage,
    String? generatingText,
  }) {
    return ReviewState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage ?? this.errorMessage,
      generatingText: generatingText ?? this.generatingText,
    );
  }
}

final aiServiceProvider = Provider<AIService>((ref) => AIService());

final reviewStateProvider = StateNotifierProvider<ReviewNotifier, ReviewState>(
  (ref) => ReviewNotifier(ref),
);

class ReviewNotifier extends StateNotifier<ReviewState> {
  final Ref _ref;
  final Map<int, List<int>> _noteScores = {};
  final Map<int, ReviewRecord?> _originalRecords = {};

  ReviewNotifier(this._ref) : super(ReviewState());

  Future<void> loadQuestions() async {
    state = state.copyWith(isLoading: true, phase: ReviewPhase.loading, errorMessage: null);
    _noteScores.clear();
    _originalRecords.clear();

    try {
      final db = _ref.read(databaseProvider);
      final aiService = _ref.read(aiServiceProvider);
      final generatePrompt = await _ref.read(generatePromptProvider.future);
      final vaultPath = await _ref.read(vaultPathProvider.future);

      final overdue = await db.overdueNotes(DateTime.now());
      final questionsPerNote = await _ref.read(reviewCountProvider.future);

      final items = <QuestionItem>[];
      for (int noteIdx = 0; noteIdx < overdue.length; noteIdx++) {
        final joined = overdue[noteIdx];
        _originalRecords[joined.note.id] = joined.record;
        _noteScores[joined.note.id] = [];

        state = state.copyWith(
          statusMessage: items.isEmpty
              ? '正在为「${joined.note.fileName}」生成题目（${noteIdx + 1}/${overdue.length}）...'
              : '正在为「${joined.note.fileName}」生成更多题目...',
          generatingText: '',
        );

        final filePath = vaultPath != null ? '$vaultPath/${joined.note.filePath}' : '';
        final file = File(filePath);
        String noteContent = '';
        if (await file.exists()) {
          noteContent = await file.readAsString();
        }

        final prompt = PromptService.render(generatePrompt, {
          'note_content': noteContent,
          'count': questionsPerNote.toString(),
        });

        int extractedCount = 0;
        final responseBuffer = StringBuffer();
        await for (final token in aiService.chatStream(
          systemPrompt: '你是一位帮助我学习的挚友。',
          userMessage: prompt,
        )) {
          responseBuffer.write(token);
          final currentText = responseBuffer.toString();
          final allParsed = parseMultipleQuestions(currentText);

          bool hadNew = false;
          while (extractedCount < allParsed.length) {
            final q = allParsed[extractedCount];
            items.add(QuestionItem(
              noteId: joined.note.id,
              fileName: joined.note.fileName,
              question: q.question,
              expansion: q.expansion,
              noteContent: noteContent,
            ));
            extractedCount++;
            hadNew = true;
          }

          if (hadNew) {
            if (state.phase == ReviewPhase.loading && state.questions.isNotEmpty) {
              state = state.copyWith(
                questions: List.from(items),
                generatingText: currentText,
                currentQuestionIndex: state.currentQuestionIndex + 1,
                phase: ReviewPhase.showingQuestions,
              );
            } else if (state.questions.isEmpty && items.length == 1) {
              state = state.copyWith(
                questions: List.from(items),
                generatingText: currentText,
                phase: ReviewPhase.showingQuestions,
              );
            } else {
              state = state.copyWith(
                questions: List.from(items),
                generatingText: currentText,
              );
            }
          } else {
            state = state.copyWith(generatingText: currentText);
          }
        }

        final fullResponse = responseBuffer.toString();
        final finalParsed = parseMultipleQuestions(fullResponse);
        if (finalParsed.isEmpty) {
          final single = parseSingleQuestion(fullResponse);
          if (single.question.isNotEmpty) finalParsed.add(single);
        }

        bool hadNewFinal = false;
        while (extractedCount < finalParsed.length) {
          final q = finalParsed[extractedCount];
          items.add(QuestionItem(
            noteId: joined.note.id,
            fileName: joined.note.fileName,
            question: q.question,
            expansion: q.expansion,
            noteContent: noteContent,
          ));
          extractedCount++;
          hadNewFinal = true;
        }

        if (hadNewFinal) {
          if (state.phase == ReviewPhase.loading && state.questions.isNotEmpty) {
            state = state.copyWith(
              questions: List.from(items),
              currentQuestionIndex: state.currentQuestionIndex + 1,
              phase: ReviewPhase.showingQuestions,
            );
          } else if (state.questions.isEmpty && items.isNotEmpty) {
            state = state.copyWith(
              questions: List.from(items),
              phase: ReviewPhase.showingQuestions,
            );
          } else {
            state = state.copyWith(questions: List.from(items));
          }
        } else if (state.phase == ReviewPhase.loading && items.isNotEmpty) {
          state = state.copyWith(phase: ReviewPhase.showingQuestions);
        }

        final contentBuffer = StringBuffer();
        for (int i = 0; i < finalParsed.length; i++) {
          final q = finalParsed[i];
          contentBuffer.writeln(
              '【题目${i + 1}】\n${q.question}\n\n【拓展${i + 1}】\n${q.expansion}');
          if (i < finalParsed.length - 1) contentBuffer.writeln();
        }
        await db.insertChatMessage(
          sessionType: 'review_${joined.note.id}',
          noteId: joined.note.id,
          role: 'assistant',
          content: contentBuffer.toString(),
        );
      }

      state = state.copyWith(
        questions: List.from(items),
        phase: items.isEmpty ? ReviewPhase.complete : state.phase,
        isLoading: false,
        statusMessage: null,
        generatingText: null,
      );
    } catch (e) {
      state = state.copyWith(
        phase: ReviewPhase.error,
        isLoading: false,
        errorMessage: '生成题目失败: ${e.toString().replaceAll(RegExp(r'Exception: '), '')}',
        statusMessage: null,
        generatingText: null,
      );
    }
  }

  Future<void> submitAnswer(String answer) async {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(userAnswer: answer);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions, isLoading: true, errorMessage: null);

    try {
      final db = _ref.read(databaseProvider);
      final aiService = _ref.read(aiServiceProvider);
      final evaluatePrompt = await _ref.read(evaluatePromptProvider.future);
      final noteContent = item.noteContent;

      await db.insertChatMessage(
        sessionType: 'review_${item.noteId}',
        noteId: item.noteId,
        role: 'user',
        content: answer,
      );

      final prompt = PromptService.render(evaluatePrompt, {
        'note_content': noteContent,
        'question': item.question,
        'user_answer': answer,
      });

      final response = await aiService.chat(
        systemPrompt: '你是一位帮助我学习的挚友。',
        userMessage: prompt,
      );

      final parsed = parseEvaluationResponse(response);
      final updated = item.copyWith(
        evaluation: parsed.evaluation,
        suggestedScore: parsed.suggestedScore,
        extension: parsed.extension,
      );
      final newQuestions2 = List<QuestionItem>.from(state.questions);
      newQuestions2[idx] = updated;
      state = state.copyWith(
        questions: newQuestions2,
        phase: ReviewPhase.evaluating,
        isLoading: false,
      );

      await db.insertChatMessage(
        sessionType: 'review_${item.noteId}',
        noteId: item.noteId,
        role: 'assistant',
        content: '【评价】\n${parsed.evaluation}\n\n【建议评分】\n${parsed.suggestedScore}\n\n【延伸】\n${parsed.extension ?? ""}',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '评价失败: ${e.toString().replaceAll(RegExp(r'Exception: '), '')}',
      );
    }
  }

  void skipToScoring() {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(
      userAnswer: '(跳过作答)',
      evaluation: '已跳过',
    );
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(
      questions: newQuestions,
      phase: ReviewPhase.evaluating,
    );
  }

  void submitSelfScore(int score) {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(selfScore: score);
    _noteScores[item.noteId]?.add(score);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions);
  }

  Future<void> _saveNoteRecord(int noteId) async {
    final scores = _noteScores[noteId];
    if (scores == null || scores.isEmpty) return;

    final avgScore = (scores.reduce((a, b) => a + b) / scores.length).round();
    final clampedScore = avgScore.clamp(0, 5);
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
    final idx = state.currentQuestionIndex;
    final currentId = state.questions[idx].noteId;

    if (state.currentQuestionIndex < state.questions.length - 1) {
      final nextId = state.questions[idx + 1].noteId;
      if (currentId != nextId) {
        await _saveNoteRecord(currentId);
      }
      state = state.copyWith(
        currentQuestionIndex: idx + 1,
        phase: ReviewPhase.showingQuestions,
      );
      return;
    }

    await _saveNoteRecord(currentId);

    if (state.isLoading) {
      // mark waiting so streaming loop will auto-advance when next question arrives
      state = state.copyWith(phase: ReviewPhase.loading);
      return;
    }

    _ref.invalidate(overdueProvider);
    state = state.copyWith(phase: ReviewPhase.complete);
  }

  void enterChatMode() {
    state = state.copyWith(phase: ReviewPhase.chatting);
  }

  void reset() {
    _noteScores.clear();
    _originalRecords.clear();
    state = ReviewState();
  }
}
