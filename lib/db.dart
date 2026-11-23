/// Локальная БД (sqflite). Схема v17 — финучёт: активы и пассивные
/// расходы (с периодичностью, психоэмоциональной градацией и заметкой)
/// и планируемые покупки (цель, срок, довод). v16 — флаг «итоги дня»
/// у задач, дневник (итоги дня / наблюдения / практики) и обновляемый
/// банк вопросов собеседника-наблюдателя. v15 — слияние задач в
/// иерархию и ручной порядок блоков на древе пути. v14 — «количество
/// раз» у шагов, ресурсы задач, ранжирование и ручной порядок задач на
/// «Сегодня», мягкое удаление из архива (purged) и компенсация
/// прогресса блоков (carry). v13 — итерации шагов и финансовый учёт.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'planner.db');
    _db = await openDatabase(
      path,
      version: 17,
      onCreate: (d, v) => _createAll(d),
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          // v1 -> v2: пересоздаём таблицы (архивация).
          await _dropAll(d);
          await _createAll(d);
          return;
        }
        if (oldV < 3) {
          // v2 -> v3: поля импорта tasks.json.
          await d.execute('ALTER TABLE notes ADD COLUMN importTag TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN externalId TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN block TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN metric TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN importTag TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN recurDaily INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE goals ADD COLUMN externalId TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE goals ADD COLUMN importTag TEXT DEFAULT \'\'');
        }
        if (oldV < 4) {
          // v3 -> v4: закрепление (isPinned), ключевые действия, привычки, пропуски.
          await d.execute('ALTER TABLE notes ADD COLUMN isPinned INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE tasks ADD COLUMN isPinned INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE tasks ADD COLUMN isKeyAction INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE tasks ADD COLUMN missedCount INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE goals ADD COLUMN isPinned INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE goals ADD COLUMN recurDaily INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE goals ADD COLUMN lastDoneAt TEXT');
          await d.execute('ALTER TABLE goals ADD COLUMN lastMissAt TEXT');
          await d.execute('ALTER TABLE goals ADD COLUMN missedCount INTEGER DEFAULT 0');
        }
        if (oldV < 5) {
          // v4 -> v5: шкала целей (goalId/horizon), комментарии, своевременность,
          // геймификация (мотивация/приз).
          await d.execute('ALTER TABLE tasks ADD COLUMN goalId TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN horizon TEXT DEFAULT \'short\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN comment TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE tasks ADD COLUMN onTime INTEGER DEFAULT -1');
          await d.execute('ALTER TABLE goals ADD COLUMN comment TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE goals ADD COLUMN motivation TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE goals ADD COLUMN reward TEXT DEFAULT \'\'');
          await d.execute('ALTER TABLE goals ADD COLUMN doneAt TEXT');
          await d.execute('ALTER TABLE events ADD COLUMN comment TEXT DEFAULT \'\'');
        }
        if (oldV < 6) {
          // v5 -> v6: процентная градация ежедневных задач, шаги задач,
          // журнал обратной связи для аудита.
          await d.execute('ALTER TABLE tasks ADD COLUMN progressPct INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE tasks ADD COLUMN pctStep INTEGER DEFAULT 100');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS task_steps(
              id TEXT PRIMARY KEY,
              taskId TEXT,
              title TEXT,
              isDone INTEGER DEFAULT 0,
              priority INTEGER DEFAULT 1,
              isKeyAction INTEGER DEFAULT 0,
              photoPath TEXT DEFAULT '',
              doneAt TEXT,
              ord INTEGER DEFAULT 0
            )
          ''');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS feedback(
              id TEXT PRIMARY KEY,
              createdAt TEXT,
              kind TEXT DEFAULT 'comment',
              itemTitle TEXT DEFAULT '',
              text TEXT DEFAULT ''
            )
          ''');
        }
        if (oldV < 7) {
          // v6 -> v7: «выходной» для ежедневных задач и привычек
          // (дата выходного не засчитывается пропуском).
          await d.execute("ALTER TABLE tasks ADD COLUMN dayOffDates TEXT DEFAULT ''");
          await d.execute("ALTER TABLE goals ADD COLUMN dayOffDates TEXT DEFAULT ''");
        }
        if (oldV < 8) {
          // v7 -> v8: значок блока, критерии достижения цели, план «если не вышло»,
          // дополнительная связь задачи с блоком (дерево связей).
          await d.execute("ALTER TABLE goals ADD COLUMN icon TEXT DEFAULT ''");
          await d.execute("ALTER TABLE goals ADD COLUMN criteria TEXT DEFAULT ''");
          await d.execute("ALTER TABLE goals ADD COLUMN ifFail TEXT DEFAULT ''");
          await d.execute("ALTER TABLE tasks ADD COLUMN linkedBlock TEXT DEFAULT ''");
        }
        if (oldV < 9) {
          // v8 -> v9: приоритет и блок у цели (команда «добавь цель»),
          // приоритет у события (команда «добавь событие»).
          await d.execute('ALTER TABLE goals ADD COLUMN priority INTEGER DEFAULT 1');
          await d.execute("ALTER TABLE goals ADD COLUMN block TEXT DEFAULT ''");
          await d.execute('ALTER TABLE events ADD COLUMN priority INTEGER DEFAULT 1');
        }
        if (oldV < 10) {
          // v9 -> v10: фактическое время выполнения задачи (минуты,
          // вводит пользователь после завершения задачи).
          await d.execute('ALTER TABLE tasks ADD COLUMN actualMin INTEGER DEFAULT 0');
        }
        if (oldV < 11) {
          // v10 -> v11: награды за продуктивные дни (экран «Сегодня») —
          // выбор награды или её пропуск, для статистики обратной связи.
          await d.execute('''
            CREATE TABLE IF NOT EXISTS day_rewards(
              id TEXT PRIMARY KEY,
              date TEXT,
              tier INTEGER DEFAULT 1,
              pct REAL DEFAULT 0,
              reward TEXT DEFAULT '',
              skipped INTEGER DEFAULT 0,
              createdAt TEXT
            )
          ''');
        }
        if (oldV < 12) {
          // v11 -> v12: посуточный журнал закреплённых задач (пин на
          // экране «Сегодня» = ежедневная задача; выполнение фиксируется
          // за каждый день независимо от наличия дедлайна).
          await d.execute('''
            CREATE TABLE IF NOT EXISTS pin_log(
              id TEXT PRIMARY KEY,
              taskId TEXT,
              title TEXT DEFAULT '',
              day TEXT,
              done INTEGER DEFAULT 0
            )
          ''');
        }
        if (oldV < 13) {
          // v12 -> v13: количество итераций у шага задачи + кластер
          // финансового учёта (источники доходов/расходов, блоки).
          await d.execute(
              'ALTER TABLE task_steps ADD COLUMN iterations INTEGER DEFAULT 1');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS finance_entries(
              id TEXT PRIMARY KEY,
              kind TEXT DEFAULT 'expense',
              source TEXT,
              amount REAL DEFAULT 0,
              block TEXT DEFAULT '',
              day TEXT,
              note TEXT DEFAULT '',
              createdAt TEXT
            )
          ''');
        }
        if (oldV < 14) {
          // v13 -> v14: «количество раз» у шага; ресурсы задач;
          // номер и ручной порядок на «Сегодня»; мягкое удаление
          // из архива (purged) — отметки прошлых дней сохраняются;
          // carry у целей — прогресс блоков не откатывается при
          // удалении задач из архива.
          await d.execute(
              'ALTER TABLE task_steps ADD COLUMN times INTEGER DEFAULT 1');
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN sortNum INTEGER DEFAULT 0');
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN manualOrder REAL DEFAULT 0');
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN purged INTEGER DEFAULT 0');
          await d.execute(
              'ALTER TABLE goals ADD COLUMN carryDone INTEGER DEFAULT 0');
          await d.execute(
              'ALTER TABLE goals ADD COLUMN carryTotal INTEGER DEFAULT 0');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS task_resources(
              id TEXT PRIMARY KEY,
              taskId TEXT,
              title TEXT,
              ord INTEGER DEFAULT 0
            )
          ''');
        }
        if (oldV < 15) {
          // v14 -> v15: иерархия задач (parentTaskId — задача слита
          // перетаскиванием внутрь другой и живёт в её блоке
          // «однородных»); ручной порядок блоков на древе пути
          // (перетаскивание завязей вверх/вниз).
          await d.execute(
              "ALTER TABLE tasks ADD COLUMN parentTaskId TEXT DEFAULT ''");
          await d.execute(
              'ALTER TABLE goals ADD COLUMN manualOrder REAL DEFAULT 0');
        }
        if (oldV < 16) {
          // v15 -> v16: флаг «итоги дня» у задачи (значок дневника на
          // экране «Сегодня»); дневник (итоги дня / дневник наблюдений /
          // практики) и обновляемый банк вопросов собеседника.
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN isDayReview INTEGER DEFAULT 0');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS diary_entries(
              id TEXT PRIMARY KEY,
              kind TEXT DEFAULT 'day_review',
              day TEXT,
              title TEXT DEFAULT '',
              text TEXT DEFAULT '',
              mood TEXT DEFAULT '',
              practiceId TEXT DEFAULT '',
              style TEXT DEFAULT '',
              createdAt TEXT
            )
          ''');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS psy_questions(
              id TEXT PRIMARY KEY,
              text TEXT DEFAULT '',
              category TEXT DEFAULT 'state',
              isActive INTEGER DEFAULT 1,
              ord INTEGER DEFAULT 0,
              createdAt TEXT
            )
          ''');
        }
        if (oldV < 17) {
          // v16 -> v17: активы и пассивные расходы (периодичность,
          // психоэмоциональная градация 1..5, заметка) и планируемые
          // покупки (цена, цель инвестиции, срок, примечание, довод).
          await d.execute('''
            CREATE TABLE IF NOT EXISTS fin_passive(
              id TEXT PRIMARY KEY,
              kind TEXT DEFAULT 'asset',
              title TEXT DEFAULT '',
              amount REAL DEFAULT 0,
              recur TEXT DEFAULT 'month',
              emotion INTEGER DEFAULT 3,
              note TEXT DEFAULT '',
              createdAt TEXT
            )
          ''');
          await d.execute('''
            CREATE TABLE IF NOT EXISTS fin_purchases(
              id TEXT PRIMARY KEY,
              title TEXT DEFAULT '',
              price REAL DEFAULT 0,
              goal TEXT DEFAULT '',
              term TEXT DEFAULT 'short',
              note TEXT DEFAULT '',
              reason TEXT DEFAULT '',
              createdAt TEXT
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> _dropAll(Database d) async {
    for (final t in ['notes', 'tasks', 'goals', 'events', 'task_steps', 'feedback', 'day_rewards', 'pin_log', 'finance_entries', 'task_resources', 'diary_entries', 'psy_questions', 'fin_passive', 'fin_purchases']) {
      await d.execute('DROP TABLE IF EXISTS $t');
    }
  }

  Future<void> _createAll(Database d) async {
    await d.execute('''
      CREATE TABLE notes(
        id TEXT PRIMARY KEY,
        title TEXT,
        text TEXT,
        isArchived INTEGER DEFAULT 0,
        createdAt TEXT,
        importTag TEXT DEFAULT '',
        isPinned INTEGER DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE tasks(
        id TEXT PRIMARY KEY,
        title TEXT,
        deadline TEXT,
        estimateMin INTEGER DEFAULT 30,
        priority INTEGER DEFAULT 1,
        isDone INTEGER DEFAULT 0,
        isArchived INTEGER DEFAULT 0,
        createdAt TEXT,
        doneAt TEXT,
        externalId TEXT DEFAULT '',
        block TEXT DEFAULT '',
        metric TEXT DEFAULT '',
        importTag TEXT DEFAULT '',
        recurDaily INTEGER DEFAULT 0,
        isPinned INTEGER DEFAULT 0,
        isKeyAction INTEGER DEFAULT 0,
        missedCount INTEGER DEFAULT 0,
        goalId TEXT DEFAULT '',
        horizon TEXT DEFAULT 'short',
        comment TEXT DEFAULT '',
        onTime INTEGER DEFAULT -1,
        progressPct INTEGER DEFAULT 0,
        pctStep INTEGER DEFAULT 100,
        actualMin INTEGER DEFAULT 0,
        dayOffDates TEXT DEFAULT '',
        linkedBlock TEXT DEFAULT '',
        sortNum INTEGER DEFAULT 0,
        manualOrder REAL DEFAULT 0,
        purged INTEGER DEFAULT 0,
        parentTaskId TEXT DEFAULT '',
        isDayReview INTEGER DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE task_steps(
        id TEXT PRIMARY KEY,
        taskId TEXT,
        title TEXT,
        isDone INTEGER DEFAULT 0,
        priority INTEGER DEFAULT 1,
        isKeyAction INTEGER DEFAULT 0,
        photoPath TEXT DEFAULT '',
        doneAt TEXT,
        ord INTEGER DEFAULT 0,
        iterations INTEGER DEFAULT 1,
        times INTEGER DEFAULT 1
      )
    ''');
    await d.execute('''
      CREATE TABLE feedback(
        id TEXT PRIMARY KEY,
        createdAt TEXT,
        kind TEXT DEFAULT 'comment',
        itemTitle TEXT DEFAULT '',
        text TEXT DEFAULT ''
      )
    ''');
    await d.execute('''
      CREATE TABLE goals(
        id TEXT PRIMARY KEY,
        title TEXT,
        horizonDays INTEGER DEFAULT 30,
        progress REAL DEFAULT 0,
        isDone INTEGER DEFAULT 0,
        isArchived INTEGER DEFAULT 0,
        createdAt TEXT,
        externalId TEXT DEFAULT '',
        importTag TEXT DEFAULT '',
        isPinned INTEGER DEFAULT 0,
        recurDaily INTEGER DEFAULT 0,
        lastDoneAt TEXT,
        lastMissAt TEXT,
        missedCount INTEGER DEFAULT 0,
        comment TEXT DEFAULT '',
        motivation TEXT DEFAULT '',
        reward TEXT DEFAULT '',
        doneAt TEXT,
        dayOffDates TEXT DEFAULT '',
        icon TEXT DEFAULT '',
        criteria TEXT DEFAULT '',
        ifFail TEXT DEFAULT '',
        priority INTEGER DEFAULT 1,
        block TEXT DEFAULT '',
        carryDone INTEGER DEFAULT 0,
        carryTotal INTEGER DEFAULT 0,
        manualOrder REAL DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE events(
        id TEXT PRIMARY KEY,
        title TEXT,
        start TEXT,
        durationMin INTEGER DEFAULT 60,
        isArchived INTEGER DEFAULT 0,
        comment TEXT DEFAULT '',
        priority INTEGER DEFAULT 1
      )
    ''');
    await d.execute('''
      CREATE TABLE day_rewards(
        id TEXT PRIMARY KEY,
        date TEXT,
        tier INTEGER DEFAULT 1,
        pct REAL DEFAULT 0,
        reward TEXT DEFAULT '',
        skipped INTEGER DEFAULT 0,
        createdAt TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE pin_log(
        id TEXT PRIMARY KEY,
        taskId TEXT,
        title TEXT DEFAULT '',
        day TEXT,
        done INTEGER DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE task_resources(
        id TEXT PRIMARY KEY,
        taskId TEXT,
        title TEXT,
        ord INTEGER DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE finance_entries(
        id TEXT PRIMARY KEY,
        kind TEXT DEFAULT 'expense',
        source TEXT,
        amount REAL DEFAULT 0,
        block TEXT DEFAULT '',
        day TEXT,
        note TEXT DEFAULT '',
        createdAt TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE diary_entries(
        id TEXT PRIMARY KEY,
        kind TEXT DEFAULT 'day_review',
        day TEXT,
        title TEXT DEFAULT '',
        text TEXT DEFAULT '',
        mood TEXT DEFAULT '',
        practiceId TEXT DEFAULT '',
        style TEXT DEFAULT '',
        createdAt TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE psy_questions(
        id TEXT PRIMARY KEY,
        text TEXT DEFAULT '',
        category TEXT DEFAULT 'state',
        isActive INTEGER DEFAULT 1,
        ord INTEGER DEFAULT 0,
        createdAt TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE fin_passive(
        id TEXT PRIMARY KEY,
        kind TEXT DEFAULT 'asset',
        title TEXT DEFAULT '',
        amount REAL DEFAULT 0,
        recur TEXT DEFAULT 'month',
        emotion INTEGER DEFAULT 3,
        note TEXT DEFAULT '',
        createdAt TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE fin_purchases(
        id TEXT PRIMARY KEY,
        title TEXT DEFAULT '',
        price REAL DEFAULT 0,
        goal TEXT DEFAULT '',
        term TEXT DEFAULT 'short',
        note TEXT DEFAULT '',
        reason TEXT DEFAULT '',
        createdAt TEXT
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> all(String table) async =>
      (await db).query(table);

  Future<void> insert(String table, Map<String, dynamic> row) async {
    await (await db).insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateRow(String table, Map<String, dynamic> row, String id) async {
    await (await db).update(table, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRow(String table, String id) async {
    await (await db).delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Полностью очищает таблицу (используется при восстановлении
  /// полной выгрузки: сначала очищаем, потом вставляем строки файла).
  Future<void> clear(String table) async {
    await (await db).delete(table);
  }
}
