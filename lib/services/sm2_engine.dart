class Sm2Result {
  final double interval;
  final double easeFactor;
  final int repetitions;
  final DateTime nextReviewDate;

  Sm2Result({
    required this.interval,
    required this.easeFactor,
    required this.repetitions,
    required this.nextReviewDate,
  });
}

class Sm2Engine {
  static Sm2Result calculate({
    required int quality,
    required double currentInterval,
    required double currentEaseFactor,
    required int currentRepetitions,
  }) {
    double newInterval;
    int newRepetitions;
    double newEaseFactor;

    if (quality >= 3) {
      if (currentRepetitions == 0) {
        newInterval = 1;
      } else if (currentRepetitions == 1) {
        newInterval = 6;
      } else {
        newInterval = (currentInterval * currentEaseFactor).roundToDouble();
      }
      newRepetitions = currentRepetitions + 1;
    } else {
      newInterval = 1;
      newRepetitions = 0;
    }

    newEaseFactor = currentEaseFactor +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (newEaseFactor < 1.3) newEaseFactor = 1.3;

    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    final nextReviewDate = dayStart.add(Duration(days: newInterval.toInt()));

    return Sm2Result(
      interval: newInterval,
      easeFactor: newEaseFactor,
      repetitions: newRepetitions,
      nextReviewDate: nextReviewDate,
    );
  }
}
