/// Экран «Цели»:
/// — секция «Ежедневные» (фиолетовая): привычки (recurDaily) и закреплённые
///   задачи/заметки/цели — всегда на виду;
/// — цели-блоки годового плана раскрываются и показывают задачи своего блока;
/// — обычные цели с прогрессом; достижение -> архив, CRUD.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../praise.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'archive_screen.dart';
import 'block_icons.dart';
import 'block_wheel.dart';
import 'common.dart';
import 'edit_dialogs.dart';
import 'fireworks.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // Ежедневные: привычки-цели + всё закреплённое.
    final habits = store.activeGoals.where((g) => g.recurDaily).toList();
    final pinnedTasks = store.activeTasks.where((t) => t.isPinned && !t.recurDaily).toList();
    final pinnedNotes = store.activeNotes.where((n) => n.isPinned).toList();
    final pinnedGoals =
        store.activeGoals.where((g) => g.isPinned && !g.recurDaily).toList();
    final hasDaily = habits.isNotEmpty;
    // Закреплённые задачи/заметки/цели — отдельная секция под ежедневными.
    final hasPinned =
        pinnedTasks.isNotEmpty || pinnedNotes.isNotEmpty || pinnedGoals.isNotEmpty;

    // Цели-блоки из импорта (externalId 'block:X') и обычные цели.
    final blockGoals = store.activeGoals
        .where((g) => g.externalId.startsWith('block:') && !g.recurDaily && !g.isPinned)
        .toList();
    final plainGoals = store.activeGoals
        .where((g) => !g.externalId.startsWith('block:') && !g.recurDaily && !g.isPinned)
        .toList();

    final empty = !hasDaily && !hasPinned && blockGoals.isEmpty && plainGoals.isEmpty;
    final wheelData = buildBlockWheelData(store);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Цели'),
            Text('${store.activeGoals.length} целей',
                style: const TextStyle(fontSize: 12, color: AppTheme.textDim, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          const FontScaleButton(),
          const AlertBell(),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Добавить блок',
            onPressed: () => showAddBlockDialog(context, store),
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Архив',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchiveScreen()),
            ),
          ),
        ],
      ),
      body: empty
          ? const EmptyHint('Целей пока нет. Добавьте первую!')
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                // Круг продуктивности: сектора по блокам годового плана,
                // наполняются от центра к внешней окружности.
                if (wheelData.isNotEmpty)
                  BlockProductivityWheel(data: wheelData),
                if (hasDaily) ...[
                  const SectionHeader('Ежедневные', color: AppTheme.daily),
                  for (final g in habits) _HabitTile(goal: g, store: store),
                ],
                if (hasPinned) ...[
                  // Закреплённое держим отдельно: это не привычки, а задачи,
                  // прикреплённые к ежедневному обзору.
                  const SectionHeader('Прикреплены к ежедневным',
                      color: AppTheme.daily),
                  for (final t in pinnedTasks) _PinnedTaskTile(task: t, store: store),
                  for (final n in pinnedNotes) _PinnedNoteTile(note: n, store: store),
                  for (final g in pinnedGoals) _GoalCard(goal: g, store: store),
                ],
                if (blockGoals.isNotEmpty) const SectionHeader('Блоки годового плана'),
                for (final g in blockGoals) _BlockGoalTile(goal: g, store: store),
                if (plainGoals.isNotEmpty) const SectionHeader('Цели'),
                for (final g in plainGoals) _GoalCard(goal: g, store: store),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showGoalEditor(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Ежедневная привычка: чекбокс «сделано сегодня», счётчик пропусков.
class _HabitTile extends StatelessWidget {
  final Goal goal;
  final AppStore store;
  const _HabitTile({required this.goal, required this.store});

  @override
  Widget build(BuildContext context) {
    final g = goal;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.daily, width: 1),
      ),
      child: ListTile(
        leading: IconButton(
          icon: Icon(
            g.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: g.isDone ? AppTheme.done : AppTheme.daily,
          ),
          tooltip: g.isDone ? 'Снять отметку' : 'Выполнено сегодня',
          onPressed: () {
            final wasDone = g.isDone;
            store.toggleGoalDone(g.id);
            if (!wasDone) {
              PraiseOverlay.show(context, Praise.forHabit());
            }
          },
        ),
        title: Text(g.title, style: TextStyle(color: g.isDone ? AppTheme.textDim : AppTheme.text)),
        subtitle: Text(
          [
            'ежедневная привычка',
            if (g.isDone) 'сделано сегодня',
            if (g.missedCount > 0) 'пропусков: ${g.missedCount}',
          ].join(' · '),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Выпадающее меню ежедневной привычки: «выходной»
            // (не считается пропуском, в выгрузке — отдельный вид записи)
            // и комментарий / причина пропуска.
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textDim),
              tooltip: 'Выходной / комментарий',
              onSelected: (v) {
                if (v == 'dayoff') {
                  store.markGoalDayOff(g.id, DateTime.now());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Сегодня отмечено как выходной — пропуск не засчитается')),
                  );
                }
                if (v == 'comment') {
                  askCommentDialog(context, g.title, (text) {
                    g.comment = g.comment.isEmpty ? text : '${g.comment}\n$text';
                    store.updateGoal(g);
                    store.addFeedback(
                        text.contains('ричин') ? 'late_reason' : 'comment',
                        g.title,
                        text);
                  });
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'dayoff',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.beach_access_outlined, size: 20),
                    title: Text('Выходной (сегодня)'),
                  ),
                ),
                PopupMenuItem(
                  value: 'comment',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.comment_outlined, size: 20),
                    title: Text('Комментарий / причина пропуска'),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                g.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
                color: g.isPinned ? AppTheme.daily : AppTheme.textDim,
              ),
              tooltip: g.isPinned ? 'Открепить' : 'Закрепить',
              onPressed: () => store.togglePinGoal(g.id),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => showGoalEditor(context, store, goal: g),
            ),
          ],
        ),
      ),
    );
  }
}

