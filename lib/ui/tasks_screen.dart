/// Экран «Задачи»: три иллюстрированных блока в ряд сверху —
/// «Навыки и привычки» (ежедневные, зелёный контур), «Быстрая дорожная карта»
/// (краткосрочные), «30% 50% 80%» (среднесрочные задачи ТЕКУЩЕГО месяца,
/// сортировка по приоритету). Ниже по центру — крупный алый блок
/// «Горящие дедлайны» (бегущий человечек). Плюс полный список задач.
/// Тап по задаче открывает карточку со шкалой пути из шагов.
/// Лупа рядом с колокольчиком — поиск по названию: неподходящие
/// задачи скрываются, после редактирования список возвращается
/// к полному виду.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'archive_screen.dart';
import 'block_icons.dart';
import 'common.dart';
import 'diary_screen.dart';
import 'edit_dialogs.dart';
import 'task_detail.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _searchOpen = false;
  final TextEditingController _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  /// Выход из режима поиска: список возвращается к полному виду.
  /// Вызывается и после редактирования задачи из результатов поиска.
  void _closeSearch() {
    if (!_searchOpen && _searchC.text.isEmpty) return;
    setState(() {
      _searchOpen = false;
      _searchC.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.visibleTasks
      ..sort((a, b) {
        final ad = a.deadline;
        final bd = b.deadline;
        if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    // Поиск по ключевым словам: задачи, не подходящие под запрос,
    // скрываются из списка (счётчики блоков при этом не меняются).
    final q = _searchOpen ? _searchC.text.trim().toLowerCase() : '';
    final items = q.isEmpty
        ? all
        : all.where((t) => t.title.toLowerCase().contains(q)).toList();
    final dailyCount =
        all.where((t) => t.recurDaily || t.horizon == 'daily').length;
    final shortCount =
        all.where((t) => t.horizon == 'short' && !t.recurDaily).length;
    final mediumCount = monthMediumTasks(store).length;
    final hotCount = store.hotTasks().length;

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchC,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Поиск по названию задачи',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Задачи'),
                  Text('${all.length} задач',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDim, fontWeight: FontWeight.normal)),
                ],
              ),
        actions: [
          // Лупа поиска — рядом с колокольчиком (слева от него).
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            tooltip: _searchOpen ? 'Закрыть поиск' : 'Поиск задач',
            onPressed: () {
              if (_searchOpen) {
                _closeSearch();
              } else {
                setState(() => _searchOpen = true);
              }
            },
          ),
          const FontScaleButton(),
          const AlertBell(),
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // Три равных блока в ряд сверху (как было изначально),
          // «Горящие дедлайны» — отдельным блоком ниже, по центру.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BlockIcon(
                    icon: Icons.self_improvement,
                    label: 'Навыки и привычки',
                    color: AppTheme.done,
                    count: dailyCount,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const TasksBlockScreen(kind: 'habits'))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BlockIcon(
                    icon: Icons.alt_route,
                    label: 'Быстрая дорожная карта',
                    color: AppTheme.accent,
                    count: shortCount,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const TasksBlockScreen(kind: 'roadmap'))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BlockIcon(
                    icon: Icons.donut_large,
                    label: '30% 50% 80%',
                    color: AppTheme.warn,
                    count: mediumCount,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const TasksBlockScreen(kind: 'medium'))),
                  ),
                ),
              ],
            ),
          ),
          // Горящие дедлайны — внизу, по центру, крупнее остальных.
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 4, 48, 4),
            child: _BlockIcon(
              icon: Icons.directions_run,
              label: 'Горящие дедлайны',
              color: AppTheme.critical,
              count: hotCount,
              height: 126,
              iconSize: 36,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TasksBlockScreen(kind: 'hot'))),
            ),
          ),
          SectionHeader(q.isEmpty ? 'Все задачи' : 'Найдено: ${items.length}'),
          if (items.isEmpty)
            EmptyHint(q.isEmpty
                ? 'Задач пока нет. Добавьте первую!'
                : 'По запросу «$q» ничего не найдено')
          else
            for (final t in items)
              TaskTile(task: t, onEdited: _closeSearch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTaskEditor(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Среднесрочные задачи ТЕКУЩЕГО календарного месяца, выстроенные
/// по приоритету (высокий сверху), затем по близости дедлайна.
List<Task> monthMediumTasks(AppStore store) {
  final now = DateTime.now();
  final list = store.visibleTasks.where((t) {
    if (t.horizon != 'medium' || t.recurDaily) return false;
    final dl = t.deadline;
    if (dl == null) return false;
    return dl.year == now.year && dl.month == now.month;
  }).toList();
  list.sort((a, b) {
    final p = b.priority.compareTo(a.priority);
    if (p != 0) return p;
    return (a.deadline ?? a.createdAt).compareTo(b.deadline ?? b.createdAt);
  });
  return list;
}

/// Иконка-блок: иллюстрация содержания + название + счётчик.
class _BlockIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int count;
  final VoidCallback onTap;
  final double height;
  final double iconSize;

  const _BlockIcon({
    required this.icon,
    required this.label,
    required this.color,
    required this.count,
    required this.onTap,
    this.height = 108,
    this.iconSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.2),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: iconSize),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.text)),
            const SizedBox(height: 2),
            Text('$count',
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Название блока по его коду (для подписи «связь: …»).
String _blockTitle(AppStore store, String blockId) {
  for (final g in store.blockGoals()) {
    if (g.externalId.substring(6) == blockId) return g.title;
  }
  return blockId;
}

/// Плитка задачи (единый вид для всех списков).
/// Тап раскрывает под задачей инлайн-панель: дорожка шагов
/// «весёлые человечки» + отметки шагов. Полная шкала пути — в меню.
class TaskTile extends StatefulWidget {
  final Task task;

  /// Цвет даты дедлайна — цвет блока, на экране которого показана
  /// задача («Горящие дедлайны» — красный, «Навыки и привычки» —
  /// зелёный и т.д.). null — обычная раскраска по близости срока.
  final Color? dateColor;

  /// Колбэк после отметки выполнения (экран «Сегодня» использует
  /// для проверки награды за продуктивный день).
  final VoidCallback? onDone;

  /// Колбэк после закрытия редактора задачи (экран «Задачи» в режиме
  /// поиска использует для возврата списка к полному виду).
  final VoidCallback? onEdited;

  /// Показывать в меню пункт «Выполнить сегодня» (экран
  /// «Запланировать на завтра»): задача отмечается выполненной
  /// прямо сейчас, не дожидаясь завтрашнего дня.
  final bool showDoneToday;

  /// Показывать значок дневника на задачах «итоги дня» (по названию
  /// или по флагу в редакторе). Тап — точка входа в дневник.
  final bool diaryEntryPoint;
  const TaskTile(
      {super.key,
      required this.task,
      this.dateColor,
      this.onDone,
      this.onEdited,
      this.showDoneToday = false,
      this.diaryEntryPoint = false});

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _expanded = false;

  /// «Будильник по дедлайну»: сразу открывается окно выбора даты
  /// и времени — выбранное время фиксируется дедлайном задачи,
  /// и системный будильник ставится на него напрямую.
  Future<void> _alarmWithDeadline(
      BuildContext context, AppStore store, Task t) async {
    final now = DateTime.now();
    final initial = t.deadline ?? now.add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !context.mounted) return;
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (tod == null || !context.mounted) return;
    t.deadline = DateTime(d.year, d.month, d.day, tod.hour, tod.minute);
    await store.updateTask(t);
    if (!context.mounted) return;
    final msg = await store.setTaskAlarm(t.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Дедлайн: ${fmtDateTime(t.deadline!)}. $msg')));
    }
  }

  /// Диалог номера очерёдности на экране «Сегодня»: задать/изменить
  /// число или убрать номер. Открывается тапом по номеру на карточке
  /// или пунктом меню «Номер очерёдности».
  Future<void> _editSortNum(BuildContext context, AppStore store) async {
    final c = TextEditingController(
        text: widget.task.sortNum > 0 ? '${widget.task.sortNum}' : '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Номер очерёдности'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: 'Номер в списке «Сегодня» (1–99)'),
          onSubmitted: (_) => Navigator.pop(ctx, 'save'),
        ),
        actions: [
          if (widget.task.sortNum > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('Убрать номер',
                  style: TextStyle(color: AppTheme.warn)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (res == 'clear') {
      await store.setTaskSortNum(widget.task.id, 0);
      return;
    }
    if (res == 'save') {
      final n = int.tryParse(c.text.trim());
      if (n != null && n > 0) {
        await store.setTaskSortNum(widget.task.id, n);
      }
    }
  }

  /// «С каким блоком связать?» — диалог выбора блока годового плана.
  Future<void> _linkBlock(BuildContext context, AppStore store) async {
    final blocks = store.blockGoals();
    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Блоков нет — импортируйте стратегию или создайте блок '
                'на экране «Цели» (иконка папки сверху)')),
      );
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('С каким блоком связать?'),
        children: [
          for (final g in blocks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.externalId.substring(6)),
              child: Row(
                children: [
                  blockIconWidget(g.icon, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(g.title)),
                ],
              ),
            ),
          if (widget.task.linkedBlock.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Row(
                children: [
                  Icon(Icons.link_off, size: 18, color: AppTheme.textDim),
                  SizedBox(width: 10),
                  Text('Отвязать от блока'),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await store.linkTaskToBlock(widget.task.id, chosen);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(chosen.isEmpty
                  ? 'Задача отвязана от блока'
                  : 'Задача связана с блоком')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = widget.task;
    final urgency = taskUrgencyColor(t);
    final hasGoal = t.goalId.isNotEmpty ||
        store.blockIdOf(t).isNotEmpty ||
        t.linkedBlock.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        // Контур — цвет горизонта задачи (ежедневная — зелёный,
        // краткосрочная — синий, среднесрочная — жёлтый). Молния
        // «ключевая» цвет контура НЕ меняет. Красный — только
        // пропущенный дедлайн (см. taskUrgencyColor).
        side: urgency != null
            ? BorderSide(
                color: urgency, width: urgency == AppTheme.critical ? 1.6 : 1)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          ListTile(
        // Тап по задаче раскрывает под ней инлайн-панель прогресса:
        // дорожка шагов «весёлые человечки» (см. TaskStepsInline).
        onTap: () => setState(() => _expanded = !_expanded),
        leading: IconButton(
          icon: const Icon(Icons.radio_button_unchecked, color: AppTheme.textDim),
          tooltip: 'Выполнить (в архив)',
          onPressed: () {
            // Награда за день — после закрытия всех окон выполнения
            // (время/причина), чтобы её сообщение не терялось под ними.
            completeTaskWithFeedback(context, store, t,
                onAfter: widget.onDone);
          },
        ),
        title: Row(
          children: [
            if (t.isKeyAction)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.key, size: 15, color: AppTheme.warn),
              ),
            // Номер очерёдности на экране «Сегодня»: видимый чип
            // на карточке. Тап — изменить или убрать номер.
            if (t.sortNum > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _editSortNum(context, store),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: AppTheme.accent, width: 1.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${t.sortNum}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            Expanded(child: Text(t.title)),
          ],
        ),
        // Дата и время дедлайна: внутри тематического блока — цветом
        // блока (dateColor), в общем списке — по близости срока.
        subtitle: deadlineInfoText(t, dateColor: widget.dateColor, extra: [
          '~${t.estimateMin} мин',
          // Фактическое время выполнения (из диалога после выполнения).
          if (t.actualMin > 0) 'итого: ${fmtDaysHoursMin(t.actualMin)}',
          if (t.linkedBlock.isNotEmpty)
            'связь: ${_blockTitle(store, t.linkedBlock)}',
          if (t.recurDaily) 'ежедневно',
          // Синхронизация с экраном «Сегодня»: если ежедневная задача
          // уже выполнена сегодня, активный экземпляр — завтрашний
          // (дедлайн на следующий день), а эта пометка видна везде.
          if (store.dailyDoneToday(t)) '✓ сделано сегодня',
          if (t.recurDaily && t.pctStep < 100) '${t.progressPct}%',
          if (t.isKeyAction) 'ключевое действие',
          if (t.missedCount > 0) 'пропусков: ${t.missedCount}',
          if (t.metric.isNotEmpty) 'метрика: ${t.metric}',
          if (t.comment.isNotEmpty) t.comment,
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Значок дневника на задачах «итоги дня»: по флагу
            // в редакторе ИЛИ по названию. Тап — вход в дневник.
            if (widget.diaryEntryPoint && AppStore.isDayReviewTask(t))
              IconButton(
                icon: const Icon(Icons.auto_stories_outlined,
                    size: 20, color: AppTheme.accent),
                tooltip: 'Дневник',
                onPressed: () => showDiaryEntryPoint(context),
              ),
            IconButton(
              icon: Icon(
                t.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
                color: t.isPinned ? AppTheme.daily : AppTheme.textDim,
              ),
              tooltip: t.isPinned ? 'Открепить' : 'Закрепить в «Ежедневные»',
              onPressed: () => store.togglePinTask(t.id),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () async {
                await showTaskEditor(context, store, task: t);
                // В режиме поиска после редактирования и подтверждения
                // список возвращается к полному виду.
                widget.onEdited?.call();
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textDim),
              tooltip: 'Ещё',
              onSelected: (v) async {
                if (v == 'link') _linkBlock(context, store);
                if (v == 'steps') showTaskDetail(context, t);
                if (v == 'children') showTaskDetail(context, t);
                if (v == 'focus') store.focusTaskSteps(t);
                if (v == 'sortnum') _editSortNum(context, store);
                if (v == 'doneToday') {
                  completeTaskWithFeedback(context, store, t,
                      onAfter: widget.onDone);
                }
                if (v == 'unmerge') {
                  await store.unmergeTask(t.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Задача отсоединена — снова в списках')),
                    );
                  }
                }
                if (v == 'alarm') {
                  await _alarmWithDeadline(context, store, t);
                }
                if (v == 'alarmOff') {
                  final msg = await store.cancelTaskAlarm(t.id);
                  // Звук ручного снятия будильника (как раньше).
                  SystemSound.play(SystemSoundType.alert);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                }
                if (v == 'archive') {
                  store.archiveTask(t.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Задача в архиве')),
                  );
                }
              },
              itemBuilder: (_) => [
                // Пункт «Просмотреть однородные» — только если внутрь
                // задачи слиты другие (перетаскиванием на «Сегодня»).
                if (store.hasChildrenTasks(t.id))
                  const PopupMenuItem(
                    value: 'children',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.account_tree, size: 20),
                      title: Text('Просмотреть однородные'),
                    ),
                  ),
                // Слитая задача — можно отсоединить обратно в списки.
                if (t.parentTaskId.isNotEmpty)
                  const PopupMenuItem(
                    value: 'unmerge',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.call_split, size: 20),
                      title: Text('Отсоединить от задачи'),
                    ),
                  ),
                if (widget.showDoneToday)
                  const PopupMenuItem(
                    value: 'doneToday',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline,
                          size: 20, color: AppTheme.done),
                      title: Text('Выполнить сегодня'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'sortnum',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.format_list_numbered, size: 20),
                    title: Text('Номер очерёдности'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'steps',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.stairs_outlined, size: 20),
                    title: Text('Шкала пути: шаги задачи'),
                  ),
                ),
                if (hasGoal)
                  const PopupMenuItem(
                    value: 'focus',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.flag_outlined, size: 20),
                      title: Text('Показать на экране «Цели»'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'link',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.account_tree_outlined, size: 20),
                    title: Text('С каким блоком связать?'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'alarm',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.alarm, size: 20),
                    title: Text('Будильник: выбрать время дедлайна'),
                  ),
                ),
                // Ручное снятие установленного будильника — со звуком.
                if (store.hasTaskAlarm(t.id))
                  const PopupMenuItem(
                    value: 'alarmOff',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.alarm_off,
                          size: 20, color: AppTheme.warn),
                      title: Text('Снять будильник'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.archive_outlined, size: 20),
                    title: Text('В архив'),
                  ),
                ),
              ],
            ),
          ],
        ),
          ),
          // Инлайн-панель шагов «весёлые человечки» — раскрывается
          // тапом по задаче, прямо под ней.
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TaskStepsInline(
                task: t,
                onOpenFull: () => showTaskDetail(context, t),
              ),
            ),
        ],
      ),
    );
  }
}

