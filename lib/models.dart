/// Доменные модели. У задач и целей есть isArchived — архивация вместо удаления.
library;

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

bool _toBool(dynamic v, [bool def = false]) =>
    v == null ? def : (v == 1 || v == true);

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

class Note {
  String id;
  String title;
  String text;
  bool isArchived;
  DateTime createdAt;
  String importTag; // метка импорта tasks.json ('' = создано вручную)
  bool isPinned; // закреплена в блоке «Ежедневные» на экране целей

  Note({
    String? id,
    this.title = '',
    this.text = '',
    this.isArchived = false,
    DateTime? createdAt,
    this.importTag = '',
    this.isPinned = false,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'text': text,
        'isArchived': isArchived ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'importTag': importTag,
        'isPinned': isPinned ? 1 : 0,
      };

  static Note fromMap(Map<String, dynamic> m) => Note(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        isArchived: _toBool(m['isArchived']),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
        importTag: (m['importTag'] ?? '').toString(),
        isPinned: _toBool(m['isPinned']),
      );
}

class Task {
  String id;
  String title;
  DateTime? deadline;
  int estimateMin;
  int priority; // 0 low, 1 medium, 2 high
  bool isDone;
  bool isArchived;
  DateTime createdAt;
  DateTime? doneAt;
  // --- поля импорта tasks.json ---
  String externalId; // id из файла (HOME-01 и т.п.)
  String block; // блок годового плана (HOME, FIN, ...)
  String metric; // метрика результата
  String importTag; // метка сессии импорта ('' = создано вручную)
  bool recurDaily; // ежедневная задача: при выполнении создаётся экземпляр на завтра
  bool isPinned; // закреплена в блоке «Ежедневные» на экране целей
  bool isKeyAction; // ключевое (целевое) действие — без него результат недостижим
  int missedCount; // сколько раз ежедневная задача была пропущена
  String goalId; // привязка к цели ('' = без цели); точка на шкале цели
  String horizon; // 'daily' | 'short' | 'medium' — положение на шкале цели
  String comment; // комментарий / причина пропуска дедлайна
  int onTime; // -1 неизвестно, 0 выполнено с опозданием, 1 вовремя
  int progressPct; // ежедневные: накопленный процент (0..100)
  int pctStep; // шаг процента за одну отметку (10/20/25/50/100)
  List<String> dayOffDates; // даты «выходного» (yyyy-MM-dd) — пропуск не считается
  String linkedBlock; // дополнительный блок-цель (externalId блока) для дерева связей
  int actualMin; // фактическое время выполнения, минут (вводит пользователь)
  int sortNum; // номер очерёдности на экране «Сегодня» (0 = без номера)
  double manualOrder; // ручной порядок перетаскиванием (0 = не задан)
  bool purged; // удалена из архива мягко: скрыта везде, кроме истории прошлых дней
  String parentTaskId; // задача слита внутрь другой (блок «однородных»), '' = самостоятельная
  bool isDayReview; // задача «итоги дня»: на её карточке — значок дневника