/// Закреплённая задача в блоке «Ежедневные».
class _PinnedTaskTile extends StatelessWidget {
  final Task task;
  final AppStore store;
  const _PinnedTaskTile({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final t = task;
    // Выполнения ежедневной задачи суммируются: показываем сколько раз
    // выполнена и когда последний раз.
    final completions = t.recurDaily ? store.dailyCompletions(t) : <Task>[];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.daily, width: 1),
      ),
      child: ListTile(
        leading: IconButton(
          icon: Icon(
            t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: t.isDone ? AppTheme.done : AppTheme.daily,
          ),
          // Выполнение — с тем же уточнением фактического времени,
          // что и на экранах «Сегодня»/«Задачи» (единое поведение).
          onPressed: () => completeTaskWithFeedback(context, store, t),
        ),
        title: Text(t.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'закреплённая задача',
                if (t.recurDaily) 'ежедневно',
                if (t.isKeyAction) 'ключевое',
              ].join(' · '),
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            if (completions.isNotEmpty)
              Text(
                'выполнений: ${completions.length} · последний раз '
                '${fmtDateTime(completions.last.doneAt ?? completions.last.createdAt)}',
                style: const TextStyle(color: AppTheme.done, fontSize: 11),
              ),
            // Градация в процентах: ежедневная задача не «сгорает»
            // после отметки, а копит процент с выбранным шагом.
            if (t.recurDaily && t.pctStep < 100) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: t.progressPct / 100,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
                color: AppTheme.done,
              ),
              Text('${t.progressPct}% (шаг +${t.pctStep}%)',
                  style:
                      const TextStyle(color: AppTheme.textDim, fontSize: 11)),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.recurDaily)
              PopupMenuButton<int>(
                icon: const Icon(Icons.percent, size: 19, color: AppTheme.done),
                tooltip: 'Шаг процента',
                onSelected: (v) => store.setTaskPctStep(t.id, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 10, child: Text('Шаг +10%')),
                  PopupMenuItem(value: 20, child: Text('Шаг +20%')),
                  PopupMenuItem(value: 25, child: Text('Шаг +25%')),
                  PopupMenuItem(value: 50, child: Text('Шаг +50%')),
                  PopupMenuItem(value: 100, child: Text('Сразу 100%')),
                ],
              ),
            if (t.recurDaily)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 19, color: AppTheme.textDim),
                tooltip: 'Выходной / комментарий',
                onSelected: (v) {
                  if (v == 'dayoff') {
                    store.markTaskDayOff(t.id, DateTime.now());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Сегодня отмечено как выходной — пропуск не засчитается')),
                    );
                  }
                  if (v == 'comment') {
                    askCommentDialog(context, t.title,
                        (text) => store.appendTaskComment(t.id, text));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'dayoff',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.beach_access_outlined, size: 20),
                      title: Text('Выходной (сегодня)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'comment',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.comment_outlined, size: 20),
                      title: Text('Комментарий / причина пропуска'),
                    ),
                  ),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.push_pin, size: 20, color: AppTheme.daily),
              tooltip: 'Открепить',
              onPressed: () => store.togglePinTask(t.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// Закреплённая заметка в блоке «Ежедневные».
class _PinnedNoteTile extends StatelessWidget {
  final Note note;
  final AppStore store;
  const _PinnedNoteTile({required this.note, required this.store});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.daily, width: 1),
      ),
      child: ListTile(
        leading: const Icon(Icons.sticky_note_2_outlined, color: AppTheme.daily),
        title: Text(note.title),
        subtitle: const Text('закреплённая заметка',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.push_pin, size: 20, color: AppTheme.daily),
          tooltip: 'Открепить',
          onPressed: () => store.togglePinNote(note.id),
        ),
      ),
    );
  }
}

