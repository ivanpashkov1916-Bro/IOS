/// Локальный парсер команд ассистента — работает без LLM.
/// Понимает русские даты словами («восьмое ноября», «на пятницу»,
/// «завтра», «26-й год») и создаёт события/задачи/заметки/цели
/// даже когда Ollama недоступна или не смогла распознать команду.
library;

/// Результат разбора даты: сама дата и подстроки, которые нужно
/// вырезать из названия.
class _DateHit {
  final DateTime date;
  final List<String> cuts;
  const _DateHit(this.date, this.cuts);
}

class LocalCommands {
  LocalCommands._();

  static const _months = {
    'января': 1, 'январь': 1, 'янв': 1,
    'февраля': 2, 'февраль': 2, 'фев': 2,
    'марта': 3, 'март': 3, 'мар': 3,
    'апреля': 4, 'апрель': 4, 'апр': 4,
    'мая': 5, 'май': 5,
    'июня': 6, 'июнь': 6, 'июн': 6,
    'июля': 7, 'июль': 7, 'июл': 7,
    'августа': 8, 'август': 8, 'авг': 8,
    'сентября': 9, 'сентябрь': 9, 'сен': 9, 'сент': 9,
    'октября': 10, 'октябрь': 10, 'окт': 10,
    'ноября': 11, 'ноябрь': 11, 'ноя': 11, 'нояб': 11,
    'декабря': 12, 'декабрь': 12, 'дек': 12,
  };

  static const _dayWords = {
    'первое': 1, 'первого': 1,
    'второе': 2, 'второго': 2,
    'третье': 3, 'третьего': 3,
    'четвёртое': 4, 'четвертое': 4, 'четвёртого': 4, 'четвертого': 4,
    'пятое': 5, 'пятого': 5,
    'шестое': 6, 'шестого': 6,
    'седьмое': 7, 'седьмого': 7,
    'восьмое': 8, 'восьмого': 8,
    'девятое': 9, 'девятого': 9,
    'десятое': 10, 'десятого': 10,
    'одиннадцатое': 11, 'одиннадцатого': 11,
    'двенадцатое': 12, 'двенадцатого': 12,
    'тринадцатое': 13, 'тринадцатого': 13,
    'четырнадцатое': 14, 'четырнадцатого': 14,
    'пятнадцатое': 15, 'пятнадцатого': 15,
    'шестнадцатое': 16, 'шестнадцатого': 16,
    'семнадцатое': 17, 'семнадцатого': 17,
    'восемнадцатое': 18, 'восемнадцатого': 18,
    'девятнадцатое': 19, 'девятнадцатого': 19,
    'двадцатое': 20, 'двадцатого': 20,
    'тридцатое': 30, 'тридцатого': 30,
  };

  static const _weekdays = {
    'понедельник': 1,
    'вторник': 2,
    'среда': 3, 'среду': 3, 'среды': 3,
    'четверг': 4,
    'пятница': 5, 'пятницу': 5, 'пятницы': 5,
    'суббота': 6, 'субботу': 6, 'субботы': 6,
    'воскресенье': 7,
  };

  static int? _dayOfWord(String w) {
    final direct = _dayWords[w];
    if (direct != null) return direct;
    // Составные: «двадцать первое», «тридцать первое».
    final parts = w.split(' ');
    if (parts.length == 2) {
      final tens = {'двадцать': 20, 'тридцать': 30}[parts[0]];
      final unit = _dayWords[parts[1]];
      if (tens != null && unit != null && tens + unit <= 31) return tens + unit;
    }
    return null;
  }

