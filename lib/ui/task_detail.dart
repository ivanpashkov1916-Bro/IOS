/// Карточка задачи (bottom sheet): шкала пути из шагов-точек,
/// иконки приоритета (волны / ! / костюм) + молния целевого действия,
/// шаги с такими же иконками, фото-подтверждение шага при наличии метрики.
/// Шаги можно именовать словами после «:» в названии задачи — они
/// подставляются автоматически при первом открытии.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'common.dart';
import 'edit_dialogs.dart';
import 'tasks_screen.dart';

Future<void> showTaskDetail(BuildContext context, Task task) async {
  final store = context.read<AppStore>();
  await store.seedStepsFromTitle(task);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TaskDetailSheet(taskId: task.id),
  );
}

class _TaskDetailSheet extends StatefulWidget {
  final String taskId;
  const _TaskDetailSheet({required this.taskId});

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  final _newStep = TextEditingController();
  final _newResource = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Пока идёт секундомер задачи — перерисовываем раз в секунду.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (context.read<AppStore>().taskTimerRunning(widget.taskId)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _newStep.dispose();
    _newResource.dispose();
    super.dispose();
  }

  /// Фото к шагу: выбор — снять камерой СЕЙЧАС или взять из галереи.
  /// Снятое фото сохраняется в системную галерею, копия привязывается
  /// к шагу и попадает в экспорт данных (выживает при переустановке).
  Future<void> _attachPhoto(AppStore store, TaskStep s) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Фото к шагу'),
        content: const Text('Снять новое фото камерой или выбрать снимок '
            'из галереи?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            icon: const Icon(Icons.photo_library_outlined, size: 19),
            label: const Text('Галерея'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'camera'),
            icon: const Icon(Icons.photo_camera_outlined, size: 19),
            label: const Text('Снять фото'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'camera') {
        final shot = await ImagePicker()
            .pickImage(source: ImageSource.camera, imageQuality: 80);
        if (shot == null) return; // пользователь закрыл камеру
        // Копия в системную галерею — снимок остаётся у пользователя,
        // даже если приложение будет удалено.
        try {
          final bytes = await File(shot.path).readAsBytes();
          await Gal.putImageBytes(bytes,
              name: 'planner_${DateTime.now().millisecondsSinceEpoch}');
        } catch (_) {
          // нет доступа к галерее — фото всё равно привяжется к шагу
        }
        await store.setStepPhoto(s.id, shot.path);
      } else {
        final res = await FilePicker.platform.pickFiles(type: FileType.image);
        final path = res?.files.single.path;
        if (path != null) await store.setStepPhoto(s.id, path);
      }
    } catch (_) {
      // отмена выбора / нет камеры — ничего не делаем
    }
  }

  /// Карандаш между фото и крестиком: редактирование названия шага.
  Future<void> _editStep(AppStore store, TaskStep s) async {
    final c = TextEditingController(text: s.title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать шаг'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название шага'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    final title = c.text.trim();
    if (saved == true && title.isNotEmpty) {
      store.updateStepTitle(s.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final matches = store.tasks.where((t) => t.id == widget.taskId).toList();
    if (matches.isEmpty) {
      // задача ушла в архив/удалена — закрываем шторку
      return const SizedBox(
          height: 120, child: Center(child: Text('Задача завершена')));
    }
    final t = matches.first;
    final steps = store.stepsForTask(t.id);
    final doneCount = steps.where((s) => s.isDone).length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.textDim,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 10),
          Text(t.title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          // Секундомер задачи — НАД значками «закрепить / редактировать /
          // в архив». Тап по «Старт» запускает отсчёт времени выполнения;
          // «Стоп» суммирует минуты в «факт». План — estimateMin задачи.
          _buildTimerRow(store, t),
          // Поверх знаков «закрепить / редактировать / в архив» — иконки
          // приоритета: волны (низкий), ! (средний), костюм (высокий).
          Row(
            children: [
              PriorityIcons(
                priority: t.priority,
                isKey: t.isKeyAction,
                onPriority: (p) => store.setTaskPriority(t.id, p),
                onKey: () => store.toggleTaskKey(t.id),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                    t.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 20,
                    color: t.isPinned ? AppTheme.daily : AppTheme.textDim),
                tooltip: 'Закрепить',
                onPressed: () => store.togglePinTask(t.id),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Редактировать',
                onPressed: () => showTaskEditor(context, store, task: t),
              ),
              IconButton(
                icon: const Icon(Icons.archive_outlined, size: 20),
                tooltip: 'В архив',
                onPressed: () {
                  store.archiveTask(t.id);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          if (t.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t.comment,
                  style:
                      const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          // Блок «Ресурсы» — по аналогии с блоком шагов: список того,
          // что нужно для выполнения задачи (ссылки, люди, инструменты,
          // документы). Каждая строка — один ресурс; блок виден на всех
          // экранах, где открывается карточка задачи.
          _buildResources(store, t),
          const SizedBox(height: 8),
          // Однородные задачи, слитые внутрь этой (перетаскиванием на
          // экране «Сегодня»): «путь» с баром прогресса — как в блоках
          // на экране «Цели». Дочерние задачи исчезают из общих списков,
          // но здесь сохраняют все свои функции: шаги, секундомер,
          // будильник, меню «три точки».
          _buildChildren(store, t),
          Text('Шаги: $doneCount/${steps.length}',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          // Шкала пути: линия + точки-шаги (цвет по приоритету шага).
          _StepScale(steps: steps),
          // Шаги можно менять местами ДОЛГИМ НАЖАТИЕМ: зажали карточку
          // шага и тянем вверх/вниз — шаги меняются местами, новый
          // порядок сохраняется в БД. Точки на шкале пути следуют тому
          // же порядку (сверху вниз = слева направо). Работает и для
          // шагов, добавленных позже.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              final ids = steps.map((s) => s.id).toList();
              if (newIndex > oldIndex) newIndex--;
              final id = ids.removeAt(oldIndex);
              ids.insert(newIndex, id);
              store.reorderSteps(t.id, ids);
            },
            children: [
              for (final s in steps) _stepCard(store, t, s),
            ],
          ),
          // Ежедневная задача: выполнения суммируются. Отмеченная
          // своевременно — с зелёной галочкой и датой/временем; сегодняшняя
          // выше, завтрашняя встанет ниже точно так же.
          if (t.recurDaily || t.horizon == 'daily')
            _DailyCompletions(task: t),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newStep,
                  decoration: const InputDecoration(
                      hintText: 'Новый шаг (или через «:» в названии)'),
                  onSubmitted: (_) => _add(store, t),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: AppTheme.accent),
                onPressed: () => _add(store, t),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Блок «Ресурсы»: список ресурсов задачи с удалением (крестик)
  /// и строкой добавления — в точности как блок шагов. Данные живут
  /// в таблице task_resources и сохраняются в БД.
  Widget _buildResources(AppStore store, Task t) {
    final res = store.resourcesForTask(t.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ресурсы (${res.length}):',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
        if (res.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
                'Ресурсов пока нет. Добавьте ссылки, людей, инструменты — '
                'всё, что нужно для выполнения.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
          ),
        for (final r in res)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 15, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.title,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.text)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => store.deleteResource(r.id),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 15, color: AppTheme.textDim),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newResource,
                decoration:
                    const InputDecoration(hintText: 'Новый ресурс'),
                onSubmitted: (_) => _addResource(store, t),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.accent),
              tooltip: 'Добавить ресурс',
              onPressed: () => _addResource(store, t),
            ),
          ],
        ),
      ],
    );
  }

  /// Блок «Однородные задачи»: путь с баром прогресса (как в блоках
  /// на экране «Цели») и карточки слитых задач со всеми их функциями.
  Widget _buildChildren(AppStore store, Task t) {
    final kids = store.childrenOfTask(t.id);
    if (kids.isEmpty) return const SizedBox();
    final done = kids.where((k) => k.isDone).length;
    final total = kids.length;
    final frac = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Однородные задачи: $done/$total',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: AppTheme.textDim.withOpacity(0.25),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 6),
          for (final k in kids) TaskTile(task: k),
        ],
      ),
    );
  }

  Future<void> _addResource(AppStore store, Task t) async {
    final title = _newResource.text.trim();
    if (title.isEmpty) return;
    _newResource.clear();
    await store.addResource(t.id, title);
  }

  /// Секундомер выполнения задачи: старт/стоп, прошедшее время против
  /// планового («планируемое время на выполнение»). Минуты копятся
  /// в поле «факт» (actualMin) и идут в статистику.
  Widget _buildTimerRow(AppStore store, Task t) {
    final running = store.taskTimerRunning(t.id);
    final startedAt = store.taskTimerStart(t.id);
    final elapsed = running && startedAt != null
        ? DateTime.now().difference(startedAt)
        : Duration.zero;
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              size: 26,
              color: running ? AppTheme.danger : AppTheme.accent,
            ),
            tooltip: running ? 'Стоп (время запишется в «факт»)' : 'Старт секундомера',
            onPressed: () async {
              if (running) {
                final mins = await store.stopTaskTimer(t.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Засечено $mins мин — добавлено в «факт» задачи')));
                }
              } else {
                store.startTaskTimer(t.id);
              }
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: 2),
          Text(
            running ? '$mm:$ss' : 'время',
            style: TextStyle(
              fontSize: running ? 16 : 13,
              fontWeight: running ? FontWeight.w600 : FontWeight.normal,
              color: running ? AppTheme.text : AppTheme.textDim,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'план ${t.estimateMin} мин · факт ${t.actualMin} мин',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Поля «количество итераций» и «количество раз» шага: компактная
  /// строка под названием шага, над рядом значков. Значения хранятся
  /// в БД (iterations, times), участвуют в статистике и уходят
  /// в экспорт вместе с остальными данными.
  Widget _countsEditor(AppStore store, TaskStep s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Row(
        children: [
          _countChip(store, s,
              icon: Icons.repeat,
              label: 'итераций: ${s.iterations}',
              isTimes: false),
          const SizedBox(width: 14),
          _countChip(store, s,
              icon: Icons.repeat_one,
              label: 'раз: ${s.times}',
              isTimes: true),
        ],
      ),
    );
  }

  Widget _countChip(AppStore store, TaskStep s,
      {required IconData icon, required String label, required bool isTimes}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _editStepCount(store, s, isTimes: isTimes),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.textDim),
            const SizedBox(width: 6),
            Text(label,
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined,
                size: 13, color: AppTheme.textDim),
          ],
        ),
      ),
    );
  }

  Future<void> _editStepCount(AppStore store, TaskStep s,
      {required bool isTimes}) async {
    final c =
        TextEditingController(text: '${isTimes ? s.times : s.iterations}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTimes ? 'Количество раз' : 'Количество итераций'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              hintText: isTimes
                  ? 'Сколько раз выполнить шаг (1–999)'
                  : 'Сколько итераций у шага (1–999)'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    final n = int.tryParse(c.text.trim());
    if (saved == true && n != null) {
      if (isTimes) {
        await store.setStepTimes(s.id, n);
      } else {
        await store.setStepIterations(s.id, n);
      }
    }
  }

  /// Карточка одного шага. Перетаскивание — долгим нажатием на любую
  /// точку карточки (обрабатывает ReorderableListView выше).
  Widget _stepCard(AppStore store, Task t, TaskStep s) {
    return Card(
      key: ValueKey(s.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: s.isKeyAction
            ? const BorderSide(color: AppTheme.warn, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            ListTile(
              dense: true,
              leading: IconButton(
                icon: Icon(
                  s.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: s.isDone ? AppTheme.done : AppTheme.textDim,
                ),
                onPressed: () => store.toggleStepDone(s.id),
              ),
              title: Text(
                s.title,
                style: TextStyle(
                  fontSize: 13,
                  color: s.isDone ? AppTheme.textDim : AppTheme.text,
                  decoration: s.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Фото-подтверждение — только если у задачи задана метрика.
                  if (t.metric.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        s.photoPath.isNotEmpty
                            ? Icons.photo
                            : Icons.photo_camera_outlined,
                        size: 19,
                        color: s.photoPath.isNotEmpty
                            ? AppTheme.done
                            : AppTheme.textDim,
                      ),
                      tooltip: 'Фото к метрике',
                      onPressed: () => _attachPhoto(store, s),
                    ),
                  // Карандаш редактирования шага — между фото и крестиком.
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 17, color: AppTheme.textDim),
                    tooltip: 'Редактировать шаг',
                    onPressed: () => _editStep(store, s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 17, color: AppTheme.textDim),
                    tooltip: 'Убрать шаг',
                    onPressed: () => store.deleteStep(s.id),
                  ),
                ],
              ),
            ),
            // Чуть ниже названия шага — количество итераций и
            // количество раз (тап по полю — ввод числа).
            _countsEditor(store, s),
            if (s.photoPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(s.photoPath),
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),
            // Дата и время выполнения шага — прямо под значками
            // фотоаппарата и крестика.
            if (s.isDone && s.doneAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'выполнено ${fmtDateTime(s.doneAt!)}',
                    style: const TextStyle(color: AppTheme.done, fontSize: 11),
                  ),
                ),
              ),
            // У каждого шага — свои иконки приоритета + молния.
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PriorityIcons(
                  priority: s.priority,
                  isKey: s.isKeyAction,
                  size: 17,
                  onPriority: (p) => store.setStepPriority(s.id, p),
                  onKey: () => store.toggleStepKey(s.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(AppStore store, Task t) async {
    final title = _newStep.text.trim();
    if (title.isEmpty) return;
    _newStep.clear();
    await store.addStep(t.id, title);
  }
}

/// Список выполнений ежедневной задачи: каждая отметка — зелёная галочка
/// с датой и временем. Суммируется: сегодняшняя выше, завтрашняя ниже.
class _DailyCompletions extends StatelessWidget {
  final Task task;
  const _DailyCompletions({required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final done = store.dailyCompletions(task);
    if (done.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Выполнения (${done.length}):',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          for (final d in done)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: AppTheme.done),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textDim),
                    ),
                  ),
                  Text(
                    fmtDateTime(d.doneAt ?? d.createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.done),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Шкала пути задачи: тонкая линия с точками-шагами.
class _StepScale extends StatelessWidget {
  final List<TaskStep> steps;
  const _StepScale({required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
            'Шагов пока нет. Разбейте задачу на шаги — они появятся здесь точками.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 24,
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 11,
                child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                        color: AppTheme.textDim.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(1))),
              ),
              for (var i = 0; i < steps.length; i++)
                Positioned(
                  left: steps.length == 1
                      ? w / 2 - 7
                      : (i / (steps.length - 1)) * (w - 14),
                  top: 5,
                  child: Tooltip(
                    message: steps[i].title,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: priorityDotColor(
                          isDone: steps[i].isDone,
                          overdue: false,
                          priority: steps[i].priority,
                        ),
                        border: steps[i].isKeyAction
                            ? Border.all(color: AppTheme.warn, width: 2)
                            : null,
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