/// Цель-блок годового плана: раскрывается, внутри — задачи этого блока.
class _BlockGoalTile extends StatelessWidget {
  final Goal goal;
  final AppStore store;
  const _BlockGoalTile({required this.goal, required this.store});

  @override
  Widget build(BuildContext context) {
    final g = goal;
    // Задачи блока: по коду импорта, по явной цели и по ручной связи.
    final allBlockTasks = store.tasksForGoal(g);
    // Ежедневные серии схлопываем: выполненные экземпляры исчезают из
    // списка, от каждой серии остаётся ОДНА ближайшая по дате
    // невыполненная задача. Когда она выполняется, появляется следующая.
    // Если невыполненных нет — серия уходит из списка полностью.
    final blockTasks = <Task>[];
    final seenSeries = <String>{};
    for (final t in allBlockTasks) {
      if (t.recurDaily || t.horizon == 'daily') {
        final key = '${t.title}|${t.externalId}';
        if (!seenSeries.add(key)) continue;
        final pending = allBlockTasks
            .where((x) => '${x.title}|${x.externalId}' == key && !x.isDone)
            .toList()
          ..sort((a, b) =>
              (a.deadline ?? a.createdAt).compareTo(b.deadline ?? b.createdAt));
        if (pending.isNotEmpty) blockTasks.add(pending.first);
      } else {
        blockTasks.add(t);
      }
    }
    final doneCount = blockTasks.where((t) => t.isDone).length;
    // Живой процент: пересчитывается из задач блока при каждой
    // отметке — снятие галочки откатывает процент ровно на долю
    // этой задачи, возврат галочки добавляет её обратно.
    // Вклад задач, удалённых из архива (carryDone/carryTotal),
    // учитывается: удаление задачи НЕ откатывает прогресс блока.
    final totalWithCarry = blockTasks.length + g.carryTotal;
    final liveProgress = totalWithCarry == 0
        ? g.progress
        : (doneCount + g.carryDone) / totalWithCarry;
    // Цели, отнесённые к этому блоку (команда «добавь цель ... в блок X»).
    final blockId = g.externalId.startsWith('block:')
        ? g.externalId.substring(6)
        : '';
    final blockGoals = store.activeGoals
        .where((x) => !x.externalId.startsWith('block:') && x.block == blockId)
        .toList();
    // Тап по задаче на экране «Задачи» — этот блок раскрывается и под
    // целью появляется шкала шагов выбранной задачи.
    final focused = store.focusTask;
    final showSteps =
        focused != null && blockTasks.any((t) => t.id == focused.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: store.focusGoalId == g.id,
        leading: blockIconWidget(g.icon, color: AppTheme.accent),
        title: Text(g.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${doneCount + g.carryDone}/${blockTasks.length + g.carryTotal} задач · ${(liveProgress * 100).round()}%',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: liveProgress.clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textDim),
              tooltip: 'Действия с блоком',
              onSelected: (v) {
                if (v == 'icon') showBlockIconPicker(context, store, g);
                if (v == 'edit') showGoalEditor(context, store, goal: g);
                if (v == 'delete') _confirmDeleteBlock(context, store, g);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'icon',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.emoji_symbols_outlined, size: 20),
                    title: Text('Сменить значок'),
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined, size: 20),
                    title: Text('Редактировать'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, size: 20),
                    title: Text('Удалить блок'),
                  ),
                ),
              ],
            ),
            const Icon(Icons.expand_more, color: AppTheme.textDim),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
        children: [
          _GoalScale(goal: g, tasks: blockTasks, store: store, ordinal: true),
          // Вторая шкала: шаги задачи, выбранной тапом (на экране
          // «Задачи» или прямо здесь, в списке задач блока).
          if (showSteps) _TaskStepsPanel(task: focused!, store: store),
          // Цели, отнесённые к этому блоку (ассистент: «добавь цель …
          // в блок …»), — их потом можно наполнить задачами.
          for (final bg in blockGoals)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined,
                  size: 18, color: AppTheme.accent),
              title: Text(bg.title, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                'цель блока · ${(bg.progress * 100).round()}%'
                '${bg.priority == 2 ? ' · важная' : (bg.priority == 0 ? ' · неспешная' : '')}',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => showGoalEditor(context, store, goal: bg),
              ),
            ),
          if (blockTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('В этом блоке нет активных задач',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            )
          else
            for (final t in blockTasks)
              // Рамка задачи — в цвете её блока, совпадает с сектором
              // круга «Продуктивность по блокам» (blockColorOf).
              Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: BlockProductivityWheel.blockColorOf(store, t.block),
                    width: 1.2,
                  ),
                ),
                child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 8),
                // Тап по задаче блока — под шкалой цели раскрывается
                // шкала шагов этой задачи (без перехода между вкладками).
                onTap: () => store.peekTaskSteps(t),
                leading: IconButton(
                  icon: Icon(
                    t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: t.isDone ? AppTheme.done : AppTheme.textDim,
                  ),
                  onPressed: () => store.toggleTaskDone(t.id),
                ),
                title: Text(t.title, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  [
                    if (t.deadline != null) 'до ${_fmtShort(t.deadline!)}',
                    if (t.recurDaily) 'ежедневно',
                    if (t.isKeyAction) 'ключевое',
                  ].join(' · '),
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                ),
                ),
              ),
        ],
      ),
    );
  }
}