  /// Все слова-дни, от длинных к коротким (чтобы «двадцать первое»
  /// не съедалось как «первое»).
  static List<String> get _dayWordKeys {
    final keys = <String>{..._dayWords.keys};
    for (final t in ['двадцать', 'тридцать']) {
      for (final u in _dayWords.keys) {
        if ((_dayWords[u] ?? 0) <= 9) keys.add('$t $u');
      }
    }
    final list = keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    return list;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Извлекает дату из фразы (нижний регистр). null — даты нет.
  static _DateHit? _extractDate(String lower, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    // сегодня / завтра / послезавтра
    final rel =
        RegExp(r'\b(послезавтра|завтра|сегодня)\b').firstMatch(lower);
    if (rel != null) {
      final w = rel.group(1)!;
      final add = w == 'послезавтра' ? 2 : (w == 'завтра' ? 1 : 0);
      return _DateHit(today.add(Duration(days: add)), [rel.group(0)!]);
    }

    // Число.месяц[.год]: 8.11, 08.11.2026
    final num = RegExp(r'\b(\d{1,2})[.\-/](\d{1,2})(?:[.\-/](\d{2,4}))?\b')
        .firstMatch(lower);
    if (num != null) {
      final d = int.parse(num.group(1)!);
      final m = int.parse(num.group(2)!);
      var y = num.group(3) != null ? int.parse(num.group(3)!) : now.year;
      if (y < 100) y += 2000;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        var date = DateTime(y, m, d);
        if (num.group(3) == null && date.isBefore(today)) {
          date = DateTime(y + 1, m, d);
        }
        return _DateHit(date, [num.group(0)!]);
      }
    }

    // Словесные даты: «восьмое ноября», «8 ноября 2026»,
    // «восьмое 11-е 26-й год», «на восьмое» (текущий месяц).
    // День, месяц и год ищем НЕЗАВИСИМО — так надёжнее для разных
    // порядков слов.
    {
      final cuts = <String>[];
      int? day;
      int? month;
      int? year;

      // 1) День словом: «восьмое», «двадцать первое».
      for (final key in _dayWordKeys) {
        final m = RegExp('(?:^|\\s)${RegExp.escape(key)}\\b')
            .firstMatch(lower);
        if (m != null) {
          final v = _dayOfWord(key);
          if (v != null) {
            day = v;
            cuts.add(m.group(0)!);
            break;
          }
        }
      }

      // 2) Месяц словом: «ноября».
      String? monthWord;
      for (final e in _months.entries) {
        final m =
            RegExp('(?:^|\\s)${RegExp.escape(e.key)}\\b').firstMatch(lower);
        if (m != null) {
          month = e.value;
          monthWord = m.group(0)!;
          break;
        }
      }

      // 3) Числа с суффиксом: «8-е», «11-е», «8-го» — день и/или месяц.
      final suffixed = RegExp(r'\b(\d{1,2})-?(?:е|ое|го|я)\b')
          .allMatches(lower)
          .toList();
      final suffixVals = <int>[];
      for (final m in suffixed) {
        final v = int.tryParse(m.group(1)!);
        if (v == null) continue;
        // Отсекаем год («26-й» ловится другим шаблоном) и время («в 18:00»).
        final after = lower.substring(m.end);
        if (RegExp(r'^\s*год').hasMatch(after)) continue;
        suffixVals.add(v);
        cuts.add(m.group(0)!);
      }
      if (day == null && suffixVals.isNotEmpty) {
        // Если рядом есть месяц словом — число это день.
        day = suffixVals.first;
      }
      if (month == null && suffixVals.length >= 2) {
        month = suffixVals[1];
      } else if (month == null &&
          suffixVals.length == 1 &&
          day != null &&
          suffixVals.first != day) {
        month = suffixVals.first;
      }
      // День цифрой перед месяцем словом: «8 ноября».
      if (day == null && monthWord != null) {
        final before = lower.substring(0, lower.indexOf(monthWord));
        final dm = RegExp(r'(\d{1,2})\s*$').firstMatch(before);
        if (dm != null) {
          day = int.tryParse(dm.group(1)!);
          if (day != null) cuts.add(dm.group(0)!);
        }
      }
      if (monthWord != null) cuts.add(monthWord);

      // 4) Год: «2026», «26-й год», «26 год».
      final ym = RegExp(r'\b(\d{4})\s*(?:год[ау]?|г\.?)?\b').firstMatch(lower) ??
          RegExp(r'\b(\d{2})-?(?:й|ый|ий|го|г)?\s*год[ау]?\b')
              .firstMatch(lower);
      if (ym != null) {
        var y = int.tryParse(ym.group(1)!);
        if (y != null) {
          if (y < 100) y += 2000;
          if (y >= 2020 && y <= 2100) {
            year = y;
            cuts.add(ym.group(0)!);
          }
        }
      }

      if (day != null && day >= 1 && day <= 31) {
        final m = month ?? now.month;
        if (m >= 1 && m <= 12) {
          var date = DateTime(year ?? now.year, m, day);
          if (year == null) {
            // Без явного года/месяца — ближайшая такая дата вперёд.
            if (date.isBefore(today)) {
              date = month == null
                  ? (m == 12
                      ? DateTime(now.year + 1, 1, day)
                      : DateTime(now.year, m + 1, day))
                  : DateTime(now.year + 1, m, day);
            }
          }
          return _DateHit(date, cuts);
        }
      }
    }

    // День недели: «в пятницу», «на понедельник» — ближайший такой день.
    final wd = RegExp(r'(?:в|во|на)\s+(\S+)').allMatches(lower);
    for (final m in wd) {
      final target = _weekdays[m.group(1)];
      if (target == null) continue;
      var add = (target - now.weekday) % 7;
      if (add == 0) add = 7;
      return _DateHit(today.add(Duration(days: add)), [m.group(0)!]);
    }
    return null;
  }

