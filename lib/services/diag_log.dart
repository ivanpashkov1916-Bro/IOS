/// Диагностический журнал приложения: кольцевой буфер последних
/// событий голосового ввода, скачивания моделей и ответов движков.
/// Нужен, чтобы по выгрузке («Ассистент» → настройки → «Диагностика»)
/// можно было понять, что происходило перед сбоем: какой движок,
/// сколько шла запись, какая ошибка пришла последней.
///
/// Ничего никуда не отправляется: журнал живёт в памяти приложения
/// и выгружается только по кнопке пользователя.
library;

class DiagLog {
  DiagLog._();

  static const int _cap = 120;
  static final List<String> _lines = [];

  static void add(String tag, String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _lines.add('$stamp [$tag] $message');
    if (_lines.length > _cap) _lines.removeRange(0, _lines.length - _cap);
  }

  static List<String> get lines => List.unmodifiable(_lines);

  /// Текст для выгрузки: сводка состояния + журнал.
  static String report(Map<String, String> state) {
    final b = StringBuffer()
      ..writeln('# Диагностика планера')
      ..writeln('Время: ${DateTime.now()}')
      ..writeln();
    state.forEach((k, v) => b.writeln('$k: $v'));
    b
      ..writeln()
      ..writeln('## Журнал (последние ${_lines.length} событий)');
    for (final l in _lines) {
      b.writeln(l);
    }
    if (_lines.isEmpty) b.writeln('(событий пока нет)');
    return b.toString();
  }
}