  Task({
    String? id,
    this.title = '',
    this.deadline,
    this.estimateMin = 30,
    this.priority = 1,
    this.isDone = false,
    this.isArchived = false,
    DateTime? createdAt,
    this.doneAt,
    this.externalId = '',
    this.block = '',
    this.metric = '',
    this.importTag = '',
    this.recurDaily = false,
    this.isPinned = false,
    this.isKeyAction = false,
    this.missedCount = 0,
    this.goalId = '',
    this.horizon = 'short',
    this.comment = '',
    this.onTime = -1,
    this.progressPct = 0,
    this.pctStep = 100,
    List<String>? dayOffDates,
    this.linkedBlock = '',
    this.actualMin = 0,
    this.sortNum = 0,
    this.manualOrder = 0,
    this.purged = false,
    this.parentTaskId = '',
    this.isDayReview = false,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        dayOffDates = dayOffDates ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'deadline': deadline?.toIso8601String(),
        'estimateMin': estimateMin,
        'priority': priority,
        'isDone': isDone ? 1 : 0,
        'isArchived': isArchived ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'externalId': externalId,
        'block': block,
        'metric': metric,
        'importTag': importTag,
        'recurDaily': recurDaily ? 1 : 0,
        'isPinned': isPinned ? 1 : 0,
        'isKeyAction': isKeyAction ? 1 : 0,
        'missedCount': missedCount,
        'goalId': goalId,
        'horizon': horizon,
        'comment': comment,
        'onTime': onTime,
        'progressPct': progressPct,
        'pctStep': pctStep,
        'dayOffDates': dayOffDates.join(';'),
        'linkedBlock': linkedBlock,
        'actualMin': actualMin,
        'sortNum': sortNum,
        'manualOrder': manualOrder,
        'purged': purged ? 1 : 0,
        'parentTaskId': parentTaskId,
        'isDayReview': isDayReview ? 1 : 0,
      };

  static Task fromMap(Map<String, dynamic> m) => Task(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        deadline: _toDate(m['deadline']),
        estimateMin: (m['estimateMin'] as num?)?.toInt() ?? 30,
        priority: (m['priority'] as num?)?.toInt() ?? 1,
        isDone: _toBool(m['isDone']),
        isArchived: _toBool(m['isArchived']),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
        doneAt: _toDate(m['doneAt']),
        externalId: (m['externalId'] ?? '').toString(),
        block: (m['block'] ?? '').toString(),
        metric: (m['metric'] ?? '').toString(),
        importTag: (m['importTag'] ?? '').toString(),
        recurDaily: _toBool(m['recurDaily']),
        isPinned: _toBool(m['isPinned']),
        isKeyAction: _toBool(m['isKeyAction']),
        missedCount: (m['missedCount'] as num?)?.toInt() ?? 0,
        goalId: (m['goalId'] ?? '').toString(),
        horizon: (m['horizon'] ?? 'short').toString(),
        comment: (m['comment'] ?? '').toString(),
        onTime: (m['onTime'] as num?)?.toInt() ?? -1,
        progressPct: (m['progressPct'] as num?)?.toInt() ?? 0,
        pctStep: (m['pctStep'] as num?)?.toInt() ?? 100,
        dayOffDates: (m['dayOffDates'] ?? '')
            .toString()
            .split(';')
            .where((e) => e.isNotEmpty)
            .toList(),
        linkedBlock: (m['linkedBlock'] ?? '').toString(),
        actualMin: (m['actualMin'] as num?)?.toInt() ?? 0,
        sortNum: (m['sortNum'] as num?)?.toInt() ?? 0,
        manualOrder: (m['manualOrder'] as num?)?.toDouble() ?? 0,
        purged: _toBool(m['purged']),
        parentTaskId: (m['parentTaskId'] ?? '').toString(),
        isDayReview: _toBool(m['isDayReview']),
      );
}

/// Шаг внутри задачи (точка на шкале пути задачи).
/// Если у задачи задана метрика, к шагу можно прикрепить фото-подтверждение.
class TaskStep {
  String id;
  String taskId;
  String title;
  bool isDone;
  int priority; // 0 низкий (волны), 1 средний (!), 2 высокий (костюм)
  bool isKeyAction; // целевое действие (молния)
  String photoPath; // фото-подтверждение ('' = нет)
  DateTime? doneAt;
  int ord; // порядок на шкале
  int iterations; // сколько итераций запланировано на шаг (минимум 1)
  int times; // «количество раз» — сколько раз шаг повторяется (минимум 1)

  TaskStep({
    String? id,
    this.taskId = '',
    this.title = '',
    this.isDone = false,
    this.priority = 1,
    this.isKeyAction = false,
    this.photoPath = '',
    this.doneAt,
    this.ord = 0,
    this.iterations = 1,
    this.times = 1,
  }) : id = id ?? newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'title': title,
        'isDone': isDone ? 1 : 0,
        'priority': priority,
        'isKeyAction': isKeyAction ? 1 : 0,
        'photoPath': photoPath,
        'doneAt': doneAt?.toIso8601String(),
        'ord': ord,
        'iterations': iterations,
        'times': times,
      };

