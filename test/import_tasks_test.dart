import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/import_tasks.dart';

void main() {
  group('parseStrategyPlan', () {
    test('полный формат годового плана', () {
      final plan = parseStrategyPlan('''
      {
        "plan": {"name": "Личный Штаб", "period": {"start": "2026-11-04", "end": "2027-10-31"}, "wip_limit": 4},
        "tasks": [
          {"id": "HOME-01", "block": "HOME", "title": "Котёл", "priority": "A",
           "deadline": "2026-11-15", "metric": "Тепло", "status": "in_progress"},
          {"id": "HLT-03", "block": "HLT", "title": "Физика 20 мин", "priority": "B",
           "deadline": "daily", "status": "in_progress"},
          {"id": "FIN-05", "block": "FIN", "title": "Масштаб", "priority": "C",
           "deadline": "2027-04-30", "status": "done"}
        ]
      }
      ''');
      expect(plan.name, 'Личный Штаб');
      expect(plan.wipLimit, 4);
      expect(plan.tasks.length, 3);
      expect(plan.blocks, ['HOME', 'HLT', 'FIN']);
      expect(plan.horizonDays, greaterThan(300));

      final a = plan.tasks[0];
      expect(a.priorityInt, 2);
      expect(a.isDaily, isFalse);
      expect(a.monthKey, '2026-11');
      expect(a.done, isFalse);

      final daily = plan.tasks[1];
      expect(daily.isDaily, isTrue);
      expect(daily.monthKey, 'daily');

      expect(plan.tasks[2].done, isTrue);
      expect(plan.tasks[2].priorityInt, 0);
    });

    test('простой массив без обёртки plan', () {
      final plan = parseStrategyPlan(
          '[{"title":"A","deadline":"2026-03-10"},{"name":"B","status":"completed"}]');
      expect(plan.tasks.length, 2);
      expect(plan.tasks[0].block, 'GEN');
      expect(plan.tasks[1].done, isTrue);
      expect(plan.tasks[1].monthKey, '—');
    });

    test('без задач -> FormatException', () {
      expect(() => parseStrategyPlan('{"tasks": []}'), throwsFormatException);
      expect(() => parseStrategyPlan('не json'), throwsA(anything));
    });

    test('blockTitle знает блоки и не падает на неизвестных', () {
      expect(blockTitle('FIN'), 'Финансы');
      expect(blockTitle('XXX'), 'Блок XXX');
    });
  });

  group('summarizeByMonth', () {
    test('группировка, daily в конце', () {
      final plan = parseStrategyPlan(
          '[{"title":"a","deadline":"2026-05-01","status":"done"},'
          '{"title":"b","deadline":"2026-05-20"},'
          '{"title":"c","deadline":"daily"},'
          '{"title":"d","deadline":"2026-01-10"}]');
      final sum = summarizeByMonth(plan.tasks);
      expect(sum.keys.toList(), ['2026-01', '2026-05', 'daily']);
      expect(sum['2026-05']!.total, 2);
      expect(sum['2026-05']!.done, 1);
      expect(sum['daily']!.total, 1);
    });
  });
}