String _fmtShort(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// Шкала цели: линия времени с месячной разметкой и «огоньками»-
/// контрольными точками. Каждая точка — задача, привязанная к цели.
/// Длина шкалы — временной интервал из загруженного файла стратегии
/// (period.start..period.end), а если файл без интервала или не
/// загружен — один год от сегодняшнего дня; границы расширяются так,
/// чтобы все задачи, события и цели попадали на шкалу (store.planRange).
/// Расстановка точек: с дедлайном — строго по своей дате на шкале;
/// без дедлайна — равномерно (среднесрочные и ежедневные по всей
/// шкале, краткосрочные между ними).
/// Цвет точки: зелёный — выполнена, красный — просрочена,
/// янтарный с обводкой — ключевое действие, серый — в работе.
class _GoalScale extends StatelessWidget {
  final Goal goal;
  final List<Task> tasks;
  final AppStore store;

  /// ordinal = true: режим блоков целей — задачи без даты идут строго
  /// по порядку списка, задачи с датой — по дате на шкале времени.
  final bool ordinal;
  const _GoalScale(
      {required this.goal,
      required this.tasks,
      required this.store,
      this.ordinal = false});

  static const _monthNames = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  @override
  Widget build(BuildContext context) {
    final range = store.planRange();
    final start = range.start;
    final end = range.end;
    final spanMs = end.difference(start).inMilliseconds.clamp(1, 1 << 62);
    final now = DateTime.now();

    // Месячная разметка: вертикальные риски на каждое 1-е число
    // интервала + подписи месяцев под баром.
    final ticks = <({double x, String label})>[];
    var m = DateTime(start.year, start.month, 1);
    if (!m.isAfter(start)) {
      m = DateTime(start.year, start.month + 1, 1);
    }
    // Первая подпись — начало интервала (чтобы левый край был подписан).
    ticks.add((
      x: 0.0,
      label:
          '${_monthNames[start.month - 1]} ${start.year.toString().substring(2)}',
    ));
    while (!m.isAfter(end)) {
      final f = m.difference(start).inMilliseconds / spanMs;
      ticks.add((
        x: f.clamp(0.0, 1.0).toDouble(),
        label: m.month == 1
            ? 'янв ${m.year.toString().substring(2)}'
            : _monthNames[m.month - 1],
      ));
      m = DateTime(m.year, m.month + 1, 1);
    }

    final noDeadline = tasks.where((t) => t.deadline == null).toList();
    final mediums = noDeadline.where((t) => t.horizon == 'medium').toList();
    final shorts = noDeadline
        .where((t) => t.horizon != 'medium' && t.horizon != 'daily' && !t.recurDaily)
        .toList();
    final dailies =
        noDeadline.where((t) => t.horizon == 'daily' || t.recurDaily).toList();

    final dots = <({double x, Task t})>[];
    // Задачи с датой — строго по своей дате на шкале времени
    // (сообразно привязке к календарю), в любом режиме.
    for (final t in tasks) {
      final dl = t.deadline;
      if (dl != null) {
        final f = dl.difference(start).inMilliseconds / spanMs;
        dots.add((x: f.clamp(0.02, 0.98).toDouble(), t: t));
      }
    }
    if (ordinal) {
      // Без даты (режим блоков): i-я такая задача списка — i-я точка
      // равномерно по шкале.
      for (var i = 0; i < noDeadline.length; i++) {
        dots.add((x: (i + 1) / (noDeadline.length + 1), t: noDeadline[i]));
      }
    } else {
      for (var i = 0; i < mediums.length; i++) {
        dots.add((x: (i + 1) / (mediums.length + 1), t: mediums[i]));
      }
      for (var i = 0; i < shorts.length; i++) {
        dots.add((x: (i + 0.5) / shorts.length, t: shorts[i]));
      }
      for (var i = 0; i < dailies.length; i++) {
        dots.add((x: (i + 1) / (dailies.length + 1), t: dailies[i]));
      }
    }

    // Точки окрашены по приоритету задачи: красный — высокий/просрочено,
    // янтарь — средний, бирюза — низкий, зелёный — выполнено.
    Color dotColor(Task t) => priorityDotColor(
          isDone: t.isDone,
          overdue: t.deadline != null && t.deadline!.isBefore(now),
          priority: t.priority,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: SizedBox(
        height: 42,
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 11,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppTheme.textDim.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Месячные риски на баре.
              for (final tick in ticks)
                Positioned(
                  left: (tick.x * (w - 14))
                      .clamp(0.0, (w - 12) > 0 ? w - 12 : 0.0)
                      .toDouble(),
                  top: 8,
                  child: Container(
                    width: 1,
                    height: 8,
                    color: AppTheme.textDim.withOpacity(0.5),
                  ),
                ),
              // Подписи месяцев под баром.
              for (final tick in ticks)
                Positioned(
                  left: (tick.x * (w - 14) - 16)
                      .clamp(0.0, (w - 40) > 0 ? w - 40 : 0.0)
                      .toDouble(),
                  top: 26,
                  width: 40,
                  child: Text(
                    tick.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 8, color: AppTheme.textDim, height: 1),
                  ),
                ),
              for (final d in dots)
                Positioned(
                  left: (d.x * (w - 14))
                      .clamp(0.0, (w - 12) > 0 ? w - 12 : 0.0)
                      .toDouble(),
                  top: 5,
                  child: Tooltip(
                    message:
                        '${d.t.title}${d.t.deadline != null ? ' · до ${_fmtShort(d.t.deadline!)}' : ''}',
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor(d.t),
                        border: d.t.isKeyAction
                            ? Border.all(color: AppTheme.warn, width: 2)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: dotColor(d.t).withOpacity(0.55),
                              blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// Диалог-праздник при достижении цели: похвала + приз.
void showGoalReward(BuildContext context, Goal g) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Цель достигнута!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Praise.forGoal()),
          const SizedBox(height: 12),
          const Text('Твой приз:',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            g.reward.isNotEmpty ? g.reward : Praise.rewardIdea(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (g.motivation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Зачем это было: ${g.motivation}',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Принять награду'),
        ),
      ],
    ),
  );
}

/// Диалог добавления блока: название + выбор значка и его размера
/// (крупный на весь блок или минималистичный, как иконки приоритета).
void showAddBlockDialog(BuildContext context, AppStore store) {
  final nameC = TextEditingController();
  var iconKey = 'folder';
  var mini = false;
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Новый блок'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameC,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Название блока'),
              ),
              const SizedBox(height: 14),
              const Text('Значок блока',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in blockIconMap.entries)
                    IconButton(
                      icon: Icon(e.value, size: 22),
                      color: iconKey == e.key
                          ? AppTheme.accent
                          : AppTheme.textDim,
                      style: iconKey == e.key
                          ? IconButton.styleFrom(
                              side: const BorderSide(color: AppTheme.accent),
                            )
                          : null,
                      onPressed: () => setState(() => iconKey = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Крупный'),
                    selected: !mini,
                    onSelected: (_) => setState(() => mini = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Мини'),
                    selected: mini,
                    onSelected: (_) => setState(() => mini = true),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameC.text.trim();
              if (name.isEmpty) return;
              await store.addBlock(name,
                  icon: mini ? 'mini:$iconKey' : iconKey);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    ),
  );
}

/// Выбор/смена значка существующего блока (с переключателем размера).
void showBlockIconPicker(BuildContext context, AppStore store, Goal g) {
  var iconKey = blockIconKey(g.icon.isEmpty ? 'folder' : g.icon);
  var mini = blockIconIsMini(g.icon);
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Значок блока «${g.title}»',
            style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in blockIconMap.entries)
                    IconButton(
                      icon: Icon(e.value, size: 22),
                      color: iconKey == e.key
                          ? AppTheme.accent
                          : AppTheme.textDim,
                      style: iconKey == e.key
                          ? IconButton.styleFrom(
                              side: const BorderSide(color: AppTheme.accent),
                            )
                          : null,
                      onPressed: () => setState(() => iconKey = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Крупный'),
                    selected: !mini,
                    onSelected: (_) => setState(() => mini = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Мини'),
                    selected: mini,
                    onSelected: (_) => setState(() => mini = true),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              store.setGoalIcon(g.id, mini ? 'mini:$iconKey' : iconKey);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

/// Подтверждение удаления блока (сам блок в архив, задачи остаются).
void _confirmDeleteBlock(BuildContext context, AppStore store, Goal g) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Удалить блок «${g.title}»?'),
      content: const Text(
          'Блок уйдёт в архив. Задачи не удалятся — у них просто исчезнет '
          'связь с этим блоком.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            store.removeBlock(g.id);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Блок удалён (в архиве)')),
            );
          },
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
}

