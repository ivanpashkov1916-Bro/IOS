/// Модальные окна CRUD: создание и редактирование всех сущностей.
/// Иконка карандаша на экранах открывает диалог с заполненными полями.
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'common.dart';

Future<DateTime?> _pickDateTime(BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? DateTime(now.year, now.month, now.day, 18)),
  );
  return DateTime(d.year, d.month, d.day, t?.hour ?? 18, t?.minute ?? 0);
}

/// Кнопки диалога: [Удалить] — только при редактировании существующего,
/// справа Отмена/Сохранить. close получает 'save' | 'delete' | 'cancel'.
Widget _saveCancel(void Function(String) close, {bool showDelete = false}) {
  return Row(
    children: [
      if (showDelete)
        TextButton(
          onPressed: () => close('delete'),
          child: const Text('Удалить', style: TextStyle(color: AppTheme.warn)),
        ),
      const Spacer(),
      TextButton(onPressed: () => close('cancel'), child: const Text('Отмена')),
      const SizedBox(width: 8),
      FilledButton(onPressed: () => close('save'), child: const Text('Сохранить')),
    ],
  );
}

/// Подтверждение удаления навсегда (без архива).
Future<bool> confirmDeleteForever(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить навсегда?'),
      content: Text('«$title» будет удалено без возможности восстановления.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.warn),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  return ok == true;
}

// ---------- Уточняющие вопросы после создания ----------
/// После добавления НОВОЙ цели/задачи/события (вручную или голосом)
/// задаём два вопроса: какие нужны ресурсы и какие шаги предпринять.
/// «Пропустить» — поля остаются пустыми, всё можно заполнить позже.
/// Ресурсы (каждая строка = один ресурс):
/// — для задачи: попадают в блок «Ресурсы» карточки задачи
///   (отдельная сущность, видна на всех экранах задачи);
/// — для цели/события: уходят в комментарий записи.
/// Шаги:
/// — для задачи: становятся точками-шагами на шкале пути
///   (6 строк = 6 шагов);
/// — для цели: создаются как краткосрочные задачи, привязанные к цели
///   (точки на шкале цели, с соблюдением ранжирования);
/// — для события: шагов нет, только ресурсы в комментарий.
Future<void> showPlanQuestions(
  BuildContext context,
  AppStore store, {
  required String kind, // 'task' | 'goal' | 'event'
  required String id,
}) async {
  final resourcesC = TextEditingController();
  final stepsC = TextEditingController();
  final title = switch (kind) {
    'task' => 'Новая задача',
    'goal' => 'Новая цель',
    _ => 'Новое событие',
  };
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$title — пара уточнений'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: resourcesC,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText:
                      'Какие ресурсы нужны? (каждый с новой строки)'),
            ),
            const SizedBox(height: 12),
            if (kind != 'event')
              TextField(
                controller: stepsC,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText:
                        'Какие шаги нужно предпринять? (каждый с новой строки)'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Пропустить'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (saved != true) return;

  final resources = resourcesC.text.trim();
  // Каждая строка поля ресурсов — один ресурс (как шаги: строка=шаг).
  final resourceLines = resources
      .split(RegExp(r'[\n;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final stepLines = stepsC.text
      .split(RegExp(r'[\n;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  if (kind == 'task') {
    final t = store.tasks.where((x) => x.id == id).firstOrNull;
    if (t == null) return;
    // Ресурсы задачи — в отдельный блок «Ресурсы» карточки задачи,
    // по строке на ресурс (виден на всех экранах задачи).
    for (final r in resourceLines) {
      await store.addResource(id, r);
    }
    if (stepLines.isNotEmpty) {
      for (final s in stepLines) {
        await store.addStep(id, s);
      }
    } else {
      // Шаги не ввели — пробуем взять их из названия после «:».
      await store.seedStepsFromTitle(t);
    }
  } else if (kind == 'goal') {
    final g = store.goals.where((x) => x.id == id).firstOrNull;
    if (g == null) return;
    if (resources.isNotEmpty) {
      g.comment = g.comment.isEmpty
          ? 'Ресурсы: $resources'
          : '${g.comment}\nРесурсы: $resources';
      await store.updateGoal(g);
    }
    // Каждый шаг — краткосрочная задача, привязанная к цели:
    // точки на шкале цели, сортировка и все функции задач сохраняются.
    for (final s in stepLines) {
      await store.addTask(Task(title: s, goalId: id, horizon: 'short'));
    }
  } else {
    final e = store.events.where((x) => x.id == id).firstOrNull;
    if (e == null) return;
    if (resources.isNotEmpty) {
      e.comment = e.comment.isEmpty
          ? 'Ресурсы: $resources'
          : '${e.comment}\nРесурсы: $resources';
      await store.updateEvent(e);
    }
  }
}

// ---------- Заметка ----------
Future<void> showNoteEditor(BuildContext context, AppStore store, {Note? note}) async {
  final titleC = TextEditingController(text: note?.title ?? '');
  final textC = TextEditingController(text: note?.text ?? '');
  bool pinned = note?.isPinned ?? false;
  final ok = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(note == null ? 'Новая заметка' : 'Редактировать заметку'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleC, decoration: const InputDecoration(hintText: 'Заголовок')),
              const SizedBox(height: 12),
              TextField(
                controller: textC,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'Текст заметки'),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Закрепить в «Ежедневные»', style: TextStyle(fontSize: 13)),
                value: pinned,
                activeColor: AppTheme.daily,
                onChanged: (v) => setS(() => pinned = v),
              ),
            ],
          ),
        ),
        actions: [_saveCancel((v) => Navigator.pop(ctx, v), showDelete: note != null)],
      ),
    ),
  );
  if (ok == 'delete' && note != null) {
    if (await confirmDeleteForever(context, note.title)) {
      await store.deleteNoteForever(note.id);
    }
    return;
  }
  if (ok != 'save') return;
  final title = titleC.text.trim();
  if (title.isEmpty) return;
  if (note == null) {
    await store.addNote(Note(title: title, text: textC.text.trim(), isPinned: pinned));
  } else {
    note.title = title;
    note.text = textC.text.trim();
    note.isPinned = pinned;
    await store.updateNote(note);
  }
}