  /// Извлекает время: «в 15:30», «в 3 часа дня», «в 7 вечера».
  /// Возвращает 'HH:mm' и вырезаемую подстроку.
  static ({String time, String matched})? _extractTime(String lower) {
    final m = RegExp(
            r'\bв\s+(\d{1,2})(?:[:.](\d{2}))?\s*(утра|дня|вечера|ночи|часа|часов|час)?')
        .firstMatch(lower);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final part = m.group(3) ?? '';
    if (h > 24 || min > 59) return null;
    if (part == 'дня' || part == 'вечера') {
      if (h < 12) h += 12;
    } else if (part == 'ночи') {
      if (h == 12) h = 0;
    } else if (part == 'час' || part == 'часа' || part == 'часов') {
      if (h < 7) h += 12; // «в 3 часа» — почти всегда день
    }
    if (h >= 24) return null;
    return (
      time: '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}',
      matched: m.group(0)!,
    );
  }

  /// Время после слова «deadline»: «18:30», «в 18:30», «6 вечера»,
  /// «в 6 утра», «в 18 часов» — предлог «в» необязателен.
  static String? _extractDeadlineTime(String after) {
    final hm = RegExp(
            r'\b(?:в\s+)?(\d{1,2})[:.](\d{2})\s*(утра|дня|вечера|ночи)?\b')
        .firstMatch(after);
    if (hm != null) {
      var h = int.parse(hm.group(1)!);
      final min = int.parse(hm.group(2)!);
      if (h > 24 || min > 59) return null;
      final part = hm.group(3) ?? '';
      if ((part == 'дня' || part == 'вечера') && h < 12) h += 12;
      if (part == 'ночи' && h == 12) h = 0;
      if (h >= 24) return null;
      return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    }
    final hw = RegExp(
            r'\b(?:в\s+)?(\d{1,2})\s+(утра|дня|вечера|ночи|часа|часов|час)\b')
        .firstMatch(after);
    if (hw != null) {
      var h = int.parse(hw.group(1)!);
      final part = hw.group(2)!;
      if (h > 24) return null;
      if ((part == 'дня' || part == 'вечера') && h < 12) h += 12;
      if (part == 'ночи' && h == 12) h = 0;
      if ((part == 'час' || part == 'часа' || part == 'часов') && h < 7) {
        h += 12; // «в 3 часа» — почти всегда день
      }
      if (h >= 24) return null;
      return '${h.toString().padLeft(2, '0')}:00';
    }
    return null;
  }

  static final _filler = RegExp(
      r'\b(добавь|добавить|создай|создать|запланируй|запланировать|'
      r'пожалуйста|новое|новую|новый|новая|мне|нам|нужно|надо|поставь|'
      r'запиши|внеси|записать|событие|встречу|встреча|встречи|в календарь|'
      r'календаре|задачу|задача|задачей|заметку|заметка|цель|целью|'
      r'срочно|срочная|срочное|важно|важная|важное)\b',
      caseSensitive: false);

