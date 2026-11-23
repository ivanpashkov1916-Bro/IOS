/// Стор приложения: состояние, операции CRUD, архивация, статистика,
/// выполнение команд ассистента. Данные сохраняются в sqflite.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'import_tasks.dart';
import 'models.dart';
import 'services/alarm_service.dart';
import 'services/custom_commands.dart';
import 'services/diag_log.dart';
import 'services/notification_service.dart';
import 'util.dart';

/// Стабильный int-id уведомления из строкового ключа
/// (API flutter_local_notifications v17 принимает только int).
int notificationIdOf(String key) => key.hashCode & 0x7fffffff;

class PeriodStat {
  final int done;
  final int total;
  final int missed;
  const PeriodStat(this.done, this.total, [this.missed = 0]);
  double get ratio => total == 0 ? 0 : done / total;
  int get percent => (ratio * 100).round();
}

/// Запись экрана «Оповещения»: просрочки, приближающиеся дедлайны,
/// невыполненные ежедневные действия, перегрузка плана.
class AlertItem {
  final String kind; // 'overdue' | 'soon' | 'habit' | 'overload'
  final String title;
  final String detail;
  const AlertItem(this.kind, this.title, this.detail);
}

/// Границы периодов статистики: [начало, конец).
List<({String name, DateTime from, DateTime to})> statPeriods([DateTime? now]) {
  final n = now ?? DateTime.now();
  final dayStart = DateTime(n.year, n.month, n.day);
  final end = dayStart.add(const Duration(days: 1));
  final weekStart = dayStart.subtract(Duration(days: n.weekday - 1));
  final monthStart = DateTime(n.year, n.month, 1);
  final qMonth = ((n.month - 1) ~/ 3) * 3 + 1;
  final quarterStart = DateTime(n.year, qMonth, 1);
  final yearStart = DateTime(n.year, 1, 1);
  return [
    (name: 'День', from: dayStart, to: end),
    (name: 'Неделя', from: weekStart, to: end),
    (name: 'Месяц', from: monthStart, to: end),
    (name: 'Квартал', from: quarterStart, to: end),
    (name: 'Год', from: yearStart, to: end),
  ];
}

class AppStore extends ChangeNotifier {
  List<Note> notes = [];
  List<Task> tasks = [];
  List<Goal> goals = [];
  List<EventItem> events = [];
  List<TaskStep> steps = [];
  List<FeedbackEntry> feedback = [];
  // Награды за продуктивные дни (выбор или пропуск на экране «Сегодня»).
  List<DayReward> dayRewards = [];

  /// Посуточный журнал закреплённых (ежедневных) задач: учёт выполнения
  /// ведётся за каждый день независимо от наличия дедлайна у задачи.
  List<PinLog> pinLogs = [];

  /// Записи финансового учёта (экран «Финансы» из «Статистики»).
  List<FinEntry> finEntries = [];

  /// Записи дневника: итоги дня, сессии дневника наблюдений, практики.
  List<DiaryEntry> diaryEntries = [];

  /// Активы и пассивные расходы (финучёт): регулярные статьи с
  /// периодичностью и психоэмоциональной градацией.
  List<FinPassive> finPassive = [];

  /// Планируемые покупки (финучёт): цена, цель, срок, довод.
  List<FinPurchase> finPurchases = [];

  /// Обновляемый банк вопросов собеседника-наблюдателя (дневник
  /// наблюдений). Редактируется в приложении, входит в выгрузку.
  List<PsyQuestion> psyQuestions = [];

  /// Ресурсы задач (блок «Ресурсы» в карточке задачи).
  List<TaskResource> resources = [];

  /// Таймеры выполнения задач (секундомер в карточке): taskId -> старт.
  /// В БД не пишется: это живой процесс; по остановке минуты
  /// суммируются в actualMin («итого»).
  final Map<String, DateTime> taskTimers = {};

  /// Масштаб шрифта на всех экранах (0.8–1.3, шаг стандартных
  /// градаций). Сохраняется в настройках, применяется глобально
  /// через MediaQuery в корне приложения.
  double fontScale = 1.0;