// ---------- Задача ----------
Future<void> showTaskEditor(BuildContext context, AppStore store, {Task? task}) async {
  final titleC = TextEditingController(text: task?.title ?? '');
  final estC = TextEditingController(text: (task?.estimateMin ?? 30).toString());
  final actC = TextEditingController(
      text: (task != null && task.actualMin > 0) ? task.actualMin.toString() : '');
  final commentC = TextEditingController(text: task?.comment ?? '');
  DateTime? deadline = task?.deadline;
  int priority = task?.priority ?? 1;
  bool recurDaily = task?.recurDaily ?? false;
  bool pinned = task?.isPinned ?? false;
  bool keyAction = task?.isKeyAction ?? false;
  bool isDayReview = task?.isDayReview ?? false;
  String horizon = task?.horizon ?? 'short';
  if (recurDaily) horizon = 'daily';
  String goalId = task?.goalId ?? '';
  final goals = store.activeGoals.where((g) => !g.recurDaily).toList();
  if (goalId.isEmpty && task != null) {
    // Показываем текущую привязку к блоку (раньше тут всегда было
    // «Без цели»): подставляем блок импорта или ручной связи.
    for (final g in goals) {
      if (!g.externalId.startsWith('block:')) continue;
      final bid = g.externalId.substring(6);
      if ((task.block.isNotEmpty && task.block == bid) ||
          (task.linkedBlock.isNotEmpty && task.linkedBlock == bid)) {
        goalId = g.id;
        break;
      }
    }
  }
  if (goalId.isNotEmpty && !goals.any((g) => g.id == goalId)) goalId = '';

  final ok = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(task == null ? 'Новая задача' : 'Редактировать задачу'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleC, decoration: const InputDecoration(hintText: 'Название')),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await _pickDateTime(ctx, deadline);
                  if (picked != null) setS(() => deadline = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    deadline == null ? 'Дедлайн: не задан (нажмите)' : 'Дедлайн: ${fmtDateTime(deadline!)}',
                    style: TextStyle(color: deadline == null ? AppTheme.textDim : AppTheme.text),
                  ),
                ),
              ),
              if (deadline != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setS(() => deadline = null),
                    child: const Text('Убрать дедлайн', style: TextStyle(fontSize: 12)),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: PriorityIcons(
                  priority: priority,
                  isKey: keyAction,
                  onPriority: (p) => setS(() => priority = p),
                  onKey: () => setS(() => keyAction = !keyAction),
                ),
              ),
              const SizedBox(height: 12),
              // Планируемое время: число под значками приоритета — минуты.
              // Рядом с полем показываем значение в формате дни/часы/минуты.
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Планируемое время на выполнение',
                    style: TextStyle(fontSize: 12, color: AppTheme.textDim)),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: estC,
                keyboardType: TextInputType.number,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: 'минуты',
                  helperText:
                      'Итого: ${fmtDaysHoursMin(int.tryParse(estC.text) ?? 0)}',
                ),
              ),
              const SizedBox(height: 16),
              // Фактическое время: заполняется вручную после завершения задачи.
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Фактически реализована за',
                    style: TextStyle(fontSize: 12, color: AppTheme.textDim)),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: actC,
                keyboardType: TextInputType.number,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: 'минуты — после завершения задачи',
                  helperText:
                      'Итого: ${fmtDaysHoursMin(int.tryParse(actC.text) ?? 0)}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentC,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'Комментарий: суть, причина пропуска...'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: goalId,
                decoration: const InputDecoration(
                    hintText: 'Блок / цель (текущая привязка подставлена)'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Без цели')),
                  for (final g in goals)
                    DropdownMenuItem(
                        value: g.id,
                        child: Text(g.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setS(() => goalId = v ?? ''),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: horizon,
                decoration: const InputDecoration(hintText: 'Горизонт задачи'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Ежедневная (равномерно по шкале)')),
                  DropdownMenuItem(value: 'short', child: Text('Краткосрочная (между среднесрочными)')),
                  DropdownMenuItem(value: 'medium', child: Text('Среднесрочная (равномерно по цели)')),
                ],
                onChanged: (v) => setS(() {
                  horizon = v ?? 'short';
                  recurDaily = horizon == 'daily';
                  if (recurDaily) pinned = true;
                }),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Ключевое действие', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Без него результат недостижим',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                value: keyAction,
                activeColor: AppTheme.warn,
                onChanged: (v) => setS(() => keyAction = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Ежедневная привычка', style: TextStyle(fontSize: 13)),
                value: recurDaily,
                activeColor: AppTheme.daily,
                onChanged: (v) => setS(() {
                  recurDaily = v;
                  horizon = v ? 'daily' : (horizon == 'daily' ? 'short' : horizon);
                  if (v) pinned = true; // привычка всегда закреплена
                }),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Закрепить в «Ежедневные»', style: TextStyle(fontSize: 13)),
                value: pinned,
                activeColor: AppTheme.daily,
                onChanged: (v) => setS(() => pinned = v),
              ),
              // Флаг «Итоги дня»: на карточке такой задачи появляется значок
              // дневника. Срабатывает И по флагу, И по названию «итоги дня».
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Итоги дня (дневник)', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Значок дневника на карточке задачи',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                value: isDayReview,
                activeColor: AppTheme.accent,
                onChanged: (v) => setS(() => isDayReview = v),
              ),
            ],
          ),
        ),
        actions: [_saveCancel((v) => Navigator.pop(ctx, v), showDelete: task != null)],
      ),
    ),
  );
  if (ok == 'delete' && task != null) {
    if (await confirmDeleteForever(context, task.title)) {
      await store.deleteTaskForever(task.id);
    }
    return;
  }
  if (ok != 'save') return;
  final title = titleC.text.trim();
  if (title.isEmpty) return;
  final estimate = int.tryParse(estC.text) ?? 30;
  final actual = int.tryParse(actC.text) ?? 0;
  if (task == null) {
    await store.addTask(Task(
      title: title,
      deadline: deadline,
      estimateMin: estimate,
      actualMin: actual,
      priority: priority,
      recurDaily: recurDaily,
      isPinned: pinned,
      isKeyAction: keyAction,
      isDayReview: isDayReview,
      goalId: goalId,
      horizon: horizon,
      comment: commentC.text.trim(),
    ));
    // Уточняющие вопросы: ресурсы и шаги (шаги -> точки на шкале).
    final created = store.justCreated;
    if (created != null && context.mounted) {
      await showPlanQuestions(context, store,
          kind: created.kind, id: created.id);
    }
    store.clearJustCreated();
  } else {
    task.title = title;
    task.deadline = deadline;
    task.estimateMin = estimate;
    task.actualMin = actual;
    task.priority = priority;
    task.recurDaily = recurDaily;
    task.isPinned = pinned;
    task.isKeyAction = keyAction;
    task.isDayReview = isDayReview;
    task.goalId = goalId;
    task.horizon = horizon;
    task.comment = commentC.text.trim();
    await store.updateTask(task);
  }
}