/// Обычная цель с прогрессом.
class _GoalCard extends StatelessWidget {
  final Goal goal;
  final AppStore store;
  const _GoalCard({required this.goal, required this.store});

  @override
  Widget build(BuildContext context) {
    final g = goal;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          children: [
            ListTile(
              leading: IconButton(
                icon: const Icon(Icons.flag_outlined, color: AppTheme.textDim),
                tooltip: 'Цель достигнута (в архив)',
                onPressed: () {
                  store.toggleGoalDone(g.id);
                  showGoalReward(context, g);
                },
              ),
              title: Text(g.title),
              subtitle: Text(
                [
                  'горизонт ${g.horizonDays} дн. · прогресс ${(g.progress * 100).round()}%',
                  if (g.comment.isNotEmpty) g.comment,
                ].join('\n'),
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      g.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20,
                      color: g.isPinned ? AppTheme.daily : AppTheme.textDim,
                    ),
                    tooltip: g.isPinned ? 'Открепить' : 'Закрепить в «Ежедневные»',
                    onPressed: () => store.togglePinGoal(g.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => showGoalEditor(context, store, goal: g),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 20),
                    tooltip: 'В архив',
                    onPressed: () {
                      store.archiveGoal(g.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Цель в архиве')),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Шкала с контрольными точками-огоньками (задачи цели).
            _GoalScale(goal: g, tasks: store.tasksForGoal(g), store: store),
            // Вторая шкала: шаги задачи, выбранной тапом на экране «Задачи».
            if (store.focusTask != null && store.focusTask!.goalId == g.id)
              _TaskStepsPanel(task: store.focusTask!, store: store),
          ],
        ),
      ),
    );
  }
}