  static String _cleanTitle(String text, List<String> cuts) {
    var t = ' $text ';
    for (final c in cuts) {
      t = t.replaceAll(c, ' ');
    }
    t = t.replaceAll(_filler, ' ');
    // Одиночные знаки препинания (обрывки вырезанных дат) убираем.
    t = t.replaceAll(RegExp(r'\s*[.,;]\s*'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Обрывки предлогов по краям: «на …», «… на».
    t = t.replaceAll(RegExp(r'^(на|во?|с|про)\s+'), '').trim();
    t = t.replaceAll(RegExp(r'\s+(на|во?|с|про)$'), '').trim();
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Разбор фразы в JSON-интент, совместимый с AppStore.handleAssistantJson.
  /// Возвращает null, если фраза не похожа на команду.
  ///
  /// Название в кавычках: «добавь событие „завтра позвонить другу"» —
  /// текст в кавычках целиком становится названием (включая слова даты),
  /// а дата вычисляется из всей фразы.
  static Map<String, dynamic>? parse(String rawText) {
    final lower = rawText.toLowerCase();
    final now = DateTime.now();

    // --- Вопросы: «что у меня сегодня», «что просрочено» ---
    if (RegExp(r'что\s+у\s+меня|планы?\s+на\s+сегодня|что\s+(?:у\s+меня\s+)?(?:на\s+)?сегодня')
        .hasMatch(lower)) {
      return {'action': 'list_today', 'title': '', 'text': rawText};
    }
    if (lower.contains('что просрочено') ||
        lower.contains('что пропущено') ||
        lower.contains('просрочк')) {
      return {'action': 'list_overdue', 'title': '', 'text': rawText};
    }

    // --- Действия над существующими записями: команда — главная
    // часть фразы, остаток — название записи в списках. ---
    String? act;
    if (RegExp(r'\b(удали\w*|убери\w*|сотри\w*|стереть)\b').hasMatch(lower)) {
      if (lower.contains('задач')) {
        act = 'delete_task';
      } else if (RegExp(r'\bцел').hasMatch(lower)) {
        act = 'delete_goal';
      } else if (lower.contains('событ') || lower.contains('встреч')) {
        act = 'delete_event';
      } else if (lower.contains('заметк')) {
        act = 'delete_note';
      }
    } else if (RegExp(r'отмени\w*\s+выполнени|сними\w*\s+отметк')
        .hasMatch(lower)) {
      act = 'cancel_task';
    } else if (RegExp(r'\b(выполни|выполнил|выполнила|готово|сделал|сделала|отметь)\b')
            .hasMatch(lower) &&
        lower.contains('задач')) {
      act = 'complete_task';
    } else if (RegExp(r'\b(разбей|разбить|разложи|раздели)\b')
        .hasMatch(lower)) {
      if (RegExp(r'\bцел').hasMatch(lower)) {
        act = 'split_goal';
      } else if (lower.contains('задач')) {
        act = 'split_task';
      } else if (lower.contains('событ') || lower.contains('встреч')) {
        act = 'split_event';
      }
    }
    if (act != null) {
      // Название — текст в кавычках либо остаток фразы без слов команды.
      final qm = RegExp(r'[«"“„]([^»"“”„]+)[»"“”]').firstMatch(rawText);
      String title;
      if (qm != null && qm.group(1)!.trim().isNotEmpty) {
        title = qm.group(1)!.trim();
      } else {
        title = lower
            .replaceAll(
                RegExp(
                    r'\b(удали\w*|убери\w*|сотри\w*|стереть|отмени\w*|сними\w*|'
                    r'выполни\w*|выполнил\w*|выполнила|готово|сделал\w*|отметь\w*|'
                    r'разбей\w*|разбить|разложи\w*|раздели\w*|задач\w*|цел\w*|'
                    r'событ\w*|встреч\w*|заметк\w*|выполнени\w*|отметк\w*|'
                    r'на\s+задачи|на\s+шаги|пожалуйста)\b'),
                ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (title.isNotEmpty) {
          title = title[0].toUpperCase() + title.substring(1);
        }
      }
      if (title.isEmpty) return null;
      return {'action': act, 'title': title, 'text': rawText};
    }

    String action;
    if (lower.contains('позвонить') || lower.contains('позвони')) {
      action = 'add_event';
    } else if (lower.contains('встреч')) {
      action = 'add_event';
    } else if (RegExp(r'\bсобыт').hasMatch(lower)) {
      action = 'add_event';
    } else if (lower.contains('напомни') || lower.contains('напоминание')) {
      action = 'add_task';
    } else if (lower.contains('задач')) {
      action = 'add_task';
    } else if (lower.contains('заметк')) {
      action = 'add_note';
    } else if (RegExp(r'\bцел').hasMatch(lower) &&
        (lower.contains('добав') ||
            lower.contains('созда') ||
            lower.contains('новая'))) {
      action = 'add_goal';
    } else {
      return null;
    }

    // Текст в кавычках («...», "...") — готовое название целиком.
    String? quoted;
    final qm =
        RegExp(r'[«"“„]([^»"“”„]+)[»"“”]').firstMatch(rawText);
    if (qm != null) {
      final q = qm.group(1)!.trim();
      if (q.isNotEmpty) quoted = q;
    }

    final cuts = <String>[];
    final dateHit = _extractDate(lower, now);
    DateTime? date;
    if (dateHit != null) {
      date = dateHit.date;
      cuts.addAll(dateHit.cuts);
    }
    String? time;
    final timeHit = _extractTime(lower);
    if (timeHit != null) {
      time = timeHit.time;
      cuts.add(timeHit.matched);
    }

    // Точный дедлайн: дата/время ПОСЛЕ слова «deadline»/«дедлайн»
    // задают дедлайн напрямую и важнее остальных упоминаний даты.
    // Только время — значит сегодня в это время.
    final dlMatch = RegExp(r'\b(?:deadline|дедлайн)\w*').firstMatch(lower);
    if (dlMatch != null) {
      final after = lower.substring(dlMatch.end);
      final dlDateHit = _extractDate(after, now);
      final dlTime = _extractDeadlineTime(after);
      if (dlDateHit != null || dlTime != null) {
        // Весь хвост «deadline …» вырезаем из названия.
        cuts.add(rawText.substring(dlMatch.start));
        date = dlDateHit?.date ?? now;
        time = dlTime ?? '18:00';
      }
    }

    String title;
    if (quoted != null) {
      // Кавычки: название = текст в кавычках как есть (с большой буквы),
      // слова даты из него НЕ вырезаем — пользователь назвал событие так.
      title = quoted[0].toUpperCase() + quoted.substring(1);
    } else {
      title = _cleanTitle(rawText, cuts);
      if (action == 'add_event' &&
          (lower.contains('позвонить') || lower.contains('позвони'))) {
        // «позвонить маме» — сохраняем глагол в названии события.
        final callIdx = lower.indexOf('позвон');
        var rest = rawText.substring(callIdx);
        for (final c in cuts) {
          rest = rest.replaceAll(
              RegExp(RegExp.escape(c), caseSensitive: false), ' ');
        }
        rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (rest.isNotEmpty) title = rest[0].toUpperCase() + rest.substring(1);
      }
    }
    if (title.isEmpty) return null;

    // Приоритет из слов «срочно»/«важно» (и обратных) — для задач,
    // событий и целей одинаково.
    String? priority;
    if (RegExp(r'не\s*(срочн|важн)|неспешн').hasMatch(lower)) {
      priority = 'low';
    } else if (RegExp(r'\b(срочн|важн|приоритет)').hasMatch(lower)) {
      priority = 'high';
    }

    final res = <String, dynamic>{
      'action': action,
      'title': title,
      // Исходная фраза — контекст для стора (поиск блока цели и т.п.).
      'text': rawText,
    };
    if (date != null) res['date'] = _iso(date);
    if (priority != null) res['priority'] = priority;
    if (time != null) {
      res['time'] = time;
    } else if (action == 'add_event' && date != null) {
      res['time'] = '12:00';
    }
    return res;
  }
}