// ---------- Цель ----------
Future<void> showGoalEditor(BuildContext context, AppStore store, {Goal? goal}) async {
  final titleC = TextEditingController(text: goal?.title ?? '');
  final motivationC = TextEditingController(text: goal?.motivation ?? '');
  final rewardC = TextEditingController(text: goal?.reward ?? '');
  final commentC = TextEditingController(text: goal?.comment ?? '');
  final criteriaC = TextEditingController(text: goal?.criteria ?? '');
  final ifFailC = TextEditingController(text: goal?.ifFail ?? '');
  int horizon = goal?.horizonDays ?? 30;
  double progress = goal?.progress ?? 0;
  bool recurDaily = goal?.recurDaily ?? false;
  bool pinned = goal?.isPinned ?? false;

  final ok = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(goal == null ? 'Новая цель' : 'Редактировать цель'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleC, decoration: const InputDecoration(hintText: 'Название цели')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: horizon,
                decoration: const InputDecoration(hintText: 'Горизонт'),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('Неделя')),
                  DropdownMenuItem(value: 30, child: Text('Месяц')),
                  DropdownMenuItem(value: 90, child: Text('Квартал')),
                  DropdownMenuItem(value: 365, child: Text('Год')),
                ],
                onChanged: (v) => setS(() => horizon = v ?? 30),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivationC,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText:
                        'Уверен(а), что цель твоя? Какое ощущение хочешь получить, когда достигнешь?'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rewardC,
                decoration: const InputDecoration(
                    hintText: 'Приз за достижение (вкусняшка, отдых, покупка...)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentC,
                maxLines: 2,
                decoration:
                    const InputDecoration(hintText: 'Комментарий: суть цели'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: criteriaC,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText:
                        'Как ты поймёшь, что цель достигнута? Какие критерии выполнения?'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifFailC,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText:
                        'Что произойдёт и что будешь делать, если цель не будет достигнута?'),
              ),
              if (goal != null && !goal.recurDaily) ...[
                const SizedBox(height: 12),
                Text('Прогресс: ${(progress * 100).round()}%',
                    style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                Slider(
                  value: progress,
                  onChanged: (v) => setS(() => progress = v),
                ),
              ],
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Ежедневная привычка', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Каждый день отмечается заново, пропуски считаются',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                value: recurDaily,
                activeColor: AppTheme.daily,
                onChanged: (v) => setS(() {
                  recurDaily = v;
                  if (v) pinned = true;
                }),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Закрепить в «Ежедневные»', style: TextStyle(fontSize: 13)),
                value: pinned,
                activeColor: AppTheme.daily,
                onChanged: (v) => setS(() => pinned = v),
              ),
            ],
          ),
        ),
        actions: [_saveCancel((v) => Navigator.pop(ctx, v), showDelete: goal != null)],
      ),
    ),
  );
  if (ok == 'delete' && goal != null) {
    if (await confirmDeleteForever(context, goal.title)) {
      await store.deleteGoalForever(goal.id);
    }
    return;
  }
  if (ok != 'save') return;
  final title = titleC.text.trim();
  if (title.isEmpty) return;
  if (goal == null) {
    await store.addGoal(Goal(
      title: title,
      horizonDays: horizon,
      recurDaily: recurDaily,
      isPinned: pinned,
      motivation: motivationC.text.trim(),
      reward: rewardC.text.trim(),
      comment: commentC.text.trim(),
      criteria: criteriaC.text.trim(),
      ifFail: ifFailC.text.trim(),
    ));
    // Уточняющие вопросы: ресурсы и шаги (шаги -> задачи на шкале цели).
    final created = store.justCreated;
    if (created != null && context.mounted) {
      await showPlanQuestions(context, store,
          kind: created.kind, id: created.id);
    }
    store.clearJustCreated();
  } else {
    goal.title = title;
    goal.horizonDays = horizon;
    goal.recurDaily = recurDaily;
    goal.isPinned = pinned;
    goal.motivation = motivationC.text.trim();
    goal.reward = rewardC.text.trim();
    goal.comment = commentC.text.trim();
    goal.criteria = criteriaC.text.trim();
    goal.ifFail = ifFailC.text.trim();
    if (!goal.recurDaily) {
      goal.progress = progress;
      if (goal.progress >= 1) goal.isDone = true;
    }
    await store.updateGoal(goal);
  }
}