/// Содержимое блока: отфильтрованные задачи.
/// «30% 50% 80%» — ТОЛЬКО задачи текущего календарного месяца
/// (без перенесённых с экрана целей блоков), сортировка по приоритету.
class TasksBlockScreen extends StatelessWidget {
  final String kind; // 'habits' | 'hot' | 'roadmap' | 'medium'
  const TasksBlockScreen({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    late final String title;
    late final List<Task> tasks;
    // Цвет даты внутри блока — цвет самого блока.
    late final Color dateColor;
    switch (kind) {
      case 'habits':
        title = 'Навыки и привычки';
        dateColor = AppTheme.done;
        tasks = store.visibleTasks
            .where((t) => t.recurDaily || t.horizon == 'daily')
            .toList();
        break;
      case 'hot':
        title = 'Горящие дедлайны';
        dateColor = AppTheme.critical;
        tasks = store.hotTasks();
        break;
      case 'roadmap':
        title = 'Быстрая дорожная карта';
        dateColor = AppTheme.accent;
        tasks = store.visibleTasks
            .where((t) => t.horizon == 'short' && !t.recurDaily)
            .toList();
        break;
      default:
        title = '30% 50% 80%';
        dateColor = AppTheme.warn;
        tasks = monthMediumTasks(store);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tasks.isEmpty
          ? const EmptyHint('В этом блоке пока пусто')
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (kind == 'medium')
                  const SectionHeader('Среднесрочные задачи месяца',
                      subtitle: 'Сортировка: по приоритету, затем по сроку'),
                for (final t in tasks)
                  // Контур задачи остаётся цвета её горизонта, а дата
                  // окрашивается в цвет этого блока.
                  TaskTile(task: t, dateColor: dateColor),
              ],
            ),
    );
  }
}
