/// Форматирование дат и общие утилиты.
library;

String two(int v) => v.toString().padLeft(2, '0');

String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Минуты — в читаемый формат «X дн Y ч Z мин» (дни/часы/минуты).
String fmtDaysHoursMin(int minutes) {
  if (minutes <= 0) return '0 мин';
  final d = minutes ~/ 1440;
  final h = (minutes % 1440) ~/ 60;
  final m = minutes % 60;
  final parts = <String>[
    if (d > 0) '$d дн',
    if (h > 0) '$h ч',
    if (m > 0 || (d == 0 && h == 0)) '$m мин',
  ];
  return parts.join(' ');
}

/// Русские числительные -> число (для парсера длительности).
const Map<String, int> _ruNum = {
  'один': 1, 'одна': 1, 'одну': 1,
  'два': 2, 'две': 2,
  'три': 3, 'четыре': 4, 'пять': 5, 'шесть': 6, 'семь': 7,
  'восемь': 8, 'девять': 9, 'десять': 10, 'одиннадцать': 11,
  'двенадцать': 12, 'пятнадцать': 15, 'двадцать': 20, 'тридцать': 30,
  'сорок': 40, 'сорока': 40, 'пятьдесят': 50, 'шестьдесят': 60,
};

int? _ruNumOf(String w) => _ruNum[w] ?? int.tryParse(w);

/// Разбор фразы длительности в минуты: «61 минута» -> 61,
/// «полтора часа» / «час с половиной» -> 90, «полчаса» -> 30,
/// «час» -> 60, «2 часа» -> 120, «два часа» -> 120,
/// «1 час 20 минут» -> 80, «1,5 часа» -> 90, «90» -> 90.
/// Возвращает null, если разобрать не удалось.
int? parseDurationMin(String raw) {
  var s = raw.toLowerCase().trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(',', '.').replaceAll('ё', 'е');
  // Голое число — минуты.
  final bare = double.tryParse(s);
  if (bare != null) return bare.round();
  if (RegExp(r'полчаса').hasMatch(s)) return 30;
  if (RegExp(r'полтора\s+час|полтора\b|час\s+с\s+половин').hasMatch(s)) {
    return 90;
  }
  var hours = 0.0;
  var minutes = 0.0;
  // «1.5 часа», «2 часа», «два часа», «час»
  final hm = RegExp(r'(\d+(?:\.\d+)?|[а-я]+)\s*(?:часа?|часов|ч\.?|часа\b)')
      .firstMatch(s);
  if (hm != null) {
    final w = hm.group(1)!;
    hours = double.tryParse(w) ?? (_ruNumOf(w)?.toDouble() ?? 1.0);
  } else if (RegExp(r'\bчас\b').hasMatch(s)) {
    hours = 1.0;
  }
  // «45 минут», «двадцать минут»
  final mm = RegExp(r'(\d+(?:\.\d+)?|[а-я]+)\s*(?:минуты?|мин\.?|м\b)')
      .firstMatch(s);
  if (mm != null) {
    final w = mm.group(1)!;
    minutes = double.tryParse(w) ?? (_ruNumOf(w)?.toDouble() ?? 0);
  }
  final total = (hours * 60 + minutes).round();
  return total > 0 ? total : null;
}