// ---------- Событие ----------
Future<void> showEventEditor(BuildContext context, AppStore store, {EventItem? event}) async {
  final titleC = TextEditingController(text: event?.title ?? '');
  final durC = TextEditingController(text: (event?.durationMin ?? 60).toString());
  final commentC = TextEditingController(text: event?.comment ?? '');
  DateTime start = event?.start ?? DateTime.now().add(const Duration(hours: 1));

  final ok = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(event == null ? 'Новое событие' : 'Редактировать событие'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleC, decoration: const InputDecoration(hintText: 'Название')),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await _pickDateTime(ctx, start);
                  if (picked != null) setS(() => start = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Начало: ${fmtDateTime(start)}',
                      style: const TextStyle(color: AppTheme.text)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: durC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Длительность, минут'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentC,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'Комментарий: как ты видишь это событие?'),
              ),
            ],
          ),
        ),
        actions: [_saveCancel((v) => Navigator.pop(ctx, v), showDelete: event != null)],
      ),
    ),
  );
  if (ok == 'delete' && event != null) {
    if (await confirmDeleteForever(context, event.title)) {
      await store.deleteEventForever(event.id);
    }
    return;
  }
  if (ok != 'save') return;
  final title = titleC.text.trim();
  if (title.isEmpty) return;
  final dur = int.tryParse(durC.text) ?? 60;
  if (event == null) {
    await store.addEvent(EventItem(
        title: title, start: start, durationMin: dur, comment: commentC.text.trim()));
    // Уточняющий вопрос: какие ресурсы нужны.
    final created = store.justCreated;
    if (created != null && context.mounted) {
      await showPlanQuestions(context, store,
          kind: created.kind, id: created.id);
    }
    store.clearJustCreated();
  } else {
    event.title = title;
    event.start = start;
    event.durationMin = dur;
    event.comment = commentC.text.trim();
    await store.updateEvent(event);
  }
}