  static TaskStep fromMap(Map<String, dynamic> m) => TaskStep(
        id: m['id'].toString(),
        taskId: (m['taskId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        isDone: _toBool(m['isDone']),
        priority: (m['priority'] as num?)?.toInt() ?? 1,
        isKeyAction: _toBool(m['isKeyAction']),
        photoPath: (m['photoPath'] ?? '').toString(),
        doneAt: _toDate(m['doneAt']),
        ord: (m['ord'] as num?)?.toInt() ?? 0,
        iterations: ((m['iterations'] as num?)?.toInt() ?? 1).clamp(1, 999),
        times: ((m['times'] as num?)?.toInt() ?? 1).clamp(1, 999),
      );
}

/// Запись финансового учёта: доход или расход от источника/статьи,
/// привязанная (по желанию) к блоку годового плана.
class FinEntry {
  String id;
  String kind; // 'income' | 'expense'
  String source; // источник дохода / статья расхода
  double amount;
  String block; // код блока ('' = без блока)
  DateTime day; // к какому дню относится операция
  String note;
  DateTime createdAt;

  FinEntry({
    String? id,
    this.kind = 'expense',
    this.source = '',
    this.amount = 0,
    this.block = '',
    DateTime? day,
    this.note = '',
    DateTime? createdAt,
  })  : id = id ?? newId(),
        day = day ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  bool get isIncome => kind == 'income';

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'source': source,
        'amount': amount,
        'block': block,
        'day': DateTime(day.year, day.month, day.day).toIso8601String(),
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  static FinEntry fromMap(Map<String, dynamic> m) => FinEntry(
        id: m['id'].toString(),
        kind: (m['kind'] ?? 'expense').toString(),
        source: (m['source'] ?? '').toString(),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        block: (m['block'] ?? '').toString(),
        day: _toDate(m['day']) ?? DateTime.now(),
        note: (m['note'] ?? '').toString(),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}

/// Запись журнала обратной связи (причины пропусков и т.п.) —
/// выгружается для аудита планирования.
class FeedbackEntry {
  String id;
  DateTime createdAt;
  String kind; // 'late_reason' | 'comment'
  String itemTitle;
  String text;

  FeedbackEntry({
    String? id,
    DateTime? createdAt,
    this.kind = 'comment',
    this.itemTitle = '',
    this.text = '',
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind,
        'itemTitle': itemTitle,
        'text': text,
      };

  static FeedbackEntry fromMap(Map<String, dynamic> m) => FeedbackEntry(
        id: m['id'].toString(),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
        kind: (m['kind'] ?? 'comment').toString(),
        itemTitle: (m['itemTitle'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
      );
}

/// Выбранная награда за продуктивный день (экран «Сегодня»).
/// Хранится для статистики «после каких наград дни продуктивнее».
/// skipped == true — пользователь нажал «Пропустить» (тоже учитываем).
class DayReward {
  String id;
  DateTime day; // день, за который выдана награда (дата без времени)
  int tier; // порог: 1 = 60%+, 2 = 80%+ (100% — особое сообщение в tier 2)
  double pct; // доля выполненных задач на момент награды (0..1)
  String reward; // текст награды ('' при пропуске)
  bool skipped;
  DateTime createdAt;

  DayReward({
    String? id,
    required this.day,
    this.tier = 1,
    this.pct = 0,
    this.reward = '',
    this.skipped = false,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': DateTime(day.year, day.month, day.day).toIso8601String(),
        'tier': tier,
        'pct': pct,
        'reward': reward,
        'skipped': skipped ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
      };

  static DayReward fromMap(Map<String, dynamic> m) => DayReward(
        id: m['id'].toString(),
        day: _toDate(m['date']) ?? DateTime.now(),
        tier: int.tryParse('${m['tier']}') ?? 1,
        pct: double.tryParse('${m['pct']}') ?? 0,
        reward: (m['reward'] ?? '').toString(),
        skipped: m['skipped'] == 1,
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}

/// Посуточная отметка закреплённой (ежедневной) задачи: выполнена она
/// в конкретный день или нет. Позволяет вести учёт выполнения ежедневных
/// задач независимо от того, задана ли у задачи дата дедлайна.
class PinLog {
  String id;
  String taskId;
  String title; // дублируем название: в статистике видно даже после архивации
  DateTime day; // день отметки (дата без времени)
  bool done;

  PinLog({
    String? id,
    this.taskId = '',
    this.title = '',
    required this.day,
    this.done = false,
  }) : id = id ?? newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'title': title,
        'day': DateTime(day.year, day.month, day.day).toIso8601String(),
        'done': done ? 1 : 0,
      };

  static PinLog fromMap(Map<String, dynamic> m) => PinLog(
        id: m['id'].toString(),
        taskId: (m['taskId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        day: _toDate(m['day']) ?? DateTime.now(),
        done: _toBool(m['done']),
      );
}

class Goal {
  String id;
  String title;
  int horizonDays;
  double progress; // 0.0 .. 1.0
  bool isDone;
  bool isArchived;
  DateTime createdAt;
  // --- поля импорта tasks.json ---
  String externalId; // 'block:HOME' и т.п.
  String importTag;
  // --- привычки ---
  bool recurDaily; // ежедневная цель-привычка (isDone = «выполнено сегодня»)
  bool isPinned; // закреплена в блоке «Ежедневные»
  DateTime? lastDoneAt; // когда привычка выполнялась в последний раз
  DateTime? lastMissAt; // когда последний раз засчитан пропуск (раз в день)
  int missedCount; // сколько дней привычка была пропущена
  String comment; // комментарий / суть цели
  String motivation; // геймификация: зачем цель, какое ощущение хочется
  String reward; // геймификация: приз за достижение
  DateTime? doneAt; // когда цель достигнута
  List<String> dayOffDates; // даты «выходного» у привычки — пропуск не считается
  String icon; // значок блока (ключ из BlockIcons), '' = по умолчанию
  String criteria; // критерии достижения цели
  String ifFail; // план, если цель не будет достигнута
  int priority; // 0 низкий, 1 средний, 2 высокий (команда «добавь цель»)
  String block; // блок годового плана, к которому отнесена цель ('' = без блока)
  // Компенсация прогресса: удалённые из архива задачи блока оставляют
  // свой вклад (carry), чтобы прогресс не откатывался назад.
  int carryDone;
  int carryTotal;
  // Ручной порядок блока на древе пути (перетаскивание завязи
  // вверх/вниз; 0 = не задан — блок идёт по рангу приоритетов).
  double manualOrder;

  Goal({
    String? id,
    this.title = '',
    this.horizonDays = 30,
    this.progress = 0,
    this.isDone = false,
    this.isArchived = false,
    DateTime? createdAt,
    this.externalId = '',
    this.importTag = '',
    this.recurDaily = false,
    this.isPinned = false,
    this.lastDoneAt,
    this.lastMissAt,
    this.missedCount = 0,
    this.comment = '',
    this.motivation = '',
    this.reward = '',
    this.doneAt,
    List<String>? dayOffDates,
    this.icon = '',
    this.criteria = '',
    this.ifFail = '',
    this.priority = 1,
    this.block = '',
    this.carryDone = 0,
    this.carryTotal = 0,
    this.manualOrder = 0,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        dayOffDates = dayOffDates ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'horizonDays': horizonDays,
        'progress': progress,
        'isDone': isDone ? 1 : 0,
        'isArchived': isArchived ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'externalId': externalId,
        'importTag': importTag,
        'recurDaily': recurDaily ? 1 : 0,
        'isPinned': isPinned ? 1 : 0,
        'lastDoneAt': lastDoneAt?.toIso8601String(),
        'lastMissAt': lastMissAt?.toIso8601String(),
        'missedCount': missedCount,
        'comment': comment,
        'motivation': motivation,
        'reward': reward,
        'doneAt': doneAt?.toIso8601String(),
        'dayOffDates': dayOffDates.join(';'),
        'icon': icon,
        'criteria': criteria,
        'ifFail': ifFail,
        'priority': priority,
        'block': block,
        'carryDone': carryDone,
        'carryTotal': carryTotal,
        'manualOrder': manualOrder,
      };

  static Goal fromMap(Map<String, dynamic> m) => Goal(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        horizonDays: (m['horizonDays'] as num?)?.toInt() ?? 30,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        isDone: _toBool(m['isDone']),
        isArchived: _toBool(m['isArchived']),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
        externalId: (m['externalId'] ?? '').toString(),
        importTag: (m['importTag'] ?? '').toString(),
        recurDaily: _toBool(m['recurDaily']),
        isPinned: _toBool(m['isPinned']),
        lastDoneAt: _toDate(m['lastDoneAt']),
        lastMissAt: _toDate(m['lastMissAt']),
        missedCount: (m['missedCount'] as num?)?.toInt() ?? 0,
        comment: (m['comment'] ?? '').toString(),
        motivation: (m['motivation'] ?? '').toString(),
        reward: (m['reward'] ?? '').toString(),
        doneAt: _toDate(m['doneAt']),
        dayOffDates: (m['dayOffDates'] ?? '')
            .toString()
            .split(';')
            .where((e) => e.isNotEmpty)
            .toList(),
        icon: (m['icon'] ?? '').toString(),
        criteria: (m['criteria'] ?? '').toString(),
        ifFail: (m['ifFail'] ?? '').toString(),
        priority: (m['priority'] as num?)?.toInt() ?? 1,
        block: (m['block'] ?? '').toString(),
        carryDone: (m['carryDone'] as num?)?.toInt() ?? 0,
        carryTotal: (m['carryTotal'] as num?)?.toInt() ?? 0,
        manualOrder: (m['manualOrder'] as num?)?.toDouble() ?? 0,
      );
}

class EventItem {
  String id;
  String title;
  DateTime start;
  int durationMin;
  bool isArchived;
  String comment; // комментарий / суть события
  int priority; // 0 низкий, 1 средний, 2 высокий (команда «добавь событие»)

  EventItem({
    String? id,
    this.title = '',
    DateTime? start,
    this.durationMin = 60,
    this.isArchived = false,
    this.comment = '',
    this.priority = 1,
  })  : id = id ?? newId(),
        start = start ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        'durationMin': durationMin,
        'isArchived': isArchived ? 1 : 0,
        'comment': comment,
        'priority': priority,
      };

  static EventItem fromMap(Map<String, dynamic> m) => EventItem(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        start: _toDate(m['start']) ?? DateTime.now(),
        durationMin: (m['durationMin'] as num?)?.toInt() ?? 60,
        isArchived: _toBool(m['isArchived']),
        comment: (m['comment'] ?? '').toString(),
        priority: (m['priority'] as num?)?.toInt() ?? 1,
      );
}


/// Ресурс задачи (блок «Ресурсы» в карточке): что нужно для выполнения.
/// Каждая строка ответа на уточняющий вопрос «Какие ресурсы нужны?» —
/// отдельный ресурс, по аналогии с шагами шкалы пути.
class TaskResource {
  String id;
  String taskId;
  String title;
  int ord; // порядок в списке ресурсов

  TaskResource({
    String? id,
    this.taskId = '',
    this.title = '',
    this.ord = 0,
  }) : id = id ?? newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'title': title,
        'ord': ord,
      };

  static TaskResource fromMap(Map<String, dynamic> m) => TaskResource(
        id: m['id'].toString(),
        taskId: (m['taskId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        ord: (m['ord'] as num?)?.toInt() ?? 0,
      );
}

/// Запись дневника. Три вида:
///  · 'day_review'  — «Итоги дня»: свободная запись за конкретный день
///    (значок дневника на задаче «итоги дня» на экране «Сегодня»);
///  · 'observation' — «Дневник наблюдений»: сохранённый диалог сессии
///    (вопросы собеседника-наблюдателя + ответы пользователя);
///  · 'practice'    — пройденная практика (ответы шагов мастера).
/// Все записи привязаны к дате, видны на экране «Заметки» и входят
/// в полную JSON-выгрузку (и обратно).
class DiaryEntry {
  String id;
  String kind; // 'day_review' | 'observation' | 'practice'
  DateTime day; // день записи (дата без времени)
  String title; // «Итоги дня», название практики, «Дневник наблюдений»
  String text; // текст записи / диалог сессии / ответы практики
  String mood; // настроение в начале сессии ('' = не указано)
  String practiceId; // для kind='practice': 'p1', 'p3', 'p4' ...
  String style; // для практик: 'garden' | 'ritual' | 'stars' | 'card'
  DateTime createdAt;

  DiaryEntry({
    String? id,
    this.kind = 'day_review',
    DateTime? day,
    this.title = '',
    this.text = '',
    this.mood = '',
    this.practiceId = '',
    this.style = '',
    DateTime? createdAt,
  })  : id = id ?? newId(),
        day = day ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'day': DateTime(day.year, day.month, day.day).toIso8601String(),
        'title': title,
        'text': text,
        'mood': mood,
        'practiceId': practiceId,
        'style': style,
        'createdAt': createdAt.toIso8601String(),
      };

  static DiaryEntry fromMap(Map<String, dynamic> m) => DiaryEntry(
        id: m['id'].toString(),
        kind: (m['kind'] ?? 'day_review').toString(),
        day: _toDate(m['day']) ?? DateTime.now(),
        title: (m['title'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        mood: (m['mood'] ?? '').toString(),
        practiceId: (m['practiceId'] ?? '').toString(),
        style: (m['style'] ?? '').toString(),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}

/// Вопрос банка «Дневника наблюдений». Банк обновляемый: вопросы можно
/// добавлять, править, отключать и удалять в приложении; входят в
/// полную JSON-выгрузку/загрузку (переносятся между устройствами).
class PsyQuestion {
  String id;
  String text;
  String category; // 'state' | 'day' | 'feelings' | 'dreams' | 'values'
  bool isActive; // отключённый вопрос не предлагается в сессиях
  int ord;
  DateTime createdAt;

  PsyQuestion({
    String? id,
    this.text = '',
    this.category = 'state',
    this.isActive = true,
    this.ord = 0,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'category': category,
        'isActive': isActive ? 1 : 0,
        'ord': ord,
        'createdAt': createdAt.toIso8601String(),
      };

  static PsyQuestion fromMap(Map<String, dynamic> m) => PsyQuestion(
        id: m['id'].toString(),
        text: (m['text'] ?? '').toString(),
        category: (m['category'] ?? 'state').toString(),
        isActive: _toBool(m['isActive'], true),
        ord: (m['ord'] as num?)?.toInt() ?? 0,
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}


/// Актив или пассивный расход (финучёт): постоянная статья с
/// периодичностью. kind='asset' — ресурс, приносящий стабильный доход
/// почти без участия; kind='expense' — регулярный пассивный расход,
/// вычитается из доходов. emotion — психоэмоциональная градация 1..5
/// (1 — самая тяжёлая, 5 — самая радостная), note — заметка о состоянии.
class FinPassive {
  String id;
  String kind; // 'asset' | 'expense'
  String title; // название ресурса / статьи
  double amount; // сумма за период recur
  String recur; // 'day' | 'month' | 'quarter' | 'year'
  int emotion; // 1..5
  String note;
  DateTime createdAt;

  FinPassive({
    String? id,
    this.kind = 'asset',
    this.title = '',
    this.amount = 0,
    this.recur = 'month',
    this.emotion = 3,
    this.note = '',
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  bool get isAsset => kind == 'asset';

  /// Нормализация суммы к месяцу — для строки «ИТОГО».
  double get perMonth {
    switch (recur) {
      case 'day':
        return amount * 30;
      case 'quarter':
        return amount / 3;
      case 'year':
        return amount / 12;
      default:
        return amount;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'amount': amount,
        'recur': recur,
        'emotion': emotion,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  static FinPassive fromMap(Map<String, dynamic> m) => FinPassive(
        id: m['id'].toString(),
        kind: (m['kind'] ?? 'asset').toString(),
        title: (m['title'] ?? '').toString(),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        recur: (m['recur'] ?? 'month').toString(),
        emotion: (m['emotion'] as num?)?.toInt() ?? 3,
        note: (m['note'] ?? '').toString(),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}

/// Планируемая покупка (расходы): название, цена, цель инвестиции,
/// срок (краткосрочная/долгосрочная), примечание и довод «почему
/// необходима именно в данном финансовом положении».
class FinPurchase {
  String id;
  String title;
  double price;
  String goal; // цель инвестиции
  String term; // 'short' | 'long'
  String note;
  String reason; // довод необходимости
  DateTime createdAt;

  FinPurchase({
    String? id,
    this.title = '',
    this.price = 0,
    this.goal = '',
    this.term = 'short',
    this.note = '',
    this.reason = '',
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'price': price,
        'goal': goal,
        'term': term,
        'note': note,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
      };

  static FinPurchase fromMap(Map<String, dynamic> m) => FinPurchase(
        id: m['id'].toString(),
        title: (m['title'] ?? '').toString(),
        price: (m['price'] as num?)?.toDouble() ?? 0,
        goal: (m['goal'] ?? '').toString(),
        term: (m['term'] ?? 'short').toString(),
        note: (m['note'] ?? '').toString(),
        reason: (m['reason'] ?? '').toString(),
        createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
      );
}
