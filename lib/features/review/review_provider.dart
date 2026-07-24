import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../services/sm2_engine.dart';
import '../../services/ai_service.dart';
import '../../services/prompt_service.dart';
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

enum ReviewPhase { loading, showingQuestions, answering, evaluating, chatting, complete }

class ReviewState {
  final ReviewPhase phase;
  final List<QuestionItem> questions;
  final int currentQuestionIndex;
  final bool isLoading;

  ReviewState({
    this.phase = ReviewPhase.loading,
    this.questions = const [],
    this.currentQuestionIndex = 0,
    this.isLoading = false,
  });

  ReviewState copyWith({
    ReviewPhase? phase,
    List<QuestionItem>? questions,
    int? currentQuestionIndex,
    bool? isLoading,
  }) {
    return ReviewState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final aiServiceProvider = Provider<AIService>((ref) => AIService());

final reviewStateProvider = StateNotifierProvider<ReviewNotifier, ReviewState>(
  (ref) => ReviewNotifier(ref),
);

class ReviewNotifier extends StateNotifier<ReviewState> {
  final Ref _ref;

  ReviewNotifier(this._ref) : super(ReviewState());

  Future<void> loadQuestions() async {
    state = state.copyWith(isLoading: true, phase: ReviewPhase.loading);

    final db = _ref.read(databaseProvider);
    final aiService = _ref.read(aiServiceProvider);
    final generatePrompt = await _ref.read(generatePromptProvider.future);
    final vaultPath = await _ref.read(vaultPathProvider.future);

    final lastCheck = await db.getLastCheckTime();
    final overdue = await db.overdueNotes(lastCheck, DateTime.now());

    final count = _ref.read(reviewCountProvider).valueOrNull ?? 5;
    final selected = overdue.take(count).toList();

    final items = <QuestionItem>[];
    for (final joined in selected) {
      final filePath = vaultPath != null ? '$vaultPath/${joined.note.filePath}' : '';
      final file = File(filePath);
      String noteContent = '';
      if (await file.exists()) {
        noteContent = await file.readAsString();
      }

      final prompt = PromptService.render(generatePrompt, {
        'note_content': noteContent,
      });

      final response = await aiService.chat(
        systemPrompt: '你是一位帮助我学习的挚友。',
        userMessage: prompt,
      );

      final parsed = parseQuestionResponse(response);
      items.add(QuestionItem(
        noteId: joined.note.id,
        fileName: joined.note.fileName,
        question: parsed.question,
        expansion: parsed.expansion,
        noteContent: noteContent,
      ));
    }

    state = state.copyWith(
      questions: items,
      currentQuestionIndex: 0,
      phase: items.isEmpty ? ReviewPhase.complete : ReviewPhase.showingQuestions,
      isLoading: false,
    );
  }

  Future<void> submitAnswer(String answer) async {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(userAnswer: answer);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions, isLoading: true);

    final aiService = _ref.read(aiServiceProvider);
    final evaluatePrompt = await _ref.read(evaluatePromptProvider.future);
    final noteContent = item.noteContent;

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
  }

  Future<void> submitSelfScore(int score) async {
    final idx = state.currentQuestionIndex;
    final item = state.questions[idx].copyWith(selfScore: score);
    final newQuestions = List<QuestionItem>.from(state.questions);
    newQuestions[idx] = item;
    state = state.copyWith(questions: newQuestions);

    final db = _ref.read(databaseProvider);
    final existing = await db.recordForNote(item.noteId);

    final result = Sm2Engine.calculate(
      quality: score,
      currentInterval: existing?.sm2Interval ?? 1.0,
      currentEaseFactor: existing?.sm2EaseFactor ?? 2.5,
      currentRepetitions: existing?.sm2Repetitions ?? 0,
    );

    await db.upsertRecord(ReviewRecordsCompanion.insert(
      noteId: Value(item.noteId),
      sm2Interval: Value(result.interval),
      sm2EaseFactor: Value(result.easeFactor),
      sm2Repetitions: Value(result.repetitions),
      nextReviewDate: result.nextReviewDate,
      lastReviewDate: Value(DateTime.now()),
      lastScore: Value(score),
    ));
  }

  void nextQuestion() {
    if (state.currentQuestionIndex < state.questions.length - 1) {
      state = state.copyWith(
        currentQuestionIndex: state.currentQuestionIndex + 1,
        phase: ReviewPhase.showingQuestions,
      );
    } else {
      state = state.copyWith(phase: ReviewPhase.complete);
    }
  }

  void enterChatMode() {
    state = state.copyWith(phase: ReviewPhase.chatting);
  }

  void reset() {
    state = ReviewState();
  }
}