/// Вторая шкала под целью: шаги, ведущие к выполнению выбранной задачи.
/// Появляется по тапу на задачу на экране «Задачи»; шаги можно
/// отмечать прямо здесь, крестик сворачивает шкалу.
class _TaskStepsPanel extends StatelessWidget {
  final Task task;
  final AppStore store;
  const _TaskStepsPanel({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final steps = store.stepsForTask(task.id);
    final done = steps.where((s) => s.isDone).length;
    final ratio = steps.isEmpty ? 0.0 : done / steps.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Шаги задачи «${task.title}»',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: AppTheme.textDim),
                tooltip: 'Скрыть шкалу',
                visualDensity: VisualDensity.compact,
                onPressed: () => store.clearTaskFocus(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
            color: AppTheme.done,
          ),
          const SizedBox(height: 4),
          Text('$done/${steps.length} шагов',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
          if (steps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                  'Шагов пока нет — откройте «Шкала пути: шаги задачи» '
                  'в меню задачи, чтобы добавить.',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
            )
          else
            for (final s in steps)
              InkWell(
                onTap: () => store.toggleStepDone(s.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        s.isDone
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: s.isDone ? AppTheme.done : AppTheme.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: s.isDone ? AppTheme.textDim : AppTheme.text,
                            decoration: s.isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
