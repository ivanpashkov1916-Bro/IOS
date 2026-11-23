/// Парсер годового плана tasks.json для «Стратегии на год» и импорта
/// во все экраны приложения. Устойчив к пропущенным полям.
library;

import 'dart:convert';

/// Человеческие названия блоков годового плана.
const Map<String, String> blockTitles = {
  'HOME': 'Дом и быт',
  'FIN': 'Финансы',
  'HLT': 'Здоровье',
  'TEA': 'Чайный бизнес',
  'DEV': 'Развитие',
  'TRN': 'Транспорт',
  'FAM': 'Семья',
  'DATA': 'База знаний',
};

String blockTitle(String block) =>
    blockTitles[block] ?? 'Блок ${block.isEmpty ? "—" : block}';

class StrategyTask {
  final String id;
  final String block;
  final String title;
  final String priorityLetter; // A / B / C
  final String quarter;
  final String deadlineRaw; // YYYY-MM-DD или 'daily'
  final String metric;
  final String status;
  final String eisenhower;

  const StrategyTask({
    required this.id,
    required this.block,
    required this.title,
    this.priorityLetter = 'B',
    this.quarter = '',
    this.deadlineRaw = '',
    this.metric = '',
    this.status = 'backlog',
    this.eisenhower = '',
  });

  bool get isDaily => deadlineRaw.trim().toLowerCase() == 'daily';

  DateTime? get deadlineDate => isDaily ? null : DateTime.tryParse(deadlineRaw);

  bool get done {
    final s = status.toLowerCase();
    return s == 'done' || s == 'completed' || s == 'выполнено';
  }

  /// Приоритет приложения: A -> 2 (высокий), B -> 1, C -> 0.
  int get priorityInt {
    switch (priorityLetter.toUpperCase()) {
      case 'A':
        return 2;
      case 'C':
        return 0;
      default:
        return 1;
    }
  }

  /// Ключ месяца для диаграммы: YYYY-MM, 'daily' или '—'.
  String get monthKey {
    if (isDaily) return 'daily';
    final d = deadlineDate;
    if (d == null) return '—';
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }
}

class StrategyPlan {
  final String name;
  final String periodStart;
  final String periodEnd;
  final int wipLimit;
  final List<StrategyTask> tasks;

  const StrategyPlan({
    required this.name,
    this.periodStart = '',
    this.periodEnd = '',
    this.wipLimit = 0,
    this.tasks = const [],
  });

  /// Горизонт плана в днях (для целей по блокам).
  int get horizonDays {
    final s = DateTime.tryParse(periodStart);
    final e = DateTime.tryParse(periodEnd);
    if (s == null || e == null) return 365;
    final days = e.difference(s).inDays;
    return days > 0 ? days : 365;
  }

  /// Уникальные блоки в порядке первого появления.
  List<String> get blocks {
    final seen = <String>[];
    for (final t in tasks) {
      if (!seen.contains(t.block)) seen.add(t.block);
    }
    return seen;
  }
}

String _s(Map<dynamic, dynamic> m, String key, [String fallback = '']) {
  final v = m[key];
  if (v == null) return fallback;
  return v.toString();
}

StrategyPlan parseStrategyPlan(String raw) {
  final decoded = jsonDecode(raw);

  Map<dynamic, dynamic> planMeta = const {};
  List<dynamic> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map) {
    final inner = decoded['tasks'] ?? decoded['items'] ?? decoded['data'];
    if (inner is List) {
      list = inner;
      final p = decoded['plan'];
      if (p is Map) planMeta = p;
    } else {
      list = [decoded];
    }
  } else {
    throw const FormatException('Ожидался JSON-массив или объект с полем tasks');
  }

  final period = planMeta['period'];
  final tasks = <StrategyTask>[];
  var auto = 0;
  for (final item in list) {
    if (item is! Map) continue;
    final title = _s(item, 'title').trim().isNotEmpty
        ? _s(item, 'title').trim()
        : _s(item, 'name').trim().isNotEmpty
            ? _s(item, 'name').trim()
            : _s(item, 'task').trim();
    if (title.isEmpty) continue;
    auto++;
    tasks.add(StrategyTask(
      id: _s(item, 'id', 'T-$auto'),
      block: _s(item, 'block', 'GEN'),
      title: title,
      priorityLetter: _s(item, 'priority', 'B'),
      quarter: _s(item, 'quarter'),
      deadlineRaw: _s(item, 'deadline').isNotEmpty
          ? _s(item, 'deadline')
          : _s(item, 'date'),
      metric: _s(item, 'metric'),
      status: _s(item, 'status', 'backlog'),
      eisenhower: _s(item, 'eisenhower'),
    ));
  }
  if (tasks.isEmpty) {
    throw const FormatException('В файле не найдено ни одной задачи');
  }

  return StrategyPlan(
    name: _s(planMeta, 'name', 'Годовой план'),
    periodStart: period is Map ? _s(period, 'start') : '',
    periodEnd: period is Map ? _s(period, 'end') : '',
    wipLimit: int.tryParse(_s(planMeta, 'wip_limit', '0')) ?? 0,
    tasks: tasks,
  );
}

/// Сводка по месяцам для столбчатой диаграммы: ключ месяца -> всего/выполнено.
Map<String, ({int total, int done})> summarizeByMonth(List<StrategyTask> tasks) {
  final map = <String, ({int total, int done})>{};
  for (final t in tasks) {
    final cur = map[t.monthKey] ?? (total: 0, done: 0);
    map[t.monthKey] = (total: cur.total + 1, done: cur.done + (t.done ? 1 : 0));
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      if (a == 'daily') return 1;
      if (b == 'daily') return -1;
      if (a == '—') return 1;
      if (b == '—') return -1;
      return a.compareTo(b);
    });
  return {for (final k in keys) k: map[k]!};
}