  /// Установить масштаб шрифта (стандартные градации: 80/90/100/115/130%).
  Future<void> setFontScale(double v) async {
    fontScale = v.clamp(0.7, 1.8);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('fontScale', fontScale);
    } catch (_) {}
  }

  /// Сохранить работающие таймеры задач (старт -> ISO): таймер
  /// продолжает идти при сворачивании и перезапуске приложения,
  /// тайминг не сбивается.
  Future<void> _persistTaskTimers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, String>{
        for (final e in taskTimers.entries)
          e.key: e.value.toIso8601String(),
      };
      await prefs.setString('taskTimers', jsonEncode(m));
    } catch (_) {}
  }

  final notifications = NotificationService();

  /// Все напоминания можно отключить одним переключателем.
  bool remindersEnabled = true;

  /// Дублировать напоминания о горящих дедлайнах системным будильником
  /// («Часы» телефона) — резервный канал, если push не сработал.
  bool alarmEnabled = true;

  /// Запрос навигации на вкладку «Цели» с раскрытой шкалой шагов задачи
  /// (тап по задаче на экране «Задачи»). Не сохраняется между запусками.
  String? focusGoalId;
  String? focusTaskId;
  int? tabRequest;

  /// Тап по задаче на экране «Задачи»: перейти на вкладку «Цели» и
  /// показать под её целью шкалу шагов, ведущих к выполнению задачи.
  void focusTaskSteps(Task t) {
    focusTaskId = t.id;
    String? gid;
    if (t.goalId.isNotEmpty) {
      gid = t.goalId;
    } else {
      final b = blockIdOf(t).isNotEmpty ? blockIdOf(t) : t.linkedBlock;
      if (b.isNotEmpty) {
        for (final g in goals) {
          if (g.externalId == 'block:$b') {
            gid = g.id;
            break;
          }
        }
      }
    }
    focusGoalId = gid;
    tabRequest = 4; // вкладка «Цели»
    notifyListeners();
  }

  void consumeTabRequest() => tabRequest = null;

  /// Тап по задаче внутри блока на экране «Цели»: показать под шкалой
  /// цели шкалу шагов этой задачи БЕЗ перехода между вкладками.
  void peekTaskSteps(Task t) {
    focusTaskId = t.id;
    focusGoalId = null;
    notifyListeners();
  }

  /// Запрос перехода на вкладку (Сегодня 0 … Путь 5 … Ассистент 7) —
  /// используется статистикой «Пропущено всего» для перехода
  /// к пропущенному пункту.
  void requestTab(int tab) {
    tabRequest = tab;
    notifyListeners();
  }

  void clearTaskFocus() {
    focusTaskId = null;
    focusGoalId = null;
    notifyListeners();
  }

  /// Задача, чья шкала шагов сейчас раскрыта на экране «Цели».
  Task? get focusTask {
    for (final t in tasks) {
      if (t.id == focusTaskId) return t;
    }
    return null;
  }

  /// Последняя созданная сущность (для уточняющих вопросов после добавления:
  /// ресурсы и шаги). UI показывает диалог и очищает поле.
  ({String kind, String id})? justCreated;

  void clearJustCreated() => justCreated = null;

  // ---------- Диалоговый сценарий ассистента (цель -> задачи -> шаги) ----------
  /// Активный этап сценария: null — не активен;
  /// 'askBlock' — ждём название блока для новой цели;
  /// 'goalTasks' — ждём список задач, из которых состоит цель/событие;
  /// 'askSteps' — ждём «да/нет» на вопрос о шагах для задач;
  /// 'taskSteps' — ждём шаги для задачи flowTaskIds[flowTaskIndex].
  /// Пока этап активен, ввод пользователя в чате трактуется как ОТВЕТ
  /// на вопрос ассистента, а не как новая команда.
  String? flowStage;
  String? flowGoalId;
  DateTime? flowEventStart; // для разбиения события: дедлайн задач подготовки
  String flowEventTitle = '';
  List<String> flowTaskIds = [];
  int flowTaskIndex = 0;

  void _resetFlow() {
    flowStage = null;
    flowGoalId = null;
    flowEventStart = null;
    flowEventTitle = '';
    flowTaskIds = [];
    flowTaskIndex = 0;
    notifyListeners();
  }

  bool get flowActive => flowStage != null;

  /// Закреплённый файл «Стратегии на год» (переживает перезапуск приложения).
  List<StrategyTask> importedTasks = [];
  String? importedFileName;

  /// Исходный текст закреплённого файла стратегии — включается в полную
  /// выгрузку, чтобы после восстановления экран «Стратегия» выглядел
  /// так же, как на момент выгрузки.
  String? strategyRaw;

  /// Временной интервал планирования из загруженного файла (period.start /
  /// period.end). null — файл без явного интервала: шкалы на один год.
  DateTime? importedPeriodStart;
  DateTime? importedPeriodEnd;

  /// Горизонт шкал времени (экран «Цели», бары с чекпоинтами задач):
  /// интервал из загруженного файла, иначе год от сегодняшнего дня.
  /// Границы расширяются так, чтобы ВСЕ задачи, события и цели
  /// попадали на шкалу своими датами.
  ({DateTime start, DateTime end}) planRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var start = importedPeriodStart ?? today;
    var end = importedPeriodEnd ?? today.add(const Duration(days: 365));
    // Ничего не должно свалиться за края шкалы.
    if (today.isBefore(start)) start = today;
    if (end.isBefore(today)) end = today;
    for (final t in tasks) {
      final dl = t.deadline;
      if (dl != null && dl.isAfter(end)) end = dl;
      if (t.createdAt.isBefore(start)) start = t.createdAt;
    }
    for (final e in events) {
      if (e.start.isAfter(end)) end = e.start;
      if (e.start.isBefore(start)) start = e.start;
    }
    for (final g in goals) {
      final gEnd = g.createdAt.add(Duration(days: g.horizonDays));
      if (gEnd.isAfter(end)) end = gEnd;
      if (g.createdAt.isBefore(start)) start = g.createdAt;
    }
    return (start: DateTime(start.year, start.month, start.day), end: end);
  }

  /// ID задач, для которых поставлен системный будильник в «Часах».
  /// Нужно, чтобы после выполнения/архивации задачи снять именно его.
  final Set<String> _armedAlarms = {};

  Future<void> _markAlarmArmed(String taskId) async {
    if (_armedAlarms.add(taskId)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            'armedDeadlineAlarms', _armedAlarms.toList());
      } catch (_) {}
    }
  }

  /// Снимает системный будильник задачи, если он ставился: прозвеневший
  /// (или ставший ненужным) разовый будильник удаляется из «Часов».
  /// Срабатывает только для будильника, созданного для этой задачи.
  Future<void> _dismissTaskAlarm(Task t) async {
    if (!_armedAlarms.remove(t.id)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'armedDeadlineAlarms', _armedAlarms.toList());
    } catch (_) {}
    // Поиск по подписи: метка «Дедлайн: <название>» совпадает и у ручного
    // будильника, и у автоматического «(через N мин)» — снимутся оба,
    // и только те, что созданы для этой задачи.
    await AlarmService.dismissAlarm('Дедлайн: ${t.title}');
  }

  /// Режим «выходной»: сегодня отдыхаем, планы сдвинуты на завтра.
  bool dayOffMode = false;

  /// Переносит все невыполненные задачи и события сегодняшнего дня
  /// на завтра (сохраняя время), сливаясь с уже существующими планами
  /// завтрашнего дня. Ежедневным задачам сегодняшний день помечается
  /// «выходным» — пропуск не засчитывается. Возвращает сводку.
  Future<String> shiftPlansForward() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var movedTasks = 0;
    var movedEvents = 0;
    for (final t in tasks) {
      if (t.isArchived || t.isDone) continue;
      final dl = t.deadline;
      if (dl == null) continue;
      final dlDay = DateTime(dl.year, dl.month, dl.day);
      if (dlDay != today) continue;
      t.deadline = dl.add(const Duration(days: 1));
      if (t.recurDaily) {
        final key = fmtDate(today);
        if (!t.dayOffDates.contains(key)) t.dayOffDates.add(key);
      }
      movedTasks++;
      unawaited(AppDb.instance
          .updateRow('tasks', t.toMap(), t.id)
          .catchError((_) {}));
    }
    for (final e in events) {
      if (e.isArchived) continue;
      final sDay = DateTime(e.start.year, e.start.month, e.start.day);
      if (sDay != today) continue;
      e.start = e.start.add(const Duration(days: 1));
      movedEvents++;
      unawaited(AppDb.instance
          .updateRow('events', e.toMap(), e.id)
          .catchError((_) {}));
    }
    notifyListeners();
    return 'Перенесено на завтра: задач — $movedTasks, событий — $movedEvents.';
  }

  /// Включить режим «выходной»: планы сегодняшнего дня уезжают на завтра.
  Future<String> enterDayOff() async {
    dayOffMode = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dayOffMode', true);
    } catch (_) {}
    return shiftPlansForward();
  }

  /// Выйти из режима «выходной» (без сдвига планов).
  Future<void> exitDayOff() async {
    dayOffMode = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dayOffMode', false);
    } catch (_) {}
  }

  Future<void> load() async {
    final db = AppDb.instance;
    notes = (await db.all('notes')).map(Note.fromMap).toList();
    tasks = (await db.all('tasks')).map(Task.fromMap).toList();
    goals = (await db.all('goals')).map(Goal.fromMap).toList();
    events = (await db.all('events')).map(EventItem.fromMap).toList();
    steps = (await db.all('task_steps')).map(TaskStep.fromMap).toList();
    feedback = (await db.all('feedback')).map(FeedbackEntry.fromMap).toList();
    dayRewards = (await db.all('day_rewards')).map(DayReward.fromMap).toList();
    pinLogs = (await db.all('pin_log')).map(PinLog.fromMap).toList();
    finEntries = (await db.all('finance_entries')).map(FinEntry.fromMap).toList();
    resources =
        (await db.all('task_resources')).map(TaskResource.fromMap).toList();
    diaryEntries =
        (await db.all('diary_entries')).map(DiaryEntry.fromMap).toList();
    finPassive =
        (await db.all('fin_passive')).map(FinPassive.fromMap).toList();
    finPurchases =
        (await db.all('fin_purchases')).map(FinPurchase.fromMap).toList();
    psyQuestions =
        (await db.all('psy_questions')).map(PsyQuestion.fromMap).toList();
    // Первый запуск после появления дневника: наполняем банк вопросов
    // стартовым набором (дальше он полностью в руках пользователя).
    if (psyQuestions.isEmpty) await _seedPsyQuestions();
    // Усиление банка (v2): досыпаем вторую порцию вопросов тем, у кого
    // банк уже был засеян первой версией. Одноразово, по флагу в prefs.
    await _seedPsyQuestionsV2();
    // Восстанавливаем закреплённый файл стратегии
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('strategyJson');
      final name = prefs.getString('strategyFileName');
      if (raw != null && raw.isNotEmpty) {
        final plan = parseStrategyPlan(raw);
        importedTasks = plan.tasks;
        importedFileName = name;
        strategyRaw = raw;
        // Временной интервал из файла (если указан) — шкалы целей
        // строятся по нему, а не по умолчанию в один год.
        importedPeriodStart = DateTime.tryParse(plan.periodStart);
        importedPeriodEnd = DateTime.tryParse(plan.periodEnd);
      }
      remindersEnabled = prefs.getBool('remindersEnabled') ?? true;
      alarmEnabled = prefs.getBool('alarmEnabled') ?? true;
      dayOffMode = prefs.getBool('dayOffMode') ?? false;
      fontScale = prefs.getDouble('fontScale') ?? 1.0;
      _armedAlarms
        ..clear()
        ..addAll(prefs.getStringList('armedDeadlineAlarms') ?? const []);
      // Таймеры выполнения задач переживают сворачивание и перезапуск:
      // старт хранится в prefs, прошедшее время считается от него.
      taskTimers.clear();
      final rawTimers = prefs.getString('taskTimers');
      if (rawTimers != null && rawTimers.isNotEmpty) {
        try {
          final m = jsonDecode(rawTimers);
          if (m is Map) {
            m.forEach((k, v) {
              final dt = DateTime.tryParse(v.toString());
              if (dt != null) taskTimers[k.toString()] = dt;
            });
          }
        } catch (_) {}
      }
    } catch (_) {
      // битый закреплённый файл — просто игнорируем, приложение не падает
    }
    await CustomCommands.load();
    await checkDailyRollover();
    notifyListeners();
  }

  // ---------- Ежедневный ролловер: пропуски и привычки ----------
  /// Вызывается при загрузке. Переносит просроченные ежедневные задачи на
  /// сегодня (+missedCount), сбрасывает привычки на новый день, считает
  /// пропуски и шлёт сводное критическое уведомление со звуком.
  Future<void> checkDailyRollover() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var missedTasks = 0;
    var missedHabits = 0;

    for (final t in tasks) {
      if (!t.recurDaily || t.isArchived) continue;
      final dl = t.deadline;
      if (dl == null) continue;
      final dlDay = DateTime(dl.year, dl.month, dl.day);
      if (dlDay.isBefore(today) && !t.isDone) {
        // День пропуска был отмечен как «выходной» — переносим без пропуска.
        final hadDayOff = t.dayOffDates.contains(fmtDate(dlDay));
        if (!hadDayOff) {
          t.missedCount++;
          missedTasks++;
        }
        // Вчерашняя ежедневная задача не выполнена -> пропуск + перенос.
        DiagLog.add('rollover',
            'перенос «${t.title}» с ${fmtDate(dlDay)} на сегодня (пропуск: ${!hadDayOff})');
        t.deadline = DateTime(today.year, today.month, today.day, 20);
        await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
        await notifications.cancel(notificationIdOf('${t.id}:30min'));
        // Просроченный системный будильник дедлайна снимаем — он
        // не должен оставаться висеть в «Часах» отключённым.
        await _dismissTaskAlarm(t);
        await _scheduleTaskReminder(t);
      }
    }

    // Самолечение от дублей ежедневных серий: если по какой-то причине
    // накопилось несколько АКТИВНЫХ экземпляров одной ежедневной задачи
    // (одно название), оставляем один — с ближайшим дедлайном,
    // остальные уходят в архив (не удаляются: их отметки остаются
    // в истории и статистике).
    final seenDaily = <String, Task>{};
    final dailyActive = tasks
        .where((t) =>
            !t.isArchived &&
            !t.purged &&
            !t.isDone &&
            (t.recurDaily || t.horizon == 'daily'))
        .toList()
      ..sort((a, b) =>
          (a.deadline ?? a.createdAt).compareTo(b.deadline ?? b.createdAt));
    for (final t in dailyActive) {
      final prev = seenDaily[t.title];
      if (prev == null) {
        seenDaily[t.title] = t;
      } else {
        t.isArchived = true;
        await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
      }
    }

    // Закреплённые задачи (пин на «Сегодня», НЕ серии recurDaily):
    // ежедневные — выполнена вчера -> сегодня снова активна; не выполнена
    // -> пропуск (раз в день, «выходной» не считается). Учёт посуточный
    // через pin_log — независимо от наличия дедлайна.
    final yesterday = today.subtract(const Duration(days: 1));
    for (final t in tasks) {
      if (!t.isPinned || t.recurDaily || t.horizon == 'daily') continue;
      if (t.isDone) {
        final da = t.doneAt;
        if (da != null &&
            DateTime(da.year, da.month, da.day).isBefore(today)) {
          // Отмечена раньше (лог выполнения записан в момент отметки) —
          // новые сутки: задача снова на экране «Сегодня».
          t.isDone = false;
          t.isArchived = false;
          t.doneAt = null;
          t.onTime = -1;
          await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
          notifyListeners();
        }
      } else if (!t.isArchived) {
        final createdDay =
            DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
        if (createdDay.isBefore(today) &&
            !hasPinLog(t.id, yesterday) &&
            !t.dayOffDates.contains(fmtDate(yesterday))) {
          t.missedCount++;
          missedTasks++;
          await _logPinDay(t, yesterday, false);
          await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
        }
      }
    }

    for (final g in goals) {
      if (!g.recurDaily || g.isArchived) continue;
      final last = g.lastDoneAt ?? g.createdAt;
      final lastDay = DateTime(last.year, last.month, last.day);
      if (lastDay.isBefore(today)) {
        // Вчера (или раньше) привычка не была выполнена -> пропуск,
        // но не чаще одного раза в день (защита от повторного запуска),
        // и не за день, отмеченный «выходным».
        final lm = g.lastMissAt;
        final countedToday =
            lm != null && DateTime(lm.year, lm.month, lm.day) == today;
        final yesterday = today.subtract(const Duration(days: 1));
        final hadDayOff = g.dayOffDates.contains(fmtDate(yesterday));
        if (!g.isDone && !countedToday && !hadDayOff) {
          g.missedCount++;
          g.lastMissAt = now;
          missedHabits++;
        }
        // Новый день — сбрасываем отметку выполнения.
        if (g.isDone) {
          g.isDone = false;
          await AppDb.instance.updateRow('goals', g.toMap(), g.id);
        } else if (!countedToday) {
          await AppDb.instance.updateRow('goals', g.toMap(), g.id);
        }
      }
    }

    final overdue = activeTasks
        .where((t) => t.deadline != null && t.deadline!.isBefore(now) && !t.isDone)
        .length;

    if (missedTasks + missedHabits + overdue > 0) {
      final parts = <String>[
        if (overdue > 0) 'просрочено задач: $overdue',
        if (missedTasks > 0) 'пропущено ежедневных задач: $missedTasks',
        if (missedHabits > 0) 'пропущено привычек: $missedHabits',
      ];
      await notifications.showCriticalNow(
        id: notificationIdOf('critical:rollover'),
        title: 'Внимание: есть пропуски',
        body: parts.join(', '),
      );
    }
    if (missedTasks + missedHabits > 0) notifyListeners();
  }

  /// Текущие критические оповещения для экрана «Оповещения».
  List<AlertItem> criticalAlerts() {
    final now = DateTime.now();
    final soon = now.add(const Duration(hours: 24));
    final list = <AlertItem>[];
    for (final t in activeTasks) {
      final dl = t.deadline;
      if (dl == null || t.isDone) continue;
      if (dl.isBefore(now)) {
        list.add(AlertItem('overdue', t.title,
            'Дедлайн был ${fmtDateTime(dl)}${t.missedCount > 0 ? ' · пропусков: ${t.missedCount}' : ''}'));
      } else if (dl.isBefore(soon)) {
        list.add(AlertItem('soon', t.title, 'Дедлайн ${fmtDateTime(dl)}'));
      }
    }
    for (final g in activeGoals) {
      if (g.recurDaily && !g.isDone) {
        list.add(AlertItem('habit', g.title,
            'Ежедневная привычка сегодня не выполнена${g.missedCount > 0 ? ' · пропусков: ${g.missedCount}' : ''}'));
      }
    }
    // Перегрузка плана: на ближайшие дни приходится >15 задач/событий в день —
    // сроки становятся критичными, предлагаем «план кинжал».
    if (overloadPerDay() > 15) {
      list.add(AlertItem('overload', 'График перегружен',
          'У тебя что-то случилось? Нужна помощь? Составим план кинжал? '
          'Задач и событий на день: ${overloadPerDay()}'));
    }
    // Просрочки вверху, затем перегруз, ближайшие дедлайны, привычки.
    int rank(String k) =>
        k == 'overdue' ? 0 : (k == 'overload' ? 1 : (k == 'soon' ? 2 : 3));
    list.sort((a, b) => rank(a.kind).compareTo(rank(b.kind)));
    return list;
  }

  /// Среднее число задач и событий на день в ближайшие 3 дня.
  int overloadPerDay() {
    final now = DateTime.now();
    var count = 0;
    for (var i = 0; i < 3; i++) {
      final day = now.add(Duration(days: i));
      count += tasksForDay(day).length + eventsForDay(day).length;
    }
    return (count / 3).ceil();
  }

  /// Задачи, привязанные к цели: явно (goalId), через блок годового плана
  /// или через ручную связь «С каким блоком связать?» (linkedBlock).
  List<Task> tasksForGoal(Goal g) {
    final isBlock = g.externalId.startsWith('block:');
    final blockId = isBlock ? g.externalId.substring(6) : '';
    return tasks
        .where((t) =>
            !t.purged &&
            (t.goalId == g.id ||
            (isBlock &&
                ((t.goalId.isEmpty && t.block == blockId) ||
                    t.linkedBlock == blockId))))
        .toList();
  }

  // ---------- Заметки ----------
  Future<void> addNote(Note n) async {
    notes.insert(0, n);
    await AppDb.instance.insert('notes', n.toMap());
    notifyListeners();
  }

  Future<void> updateNote(Note n) async {
    await AppDb.instance.updateRow('notes', n.toMap(), n.id);
    notifyListeners();
  }

  Future<void> archiveNote(String id) => _archive(notes, id, 'notes');
  Future<void> restoreNote(String id) => _restore(notes, id, 'notes');

  // ---------- Задачи ----------
  Future<void> addTask(Task t) async {
    tasks.insert(0, t);
    await AppDb.instance.insert('tasks', t.toMap());
    await _scheduleTaskReminder(t);
    // Авто-шаги: всё, что в названии после «:», раскладываем на шкалу
    // отдельными шагами (слова разделяются по «и», запятым, точкам с запятой).
    await seedStepsFromTitle(t);
    justCreated = (kind: 'task', id: t.id);
    notifyListeners();
  }

  Future<void> updateTask(Task t) async {
    // Дедлайн мог измениться: старый системный будильник задачи молча
    // снимаем (без открытия «Часов»). Новый НЕ ставим автоматически —
    // будильник ставится только вручную из меню задачи.
    if (_armedAlarms.contains(t.id)) {
      await _dismissTaskAlarm(t);
    }
    await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
    await notifications.cancel(notificationIdOf('${t.id}:30min'));
    if (!t.isDone && !t.isArchived) await _scheduleTaskReminder(t);
    notifyListeners();
  }

  /// Выполненная задача уходит в архив (по ТЗ). Повторный тап возвращает её.
  /// Ежедневная задача (recurDaily) дополнительно создаёт экземпляр на завтра.
  /// ОПТИМИСТИЧНО: UI обновляется мгновенно, БД и напоминания — в фоне,
  /// чтобы чекбокс никогда не «подвисал».
  void toggleTaskDone(String id) {
    final t = tasks.firstWhere((x) => x.id == id);
    // Ежедневная задача с шагом < 100%: отметка добавляет процент,
    // полное завершение — только на 100%.
    if (!t.isDone && t.recurDaily && t.pctStep < 100) {
      t.progressPct = (t.progressPct + t.pctStep).clamp(0, 100);
      if (t.progressPct < 100) {
        notifyListeners();
        unawaited(AppDb.instance
            .updateRow('tasks', t.toMap(), t.id)
            .catchError((_) {}));
        return;
      }
      t.progressPct = 0; // на 100% — обычное завершение и новый день
    }
    if (t.isDone) {
      t.isDone = false;
      t.isArchived = false;
      t.doneAt = null;
      t.onTime = -1;
      notifyListeners();
      unawaited(_persistTaskUndone(t));
      // Снятие отметки у закреплённой задачи — откат отметки дня.
      if (t.isPinned && !t.recurDaily && t.horizon != 'daily') {
        unawaited(_removePinLog(t.id, DateTime.now()));
      }
    } else {
      final now = DateTime.now();
      t.isDone = true;
      t.isArchived = true;
      t.doneAt = now;
      // Своевременность: без дедлайна считаем выполненным вовремя.
      t.onTime = (t.deadline == null || !now.isAfter(t.deadline!)) ? 1 : 0;
      notifyListeners();
      unawaited(_persistTaskDone(t));
      // Закреплённая ежедневная задача: выполнение фиксируется за
      // сегодня, на новые сутки она снова появится активной.
      if (t.isPinned && !t.recurDaily && t.horizon != 'daily') {
        unawaited(_logPinDay(t, now, true));
      }
    }
  }

  Future<void> _persistTaskUndone(Task t) async {
    try {
      await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
      await _scheduleTaskReminder(t);
      // Снятие отметки откатывает прогресс целей-блоков назад —
      // проценты возвращаются ровно на столько, на сколько прибавились.
      await _refreshBlockGoalProgress();
    } catch (_) {}
  }

  Future<void> _persistTaskDone(Task t) async {
    try {
      await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
      await notifications.cancel(notificationIdOf('${t.id}:30min'));
      // Прозвеневший/ненужный системный будильник дедлайна — удаляем.
      await _dismissTaskAlarm(t);
      if (t.recurDaily || t.horizon == 'daily') {
        final now = DateTime.now();
        final tomorrow =
            DateTime(now.year, now.month, now.day, 20).add(const Duration(days: 1));
        // Страховка от дублей: если активный экземпляр этой ежедневной
        // задачи уже есть (повторные отметки, восстановление из архива) —
        // новый НЕ создаём. Раньше каждый цикл отметки плодил копию,
        // и на «Сегодня»/«Календаре» задачи задваивались.
        final hasActiveTwin = tasks.any((x) =>
            x.id != t.id &&
            !x.isArchived &&
            !x.purged &&
            (x.recurDaily || x.horizon == 'daily') &&
            x.title == t.title);
        if (hasActiveTwin) {
          DiagLog.add('daily',
              'двойник уже активен — экземпляр «${t.title}» НЕ создавался');
        }
        if (!hasActiveTwin) {
        final next = Task(
          title: t.title,
          deadline: tomorrow,
          estimateMin: t.estimateMin,
          priority: t.priority,
          externalId: t.externalId,
          block: t.block,
          metric: t.metric,
          importTag: t.importTag,
          recurDaily: t.recurDaily,
          isPinned: t.isPinned,
          isKeyAction: t.isKeyAction,
          goalId: t.goalId,
          horizon: 'daily',
          comment: t.comment,
          pctStep: t.pctStep,
        );
        tasks.insert(0, next);
        await AppDb.instance.insert('tasks', next.toMap());
        DiagLog.add('daily',
            'выполнена «${t.title}» — создан экземпляр на ${next.deadline}');
        // Шкала пути и ресурсы переезжают на новый день ВМЕСТЕ
        // с задачей: копируем шаги (названия, порядок, приоритеты,
        // молнии, итерации, «количество раз») и ресурсы. Отметки
        // выполнения и фото сбрасываются — новый день, новые
        // подтверждения.
        for (final st in stepsForTask(t.id)) {
          final ns = TaskStep(
            taskId: next.id,
            title: st.title,
            ord: st.ord,
            priority: st.priority,
            isKeyAction: st.isKeyAction,
            iterations: st.iterations,
            times: st.times,
          );
          steps.add(ns);
          await AppDb.instance.insert('task_steps', ns.toMap());
        }
        for (final r in resourcesForTask(t.id)) {
          final nr = TaskResource(taskId: next.id, title: r.title, ord: r.ord);
          resources.add(nr);
          await AppDb.instance.insert('task_resources', nr.toMap());
        }
        notifyListeners();
        }
      }
      await _refreshBlockGoalProgress();
    } catch (_) {}
  }

  Future<void> archiveTask(String id) async {
    final idx = tasks.indexWhere((x) => x.id == id);
    if (idx >= 0) await _dismissTaskAlarm(tasks[idx]);
    await _archive(tasks, id, 'tasks');
  }
  Future<void> restoreTask(String id) async {
    await _restore(tasks, id, 'tasks');
    final t = tasks.firstWhere((x) => x.id == id);
    if (!t.isDone) await _scheduleTaskReminder(t);
  }

  // ---------- Цели ----------
  Future<void> addGoal(Goal g) async {
    goals.insert(0, g);
    await AppDb.instance.insert('goals', g.toMap());
    justCreated = (kind: 'goal', id: g.id);
    notifyListeners();
  }

  Future<void> updateGoal(Goal g) async {
    await AppDb.instance.updateRow('goals', g.toMap(), g.id);
    notifyListeners();
  }

  /// Достигнутая цель уходит в архив (по ТЗ).
  /// Ежедневная привычка (recurDaily) НЕ архивируется: отмечается выполненной
  /// сегодня, а на новый день отметка сбрасывается в checkDailyRollover().
  /// ОПТИМИСТИЧНО: UI обновляется мгновенно, запись в БД — в фоне.
  void toggleGoalDone(String id) {
    final g = goals.firstWhere((x) => x.id == id);
    if (g.recurDaily) {
      if (g.isDone) {
        g.isDone = false;
      } else {
        g.isDone = true;
        g.lastDoneAt = DateTime.now();
      }
      notifyListeners();
      unawaited(AppDb.instance
          .updateRow('goals', g.toMap(), g.id)
          .catchError((_) {}));
      return;
    }
    if (g.isDone) {
      g.isDone = false;
      g.isArchived = false;
      g.doneAt = null;
      if (g.progress >= 1) g.progress = 0.9;
    } else {
      g.isDone = true;
      g.isArchived = true;
      g.progress = 1;
      g.doneAt = DateTime.now();
    }
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('goals', g.toMap(), g.id).catchError((_) {}));
  }

  /// Дописать строку в комментарий (причина пропуска дедлайна и т.п.).
  /// Параллельно пишется в журнал обратной связи для аудита.
  Future<void> appendTaskComment(String id, String text) async {
    Task? t;
    for (final x in tasks) {
      if (x.id == id) {
        t = x;
        break;
      }
    }
    if (t == null) return;
    t.comment = t.comment.isEmpty ? text : '${t.comment}\n$text';
    await addFeedback(
        text.contains('ричин') ? 'late_reason' : 'comment', t.title, text);
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Шаг процента для ежедневной задачи (выпадающее меню на экране целей).
  Future<void> setTaskPctStep(String id, int step) async {
    final t = tasks.firstWhere((x) => x.id == id);
    t.pctStep = step;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  // ---------- «Выходной» для ежедневных (не считается пропуском) ----------
  /// Отметить день как выходной для ежедневной задачи и записать это
  /// в журнал обратной связи отдельным видом — при аудите «выходной»
  /// разбирается отдельно от причин пропуска.
  Future<void> markTaskDayOff(String id, DateTime day) async {
    final t = tasks.firstWhere((x) => x.id == id);
    final key = fmtDate(day);
    if (!t.dayOffDates.contains(key)) t.dayOffDates.add(key);
    await addFeedback('day_off', t.title, 'Выходной (${fmtDate(day)})');
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Отметить день как выходной для ежедневной привычки (цели).
  Future<void> markGoalDayOff(String id, DateTime day) async {
    final g = goals.firstWhere((x) => x.id == id);
    final key = fmtDate(day);
    if (!g.dayOffDates.contains(key)) g.dayOffDates.add(key);
    await addFeedback('day_off', g.title, 'Выходной (${fmtDate(day)})');
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('goals', g.toMap(), g.id).catchError((_) {}));
  }

  // ---------- Привязка задачи к блоку годового плана ----------
  /// «С каким блоком связать?» — блоки берутся из целей-блоков.
  List<Goal> blockGoals() => goals
      .where((g) => !g.isArchived && g.externalId.startsWith('block:'))
      .toList();

  /// Ручная связь задачи с блоком — записывается в linkedBlock
  /// (исходный блок импорта t.block не трогаем), чтобы связи было
  /// видно и в блоке, и на дереве связей.
  Future<void> linkTaskToBlock(String taskId, String blockId) async {
    final t = tasks.firstWhere((x) => x.id == taskId);
    t.linkedBlock = blockId;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Основной блок задачи: блок явной цели (goalId) или блок импорта.
  String blockIdOf(Task t) {
    if (t.goalId.isNotEmpty) {
      for (final g in goals) {
        if (g.id == t.goalId && g.externalId.startsWith('block:')) {
          return g.externalId.substring(6);
        }
      }
    }
    return t.block;
  }

  /// Нити дерева связей: ключ «A|B» (id блоков, отсортированы) ->
  /// число связанных задач между этими блоками.
  Map<String, int> blockLinks() {
    final res = <String, int>{};
    for (final t in tasks) {
      final a = blockIdOf(t);
      final b = t.linkedBlock;
      if (a.isEmpty || b.isEmpty || a == b) continue;
      final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      res[key] = (res[key] ?? 0) + 1;
    }
    return res;
  }

  // ---------- Блоки на экране целей: добавление / удаление / значок ----------
  /// Добавить свой блок годового плана (цель-блок) с выбранным значком.
  Future<Goal> addBlock(String title, {String icon = ''}) async {
    final g = Goal(
      title: title,
      horizonDays: 365,
      externalId: 'block:U${newId()}',
      icon: icon,
    );
    goals.insert(0, g);
    await AppDb.instance.insert('goals', g.toMap());
    notifyListeners();
    return g;
  }

  /// Удалить блок: сам блок уходит в архив, задачи не удаляются —
  /// у них просто очищается связь с этим блоком.
  Future<void> removeBlock(String goalId) async {
    Goal? g;
    for (final x in goals) {
      if (x.id == goalId) {
        g = x;
        break;
      }
    }
    if (g == null) return;
    final blockId = g.externalId.startsWith('block:')
        ? g.externalId.substring(6)
        : '';
    for (final t in tasks) {
      var changed = false;
      if (blockId.isNotEmpty && t.linkedBlock == blockId) {
        t.linkedBlock = '';
        changed = true;
      }
      if (t.goalId == g.id) {
        t.goalId = '';
        changed = true;
      }
      if (changed) {
        unawaited(
            AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
      }
    }
    await archiveGoal(g.id);
  }

  /// Сменить значок блока.
  Future<void> setGoalIcon(String goalId, String icon) async {
    final g = goals.firstWhere((x) => x.id == goalId);
    g.icon = icon;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('goals', g.toMap(), g.id).catchError((_) {}));
  }

  // ---------- Горящие задачи (блок с бегущим человечком) ----------
  /// Горящие дедлайны и высокий приоритет: просрочено, дедлайн < 24 ч
  /// или высокий приоритет с дедлайном < 48 ч. Сортировка по сроку.
  List<Task> hotTasks() {
    final now = DateTime.now();
    // Слитые однородные задачи в блок «горящие» не попадают —
    // они живут внутри задачи-родителя.
    final list = activeTasks.where((t) {
      if (t.parentTaskId.isNotEmpty) return false;
      final dl = t.deadline;
      if (dl == null) return t.priority == 2 && t.isKeyAction;
      if (dl.isBefore(now)) return true;
      if (dl.isBefore(now.add(const Duration(hours: 24)))) return true;
      return t.priority == 2 &&
          dl.isBefore(now.add(const Duration(hours: 48)));
    }).toList();
    list.sort((a, b) {
      final ad = a.deadline, bd = b.deadline;
      if (ad == null && bd == null) return b.priority.compareTo(a.priority);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return list;
  }

  // ---------- Выполнения ежедневной задачи (суммируются) ----------
  /// Выполненные экземпляры той же ежедневной задачи (по названию),
  /// в хронологическом порядке: сегодняшняя выше, завтрашняя — ниже.
  List<Task> dailyCompletions(Task t) {
    final list = tasks
        .where((x) =>
            x.isDone &&
            (x.recurDaily || x.horizon == 'daily') &&
            x.title == t.title)
        .toList();
    list.sort((a, b) =>
        (a.doneAt ?? a.createdAt).compareTo(b.doneAt ?? b.createdAt));
    return list;
  }

  /// Ежедневная задача уже выполнена СЕГОДНЯ (есть выполненный
  /// экземпляр с тем же названием). По ней экраны «Сегодня», «Задачи»
  /// и «Навыки и привычки» показывают отметку синхронно: активный
  /// экземпляр — уже завтрашний (дедлайн на следующий день), а значок
  /// «сделано сегодня» подтверждает сегодняшнее выполнение.
  bool dailyDoneToday(Task t) {
    if (!t.recurDaily && t.horizon != 'daily') return false;
    final now = DateTime.now();
    return tasks.any((x) =>
        x.isDone &&
        (x.recurDaily || x.horizon == 'daily') &&
        x.title == t.title &&
        x.doneAt != null &&
        isSameDay(x.doneAt!, now));
  }

  // ---------- Шаги задачи (шкала пути) ----------
  List<TaskStep> stepsForTask(String taskId) => steps
      .where((s) => s.taskId == taskId)
      .toList()
    ..sort((a, b) => a.ord.compareTo(b.ord));

  /// Авто-семена: всё, что в названии задачи написано после «:»,
  /// раскладывается на шкалу отдельными шагами. Действия разделяются
  /// по «и», запятым, точкам с запятой и перечислениям.
  /// «реанимация отопления: диагностика и ремонт котла» ->
  /// шаг «диагностика», шаг «ремонт котла».
  Future<void> seedStepsFromTitle(Task t) async {
    if (stepsForTask(t.id).isNotEmpty || !t.title.contains(':')) return;
    final parts = t.title.split(':');
    if (parts.length < 2) return;
    final tail = parts.sublist(1).join(':');
    final items = tail
        .split(RegExp(r'\s+и\s+|[,;•]'))
        .map((e) => e.trim().replaceAll(RegExp(r'[.\s]+$'), ''))
        .where((e) => e.length > 1)
        .toList();
    var ord = 0;
    for (final p in items) {
      await addStep(t.id, p, ord: ord++);
    }
  }

  Future<void> addStep(String taskId, String title,
      {int? ord, int priority = 1, bool isKeyAction = false}) async {
    // В тексте шага может быть указано «N раз» / «N повторений» /
    // «N итераций» — выносим в параметры шага (карточка показывает
    // «итераций» и «раз», ассистент понимает слово «повторений»).
    var clean = title.trim();
    var times = 1;
    var iterations = 1;
    final tm = RegExp(r'(\d+)\s*(повторени\w*|раза?|раз)\b',
            caseSensitive: false)
        .firstMatch(clean);
    if (tm != null) {
      times = (int.tryParse(tm.group(1)!) ?? 1).clamp(1, 999);
      clean = clean.replaceRange(tm.start, tm.end, '').trim();
    }
    final im = RegExp(r'(\d+)\s*итераци\w*\b', caseSensitive: false)
        .firstMatch(clean);
    if (im != null) {
      iterations = (int.tryParse(im.group(1)!) ?? 1).clamp(1, 999);
      clean = clean.replaceRange(im.start, im.end, '').trim();
    }
    clean = clean
        .replaceAll(RegExp(r'[\s,;:()\-]+\$'), '')
        .replaceAll(RegExp(r'^[\s,;:()\-]+'), '')
        .trim();
    if (clean.isEmpty) clean = title.trim();
    final s = TaskStep(
      taskId: taskId,
      title: clean,
      ord: ord ?? stepsForTask(taskId).length,
      priority: priority,
      isKeyAction: isKeyAction,
      iterations: iterations,
      times: times,
    );
    steps.add(s);
    await AppDb.instance.insert('task_steps', s.toMap());
    notifyListeners();
  }

  // ---------- Ресурсы задачи (блок «Ресурсы») ----------
  List<TaskResource> resourcesForTask(String taskId) => resources
      .where((r) => r.taskId == taskId)
      .toList()
    ..sort((a, b) => a.ord.compareTo(b.ord));

  Future<void> addResource(String taskId, String title) async {
    final r = TaskResource(
      taskId: taskId,
      title: title.trim(),
      ord: resourcesForTask(taskId).length,
    );
    if (r.title.isEmpty) return;
    resources.add(r);
    await AppDb.instance.insert('task_resources', r.toMap());
    notifyListeners();
  }

  Future<void> deleteResource(String id) async {
    resources.removeWhere((r) => r.id == id);
    notifyListeners();
    unawaited(
        AppDb.instance.deleteRow('task_resources', id).catchError((_) {}));
  }

  /// Оптимистичный тоггл шага; возвращает шаг (для фото-подтверждения).
  TaskStep toggleStepDone(String stepId) {
    final s = steps.firstWhere((x) => x.id == stepId);
    s.isDone = !s.isDone;
    s.doneAt = s.isDone ? DateTime.now() : null;
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
    // Зависимость карточки от шкалы пути: отмечены ВСЕ шаги ->
    // задача закрывается автоматически (чекпоинт выполнения).
    // Частичное выполнение шагов задачу не закрывает — чекпоинт
    // тогда ставится вручную по усмотрению пользователя.
    if (s.isDone) {
      final sibs = stepsForTask(s.taskId);
      if (sibs.isNotEmpty && sibs.every((x) => x.isDone)) {
        final t = tasks.firstWhere((x) => x.id == s.taskId,
            orElse: () => Task());
        if (t.id == s.taskId && !t.isDone) {
          toggleTaskDone(t.id);
        }
      }
    }
    return s;
  }

  /// «Количество раз» шага (сколько раз повторить), 1..999.
  Future<void> setStepTimes(String stepId, int n) async {
    final s = steps.firstWhere((x) => x.id == stepId, orElse: () => TaskStep());
    if (s.id != stepId) return;
    s.times = n.clamp(1, 999);
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  void setStepPriority(String stepId, int priority) {
    final s = steps.firstWhere((x) => x.id == stepId);
    s.priority = priority;
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  void toggleStepKey(String stepId) {
    final s = steps.firstWhere((x) => x.id == stepId);
    s.isKeyAction = !s.isKeyAction;
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  /// Перетаскивание шагов долгим нажатием: [orderedIds] — новый порядок
  /// сверху вниз. ord пересчитывается 0..n-1 и сохраняется в БД; точки
  /// на шкале пути следуют этому же порядку (сверху вниз = слева
  /// направо). Действует и на шаги, добавленные позже.
  void reorderSteps(String taskId, List<String> orderedIds) {
    var i = 0;
    var changed = false;
    for (final id in orderedIds) {
      final idx = steps.indexWhere((x) => x.id == id && x.taskId == taskId);
      if (idx < 0) continue;
      final s = steps[idx];
      if (s.ord != i) {
        s.ord = i;
        changed = true;
        unawaited(AppDb.instance
            .updateRow('task_steps', s.toMap(), s.id)
            .catchError((_) {}));
      }
      i++;
    }
    if (changed) notifyListeners();
  }

  /// Фото-подтверждение шага. Файл КОПИРУЕТСЯ в документы приложения
  /// (папка photos/): ссылки на кэш камеры/галереи недолговечны, а так
  /// фото живёт вместе с данными и попадает в полную выгрузку.
  Future<void> setStepPhoto(String stepId, String path) async {
    final s = steps.firstWhere((x) => x.id == stepId);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/photos');
      await dir.create(recursive: true);
      final ext = path.contains('.') ? path.split('.').last : 'jpg';
      final dest = '${dir.path}/$stepId.$ext';
      if (path != dest) await File(path).copy(dest);
      s.photoPath = dest;
    } catch (_) {
      // Копирование не удалось — сохраняем исходный путь как есть.
      s.photoPath = path;
    }
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  /// Редактирование названия шага (карандаш между фото и крестиком).
  void updateStepTitle(String stepId, String title) {
    final s = steps.firstWhere((x) => x.id == stepId);
    s.title = title;
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  Future<void> deleteStep(String stepId) async {
    steps.removeWhere((x) => x.id == stepId);
    await AppDb.instance.deleteRow('task_steps', stepId);
    notifyListeners();
  }

  // ---------- Журнал обратной связи (для аудита) ----------
  Future<void> addFeedback(String kind, String itemTitle, String text) async {
    final e = FeedbackEntry(kind: kind, itemTitle: itemTitle, text: text);
    feedback.insert(0, e);
    unawaited(
        AppDb.instance.insert('feedback', e.toMap()).catchError((_) {}));
  }

  // ---------- Награды за продуктивный день (экран «Сегодня») ----------
  static String _rewardDayKey(DateTime day) =>
      DateTime(day.year, day.month, day.day).toIso8601String();

  /// Порог tier (1=60%+, 2=85%+, 3=100%) сегодня уже отмечался —
  /// диалог не дублируем.
  bool hasDayReward(DateTime day, int tier) {
    final key = _rewardDayKey(day);
    return dayRewards.any((r) =>
        DateTime(r.day.year, r.day.month, r.day.day).toIso8601String() ==
            key &&
        r.tier == tier);
  }

  /// Запись выбранной награды (или пропуска) — участвует в статистике
  /// «после каких наград дни продуктивнее» и попадает в выгрузку.
  Future<void> logDayReward({
    required DateTime day,
    required int tier,
    required double pct,
    String reward = '',
    bool skipped = false,
  }) async {
    final r = DayReward(
        day: day, tier: tier, pct: pct, reward: reward, skipped: skipped);
    dayRewards.insert(0, r);
    await addFeedback(
        'reward_choice',
        'День ${fmtDate(day)} (${(pct * 100).round()}%)',
        skipped ? 'награду пропустил(а)' : 'награда: $reward');
    notifyListeners();
    unawaited(
        AppDb.instance.insert('day_rewards', r.toMap()).catchError((_) {}));
  }

  /// Награды за конкретный день (для экрана «Путь» и статистики).
  List<DayReward> rewardsForDay(DateTime day) {
    final key = _rewardDayKey(day);
    return dayRewards
        .where((r) =>
            DateTime(r.day.year, r.day.month, r.day.day).toIso8601String() ==
            key)
        .toList();
  }

  // ---------- Посуточный журнал закреплённых задач ----------
  /// Есть ли отметка за день [day] у задачи [taskId].
  bool hasPinLog(String taskId, DateTime day) {
    final key = _rewardDayKey(day);
    return pinLogs.any((l) =>
        l.taskId == taskId &&
        DateTime(l.day.year, l.day.month, l.day.day).toIso8601String() ==
            key);
  }

  Future<void> _logPinDay(Task t, DateTime day, bool done) async {
    if (hasPinLog(t.id, day)) return;
    final l = PinLog(taskId: t.id, title: t.title, day: day, done: done);
    pinLogs.insert(0, l);
    notifyListeners();
    unawaited(AppDb.instance.insert('pin_log', l.toMap()).catchError((_) {}));
  }

  /// Убрать отметку дня (пользователь снял выполнение закреплённой
  /// задачи в тот же день — отметка откатывается).
  Future<void> _removePinLog(String taskId, DateTime day) async {
    final key = _rewardDayKey(day);
    final doomed = pinLogs
        .where((l) =>
            l.taskId == taskId &&
            DateTime(l.day.year, l.day.month, l.day.day).toIso8601String() ==
                key)
        .toList();
    for (final l in doomed) {
      pinLogs.remove(l);
      unawaited(AppDb.instance.deleteRow('pin_log', l.id).catchError((_) {}));
    }
    if (doomed.isNotEmpty) notifyListeners();
  }

  /// Бар дней закреплённой задачи (как у ежедневной серии, но данные —
  /// из pin_log): зелёный — выполнена, красный — пропущена, серый —
  /// день не наступил / выходной. Интервал: от создания до дедлайна
  /// (не длиннее года) или год от создания.
  List<({DateTime day, bool? done})> pinDayBar(Task t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
    final start = dateOnly(t.createdAt);
    final maxEnd = start.add(const Duration(days: 364));
    var end = t.deadline != null ? dateOnly(t.deadline!) : maxEnd;
    if (end.isAfter(maxEnd)) end = maxEnd;
    if (end.isBefore(today)) end = today;
    final byDay = <String, bool>{};
    for (final l in pinLogs) {
      if (l.taskId != t.id) continue;
      byDay[fmtDate(l.day)] = l.done;
    }
    // Сегодняшняя отметка ещё могла не попасть в журнал (день не
    // закрыт): берём текущее состояние задачи.
    if (t.isDone && t.doneAt != null && isSameDay(t.doneAt!, now)) {
      byDay[fmtDate(today)] = true;
    }
    final daysOff = t.dayOffDates.toSet();
    final res = <({DateTime day, bool? done})>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final k = fmtDate(d);
      if (byDay.containsKey(k)) {
        res.add((day: d, done: byDay[k]));
      } else if (daysOff.contains(k) || !d.isBefore(today)) {
        res.add((day: d, done: null));
      } else {
        res.add((day: d, done: false));
      }
    }
    return res;
  }

  /// «Фактически реализовано за» — минуты из диалога после выполнения
  /// задачи («полтора часа» -> 90). Отображается в карточке: «Итого».
  Future<void> setTaskActualMin(String id, int minutes) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id || minutes <= 0) return;
    t.actualMin = minutes;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  // ---------- Таймер выполнения задачи (секундомер в карточке) ----------
  bool taskTimerRunning(String id) => taskTimers.containsKey(id);

  DateTime? taskTimerStart(String id) => taskTimers[id];

  /// Запуск секундомера. Повторный запуск по той же задаче — ничего
  /// не делает (таймер уже идёт со старого времени). Старт пишется
  /// в настройки: при сворачивании/закрытии приложения отсчёт
  /// продолжается — время считается от сохранённого момента старта.
  void startTaskTimer(String id) {
    final isNew = !taskTimers.containsKey(id);
    taskTimers.putIfAbsent(id, () => DateTime.now());
    notifyListeners();
    if (isNew) unawaited(_persistTaskTimers());
  }

  /// Остановка: прошедшие минуты (минимум 1, если что-то засекли)
  /// ПРИБАВЛЯЮТСЯ к «итого» задачи. Возвращает добавленные минуты.
  Future<int> stopTaskTimer(String id) async {
    final start = taskTimers.remove(id);
    if (start == null) return 0;
    unawaited(_persistTaskTimers());
    final secs = DateTime.now().difference(start).inSeconds;
    final mins = secs <= 0 ? 0 : (secs + 30) ~/ 60; // округление к минуте
    if (mins > 0) {
      final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
      if (t.id == id) {
        t.actualMin += mins;
        unawaited(AppDb.instance
            .updateRow('tasks', t.toMap(), t.id)
            .catchError((_) {}));
      }
    }
    notifyListeners();
    return mins;
  }

  // ---------- Количество итераций шага ----------
  Future<void> setStepIterations(String stepId, int n) async {
    final s = steps.firstWhere((x) => x.id == stepId, orElse: () => TaskStep());
    if (s.id != stepId) return;
    s.iterations = n.clamp(1, 999);
    notifyListeners();
    unawaited(AppDb.instance
        .updateRow('task_steps', s.toMap(), s.id)
        .catchError((_) {}));
  }

  // ---------- Финансовый учёт ----------
  Future<void> addFinEntry(FinEntry e) async {
    finEntries.add(e);
    notifyListeners();
    await AppDb.instance.insert('finance_entries', e.toMap());
  }

  Future<void> deleteFinEntry(String id) async {
    finEntries.removeWhere((e) => e.id == id);
    notifyListeners();
    await AppDb.instance.deleteRow('finance_entries', id);
  }

  /// Редактирование сохранённой записи финучёта: вид, источник/статья,
  /// сумма, блок, заметка меняются на месте (id и дата сохраняются).
  Future<void> updateFinEntry(FinEntry e) async {
    final idx = finEntries.indexWhere((x) => x.id == e.id);
    if (idx < 0) return;
    finEntries[idx] = e;
    notifyListeners();
    await AppDb.instance.updateRow('finance_entries', e.toMap(), e.id);
  }

  /// Уже встречавшиеся источники дохода / статьи расхода — для
  /// подсказок в поле ввода (учёт количества источников).
  List<String> finSources(String kind) {
    final set = <String>{};
    for (final e in finEntries) {
      if (e.kind == kind && e.source.trim().isNotEmpty) {
        set.add(e.source.trim());
      }
    }
    return set.toList()..sort();
  }

  /// Суммы по видам за произвольный интервал (null — за всё время).
  ({double income, double expense}) finTotals({DateTime? from, DateTime? to}) {
    var inc = 0.0, exp = 0.0;
    for (final e in finEntries) {
      if (from != null && e.day.isBefore(from)) continue;
      if (to != null && e.day.isAfter(to)) continue;
      if (e.isIncome) {
        inc += e.amount;
      } else {
        exp += e.amount;
      }
    }
    return (income: inc, expense: exp);
  }

  /// Суммы по источникам (источник -> сумма) для вида kind.
  Map<String, double> finBySource(String kind) {
    final m = <String, double>{};
    for (final e in finEntries) {
      if (e.kind != kind) continue;
      final k = e.source.trim().isEmpty ? 'Без названия' : e.source.trim();
      m[k] = (m[k] ?? 0) + e.amount;
    }
    return m;
  }

  /// Суммы по блокам планирования (код блока -> доход/расход).
  Map<String, ({double income, double expense})> finByBlock() {
    final m = <String, ({double income, double expense})>{};
    for (final e in finEntries) {
      final cur = m[e.block] ?? (income: 0.0, expense: 0.0);
      m[e.block] = e.isIncome
          ? (income: cur.income + e.amount, expense: cur.expense)
          : (income: cur.income, expense: cur.expense + e.amount);
    }
    return m;
  }

  // ---------- Дневник (итоги дня / наблюдения / практики) ----------
  /// Признак задачи «итоги дня»: включён флаг в редакторе задачи ИЛИ
  /// название содержит «итоги дня» (работает любой из двух).
  static bool isDayReviewTask(Task t) =>
      t.isDayReview || t.title.toLowerCase().contains('итоги дня');

  /// Записи дневника за конкретный день (всех видов).
  List<DiaryEntry> diaryForDay(DateTime day) => diaryEntries
      .where((e) => isSameDay(e.day, day))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> addDiaryEntry(DiaryEntry e) async {
    diaryEntries.insert(0, e);
    notifyListeners();
    await AppDb.instance.insert('diary_entries', e.toMap());
  }

  Future<void> updateDiaryEntry(DiaryEntry e) async {
    notifyListeners();
    await AppDb.instance.updateRow('diary_entries', e.toMap(), e.id);
  }

  /// Удаление записи дневника (записи личные — удаляются сразу,
  /// без архива; в полную выгрузку попадают только существующие).
  Future<void> deleteDiaryEntry(String id) async {
    diaryEntries.removeWhere((e) => e.id == id);
    notifyListeners();
    await AppDb.instance.deleteRow('diary_entries', id);
  }

  // ---------- Банк вопросов «Дневника наблюдений» ----------
  /// Активные вопросы банка (отключённые в сессиях не предлагаются).
  List<PsyQuestion> get activePsyQuestions =>
      psyQuestions.where((q) => q.isActive && q.text.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.ord.compareTo(b.ord));

  Future<void> addPsyQuestion(String text, {String category = 'state'}) async {
    final q = PsyQuestion(
      text: text.trim(),
      category: category,
      ord: psyQuestions.length,
    );
    if (q.text.isEmpty) return;
    psyQuestions.add(q);
    notifyListeners();
    await AppDb.instance.insert('psy_questions', q.toMap());
  }

  Future<void> updatePsyQuestion(PsyQuestion q) async {
    notifyListeners();
    await AppDb.instance.updateRow('psy_questions', q.toMap(), q.id);
  }

  Future<void> deletePsyQuestion(String id) async {
    psyQuestions.removeWhere((q) => q.id == id);
    notifyListeners();
    await AppDb.instance.deleteRow('psy_questions', id);
  }

  // ---------- Финучёт: активы / пассивные расходы / покупки ----------
  Future<void> addFinPassive(FinPassive e) async {
    finPassive.add(e);
    notifyListeners();
    await AppDb.instance.insert('fin_passive', e.toMap());
  }

  Future<void> updateFinPassive(FinPassive e) async {
    notifyListeners();
    await AppDb.instance.updateRow('fin_passive', e.toMap(), e.id);
  }

  Future<void> deleteFinPassive(String id) async {
    finPassive.removeWhere((e) => e.id == id);
    notifyListeners();
    await AppDb.instance.deleteRow('fin_passive', id);
  }

  /// Сумма активов ('asset') или пассивных расходов ('expense'),
  /// нормализованная к месяцу — для строк «ИТОГО» и вычета из доходов.
  double passiveMonthly(String kind) {
    var s = 0.0;
    for (final e in finPassive) {
      if (e.kind == kind) s += e.perMonth;
    }
    return s;
  }

  Future<void> addFinPurchase(FinPurchase p) async {
    finPurchases.add(p);
    notifyListeners();
    await AppDb.instance.insert('fin_purchases', p.toMap());
  }

  Future<void> updateFinPurchase(FinPurchase p) async {
    notifyListeners();
    await AppDb.instance.updateRow('fin_purchases', p.toMap(), p.id);
  }

  Future<void> deleteFinPurchase(String id) async {
    finPurchases.removeWhere((p) => p.id == id);
    notifyListeners();
    await AppDb.instance.deleteRow('fin_purchases', id);
  }

  /// Стартовый набор вопросов банка (первый запуск). Триггеры на
  /// эмоциональный отклик: состояние, атрибутика дня, инсайты.
  Future<void> _seedPsyQuestions() async {
    const seed = <(String, String)>[
      ('Какое настроение было у дня сегодня — одним словом или образом?', 'state'),
      ('Что сегодня случилось такого, что хочется запомнить?', 'day'),
      ('За что сегодняшний день можно сказать себе спасибо?', 'day'),
      ('Какой момент дня вызвал самый сильный эмоциональный отклик?', 'feelings'),
      ('Что сегодня отняло больше всего сил? А что их дало?', 'state'),
      ('Если бы сегодняшний день был песней — какой?', 'feelings'),
      ('Какая мелочь сегодня порадовала неожиданно?', 'day'),
      ('О чём ты сегодня думал(а) чаще всего?', 'state'),
      ('Что сегодня получилось лучше, чем ожидалось?', 'day'),
      ('Был ли сегодня момент, когда захотелось остановить время?', 'feelings'),
      ('Какое решение сегодня далось легко? А какое — с трудом?', 'day'),
      ('Что бы ты сказал(а) себе утреннему(ей), зная, как прошёл день?', 'values'),
      ('Какая вещь, звук или запах сегодня запомнились? Чем они зацепили?', 'feelings'),
      ('Где сегодня было больше всего «тебя настоящего»?', 'values'),
      ('Что сегодня хотелось сделать, но не сделалось? Что помешало?', 'state'),
      ('Какая мысль сегодня крутилась и не отпускала?', 'dreams'),
      ('Если взять из сегодняшнего дня одну фотографию — что на ней?', 'day'),
      ('Что сегодня удивило — в себе или вокруг?', 'day'),
      ('Какое желание сегодня шепнуло о себе — даже тихонько?', 'dreams'),
      ('Что ты сегодня сделал(а) для себя, а что — «надо»?', 'values'),
      ('Какой разговор сегодня остался с тобой? О чём он был на самом деле?', 'feelings'),
      ('Что сегодня получилось отпустить? А что пока держит?', 'state'),
      ('Куда сегодняшний день тебя чуть-чуть сдвинул?', 'dreams'),
      ('Чем бы ты наполнил(а) завтрашний день, если бы он был только твой?', 'dreams'),
    ];
    var i = 0;
    for (final (text, cat) in seed) {
      final q = PsyQuestion(text: text, category: cat, ord: i++);
      psyQuestions.add(q);
      await AppDb.instance.insert('psy_questions', q.toMap());
    }
    notifyListeners();
  }

  /// Вторая порция вопросов банка (усиление «банк вместо модели»).
  /// Одноразовая досыпка по флагу 'psySeedV2': вопросы, которых ещё
  /// нет в банке (по тексту), добавляются; пользовательские правки
  /// и удаления существующих вопросов не трогаем.
  Future<void> _seedPsyQuestionsV2() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('psySeedV2') ?? false) return;
      const seed2 = <(String, String)>[
        ('Что сегодня тело говорило тебе весь день? Прислушался(ась) ли ты?', 'state'),
        ('Какой момент сегодня ты бы повторил(а), не меняя ничего?', 'day'),
        ('Что сегодня было труднее — начать, продолжить или закончить?', 'day'),
        ('Какая эмоция сегодня была самой громкой? А самой тихой?', 'feelings'),
        ('Что бы изменилось, если бы сегодня ты был(а) к себе чуть добрее?', 'values'),
        ('О чём ты сегодня молчал(а)? Перед кем и почему?', 'feelings'),
        ('Какое «вчера» сегодня напомнило о себе? Чем именно?', 'state'),
        ('Что сегодня ты делал(а) на автопилоте? А что — осознанно?', 'day'),
        ('Какая мечта сегодня мелькнула на секунду — и куда спряталась?', 'dreams'),
        ('Что сегодняшний день сказал бы тебе, если бы умел говорить?', 'day'),
        ('За что сегодня ты можешь себя похвалить — даже за мелочь?', 'values'),
        ('Чьё присутствие сегодня было тёплым? А чьё — тяжёлым?', 'feelings'),
        ('Что сегодня казалось огромным, а к вечеру стало маленьким?', 'state'),
        ('Если бы сегодня был цвет и температура — какие?', 'feelings'),
        ('Какое обещание себе ты сегодня сдержал(а)? А какое — отложил(а)?', 'values'),
        ('Что нового ты сегодня заметил(а) в привычном месте?', 'day'),
        ('Куда сегодня уходила энергия по капле? Был ли «тихий расход»?', 'state'),
        ('Что сегодня хотелось сфотографировать или записать — и почему?', 'day'),
        ('О чём мечтается, когда представляешь себя через год?', 'dreams'),
        ('Какой страх сегодня притворялся заботой или логикой?', 'feelings'),
        ('Что из сегодняшнего ты заберёшь с собой в завтра?', 'values'),
        ('Когда сегодня время летело? А когда — тянулось?', 'day'),
        ('Что бы ты сделал(а) сегодня иначе, проживи день ещё раз?', 'state'),
        ('Какое маленькое «смелое» ты сегодня совершил(а) — или отложил(а)?', 'dreams'),
      ];
      final existing = psyQuestions.map((q) => q.text.trim()).toSet();
      var ord = psyQuestions.length;
      for (final (text, cat) in seed2) {
        if (existing.contains(text)) continue;
        final q = PsyQuestion(text: text, category: cat, ord: ord++);
        psyQuestions.add(q);
        await AppDb.instance.insert('psy_questions', q.toMap());
      }
      await prefs.setBool('psySeedV2', true);
      notifyListeners();
    } catch (_) {}
  }

  // ---------- Контекст для собеседника-наблюдателя ----------
  /// Что видит модель-собеседник в сессии дневника наблюдений.
  /// Сейчас — ТОЛЬКО записи дневника (последние [maxEntries]).
  /// Слой расширяемый: при fullContext=true сюда же добавляется
  /// сводка задач и целей (для мощных моделей — совокупный анализ
  /// задач, целей и дневника). Флаг зарезервирован на будущее.
  String buildPsyContext({bool fullContext = false, int maxEntries = 14}) {
    final b = StringBuffer();
    final entries = diaryEntries.toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    if (entries.isNotEmpty) {
      b.writeln('Записи дневника пользователя (новые сверху):');
      for (final e in entries.take(maxEntries)) {
        final kindLabel = e.kind == 'observation'
            ? 'наблюдение'
            : (e.kind == 'practice' ? 'практика' : 'итоги дня');
        final snippet = e.text.length > 220
            ? '${e.text.substring(0, 220)}…'
            : e.text;
        b.writeln('- [${fmtDate(e.day)}] ($kindLabel) ${e.title}: $snippet');
      }
    }
    if (fullContext) {
      // Расширение контекста (зарезервировано): задачи и цели.
      b.writeln('Активные задачи:');
      for (final t in activeTasks.take(20)) {
        b.writeln('- ${t.title}'
            '${t.deadline != null ? ' (до ${fmtDateTime(t.deadline!)})' : ''}');
      }
      b.writeln('Цели:');
      for (final g in activeGoals.take(20)) {
        b.writeln('- ${g.title} (${(g.progress * 100).round()}%)');
      }
    }
    return b.toString().trim();
  }

  /// Задачи прошедшего дня для карточки дня в календаре: что было
  /// выполнено (включая архивные) и что невыполнено (можно убрать
  /// в архив принудительно). Закреплённые задачи без дедлайна
  /// определяются по посуточному журналу pin_log.
  ({List<Task> done, List<Task> missed, List<String> pinnedDone}) pastDayTasks(
      DateTime day) {
    final done = <Task>[];
    final missed = <Task>[];
    final seen = <String>{};
    for (final t in tasks) {
      final dl = t.deadline;
      final onDay = dl != null && isSameDay(dl, day);
      final doneDay = t.doneAt != null && isSameDay(t.doneAt!, day);
      if (t.isDone && (doneDay || onDay)) {
        done.add(t);
        seen.add(t.id);
      } else if (!t.isDone && !t.isArchived && onDay) {
        missed.add(t);
        seen.add(t.id);
      }
    }
    // Закрепы, выполненные в этот день по журналу (у самой задачи
    // дедлайн мог быть на другой день или отсутствовать).
    final pinnedDone = <String>[];
    for (final l in pinLogs) {
      if (l.done && isSameDay(l.day, day) && !seen.contains(l.taskId)) {
        pinnedDone.add(l.title.isEmpty ? 'Закреплённая задача' : l.title);
      }
    }
    done.sort((a, b) => a.title.compareTo(b.title));
    missed.sort((a, b) => (a.deadline ?? a.createdAt)
        .compareTo(b.deadline ?? b.createdAt));
    return (done: done, missed: missed, pinnedDone: pinnedDone);
  }

  String buildFeedbackExport() {
    String kindLabel(String k) => k == 'late_reason'
        ? 'причина пропуска'
        : (k == 'day_off' ? 'выходной' : 'комментарий');
    final b = StringBuffer('# Журнал обратной связи\n');
    for (final e in feedback) {
      b.writeln('- [${fmtDateTime(e.createdAt)}] '
          '(${kindLabel(e.kind)}) '
          '${e.itemTitle}: ${e.text}');
    }
    return b.toString();
  }

  // ---------- Закрепление (пины) ----------
  Future<void> togglePinNote(String id) async {
    final n = notes.firstWhere((x) => x.id == id);
    n.isPinned = !n.isPinned;
    await AppDb.instance.updateRow('notes', n.toMap(), n.id);
    notifyListeners();
  }

  Future<void> togglePinTask(String id) async {
    final t = tasks.firstWhere((x) => x.id == id);
    t.isPinned = !t.isPinned;
    await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
    notifyListeners();
  }

  Future<void> togglePinGoal(String id) async {
    final g = goals.firstWhere((x) => x.id == id);
    g.isPinned = !g.isPinned;
    await AppDb.instance.updateRow('goals', g.toMap(), g.id);
    notifyListeners();
  }

  Future<void> archiveGoal(String id) => _archive(goals, id, 'goals');
  Future<void> restoreGoal(String id) => _restore(goals, id, 'goals');

  // ---------- События ----------
  Future<void> addEvent(EventItem e) async {
    events.add(e);
    await AppDb.instance.insert('events', e.toMap());
    await _scheduleEventReminders(e);
    justCreated = (kind: 'event', id: e.id);
    notifyListeners();
  }

  Future<void> updateEvent(EventItem e) async {
    await AppDb.instance.updateRow('events', e.toMap(), e.id);
    await _cancelEventReminders(e);
    if (!e.isArchived) await _scheduleEventReminders(e);
    notifyListeners();
  }

  Future<void> archiveEvent(String id) async {
    final e = events.firstWhere((x) => x.id == id);
    await _cancelEventReminders(e);
    await _archive(events, id, 'events');
  }

  Future<void> restoreEvent(String id) async {
    await _restore(events, id, 'events');
    final e = events.firstWhere((x) => x.id == id);
    await _scheduleEventReminders(e);
  }

  // ---------- Удаление навсегда ----------
  Future<void> deleteNoteForever(String id) async {
    await AppDb.instance.deleteRow('notes', id);
    notes.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  /// Удаление задачи из архива навсегда. Два режима на выбор:
  ///  - withTree=true  — задача удаляется ВМЕСТЕ с деревом связей:
  ///    её шаги и ресурсы стираются из БД;
  ///  - withTree=false — удаляется только сама задача, дерево связей
  ///    (шаги, ресурсы) остаётся нетронутым.
  /// В ОБОИХ режимах прошлый прогресс не откатывается:
  ///  - вклад задачи в прогресс блока переносится в счётчики
  ///    carryDone/carryTotal цели-блока (процент блока не меняется);
  ///  - строка задачи сохраняется с флагом purged, поэтому прошлые
  ///    дни календаря НЕ теряют её отметок (кружки и галочки);
  ///  - выполненная задача дополнительно оставляет отметку в
  ///    посуточном журнале (pin_log) — название видно в истории.
  Future<void> deleteTaskForever(String id, {bool withTree = false}) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id) return;
    await notifications.cancel(notificationIdOf('$id:30min'));
    await _dismissTaskAlarm(t);

    // 1) Прогресс блока не откатывается: переносим вклад задачи
    // в carry-счётчики цели-блока (компенсация удалённой задачи).
    if (t.block.isNotEmpty) {
      for (final g in goals) {
        if (g.externalId == 'block:${t.block}') {
          g.carryTotal += 1;
          if (t.isDone) g.carryDone += 1;
          await AppDb.instance.updateRow('goals', g.toMap(), g.id);
          break;
        }
      }
    }

    // 2) Отметка в посуточном журнале: название выполненной задачи
    // остаётся в истории даже при полном удалении дерева связей.
    if (t.isDone) {
      final day = t.doneAt ?? DateTime.now();
      final logged = pinLogs
          .any((l) => l.taskId == id && isSameDay(l.day, day) && l.done);
      if (!logged) {
        final log =
            PinLog(taskId: id, title: t.title, day: day, done: true);
        pinLogs.add(log);
        await AppDb.instance.insert('pin_log', log.toMap());
      }
    }

    if (withTree) {
      // 3а) Полная очистка: шаги и ресурсы (дерево связей) удаляются.
      for (final s in steps.where((x) => x.taskId == id).toList()) {
        await AppDb.instance.deleteRow('task_steps', s.id);
      }
      steps.removeWhere((x) => x.taskId == id);
      for (final r in resources.where((x) => x.taskId == id).toList()) {
        await AppDb.instance.deleteRow('task_resources', r.id);
      }
      resources.removeWhere((x) => x.taskId == id);
    }

    // 3б) Строка задачи остаётся с флагом purged: календарь продолжает
    // показывать её отметки в прошлых днях, а списки и архив — нет.
    t.purged = true;
    t.isArchived = true;
    await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
    notifyListeners();
  }

  /// Номер очерёдности задачи на экране «Сегодня» (0 — убрать номер).
  /// Номерная группа идёт сразу после закреплённых, до стандартных
  /// ежедневных/краткосрочных/среднесрочных.
  /// Если назначенный номер УЖЕ занят, задачи с этим и бо́льшими
  /// номерами сдвигаются на +1 (старая «3» становится «4» и т.д.),
  /// номера перед вставленным не меняются. Ранжирование прежнее.
  Future<void> setTaskSortNum(String id, int n) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id) return;
    final num = n.clamp(0, 99);
    if (num > 0) {
      t.manualOrder = 0; // номер заменяет ручную позицию
      final clash = tasks.any((x) =>
          x.id != id &&
          !x.isArchived &&
          !x.purged &&
          x.sortNum == num &&
          x.sortNum < 99);
      if (clash) {
        // Сдвиг хвоста списка вперёд, чтобы освободить номер.
        final affected = tasks
            .where((x) =>
                x.id != id &&
                !x.isArchived &&
                !x.purged &&
                x.sortNum >= num &&
                x.sortNum < 99)
            .toList();
        for (final x in affected) {
          x.sortNum += 1;
          unawaited(AppDb.instance
              .updateRow('tasks', x.toMap(), x.id)
              .catchError((_) {}));
        }
      }
    }
    t.sortNum = num;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Ручной порядок перетаскиванием на «Сегодня» (дробная позиция —
  /// вставка между соседями без перенумерации остальных).
  Future<void> setTaskManualOrder(String id, double pos) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id) return;
    t.manualOrder = pos;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Перенос задачи на следующий календарный день (свайп влево на
  /// экране «Сегодня»): дедлайн сдвигается на +1 день с сохранением
  /// времени, действие пишется в журнал обратной связи (причина
  /// переноса — по желанию) и попадает в выгружаемые отчёты.
  Future<String> postponeTaskToTomorrow(String id, {String reason = ''}) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id) return 'Задача не найдена.';
    final base = t.deadline ?? DateTime.now();
    t.deadline = DateTime(base.year, base.month, base.day, base.hour,
            base.minute)
        .add(const Duration(days: 1));
    await AppDb.instance.updateRow('tasks', t.toMap(), t.id);
    await notifications.cancel(notificationIdOf('${t.id}:30min'));
    await _scheduleTaskReminder(t);
    await addFeedback(
        'postpone',
        t.title,
        reason.trim().isEmpty
            ? 'Перенесена на завтра (свайп)'
            : 'Перенесена на завтра: ${reason.trim()}');
    notifyListeners();
    return '«${t.title}» перенесена на завтра';
  }

  /// Ручной порядок задач на экране «Сегодня» (перетаскивание карточек
  /// долгим нажатием, как шаги на шкале пути): каждая задача получает
  /// свою позицию, порядок сохраняется в БД и переживает перезапуск.
  /// Ручной порядок важнее номера очерёдности, номер — важнее
  /// стандартных групп (ежедневные/краткосрочные/среднесрочные).
  Future<void> reorderTodayTasks(List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      final t = tasks.firstWhere((x) => x.id == ids[i], orElse: () => Task());
      if (t.id != ids[i]) continue;
      t.manualOrder = (i + 1).toDouble();
      unawaited(
          AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
    }
    notifyListeners();
  }

  // ---------- Слияние задач (иерархия «однородных») ----------
  /// Однородные (слитые) задачи внутри [taskId]: они исчезают из
  /// списка «Сегодня» и живут внутри карточки родителя, сохраняя
  /// все функции задачи.
  List<Task> childrenOfTask(String taskId) => tasks
      .where((t) => t.parentTaskId == taskId && !t.isArchived && !t.purged)
      .toList()
    ..sort((a, b) =>
        (a.deadline ?? a.createdAt).compareTo(b.deadline ?? b.createdAt));

  /// Есть ли у задачи слитые однородные (для пункта меню
  /// «Просмотреть однородные»).
  bool hasChildrenTasks(String taskId) =>
      tasks.any((t) => t.parentTaskId == taskId && !t.isArchived && !t.purged);

  /// Слияние: [childId] перетянута поверх [parentId] — становится
  /// однородной внутри неё (исчезает из списка «Сегодня»).
  /// Родителем может быть только самостоятельная задача; если у
  /// перетаскиваемой есть свои однородные — они переезжают к новому
  /// родителю (иерархия одноуровневая, как бар блоков на «Целях»).
  Future<String> mergeTaskInto(String childId, String parentId) async {
    if (childId == parentId) return 'Задачу нельзя слить саму с собой.';
    final child = tasks.firstWhere((x) => x.id == childId, orElse: () => Task());
    final parent =
        tasks.firstWhere((x) => x.id == parentId, orElse: () => Task());
    if (child.id != childId || parent.id != parentId) {
      return 'Задача не найдена.';
    }
    if (parent.parentTaskId.isNotEmpty) {
      return 'Сливать можно только в самостоятельную задачу.';
    }
    // Защита от циклов: родитель не должен быть потомком child.
    // (иерархия одноуровневая, достаточно проверить parentTaskId)
    if (parent.parentTaskId == childId) {
      return 'Нельзя: эта задача уже внутри перетаскиваемой.';
    }
    // Однородные перетаскиваемой задачи переезжают к новому родителю.
    for (final sub in childrenOfTask(childId)) {
      sub.parentTaskId = parentId;
      unawaited(AppDb.instance
          .updateRow('tasks', sub.toMap(), sub.id)
          .catchError((_) {}));
    }
    child.parentTaskId = parentId;
    child.manualOrder = 0; // внутри родителя свой порядок
    await AppDb.instance.updateRow('tasks', child.toMap(), child.id);
    await addFeedback('merge', parent.title,
        'Задача «${child.title}» слита внутрь (однородные)');
    notifyListeners();
    return '«${child.title}» теперь внутри «${parent.title}»';
  }

  /// Отсоединить однородную задачу: она снова самостоятельная и
  /// возвращается в списки (на «Сегодня» — если дедлайн сегодня).
  Future<void> unmergeTask(String id) async {
    final t = tasks.firstWhere((x) => x.id == id, orElse: () => Task());
    if (t.id != id) return;
    t.parentTaskId = '';
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Активные самостоятельные задачи (без слитых однородных) —
  /// для списков экранов «Задачи» и блоков.
  List<Task> get visibleTasks =>
      activeTasks.where((t) => t.parentTaskId.isEmpty).toList();

  /// Ручной порядок блоков на древе пути (перетаскивание завязи
  /// вверх/вниз): каждому блоку присваивается позиция, порядок
  /// сохраняется в БД. Новые блоки (позиция 0) растут выше
  /// упорядоченных, удалённые не ломают остальной порядок.
  Future<void> reorderBlockGoals(List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      final g = goals.firstWhere((x) => x.id == ids[i], orElse: () => Goal());
      if (g.id != ids[i]) continue;
      g.manualOrder = (i + 1).toDouble();
      unawaited(
          AppDb.instance.updateRow('goals', g.toMap(), g.id).catchError((_) {}));
    }
    notifyListeners();
  }

  /// Смена приоритета задачи иконками (волны / ! / костюм).
  void setTaskPriority(String id, int priority) {
    final t = tasks.firstWhere((x) => x.id == id);
    t.priority = priority;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  /// Молния: переключить «целевое действие» у задачи.
  void toggleTaskKey(String id) {
    final t = tasks.firstWhere((x) => x.id == id);
    t.isKeyAction = !t.isKeyAction;
    notifyListeners();
    unawaited(
        AppDb.instance.updateRow('tasks', t.toMap(), t.id).catchError((_) {}));
  }

  Future<void> deleteGoalForever(String id) async {
    await AppDb.instance.deleteRow('goals', id);
    goals.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  Future<void> deleteEventForever(String id) async {
    for (final offset in [15, 0]) {
      await notifications.cancel(notificationIdOf('$id:$offset'));
    }
    await AppDb.instance.deleteRow('events', id);
    events.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  // ---------- Импорт годового плана (tasks.json) ----------
  /// Импортирует файл стратегии и распределяет по всем экранам:
  /// блоки -> Цели, задачи -> Задачи (дедлайны -> Календарь, daily -> Сегодня),
  /// сводка -> Заметка. Предыдущий импорт полностью заменяется.
  /// Файл закрепляется (SharedPreferences) и переживает перезапуск.
  /// Возвращает текст-итог для снэкбара.
  Future<String> importStrategy(String raw, String fileName) async {
    final plan = parseStrategyPlan(raw); // бросает FormatException — ловит UI
    final tag = 'imp:${DateTime.now().millisecondsSinceEpoch}';

    // 1) Удаляем предыдущий импорт (только записи с меткой, ручные не трогаем)
    for (final t in tasks.where((x) => x.importTag.isNotEmpty).toList()) {
      await notifications.cancel(notificationIdOf('${t.id}:30min'));
      await AppDb.instance.deleteRow('tasks', t.id);
      tasks.removeWhere((x) => x.id == t.id);
    }
    for (final g in goals.where((x) => x.importTag.isNotEmpty).toList()) {
      await AppDb.instance.deleteRow('goals', g.id);
      goals.removeWhere((x) => x.id == g.id);
    }
    for (final n in notes.where((x) => x.importTag.isNotEmpty).toList()) {
      await AppDb.instance.deleteRow('notes', n.id);
      notes.removeWhere((x) => x.id == n.id);
    }

    // 2) Цели по блокам
    for (final b in plan.blocks) {
      await addGoal(Goal(
        title: blockTitle(b),
        horizonDays: plan.horizonDays,
        externalId: 'block:$b',
        importTag: tag,
      ));
    }

    // 3) Задачи (daily -> сегодня 20:00 + recurDaily).
    // Дублей нет: задача, которая УЖЕ есть в списках (та же внешняя
    // ссылка или то же название в том же блоке), пропускается.
    String taskKey(String extId, String title, String block) =>
        extId.isNotEmpty
            ? 'e:$extId'
            : 't:${title.toLowerCase().trim()}|$block';
    final existing = <String>{
      for (final t in tasks) taskKey(t.externalId, t.title, t.block),
    };
    var skipped = 0;
    final now = DateTime.now();
    for (final it in plan.tasks) {
      if (!existing.add(taskKey(it.id, it.title, it.block))) {
        skipped++;
        continue;
      }
      DateTime? dl;
      String horizon;
      if (it.isDaily) {
        dl = DateTime(now.year, now.month, now.day, 20);
        horizon = 'daily';
      } else {
        final d = it.deadlineDate;
        if (d != null) dl = DateTime(d.year, d.month, d.day, 18);
        // Краткосрочные — в ближайшую неделю, остальные — среднесрочные
        // (на шкале цели расставляются равномерно).
        horizon =
            (dl != null && dl.difference(now).inDays <= 7) ? 'short' : 'medium';
      }
      await addTask(Task(
        title: it.title,
        deadline: dl,
        estimateMin: 60,
        priority: it.priorityInt,
        externalId: it.id,
        block: it.block,
        metric: it.metric,
        importTag: tag,
        recurDaily: it.isDaily,
        horizon: horizon,
      ));
    }

    // 4) Заметка-сводка плана
    final doneCount = plan.tasks.where((t) => t.done).length;
    final summary = StringBuffer()
      ..writeln('Период: ${plan.periodStart} — ${plan.periodEnd}')
      ..writeln('Задач: ${plan.tasks.length}, выполнено: $doneCount')
      ..writeln('WIP-лимит: ${plan.wipLimit}')
      ..writeln('Блоки: ${plan.blocks.map(blockTitle).join(', ')}');
    await addNote(Note(
      title: 'Годовой план: ${plan.name}',
      text: summary.toString(),
      importTag: tag,
    ));

    // 5) Закрепляем файл
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('strategyJson', raw);
    await prefs.setString('strategyFileName', fileName);
    importedTasks = plan.tasks;
    importedFileName = fileName;
    strategyRaw = raw;

    await _refreshBlockGoalProgress();
    justCreated = null; // массовый импорт — уточняющие вопросы не задаём
    notifyListeners();
    final added = plan.tasks.length - skipped;
    return 'Импортировано: $added задач, ${plan.blocks.length} целей.'
        '${skipped > 0 ? ' Пропущено дублей: $skipped.' : ''} '
        'Файл закреплён.';
  }

  /// Отвязать файл стратегии и убрать импортированные данные.
  Future<void> clearStrategy() async {
    for (final t in tasks.where((x) => x.importTag.isNotEmpty).toList()) {
      await notifications.cancel(notificationIdOf('${t.id}:30min'));
      await AppDb.instance.deleteRow('tasks', t.id);
      tasks.removeWhere((x) => x.id == t.id);
    }
    for (final g in goals.where((x) => x.importTag.isNotEmpty).toList()) {
      await AppDb.instance.deleteRow('goals', g.id);
      goals.removeWhere((x) => x.id == g.id);
    }
    for (final n in notes.where((x) => x.importTag.isNotEmpty).toList()) {
      await AppDb.instance.deleteRow('notes', n.id);
      notes.removeWhere((x) => x.id == n.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('strategyJson');
    await prefs.remove('strategyFileName');
    importedTasks = [];
    importedFileName = null;
    strategyRaw = null;
    notifyListeners();
  }

  /// Прогресс целей-блоков = доля выполненных задач их блока.
  /// Учитывает carry-счётчики (вклад задач, удалённых из архива):
  /// удаление задачи не откатывает прогресс блока.
  Future<void> _refreshBlockGoalProgress() async {
    var changed = false;
    for (final g in goals) {
      if (!g.externalId.startsWith('block:')) continue;
      final block = g.externalId.substring(6);
      final bt = tasks.where((t) => t.block == block && !t.purged).toList();
      final total = bt.length + g.carryTotal;
      if (total == 0) continue;
      final done = bt.where((t) => t.isDone).length + g.carryDone;
      final p = done / total;
      if ((g.progress - p).abs() > 0.001 || (p < 1 && g.isDone)) {
        g.progress = p;
        if (p >= 1 && !g.isDone) {
          g.isDone = true;
          g.isArchived = true;
        } else if (p < 1 && g.isDone) {
          // Откат: отметку о выполнении сняли — блок возвращается
          // из архива в работу, проценты уменьшаются.
          g.isDone = false;
          g.isArchived = false;
          g.doneAt = null;
        }
        await AppDb.instance.updateRow('goals', g.toMap(), g.id);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ---------- Архивация (generic) ----------
  Future<void> _archive(List<dynamic> list, String id, String table) async {
    final item = list.firstWhere((x) => x.id == id);
    item.isArchived = true;
    await AppDb.instance.updateRow(table, item.toMap() as Map<String, dynamic>, id);
    notifyListeners();
  }

  Future<void> _restore(List<dynamic> list, String id, String table) async {
    final item = list.firstWhere((x) => x.id == id);
    item.isArchived = false;
    await AppDb.instance.updateRow(table, item.toMap() as Map<String, dynamic>, id);
    notifyListeners();
  }

  // ---------- Напоминания ----------
  /// Переключатель всех напоминаний. При отключении всё отменяется,
  /// при включении — перепланируется заново.
  Future<void> setRemindersEnabled(bool v) async {
    remindersEnabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remindersEnabled', v);
    } catch (_) {}
    if (v) {
      await rescheduleAllReminders();
    } else {
      await notifications.cancelAll();
    }
    notifyListeners();
  }

  /// Переключатель дублирования горящих дедлайнов системным будильником.
  Future<void> setAlarmEnabled(bool v) async {
    alarmEnabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('alarmEnabled', v);
    } catch (_) {}
    if (v) await rescheduleAllReminders();
    notifyListeners();
  }

  /// Момент системного будильника задачи: ровно за 240 минут до
  /// дедлайна; если этот момент уже прошёл — на сам дедлайн (или
  /// через минуту). null — дедлайна нет, будильник не нужен.
  DateTime? _alarmTimeFor(Task t) {
    final dl = t.deadline;
    if (dl == null) return null;
    var at = dl.subtract(const Duration(minutes: 240));
    final now = DateTime.now();
    if (at.isBefore(now)) {
      at = dl.isAfter(now) ? dl : now.add(const Duration(minutes: 1));
    }
    return at;
  }

  /// Стоит ли по задаче системный будильник (для пункта меню
  /// «Снять будильник»).
  bool hasTaskAlarm(String taskId) => _armedAlarms.contains(taskId);

  /// Ручная установка системного будильника по дедлайну задачи
  /// (пункт меню задачи «Будильник по дедлайну»). Будильник на задачу
  /// всегда ОДИН: прежний (если был) молча снимается, новый ставится
  /// на актуальный дедлайн.
  Future<String> setTaskAlarm(String taskId) async {
    final t = tasks.firstWhere((x) => x.id == taskId);
    final at = _alarmTimeFor(t);
    if (at == null) {
      return 'У задачи нет дедлайна — будильник не нужен.';
    }
    if (_armedAlarms.contains(t.id)) await _dismissTaskAlarm(t);
    final ok = await AlarmService.setAlarm(at, 'Дедлайн: ${t.title}');
    if (ok) await _markAlarmArmed(taskId);
    return ok
        ? 'Будильник установлен на ${fmtDateTime(at)}'
        : 'Не удалось установить будильник — проверьте приложение «Часы».';
  }

  /// Ручное снятие системного будильника задачи (пункт меню
  /// «Снять будильник»). UI подтверждает снятие звуком.
  Future<String> cancelTaskAlarm(String taskId) async {
    final t = tasks.firstWhere((x) => x.id == taskId);
    if (!_armedAlarms.contains(t.id)) {
      return 'У этой задачи будильник не установлен.';
    }
    await _dismissTaskAlarm(t);
    return 'Будильник снят';
  }

  Future<void> _scheduleEventReminders(EventItem e) async {
    if (!remindersEnabled || e.isArchived) return;
    try {
      for (final offset in [15, 0]) {
        final at = e.start.subtract(Duration(minutes: offset));
        if (at.isBefore(DateTime.now())) continue;
        await notifications.schedule(
          id: notificationIdOf('${e.id}:$offset'),
          title: e.title,
          body: offset == 0 ? 'начинается сейчас' : 'начнётся через $offset мин',
          dateTime: at,
        );
      }
    } catch (_) {
      // Сбой напоминания не должен ронять основной сценарий.
    }
  }

  Future<void> _cancelEventReminders(EventItem e) async {
    for (final offset in [15, 0]) {
      await notifications.cancel(notificationIdOf('${e.id}:$offset'));
    }
  }

  /// Напоминание о дедлайне задачи: за время, равное 4× оценки выполнения.
  /// 15 мин на выполнение -> за час; 1 день -> за 4 дня, и т.д.
  /// Если времени до выполнения мало (оценка ≤ 30 мин) или действие
  /// ключевое — включается настойчивая «сирена» критического канала.
  Future<void> _scheduleTaskReminder(Task t) async {
    if (!remindersEnabled) return;
    final dl = t.deadline;
    if (dl == null || t.isDone || t.isArchived) return;
    final est = t.estimateMin <= 0 ? 30 : t.estimateMin;
    final lead = Duration(minutes: est * 4);
    final at = dl.subtract(lead);
    if (at.isBefore(DateTime.now())) return;
    final siren = t.isKeyAction || est <= 30;
    String leadText;
    if (lead.inMinutes < 60) {
      leadText = '${lead.inMinutes} мин';
    } else if (lead.inHours < 24) {
      leadText = '${lead.inHours} ч';
    } else {
      leadText = '${lead.inDays} дн.';
    }
    try {
      if (siren) {
        await notifications.scheduleCritical(
          id: notificationIdOf('${t.id}:30min'),
          title: t.isKeyAction ? 'Ключевое действие: ${t.title}' : t.title,
          body: 'дедлайн через $leadText (в ${fmtTime(dl)})',
          dateTime: at,
          insistent: true,
        );
        // Системный будильник автоматически НЕ ставится: только вручную
        // из меню задачи («Будильник: выбрать время дедлайна»), за
        // 240 минут до срока. Иначе будильники множились в «Часах»,
        // а приложение «Часы» открывалось после каждого добавления
        // или удаления задачи.
      } else {
        await notifications.schedule(
          id: notificationIdOf('${t.id}:30min'),
          title: t.title,
          body: 'дедлайн через $leadText (в ${fmtTime(dl)})',
          dateTime: at,
        );
      }
    } catch (_) {
      // Сбой напоминания не должен ронять основной сценарий.
    }
  }

  /// Перепланировать все напоминания (важно после перезагрузки устройства).
  Future<void> rescheduleAllReminders() async {
    await notifications.cancelAll();
    // Уборка флагов системных будильников: сработавший разовый
    // будильник «Часы» отключают сами, задача могла быть выполнена
    // или удалена — флаг снимаем, чтобы при новом дедлайне будильник
    // встал заново (и ровно один). Сами будильники в «Часах» при
    // этом НЕ дублируются: новые ставятся только для задач без флага.
    final now = DateTime.now();
    final ids = tasks.map((t) => t.id).toSet();
    final stale = _armedAlarms.where((id) {
      if (!ids.contains(id)) return true;
      final t = tasks.firstWhere((x) => x.id == id);
      final dl = t.deadline;
      return t.isDone || t.isArchived || dl == null || dl.isBefore(now);
    }).toList();
    if (stale.isNotEmpty) {
      _armedAlarms.removeAll(stale);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            'armedDeadlineAlarms', _armedAlarms.toList());
      } catch (_) {}
    }
    for (final e in events) {
      if (!e.isArchived) await _scheduleEventReminders(e);
    }
    for (final t in tasks) {
      if (!t.isDone && !t.isArchived) await _scheduleTaskReminder(t);
    }
  }

  // ---------- Выборки ----------
  List<Note> get activeNotes => notes.where((n) => !n.isArchived).toList();
  List<Task> get activeTasks => tasks.where((t) => !t.isArchived && !t.purged).toList();
  List<Goal> get activeGoals => goals.where((g) => !g.isArchived).toList();
  List<EventItem> get activeEvents => events.where((e) => !e.isArchived).toList();

  List<Note> get archivedNotes => notes.where((n) => n.isArchived).toList();
  List<Task> get archivedTasks => tasks.where((t) => t.isArchived && !t.purged).toList();
  List<Goal> get archivedGoals => goals.where((g) => g.isArchived).toList();
  List<EventItem> get archivedEvents => events.where((e) => e.isArchived).toList();

  List<EventItem> eventsForDay(DateTime day) =>
      activeEvents.where((e) => isSameDay(e.start, day)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<Task> tasksForDay(DateTime day) {
    final now = DateTime.now();
    final isToday = isSameDay(day, now);
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
    return activeTasks
        .where((t) {
          // Слитая (однородная) задача живёт только внутри родителя —
          // в списке дня она не показывается.
          if (t.parentTaskId.isNotEmpty) return false;
          // Закреплённая (пин) задача — ежедневная: висит на экране
          // «Сегодня» КАЖДЫЙ день, независимо от того, задан ли дедлайн.
          // Исключение: её перенесли свайпом на будущий день — тогда
          // до наступления этого дня она скрыта (вернуть её на сегодня
          // можно через экран «Запланировать на завтра»).
          if (isToday && t.isPinned) {
            final dl = t.deadline;
            return dl == null || !dl.isAfter(endOfDay);
          }
          // Остальные задачи видны только в день своего дедлайна.
          // Ежедневная задача, отмеченная выполненной, уходит в архив,
          // а на следующий день появляется новый экземпляр с дедлайном
          // на завтра.
          return t.deadline != null &&
              (isSameDay(t.deadline!, day) ||
                  (isToday && t.deadline!.isBefore(now)));
        })
        .toList()
      // Иерархия дня: закреплённые ежедневные -> закреплённые
      // краткосрочные -> закреплённые среднесрочные -> прочие
      // ежедневные -> краткосрочные -> среднесрочные -> остальные.
      // Внутри группы — по времени дедлайна.
      ..sort((a, b) {
        final ra = todayRank(a);
        final rb = todayRank(b);
        if (ra != rb) return ra.compareTo(rb);
        // Внутри группы «с номером» — по номеру/ручной позиции.
        if (ra == 3) {
          final pa = todayPosition(a);
          final pb = todayPosition(b);
          if (pa != pb) return pa.compareTo(pb);
        }
        return (a.deadline ?? a.createdAt).compareTo(b.deadline ?? b.createdAt);
      });
  }

  /// Ранг задачи в списке дня (экран «Сегодня» и карточка дня
  /// в календаре): меньше — выше.
  static int todayRank(Task t) {
    final daily = t.recurDaily || t.horizon == 'daily';
    if (t.isPinned) {
      if (daily) return 0; // закреплённые ежедневные
      if (t.horizon == 'short') return 1; // закреплённые краткосрочные
      return 2; // закреплённые среднесрочные и без горизонта
    }
    // Задачи с номером очерёдности (sortNum) или переставленные
    // вручную (manualOrder) — сразу после закреплённых.
    if (t.sortNum > 0 || t.manualOrder > 0) return 3;
    if (daily) return 4;
    if (t.horizon == 'short') return 5;
    if (t.horizon == 'medium') return 6;
    return 7;
  }

  /// Эффективная позиция задачи с номером/ручным порядком:
  /// ручная перестановка важнее номера, номер важнее группы.
  static double todayPosition(Task t) {
    if (t.manualOrder > 0) return t.manualOrder;
    if (t.sortNum > 0) return t.sortNum.toDouble();
    return 0;
  }

  /// Отметки дня в календаре: ОДИН кружок-чекпоинт на каждую задачу
  /// этого дня (и на каждую ежедневную привычку — каждый день).
  /// Галочка/награда ставится на кружок ТОЛЬКО той задачи, которая
  /// выполнена. kind: 'daily' | 'key' | 'medium' | 'short' | 'plain'.
  /// Для отметок смотрим и архивные задачи: выполненные уходят в архив,
  /// но их кружок за тот день остаётся с отметкой.
  List<({String kind, bool done})> calendarCheckpoints(DateTime day) {
    final now = DateTime.now();
    final res = <({String kind, bool done})>[];
    // Ежедневные серии покрываются отдельно ниже (кружок на КАЖДЫЙ день
    // интервала), поэтому в дневном цикле по дедлайнам их пропускаем.
    final allDay = tasks.where((t) =>
        t.deadline != null &&
        isSameDay(t.deadline!, day) &&
        !(t.recurDaily || t.horizon == 'daily'));
    for (final t in allDay) {
      // Закреплённая ежедневная задача с датой — белый кружок в день
      // дедлайна; отметка выполнения — посуточная (из pin_log).
      if (t.isPinned) {
        final dayKey = fmtDate(DateTime(day.year, day.month, day.day));
        var done = false;
        var logged = false;
        for (final l in pinLogs) {
          if (l.taskId == t.id && fmtDate(l.day) == dayKey) {
            done = l.done;
            logged = true;
          }
        }
        if (!logged) {
          done = t.isDone && t.doneAt != null && isSameDay(t.doneAt!, day);
        }
        res.add((kind: 'pinned', done: done));
        continue;
      }
      final String kind;
      if (t.isKeyAction || (!t.isDone && t.deadline!.isBefore(now))) {
        kind = 'key';
      } else if (t.horizon == 'medium') {
        kind = 'medium';
      } else if (t.horizon == 'short') {
        kind = 'short';
      } else {
        kind = 'plain';
      }
      res.add((kind: kind, done: t.isDone));
    }
    // Ежедневные задачи: зелёный кружок на каждый день интервала серии —
    // от самого раннего создания до самого позднего дедлайна, но не
    // меньше квартала от начала (интервал по умолчанию = квартал).
    final series = <String, List<Task>>{};
    for (final t in tasks) {
      if (t.recurDaily || t.horizon == 'daily') {
        series.putIfAbsent('${t.title}|${t.externalId}', () => []).add(t);
      }
    }
    final dayOnly = DateTime(day.year, day.month, day.day);
    for (final list in series.values) {
      var start = list.first.createdAt;
      DateTime? latestDl;
      for (final t in list) {
        if (t.createdAt.isBefore(start)) start = t.createdAt;
        final dl = t.deadline;
        if (dl != null && (latestDl == null || dl.isAfter(latestDl!))) {
          latestDl = dl;
        }
      }
      final startDay = DateTime(start.year, start.month, start.day);
      var endDay = startDay.add(const Duration(days: 89));
      if (latestDl != null) {
        final dlDay =
            DateTime(latestDl!.year, latestDl!.month, latestDl!.day);
        if (dlDay.isAfter(endDay)) endDay = dlDay;
      }
      if (dayOnly.isBefore(startDay) || dayOnly.isAfter(endDay)) continue;
      // День, отмеченный «выходным», — без кружка.
      if (list.any((t) => t.dayOffDates.contains(fmtDate(dayOnly)))) {
        continue;
      }
      final done = list.any((t) =>
          t.isDone && t.doneAt != null && isSameDay(t.doneAt!, dayOnly));
      res.add((kind: 'daily', done: done));
    }
    // Ежедневные привычки (цели recurDaily) — зелёный кружок каждый день.
    for (final g in goals.where((g) => g.recurDaily && !g.isArchived)) {
      res.add((
        kind: 'daily',
        done: (g.lastDoneAt != null && isSameDay(g.lastDoneAt!, day)) ||
            (isSameDay(day, now) && g.isDone),
      ));
    }
    // Порядок: ежедневные -> закреплённые -> ключевые -> среднесрочные
    // -> краткосрочные.
    const rank = {
      'daily': 0,
      'pinned': 1,
      'key': 2,
      'medium': 3,
      'short': 4,
      'plain': 5,
    };
    res.sort((a, b) => rank[a.kind]!.compareTo(rank[b.kind]!));
    return res;
  }

  /// Расширенная разбивка кружков календаря — для диагностики задвоений:
  /// каждый кружок с подписью источника (какая серия/задача/привычка
  /// его нарисовала). Логика зеркалит calendarCheckpoints; kind='habit'
  /// отделяет привычки-цели от ежедневных серий задач ('daily').
  List<({String kind, bool done, String label})> calendarCheckpointDetails(
      DateTime day) {
    final now = DateTime.now();
    final res = <({String kind, bool done, String label})>[];
    final allDay = tasks.where((t) =>
        t.deadline != null &&
        isSameDay(t.deadline!, day) &&
        !(t.recurDaily || t.horizon == 'daily'));
    for (final t in allDay) {
      if (t.isPinned) {
        final dayKey = fmtDate(DateTime(day.year, day.month, day.day));
        var done = false;
        var logged = false;
        for (final l in pinLogs) {
          if (l.taskId == t.id && fmtDate(l.day) == dayKey) {
            done = l.done;
            logged = true;
          }
        }
        if (!logged) {
          done = t.isDone && t.doneAt != null && isSameDay(t.doneAt!, day);
        }
        res.add((kind: 'pinned', done: done, label: t.title));
        continue;
      }
      final String kind;
      if (t.isKeyAction || (!t.isDone && t.deadline!.isBefore(now))) {
        kind = 'key';
      } else if (t.horizon == 'medium') {
        kind = 'medium';
      } else if (t.horizon == 'short') {
        kind = 'short';
      } else {
        kind = 'plain';
      }
      res.add((kind: kind, done: t.isDone, label: t.title));
    }
    final series = <String, List<Task>>{};
    for (final t in tasks) {
      if (t.recurDaily || t.horizon == 'daily') {
        series.putIfAbsent('${t.title}|${t.externalId}', () => []).add(t);
      }
    }
    final dayOnly = DateTime(day.year, day.month, day.day);
    for (final e in series.entries) {
      final list = e.value;
      var start = list.first.createdAt;
      DateTime? latestDl;
      for (final t in list) {
        if (t.createdAt.isBefore(start)) start = t.createdAt;
        final dl = t.deadline;
        if (dl != null && (latestDl == null || dl.isAfter(latestDl!))) {
          latestDl = dl;
        }
      }
      final startDay = DateTime(start.year, start.month, start.day);
      var endDay = startDay.add(const Duration(days: 89));
      if (latestDl != null) {
        final dlDay =
            DateTime(latestDl!.year, latestDl!.month, latestDl!.day);
        if (dlDay.isAfter(endDay)) endDay = dlDay;
      }
      if (dayOnly.isBefore(startDay) || dayOnly.isAfter(endDay)) continue;
      if (list.any((t) => t.dayOffDates.contains(fmtDate(dayOnly)))) {
        continue;
      }
      final done = list.any((t) =>
          t.isDone && t.doneAt != null && isSameDay(t.doneAt!, dayOnly));
      res.add((
        kind: 'daily',
        done: done,
        label: 'серия: ${e.key.substring(0, e.key.indexOf('|'))}',
      ));
    }
    for (final g in goals.where((g) => g.recurDaily && !g.isArchived)) {
      res.add((
        kind: 'habit',
        done: (g.lastDoneAt != null && isSameDay(g.lastDoneAt!, day)) ||
            (isSameDay(day, now) && g.isDone),
        label: 'привычка: ${g.title}',
      ));
    }
    return res;
  }

  // ---------- Статистика ----------
  PeriodStat taskStat(DateTime from, DateTime to) {
    final inPeriod =
        tasks.where((t) => !t.createdAt.isBefore(from) && t.createdAt.isBefore(to)).toList();
    final now = DateTime.now();
    // Пропуски: накопленные пропуски ежедневных + просроченные прямо сейчас.
    final missed = inPeriod.fold<int>(0, (s, t) => s + t.missedCount) +
        inPeriod
            .where((t) =>
                !t.recurDaily &&
                !t.isDone &&
                !t.isArchived &&
                t.deadline != null &&
                t.deadline!.isBefore(now))
            .length;
    // Посуточные отметки закреплённых (ежедневных) задач учитываются
    // независимо от дат: каждый день — отдельная единица учёта.
    final pins = pinLogs
        .where((l) => !l.day.isBefore(from) && l.day.isBefore(to))
        .toList();
    final pinsDone = pins.where((l) => l.done).length;
    return PeriodStat(
        inPeriod.where((t) => t.isDone).length + pinsDone,
        inPeriod.length + pins.length,
        missed + pins.where((l) => !l.done).length);
  }

  PeriodStat goalStat(DateTime from, DateTime to) {
    final inPeriod =
        goals.where((g) => !g.createdAt.isBefore(from) && g.createdAt.isBefore(to)).toList();
    final missed = inPeriod.fold<int>(0, (s, g) => s + g.missedCount);
    return PeriodStat(inPeriod.where((g) => g.isDone && !g.recurDaily).length, inPeriod.length, missed);
  }

  // ---------- Команды ассистента (JSON от Ollama) ----------
  int _priorityOf(dynamic v) {
    final s = (v ?? '').toString().toLowerCase();
    if (s.contains('high') || s.contains('высок')) return 2;
    if (s.contains('low') || s.contains('низк')) return 0;
    return 1;
  }

  DateTime? _parseDateTime(dynamic date, dynamic time) {
    if (date == null) return null;
    var raw = date.toString().trim();
    // Модель может вернуть «08.11.2026» или «08/11/2026» — приводим к ISO.
    final dm = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{2,4})$').firstMatch(raw);
    if (dm != null) {
      var y = int.parse(dm.group(3)!);
      if (y < 100) y += 2000;
      raw = '${y.toString().padLeft(4, '0')}-${dm.group(2)!.padLeft(2, '0')}-${dm.group(1)!.padLeft(2, '0')}';
    }
    final d = DateTime.tryParse(raw);
    if (d == null) return null;
    if (time != null) {
      final parts = time.toString().split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? d.hour;
        final m = int.tryParse(parts[1]) ?? d.minute;
        return DateTime(d.year, d.month, d.day, h, m);
      }
    }
    return d;
  }

  /// Отсекает «попугайские» ответы слабой LLM: плейсхолдеры вместо
  /// реального названия (модель скопировала формат, а не команду).
  bool _isPlaceholder(String title) {
    final s = title.toLowerCase().trim();
    return s == 'title' ||
        s == 'название' ||
        s == 'string' ||
        s == '...' ||
        s == 'задача' ||
        s.startsWith('название_');
  }

  /// Выполняет JSON-интент от LLM. Возвращает текст-ответ для чата.
  /// Пустая строка = интент не распознан (вызывающий код сохранит заметку).
  Future<String> handleAssistantJson(Map<String, dynamic> j) async {
    final action = (j['action'] ?? '').toString().toLowerCase().trim();
    final title = (j['title'] ?? '').toString().trim();

    switch (action) {
      case 'add_task':
      case 'create_task':
        if (title.isEmpty || _isPlaceholder(title)) return '';
        DateTime? dl = _parseDateTime(j['date'] ?? j['deadline'], j['time']);
        if (dl == null && j['deadline_days'] != null) {
          final days = int.tryParse(j['deadline_days'].toString()) ?? 0;
          final n = DateTime.now().add(Duration(days: days));
          dl = DateTime(n.year, n.month, n.day, 18);
        }
        // Дата не указана — ставим дедлайн СЕГОДНЯ вечером, чтобы задача
        // из чата ассистента сразу появилась на экране «Сегодня».
        if (dl == null) {
          final n = DateTime.now();
          dl = DateTime(n.year, n.month, n.day, 20);
        }
        await addTask(Task(
            title: title, deadline: dl, priority: _priorityOf(j['priority'])));
        return isSameDay(dl, DateTime.now())
            ? 'Задача «$title» добавлена на сегодня (дедлайн ${fmtTime(dl)}) — она на экране «Сегодня».'
            : 'Задача «$title» добавлена, дедлайн ${fmtDateTime(dl)}.';

      case 'add_note':
      case 'create_note':
        await addNote(Note(
          title: title.isEmpty ? 'Заметка' : title,
          text: (j['text'] ?? '').toString(),
        ));
        return 'Заметка «${title.isEmpty ? 'Заметка' : title}» добавлена.';

      case 'add_goal':
      case 'create_goal':
        if (title.isEmpty || _isPlaceholder(title)) {
          return 'Не хватает названия цели. Скажите: добавь цель «название».';
        }
        final days = int.tryParse((j['deadline_days'] ?? j['horizon_days'] ?? '30').toString()) ?? 30;
        final goal = Goal(
            title: title,
            horizonDays: days,
            priority: _priorityOf(j['priority']));
        // Цель относится к блоку из контекста: поле block от модели
        // или название блока, встретившееся в исходной фразе.
        final blocks = blockGoals();
        Goal? blk;
        final jBlock = (j['block'] ?? '').toString().trim().toLowerCase();
        final raw = '${j['text'] ?? ''} $title'.toLowerCase();
        for (final g in blocks) {
          final bt = g.title.toLowerCase();
          final bid = g.externalId.substring(6).toLowerCase();
          if (jBlock.isNotEmpty && (bt.contains(jBlock) || bid.contains(jBlock))) {
            blk = g;
            break;
          }
          if (bt.length >= 3 && raw.contains(bt)) {
            blk = g;
            break;
          }
        }
        if (blk != null) goal.block = blk.externalId.substring(6);
        await addGoal(goal);
        // Диалоговый сценарий: спрашиваем задачи цели (и блок, если не
        // определён) прямо в чате. Диалог «ресурсы+шаги» поверх не нужен.
        justCreated = null;
        return _startGoalFlow(goal,
            prefix: blk != null
                ? 'Цель «$title» добавлена в блок «${blk.title}» (горизонт $days дн.).'
                : 'Цель «$title» добавлена (горизонт $days дн.).');

      case 'add_event':
      case 'create_event':
      case 'add_meeting':
        // Если модель не смогла выделить название — берём исходный текст
        // фразы, чтобы событие всё равно создалось.
        var evTitle = title;
        if (evTitle.isEmpty || _isPlaceholder(evTitle)) {
          evTitle = (j['text'] ?? '').toString().trim();
        }
        if (evTitle.isEmpty) return 'Не хватает названия события.';
        var start = _parseDateTime(j['date'], j['time']);
        // Дата не распознана — ставим на сегодня, чтобы событие не потерялось.
        start ??= DateTime(DateTime.now().year, DateTime.now().month,
            DateTime.now().day, 18);
        final dur = int.tryParse((j['duration_min'] ?? '60').toString()) ?? 60;
        await addEvent(EventItem(
            title: evTitle,
            start: start,
            durationMin: dur,
            priority: _priorityOf(j['priority'])));
        // Событие дублируется в заметки (встречи, «позвонить» и т.п.),
        // чтобы его было видно на обоих экранах.
        await addNote(Note(
          title: 'Событие: $evTitle',
          text: 'Дата: ${fmtDateTime(start)}',
        ));
        return 'Событие «$evTitle» запланировано на ${fmtDateTime(start)} и сохранено в заметках.';

      case 'complete_task':
        final found = activeTasks
            .where((t) => t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл задачу «$title».';
        toggleTaskDone(found.first.id);
        return 'Задача «${found.first.title}» выполнена и ушла в архив. Отлично!';

      case 'complete_goal':
        final found = activeGoals
            .where((g) => g.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл цель «$title».';
        toggleGoalDone(found.first.id);
        return found.first.recurDaily
            ? 'Привычка «${found.first.title}» отмечена на сегодня.'
            : 'Цель «${found.first.title}» достигнута и в архиве. Поздравляю!';

      case 'delete_task':
        // Голосовое удаление — это архивация (по философии приложения
        // «архив вместо удаления»): задачу можно вернуть из архива.
        final found = activeTasks
            .where((t) => t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл задачу «$title».';
        await archiveTask(found.first.id);
        return 'Задача «${found.first.title}» убрана в архив — при необходимости вернёте её оттуда.';

      case 'delete_note':
        final found = activeNotes
            .where((n) => n.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл заметку «$title».';
        await archiveNote(found.first.id);
        return 'Заметка «${found.first.title}» в архиве.';

      case 'delete_goal':
        final found = activeGoals
            .where((g) => g.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл цель «$title».';
        await archiveGoal(found.first.id);
        return 'Цель «${found.first.title}» убрана в архив.';

      case 'delete_event':
        final found = activeEvents
            .where((e) => e.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл событие «$title».';
        await archiveEvent(found.first.id);
        return 'Событие «${found.first.title}» в архиве.';

      case 'split_goal':
      case 'goal_to_tasks':
        // «Разбей цель X на задачи»: находим цель и запускаем
        // диалоговый сценарий наполнения (как при добавлении цели).
        final found = activeGoals
            .where((g) => g.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл цель «$title».';
        return _startGoalTasksFlow(found.first,
            prefix: 'Разбиваю цель «${found.first.title}».');

      case 'split_task':
      case 'task_to_steps':
        // «Разбей задачу X на шаги»: спрашиваем шаги и кладём их
        // на шкалу пути задачи.
        final found = tasks
            .where((t) => !t.isDone &&
                t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл активную задачу «$title».';
        _resetFlow();
        flowStage = 'taskSteps';
        flowTaskIds = [found.first.id];
        flowTaskIndex = 0;
        notifyListeners();
        return 'Из каких шагов состоит задача «${found.first.title}»? '
            'Перечислите через запятую или с новой строки — они появятся '
            'на шкале пути. Или напишите «пропустить».';

      case 'split_event':
      case 'event_to_tasks':
        // «Разбей событие X»: задачи подготовки с дедлайном к началу
        // события (видны и на экране задач, и в календаре).
        final found = activeEvents
            .where((e) => e.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл событие «$title».';
        _resetFlow();
        flowStage = 'goalTasks';
        flowEventStart = found.first.start;
        flowEventTitle = found.first.title;
        notifyListeners();
        return 'Из каких задач состоит подготовка к событию '
            '«${found.first.title}»? Перечислите через запятую — задачи '
            'получат дедлайны к ${fmtDateTime(found.first.start)}. '
            'Или напишите «пропустить».';

      case 'edit_task':
      case 'update_task':
      case 'correct_task':
        // «Откорректируй / внеси изменения»: находим задачу по названию
        // и применяем переданные изменения (новое название, срок,
        // приоритет, оценка времени) — без ручного ввода.
        final found = tasks
            .where((t) => !t.isDone &&
                t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл активную задачу «$title».';
        final t = found.first;
        final changes = <String>[];
        final newTitle =
            (j['new_title'] ?? j['rename_to'] ?? '').toString().trim();
        if (newTitle.isNotEmpty) {
          t.title = newTitle;
          changes.add('название: «$newTitle»');
        }
        DateTime? dl = _parseDateTime(j['date'] ?? j['deadline'], j['time']);
        if (dl == null && j['deadline_days'] != null) {
          final days = int.tryParse(j['deadline_days'].toString()) ?? 0;
          final n = DateTime.now().add(Duration(days: days));
          dl = DateTime(n.year, n.month, n.day, 18);
        }
        if (dl != null) {
          t.deadline = dl;
          changes.add('дедлайн ${fmtDateTime(dl)}');
        }
        if (j['estimate_min'] != null) {
          final est = int.tryParse(j['estimate_min'].toString());
          if (est != null && est > 0) {
            t.estimateMin = est;
            changes.add('оценка $est мин');
          }
        }
        if (j['priority'] != null) {
          t.priority = _priorityOf(j['priority']);
          changes.add('приоритет ${['низкий', 'средний', 'высокий'][t.priority]}');
        }
        if (changes.isEmpty) return 'Что именно изменить в задаче «${t.title}»?';
        await updateTask(t);
        return 'Задача «${t.title}» обновлена: ${changes.join(', ')}.';

      case 'schedule_task':
      case 'reschedule_task':
        // «Запланируй»: поставить/перенести дедлайн существующей задачи.
        final found = tasks
            .where((t) => !t.isDone &&
                t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл активную задачу «$title».';
        final t = found.first;
        DateTime? dl = _parseDateTime(j['date'] ?? j['deadline'], j['time']);
        if (dl == null && j['deadline_days'] != null) {
          final days = int.tryParse(j['deadline_days'].toString()) ?? 0;
          final n = DateTime.now().add(Duration(days: days));
          dl = DateTime(n.year, n.month, n.day, 18);
        }
        if (dl == null) return 'На когда запланировать «${t.title}»? Скажите дату.';
        t.deadline = dl;
        await updateTask(t);
        return 'Задача «${t.title}» запланирована на ${fmtDateTime(dl)}.';

      case 'cancel_task':
      case 'uncomplete_task':
        // «Отмени»: снять отметку выполнения — задача возвращается из архива.
        final found = tasks
            .where((t) => t.isDone &&
                t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл выполненную задачу «$title».';
        toggleTaskDone(found.first.id);
        return 'Выполнение задачи «${found.first.title}» отменено — она снова активна.';

      case 'link_task':
      case 'link_block':
        // «Свяжи задачу X с блоком Y»: привязка к блоку годового плана.
        final blockName = (j['block'] ?? j['text'] ?? '').toString().trim();
        final found = activeTasks
            .where((t) => t.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isEmpty) return 'Не нашёл задачу «$title».';
        final blocks = blockGoals();
        if (blocks.isEmpty) {
          return 'Блоков годового плана нет — сначала импортируйте стратегию.';
        }
        Goal? block;
        for (final g in blocks) {
          final gTitle = g.title.toLowerCase();
          final gId = g.externalId.substring(6).toLowerCase();
          final q = blockName.toLowerCase();
          if (gTitle.contains(q) || gId.contains(q)) {
            block = g;
            break;
          }
        }
        block ??= blocks.first;
        await linkTaskToBlock(found.first.id, block.externalId.substring(6));
        return 'Задача «${found.first.title}» связана с блоком «${block.title}».';

      case 'pin_habit':
      case 'add_habit':
        // Ежедневная привычка: если цель с таким названием есть — закрепляем,
        // иначе создаём новую привычку (recurDaily + pin).
        final found = goals
            .where((g) => g.title.toLowerCase().contains(title.toLowerCase()))
            .toList();
        if (found.isNotEmpty) {
          final g = found.first;
          g.recurDaily = true;
          g.isPinned = true;
          await updateGoal(g);
          return '«${g.title}» закреплена как ежедневная привычка.';
        }
        if (title.isEmpty) return 'Не хватает названия привычки.';
        await addGoal(Goal(
          title: title,
          horizonDays: 365,
          recurDaily: true,
          isPinned: true,
        ));
        return 'Ежедневная привычка «$title» создана и закреплена.';

      case 'list_today':
      case 'query_today':
        return todaySummary();

      case 'list_overdue':
      case 'query_overdue':
        final alerts = criticalAlerts();
        if (alerts.isEmpty) return 'Критических напоминаний нет. Всё под контролем!';
        return 'Внимание: ${alerts.map((a) => '${a.title} (${a.detail})').join('; ')}.';

      default:
        return '';
    }
  }

  // ---------- Диалоговый сценарий «цель -> задачи -> шаги» ----------
  /// Старт сценария для новой цели: если блок не определён — сначала
  /// спрашиваем его, затем задачи, из которых состоит цель.
  String _startGoalFlow(Goal g, {String prefix = ''}) {
    _resetFlow();
    flowGoalId = g.id;
    final blocks = blockGoals();
    if (g.block.isEmpty && blocks.isNotEmpty) {
      flowStage = 'askBlock';
      notifyListeners();
      return '$prefix\nВ какой блок разместить цель? Назовите один из: '
          '${blocks.map((b) => '«${b.title}»').join(', ')} — или напишите «пропустить».';
    }
    flowStage = 'goalTasks';
    notifyListeners();
    return '$prefix\nИз каких задач состоит цель? Перечислите через запятую '
        'или с новой строки — задачи появятся на экране «Задачи» и '
        'в календаре. Или напишите «пропустить».';
  }

  /// Старт сценария для существующей цели (команда «разбей цель»).
  String _startGoalTasksFlow(Goal g, {String prefix = ''}) {
    _resetFlow();
    flowGoalId = g.id;
    flowStage = 'goalTasks';
    notifyListeners();
    return '$prefix\nИз каких задач состоит цель «${g.title}»? Перечислите '
        'через запятую или с новой строки — они станут задачами с '
        'дедлайнами по шкале цели. Или напишите «пропустить».';
  }

  Goal? get _flowGoal {
    for (final g in goals) {
      if (g.id == flowGoalId) return g;
    }
    return null;
  }

  bool _isSkip(String t) {
    final s = t.toLowerCase().trim();
    return s == 'пропустить' ||
        s == 'пропусти' ||
        s == 'skip' ||
        s == 'отмена' ||
        s == 'не надо' ||
        s == 'без задач' ||
        s == 'без шагов';
  }

  /// Разделитель перечислений: запятые, точки с запятой, переводы строк,
  /// «•», связка « и » между пунктами.
  List<String> _splitItems(String text) => text
      .split(RegExp(r'[,;\n•]|(?:\s+и\s+(?=\S))'))
      .map((e) => e.trim().replaceAll(RegExp(r'^[.\-–—\d) ]+'), '').trim())
      .where((e) => e.length > 1)
      .map((e) => e[0].toUpperCase() + e.substring(1))
      .toList();

  /// Обработка ответа пользователя в активном сценарии.
  /// Вызывается экраном ассистента ДО парсеров команд.
  Future<String> handleFlowInput(String text) async {
    final stage = flowStage;
    if (stage == null) return '';

    switch (stage) {
      case 'askBlock':
        final g = _flowGoal;
        if (g == null) {
          _resetFlow();
          return 'Цель не найдена — сценарий завершён.';
        }
        if (_isSkip(text)) {
          flowStage = 'goalTasks';
          notifyListeners();
          return 'Хорошо, цель «${g.title}» остаётся без блока.\n'
              'Из каких задач состоит цель? Перечислите через запятую '
              'или напишите «пропустить».';
        }
        final q = text.toLowerCase();
        Goal? blk;
        for (final b in blockGoals()) {
          final bt = b.title.toLowerCase();
          final bid = b.externalId.substring(6).toLowerCase();
          if (bt.contains(q) || q.contains(bt) || bid.contains(q)) {
            blk = b;
            break;
          }
        }
        if (blk == null) {
          return 'Блок «$text» не найден. Назовите один из: '
              '${blockGoals().map((b) => '«${b.title}»').join(', ')} — или «пропустить».';
        }
        g.block = blk.externalId.substring(6);
        await updateGoal(g);
        flowStage = 'goalTasks';
        notifyListeners();
        return 'Цель «${g.title}» размещена в блоке «${blk.title}».\n'
            'Из каких задач состоит цель? Перечислите через запятую '
            'или напишите «пропустить».';

      case 'goalTasks':
        if (_isSkip(text)) {
          _resetFlow();
          return 'Принято — без задач. Цель можно наполнить позже '
              'командой «разбей цель».';
        }
        final items = _splitItems(text);
        if (items.isEmpty) {
          return 'Не расслышал пункты. Перечислите задачи через запятую '
              'или напишите «пропустить».';
        }
        final g = _flowGoal;
        final eventStart = flowEventStart;
        flowTaskIds = [];
        final n = items.length;
        for (var i = 0; i < n; i++) {
          DateTime? dl;
          String horizon = 'short';
          if (eventStart != null) {
            // Задачи подготовки к событию: равномерно от сегодня
            // к началу события.
            final now = DateTime.now();
            final total = eventStart.difference(now).inMilliseconds;
            final at = total > 0
                ? now.add(Duration(milliseconds: (total * (i + 1) / (n + 1)).round()))
                : eventStart;
            dl = DateTime(at.year, at.month, at.day, 18);
          } else if (g != null) {
            // Задачи цели: равномерно по горизонту цели — видны
            // в календаре и ложатся точками на шкалу цели.
            final days = g.horizonDays <= 0 ? 30 : g.horizonDays;
            final at = DateTime.now()
                .add(Duration(days: (days * (i + 1) / (n + 1)).ceil()));
            dl = DateTime(at.year, at.month, at.day, 18);
            horizon =
                dl.difference(DateTime.now()).inDays <= 7 ? 'short' : 'medium';
          } else {
            final now = DateTime.now();
            dl = DateTime(now.year, now.month, now.day, 20);
          }
          final t = Task(
            title: items[i],
            deadline: dl,
            goalId: g?.id ?? '',
            horizon: horizon,
          );
          await addTask(t);
          flowTaskIds.add(t.id);
        }
        flowTaskIndex = 0;
        justCreated = null; // пункты уже созданы — диалог не нужен
        flowStage = 'askSteps';
        notifyListeners();
        final where = g != null ? 'цели «${g.title}»' : 'события «$flowEventTitle»';
        final b = StringBuffer('Задачи $where:\n');
        for (var i = 0; i < items.length; i++) {
          b.writeln('• ${items[i]}');
        }
        b.write('Построить шаги или последовательность действий для '
            'каждой задачи? (да/нет)');
        return b.toString();

      case 'askSteps':
        final s = text.toLowerCase().trim();
        if (s.startsWith('да') || s == 'давай' || s == 'yes' || s == '+') {
          if (flowTaskIds.isEmpty) {
            _resetFlow();
            return 'Задач нет — шаги строить не для чего.';
          }
          flowStage = 'taskSteps';
          flowTaskIndex = 0;
          notifyListeners();
          return 'Шаги для задачи «${_flowTaskTitle()}» — перечислите '
              'через запятую или напишите «пропустить».';
        }
        _resetFlow();
        return 'Хорошо. Шаги всегда можно добавить: тап по задаче на '
            'экране «Задачи» → «Шкала пути: шаги задачи».';

      case 'taskSteps':
        final currentId = flowTaskIds[flowTaskIndex];
        if (!_isSkip(text)) {
          final items = _splitItems(text);
          for (final s in items) {
            await addStep(currentId, s);
          }
        }
        flowTaskIndex++;
        if (flowTaskIndex < flowTaskIds.length) {
          notifyListeners();
          return 'Шаги для задачи «${_flowTaskTitle()}» — перечислите '
              'через запятую или напишите «пропустить».';
        }
        final totalSteps =
            flowTaskIds.fold<int>(0, (sum, id) => sum + stepsForTask(id).length);
        final tasksN = flowTaskIds.length;
        _resetFlow();
        return 'Готово: задач — $tasksN, шагов на шкалах — $totalSteps. '
            'Шкалы видны по тапу на задачу («Сегодня», «Задачи») и на '
            'экране «Цели».';

      default:
        _resetFlow();
        return '';
    }
  }

  String _flowTaskTitle() {
    if (flowTaskIndex >= flowTaskIds.length) return '';
    final id = flowTaskIds[flowTaskIndex];
    for (final t in tasks) {
      if (t.id == id) return t.title;
    }
    return '';
  }

  // ---------- Пропущенные задачи/события (экран «Статистика») ----------
  /// Список пропущенного для окошка «Пропущено всего»: просроченные
  /// задачи, ежедневные серии и привычки с накопленными пропусками,
  /// прошедшие события (за последние 30 дней). tabIndex — вкладка,
  /// где элемент находится (для перехода по тапу).
  /// ВАЖНО: карточка «Пропущено всего» считает missedCount по ВСЕМ
  /// задачам (включая выполненные и архивные экземпляры ежедневных
  /// серий), поэтому список собирается по тем же данным — иначе
  /// карточка показывает число, а окошко пустое.
  List<({String kind, String id, String title, String detail, int tab})>
      missedItems() {
    final now = DateTime.now();
    final res =
        <({String kind, String id, String title, String detail, int tab})>[];
    for (final t in tasks) {
      if (t.purged) continue;
      final daily = t.recurDaily || t.horizon == 'daily';
      final dl = t.deadline;
      if (!daily &&
          !t.isArchived &&
          !t.isDone &&
          dl != null &&
          dl.isBefore(now)) {
        res.add((
          kind: 'task',
          id: t.id,
          title: t.title,
          detail: 'дедлайн был ${fmtDateTime(dl)}',
          tab: 3,
        ));
      } else if (!daily && t.missedCount > 0) {
        res.add((
          kind: 'task',
          id: t.id,
          title: t.title,
          detail: 'пропусков: ${t.missedCount}',
          tab: 3,
        ));
      }
    }
    // Ежедневные серии: пропуски накапливаются на экземплярах, которые
    // после выполнения уходят в архив — группируем серию по названию,
    // чтобы список совпадал с суммой в карточке.
    final seriesMissed = <String, int>{};
    final seriesActiveId = <String, String>{};
    for (final t in tasks) {
      if (t.purged) continue;
      if (!(t.recurDaily || t.horizon == 'daily')) continue;
      if (t.missedCount > 0) {
        seriesMissed[t.title] = (seriesMissed[t.title] ?? 0) + t.missedCount;
      }
      if (!t.isArchived && !t.isDone) seriesActiveId[t.title] = t.id;
    }
    for (final e in seriesMissed.entries) {
      res.add((
        kind: 'task',
        id: seriesActiveId[e.key] ?? '',
        title: e.key,
        detail: 'ежедневная · пропусков: ${e.value}',
        tab: 3,
      ));
    }
    for (final g in goals) {
      if (g.recurDaily && g.missedCount > 0) {
        res.add((
          kind: 'goal',
          id: g.id,
          title: g.title,
          detail:
              'привычка${g.isArchived ? ' (в архиве)' : ''} · пропусков: ${g.missedCount}',
          tab: 4,
        ));
      }
    }
    for (final e in activeEvents) {
      if (e.start.isBefore(now) &&
          e.start.isAfter(now.subtract(const Duration(days: 30)))) {
        res.add((
          kind: 'event',
          id: e.id,
          title: e.title,
          detail: 'прошло ${fmtDateTime(e.start)}',
          tab: 2,
        ));
      }
    }
    return res;
  }

  /// Бар дней ежедневной задачи для дерева связей: одна отметка на
  /// каждый день интервала задачи (интервал в год — 365 отметок).
  /// Статус дня: true — выполнен (зелёная галочка), false — пропущен
  /// (красный крест), null — выходной или день ещё не наступил.
  /// Выполнение определяется по экземплярам серии (ежедневная задача
  /// при выполнении порождает экземпляр на следующий день с тем же
  /// названием и внешним кодом), выходные — по dayOffDates.
  List<({DateTime day, bool? done})> dailyDayBar(Task t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final series = tasks
        .where((x) =>
            x.recurDaily && x.title == t.title && x.externalId == t.externalId)
        .toList();
    if (series.isEmpty) series.add(t);

    DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
    var start = dateOnly(series.first.createdAt);
    DateTime? lastDeadline;
    for (final x in series) {
      final c = dateOnly(x.createdAt);
      if (c.isBefore(start)) start = c;
      final dl = x.deadline;
      if (dl != null &&
          (lastDeadline == null || dateOnly(dl).isAfter(lastDeadline))) {
        lastDeadline = dateOnly(dl);
      }
    }
    // Без дедлайна интервал — год от старта; с дедлайном — до него,
    // но не длиннее года и не короче сегодняшнего дня.
    final maxEnd = start.add(const Duration(days: 364));
    var end = lastDeadline ?? maxEnd;
    if (end.isAfter(maxEnd)) end = maxEnd;
    if (end.isBefore(today)) end = today;
    if (end.isBefore(start)) end = start;

    final daysOff = t.dayOffDates.toSet();
    final doneDays = <String>{};
    for (final x in series) {
      final da = x.doneAt;
      if (x.isDone && da != null) {
        doneDays.add(
            '${da.year.toString().padLeft(4, '0')}-${da.month.toString().padLeft(2, '0')}-${da.day.toString().padLeft(2, '0')}');
      }
    }

    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final res = <({DateTime day, bool? done})>[];
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      final k = key(d);
      if (doneDays.contains(k)) {
        res.add((day: d, done: true));
      } else if (daysOff.contains(k) || !d.isBefore(today)) {
        res.add((day: d, done: null));
      } else {
        res.add((day: d, done: false));
      }
    }
    return res;
  }

  /// Комментарий к событию (причина пропуска) с записью в журнал.
  Future<void> appendEventComment(String id, String text) async {
    EventItem? e;
    for (final x in events) {
      if (x.id == id) {
        e = x;
        break;
      }
    }
    if (e == null) return;
    e.comment = e.comment.isEmpty ? text : '${e.comment}\n$text';
    await addFeedback(
        text.contains('ричин') ? 'late_reason' : 'comment', e.title, text);
    await updateEvent(e);
  }

  /// Комментарий к цели/привычке с записью в журнал.
  Future<void> appendGoalComment(String id, String text) async {
    Goal? g;
    for (final x in goals) {
      if (x.id == id) {
        g = x;
        break;
      }
    }
    if (g == null) return;
    g.comment = g.comment.isEmpty ? text : '${g.comment}\n$text';
    await addFeedback(
        text.contains('ричин') ? 'late_reason' : 'comment', g.title, text);
    await updateGoal(g);
  }

  // ---------- Экспорт отчёта ----------
  /// Markdown-отчёт: достигнутые и пропущенные цели/задачи, своевременность.
  /// Нужен для аудита: при следующем планировании видно, сколько времени
  /// реально уходит на похожие действия.
  String buildReport() {
    final b = StringBuffer();
    b.writeln('# Отчёт планировщика');
    b.writeln('Сформирован: ${fmtDateTime(DateTime.now())}');
    b.writeln();

    final doneGoals =
        goals.where((g) => g.isDone && !g.recurDaily).toList();
    final activeG = activeGoals.where((g) => !g.recurDaily).toList();
    final habits = goals.where((g) => g.recurDaily).toList();
    final doneTasks = tasks.where((t) => t.isDone).toList();
    final onTimeN = doneTasks.where((t) => t.onTime == 1).length;
    final lateN = doneTasks.where((t) => t.onTime == 0).length;
    final missedTasks =
        tasks.fold<int>(0, (s, t) => s + t.missedCount);
    final missedGoals = goals.fold<int>(0, (s, g) => s + g.missedCount);

    b.writeln('## Сводка');
    b.writeln('- Целей достигнуто: ${doneGoals.length}');
    b.writeln('- Целей в работе: ${activeG.length}');
    b.writeln('- Задач выполнено: ${doneTasks.length} '
        '(вовремя: $onTimeN, с опозданием: $lateN)');
    b.writeln('- Пропусков всего: ${missedTasks + missedGoals}');
    b.writeln();

    if (doneGoals.isNotEmpty) {
      b.writeln('## Достигнутые цели');
      for (final g in doneGoals) {
        final days =
            g.doneAt == null ? null : g.doneAt!.difference(g.createdAt).inDays;
        b.writeln('- ${g.title}'
            '${days != null ? ' — за $days дн. (план: ${g.horizonDays} дн.)' : ''}'
            '${g.comment.isNotEmpty ? '\n  Комментарий: ${g.comment}' : ''}');
      }
      b.writeln();
    }

    if (habits.isNotEmpty) {
      b.writeln('## Ежедневные привычки');
      for (final g in habits) {
        b.writeln('- ${g.title}: пропусков ${g.missedCount}'
            '${g.lastDoneAt != null ? ', последний раз ${fmtDateTime(g.lastDoneAt!)}' : ''}');
      }
      b.writeln();
    }

    if (lateN > 0) {
      b.writeln('## Выполнено с опозданием');
      for (final t in doneTasks.where((t) => t.onTime == 0)) {
        b.writeln('- ${t.title}'
            '${t.deadline != null ? ' (дедлайн ${fmtDateTime(t.deadline!)})' : ''}'
            '${t.comment.isNotEmpty ? '\n  Причина: ${t.comment}' : ''}');
      }
      b.writeln();
    }

    final overdue = activeTasks
        .where((t) => t.deadline != null && t.deadline!.isBefore(DateTime.now()))
        .toList();
    if (overdue.isNotEmpty) {
      b.writeln('## Просрочено сейчас');
      for (final t in overdue) {
        b.writeln('- ${t.title} (дедлайн ${fmtDateTime(t.deadline!)})'
            '${t.comment.isNotEmpty ? ' — ${t.comment}' : ''}');
      }
      b.writeln();
    }

    // Ориентир для будущего планирования: среднее время по типам задач.
    final withEst = doneTasks.where((t) => t.estimateMin > 0).toList();
    if (withEst.isNotEmpty) {
      final avg =
          withEst.fold<int>(0, (s, t) => s + t.estimateMin) ~/ withEst.length;
      b.writeln('## Ориентиры для планирования');
      b.writeln('- Средняя оценка задачи: $avg мин');
      b.writeln('- Доля выполненных вовремя: '
          '${doneTasks.isEmpty ? 0 : (onTimeN * 100 ~/ doneTasks.length)}%');
    }

    if (feedback.isNotEmpty) {
      b.writeln();
      b.writeln('## Журнал обратной связи (причины пропусков)');
      for (final e in feedback.take(50)) {
        b.writeln('- [${fmtDateTime(e.createdAt)}] ${e.itemTitle}: ${e.text}');
      }
    }

    // Награды за продуктивные дни: какие награды выбирались и какой
    // прогресс дня был на тот момент — для поиска наград, после которых
    // дни получаются продуктивнее. Пропуски тоже учитываются.
    if (dayRewards.isNotEmpty) {
      b.writeln();
      b.writeln('## Награды за продуктивные дни');
      for (final r in dayRewards.take(50)) {
        b.writeln('- ${fmtDate(r.day)} — выполнено ${(r.pct * 100).round()}%: '
            '${r.skipped ? 'награду пропустил(а)' : r.reward}');
      }
      // Средний прогресс дня по каждой награде (без пропусков).
      final byReward = <String, List<double>>{};
      for (final r in dayRewards) {
        if (r.skipped || r.reward.isEmpty) continue;
        byReward.putIfAbsent(r.reward, () => []).add(r.pct);
      }
      if (byReward.isNotEmpty) {
        b.writeln();
        b.writeln('## Средний прогресс дня по наградам');
        final rows = byReward.entries.toList()
          ..sort((a, b) {
            final am = a.value.reduce((x, y) => x + y) / a.value.length;
            final bm = b.value.reduce((x, y) => x + y) / b.value.length;
            return bm.compareTo(am);
          });
        for (final e in rows) {
          final avg = e.value.reduce((x, y) => x + y) / e.value.length;
          b.writeln('- ${e.key}: ${(avg * 100).round()}% '
              '(выбиралось ${e.value.length} раз)');
        }
      }
      final skips = dayRewards.where((r) => r.skipped).length;
      if (skips > 0) {
        b.writeln('- Пропусков выбора награды: $skips');
      }
    }
    return b.toString();
  }

  // ---------- Полная выгрузка состояния ----------
  /// Все задачи, цели, события, заметки, шаги, журнал, посуточные
  /// отметки закрепов, финучёт, дневник и банк вопросов одним JSON.
  /// Этот же файл загружается обратно на экране «Стратегия» (кнопка
  /// «Загрузить»): восстановление 1-в-1 — ежедневные остаются
  /// ежедневными, привязки к целям/блокам и дедлайны сохраняются.
  String buildFullExport() {
    const encoder = JsonEncoder.withIndent('  ');
    // Фото-подтверждения шагов встраиваем в выгрузку (base64): они
    // привязаны к своим шагам по имени файла и не теряются при
    // переустановке — восстановление раскладывает их обратно.
    final photos = <Map<String, String>>[];
    for (final s in steps) {
      if (s.photoPath.isEmpty) continue;
      try {
        final f = File(s.photoPath);
        if (!f.existsSync()) continue;
        final bytes = f.readAsBytesSync();
        if (bytes.length > 8 * 1024 * 1024) continue; // страховка от гигантов
        photos.add({
          'stepId': s.id,
          'fileName': s.photoPath.split('/').last,
          'base64': base64Encode(bytes),
        });
      } catch (_) {}
    }
    return encoder.convert({
      'app': 'planner',
      'kind': 'full_backup',
      'version': 14,
      'exportedAt': DateTime.now().toIso8601String(),
      'notes': notes.map((e) => e.toMap()).toList(),
      'tasks': tasks.map((e) => e.toMap()).toList(),
      'goals': goals.map((e) => e.toMap()).toList(),
      'events': events.map((e) => e.toMap()).toList(),
      'task_steps': steps.map((e) => e.toMap()).toList(),
      'task_resources': resources.map((e) => e.toMap()).toList(),
      'feedback': feedback.map((e) => e.toMap()).toList(),
      'day_rewards': dayRewards.map((e) => e.toMap()).toList(),
      'pin_log': pinLogs.map((e) => e.toMap()).toList(),
      'finance_entries': finEntries.map((e) => e.toMap()).toList(),
      'fin_passive': finPassive.map((e) => e.toMap()).toList(),
      'fin_purchases': finPurchases.map((e) => e.toMap()).toList(),
      'diary_entries': diaryEntries.map((e) => e.toMap()).toList(),
      'psy_questions': psyQuestions.map((e) => e.toMap()).toList(),
      if (photos.isNotEmpty) 'photos': photos,
      if (importedFileName != null) 'strategyFile': importedFileName,
      if (strategyRaw != null) 'strategyJson': strategyRaw,
    });
  }

  /// Признак файла полной выгрузки (а не tasks.json стратегии):
  /// объект с меткой приложения и массивом задач.
  static bool looksLikeFullBackup(String raw) {
    try {
      final d = jsonDecode(raw);
      return d is Map && d['app'] == 'planner' && d['tasks'] is List;
    } catch (_) {
      return false;
    }
  }

  /// Восстановление полной выгрузки: все таблицы заменяются содержимым
  /// файла 1-в-1 (id, ежедневность, закрепы, привязки к целям и блокам,
  /// дедлайны, прогресс, посуточный журнал — всё как на момент выгрузки).
  /// Совместима со старыми выгрузками (version 9, без pin_log).
  /// Возвращает текст-итог для снэкбара.
  Future<String> restoreFullBackup(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['app'] != 'planner' ||
        decoded['tasks'] is! List) {
      throw const FormatException('Это не файл полной выгрузки планера');
    }
    List<Map<String, dynamic>> rows(String key) => [
          for (final e in (decoded[key] as List? ?? const []))
            if (e is Map) Map<String, dynamic>.from(e),
        ];
    final newNotes = rows('notes').map(Note.fromMap).toList();
    final newTasks = rows('tasks').map(Task.fromMap).toList();
    final newGoals = rows('goals').map(Goal.fromMap).toList();
    final newEvents = rows('events').map(EventItem.fromMap).toList();
    final newSteps = rows('task_steps').map(TaskStep.fromMap).toList();
    final newFeedback = rows('feedback').map(FeedbackEntry.fromMap).toList();
    final newRewards = rows('day_rewards').map(DayReward.fromMap).toList();
    final newPinLogs = rows('pin_log').map(PinLog.fromMap).toList();
    final newFin = rows('finance_entries').map(FinEntry.fromMap).toList();
    final newResources =
        rows('task_resources').map(TaskResource.fromMap).toList();
    final newDiary = rows('diary_entries').map(DiaryEntry.fromMap).toList();
    final newPsy = rows('psy_questions').map(PsyQuestion.fromMap).toList();
    final newFinPassive =
        rows('fin_passive').map(FinPassive.fromMap).toList();
    final newFinPurchases =
        rows('fin_purchases').map(FinPurchase.fromMap).toList();

    // 1) Снимаем все запланированные напоминания старого состояния.
    await notifications.cancelAll();

    // 2) Заменяем содержимое таблиц целиком.
    final db = AppDb.instance;
    const tables = [
      'notes',
      'tasks',
      'goals',
      'events',
      'task_steps',
      'task_resources',
      'feedback',
      'day_rewards',
      'pin_log',
      'finance_entries',
      'fin_passive',
      'fin_purchases',
      'diary_entries',
      'psy_questions',
    ];
    for (final t in tables) {
      await db.clear(t);
    }
    for (final e in newNotes) {
      await db.insert('notes', e.toMap());
    }
    for (final e in newTasks) {
      await db.insert('tasks', e.toMap());
    }
    // Для разбора задвоений ежедневных: фиксируем, сколько ежедневных
    // (и сколько активных) приехало с файлом выгрузки.
    final dailyIn = newTasks
        .where((t) => (t.recurDaily || t.horizon == 'daily') && !t.isArchived)
        .length;
    DiagLog.add('import',
        'восстановление из JSON: задач ${newTasks.length}, активных ежедневных $dailyIn');
    for (final e in newGoals) {
      await db.insert('goals', e.toMap());
    }
    for (final e in newEvents) {
      await db.insert('events', e.toMap());
    }
    for (final e in newSteps) {
      await db.insert('task_steps', e.toMap());
    }
    for (final e in newResources) {
      await db.insert('task_resources', e.toMap());
    }
    for (final e in newFeedback) {
      await db.insert('feedback', e.toMap());
    }
    for (final e in newRewards) {
      await db.insert('day_rewards', e.toMap());
    }
    for (final e in newPinLogs) {
      await db.insert('pin_log', e.toMap());
    }
    for (final e in newFin) {
      await db.insert('finance_entries', e.toMap());
    }
    for (final e in newDiary) {
      await db.insert('diary_entries', e.toMap());
    }
    for (final e in newPsy) {
      await db.insert('psy_questions', e.toMap());
    }
    for (final e in newFinPassive) {
      await db.insert('fin_passive', e.toMap());
    }
    for (final e in newFinPurchases) {
      await db.insert('fin_purchases', e.toMap());
    }

    // Фото из выгрузки раскладываем обратно в documents/photos и
    // прописываем новые пути в шагах (старые пути указывали на
    // документы ПРЕЖНЕЙ установки и после переустановки недействительны).
    final photoRows = decoded['photos'];
    if (photoRows is List && photoRows.isNotEmpty) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory('${docs.path}/photos');
        await dir.create(recursive: true);
        final pathByStep = <String, String>{};
        for (final p in photoRows) {
          if (p is! Map) continue;
          final stepId = (p['stepId'] ?? '').toString();
          final fileName = (p['fileName'] ?? '').toString();
          final b64 = (p['base64'] ?? '').toString();
          if (stepId.isEmpty || fileName.isEmpty || b64.isEmpty) continue;
          try {
            final f = File('${dir.path}/$fileName');
            await f.writeAsBytes(base64Decode(b64));
            pathByStep[stepId] = f.path;
          } catch (_) {}
        }
        if (pathByStep.isNotEmpty) {
          for (final s in newSteps) {
            final np = pathByStep[s.id];
            if (np != null && s.photoPath != np) {
              s.photoPath = np;
              await db.updateRow('task_steps', s.toMap(), s.id);
            }
          }
        }
      } catch (_) {}
    }

    // 3) Возвращаем закреплённый файл стратегии (если был выгружен) —
    // экран «Стратегия» после восстановления выглядит как прежде.
    final stratRaw = decoded['strategyJson']?.toString();
    final stratName =
        decoded['strategyFile']?.toString() ?? 'planner_export.json';
    final prefs = await SharedPreferences.getInstance();
    if (stratRaw != null && stratRaw.isNotEmpty) {
      await prefs.setString('strategyJson', stratRaw);
      await prefs.setString('strategyFileName', stratName);
    } else {
      await prefs.remove('strategyJson');
      await prefs.remove('strategyFileName');
    }

    // 4) Перечитываем состояние из БД как при обычном запуске
    // (включая перенос ежедневных задач на сегодня), затем
    // перепланируем напоминания уже для восстановленных данных.
    await load();
    await rescheduleAllReminders();

    final daily = newTasks.where((t) => t.recurDaily || t.isPinned).length;
    return 'Восстановлено: задач ${newTasks.length} (ежедневных $daily), '
        'целей ${newGoals.length}, событий ${newEvents.length}, '
        'заметок ${newNotes.length}'
        '${newFin.isNotEmpty ? ', финансовых записей ${newFin.length}' : ''}'
        '${newFinPassive.isNotEmpty ? ', активов/пассивных ${newFinPassive.length}' : ''}'
        '${newFinPurchases.isNotEmpty ? ', покупок ${newFinPurchases.length}' : ''}'
        '${newDiary.isNotEmpty ? ', записей дневника ${newDiary.length}' : ''}'
        '${newPsy.isNotEmpty ? ', вопросов банка ${newPsy.length}' : ''}.';
  }

  /// Сводка «что у меня сегодня»: список с пунктами, каждый пункт
  /// обязательно с НОВОЙ строки — так читается в чате ассистента.
  String todaySummary() {
    final now = DateTime.now();
    final ev = eventsForDay(now);
    final ts = tasksForDay(now);
    final b = StringBuffer('Сегодня, ${fmtDate(now)}:');
    if (ev.isEmpty && ts.isEmpty) {
      b.write('\n• Планов нет — день свободен.');
    } else {
      for (final e in ev) {
        b.write('\n• Событие «${e.title}» в ${fmtTime(e.start)} '
            '(${e.durationMin} мин)');
      }
      for (final t in ts) {
        b.write('\n• Задача «${t.title}»'
            '${t.deadline != null ? ' — до ${fmtTime(t.deadline!)}' : ''}'
            '${t.isKeyAction ? ' (ключевое действие)' : ''}');
      }
    }
    return b.toString();
  }
}
