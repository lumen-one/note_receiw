import 'package:flutter_test/flutter_test.dart';
import 'package:phone_note_review/services/sm2_engine.dart';

void main() {
  group('Sm2Engine.calculate', () {
    test('首次复习（q=5）用第一个自定义间隔', () {
      final r = Sm2Engine.calculate(
        quality: 5,
        currentInterval: 1,
        currentEaseFactor: 2.5,
        currentRepetitions: 0,
        customIntervals: [1, 6, 15, 38],
      );
      expect(r.interval, 1);
      expect(r.repetitions, 1);
      expect(r.easeFactor, closeTo(2.6, 1e-9));
    });

    test('q=4 时难度系数不变', () {
      final r = Sm2Engine.calculate(
        quality: 4,
        currentInterval: 6,
        currentEaseFactor: 2.5,
        currentRepetitions: 1,
        customIntervals: [1, 6, 15, 38],
      );
      expect(r.interval, 6);
      expect(r.easeFactor, closeTo(2.5, 1e-9));
      expect(r.repetitions, 2);
    });

    test('q=3 时难度系数下降 0.14', () {
      final r = Sm2Engine.calculate(
        quality: 3,
        currentInterval: 15,
        currentEaseFactor: 2.5,
        currentRepetitions: 2,
        customIntervals: [1, 6, 15, 38],
      );
      expect(r.interval, 15);
      expect(r.easeFactor, closeTo(2.36, 1e-9));
    });

    test('q<3 重置连击次数并回到 1 天', () {
      final r = Sm2Engine.calculate(
        quality: 2,
        currentInterval: 38,
        currentEaseFactor: 2.5,
        currentRepetitions: 3,
        customIntervals: [1, 6, 15, 38],
      );
      expect(r.interval, 1);
      expect(r.repetitions, 0);
      expect(r.easeFactor, closeTo(2.18, 1e-9));
    });

    test('难度系数不低于 1.3', () {
      var ef = 2.5;
      for (var i = 0; i < 10; i++) {
        ef = Sm2Engine.calculate(
          quality: 0,
          currentInterval: 1,
          currentEaseFactor: ef,
          currentRepetitions: 0,
        ).easeFactor;
      }
      expect(ef, 1.3);
    });

    test('自定义间隔用完后退回 SM-2 乘法', () {
      final r = Sm2Engine.calculate(
        quality: 5,
        currentInterval: 15,
        currentEaseFactor: 2.5,
        currentRepetitions: 4,
        customIntervals: [1, 6, 15, 38],
      );
      // 15 * 2.5 = 37.5 -> 38
      expect(r.interval, 38);
      expect(r.repetitions, 5);
    });

    test('不传自定义间隔时走默认 1 / 6 / EF 乘法', () {
      expect(
        Sm2Engine.calculate(
          quality: 5,
          currentInterval: 1,
          currentEaseFactor: 2.5,
          currentRepetitions: 0,
        ).interval,
        1,
      );
      expect(
        Sm2Engine.calculate(
          quality: 5,
          currentInterval: 1,
          currentEaseFactor: 2.5,
          currentRepetitions: 1,
        ).interval,
        6,
      );
    });

    test('下次复习时间落在当天零点起算的第 N 天', () {
      final r = Sm2Engine.calculate(
        quality: 5,
        currentInterval: 1,
        currentEaseFactor: 2.5,
        currentRepetitions: 0,
        customIntervals: [1],
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(r.nextReviewDate, today.add(const Duration(days: 1)));
      expect(r.nextReviewDate.hour, 0);
      expect(r.nextReviewDate.minute, 0);
    });
  });
}
