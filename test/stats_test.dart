import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/store.dart';

void main() {
  group('statPeriods', () {
    test('пять периодов в правильном порядке', () {
      final periods = statPeriods(DateTime(2026, 11, 4, 15));
      expect(periods.map((p) => p.name).toList(),
          ['День', 'Неделя', 'Месяц', 'Квартал', 'Год']);
      expect(periods[0].from, DateTime(2026, 11, 4));
      expect(periods[0].to, DateTime(2026, 11, 5));
      // 4 ноября 2026 — среда, неделя началась в понедельник 2-го
      expect(periods[1].from, DateTime(2026, 11, 2));
      expect(periods[2].from, DateTime(2026, 11, 1));
      expect(periods[3].from, DateTime(2026, 10, 1)); // Q4
      expect(periods[4].from, DateTime(2026, 1, 1));
    });
  });

  group('PeriodStat', () {
    test('пустой период -> 0%', () {
      const s = PeriodStat(0, 0);
      expect(s.ratio, 0);
      expect(s.percent, 0);
    });

    test('процент округляется', () {
      const s = PeriodStat(1, 3);
      expect(s.percent, 33);
    });
  });

  test('notificationIdOf стабилен и неотрицателен', () {
    final a = notificationIdOf('task:1');
    final b = notificationIdOf('task:1');
    expect(a, b);
    expect(a >= 0, isTrue);
  });
}
