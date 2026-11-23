/// Экран «Сегодня»: план на день + быстрое добавление задачи.
/// Карточки задач — те же, что на экране «Задачи» (TaskTile):
/// весь функционал редактирования (шаги, связь с блоком, будильник,
/// архив, закрепление) доступен и здесь. После отметки выполнения
/// проверяется награда за продуктивный день (60%/85%/100%).
/// Карточки можно менять местами долгим нажатием (как шаги на шкале
/// пути) — порядок сохраняется в БД. Свайп влево — перенос задачи
/// на следующий календарный день (можно указать причину переноса,
/// она пишется в журнал и попадает в отчёты).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'common.dart';
import 'day_reward.dart';
import 'edit_dialogs.dart';
import 'tasks_screen.dart';
import 'tomorrow_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _quickAdd = TextEditingController();

  /// Автопрокрутка списка при перетаскивании карточки к краю экрана:
  /// палец у верхнего/нижнего края — список плавно едет, пока не
  /// найдётся нужное место вставки.
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollSpeed = 0;
  DateTime _lastDragMove = DateTime.now();

  /// Идёт ли сейчас перетаскивание карточки (ставят сами карточки).
  /// Пока true — таймер автопрокрутки живёт, даже если палец
  /// неподвижен у края (onMove тогда не приходит).
  bool _dragActive = false;

  void _onCardDragStart() => _dragActive = true;

  void _onCardDragEnd() {
    _dragActive = false;
    _stopAutoScroll();
  }

  Future<void> _addQuick(AppStore store) async {
    final title = _quickAdd.text.trim();
    if (title.isEmpty) return;
    _quickAdd.clear();
    final now = DateTime.now();
    await store.addTask(Task(
      title: title,
      deadline: DateTime(now.year, now.month, now.day, 18),
    ));
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scroll.dispose();
    _quickAdd.dispose();
    super.dispose();
  }

  /// Перетаскиваемая карточка движется над экраном: если палец у края
  /// списка — включаем автопрокрутку (скорость тем выше, чем ближе к
  /// краю), в середине — останавливаем. DragTarget накрывает ВЕСЬ экран
  /// (включая AppBar), поэтому прокрутка работает и вверх, и вниз:
  /// палец выше списка (dy < 0) — скорость вверх максимальна.
  void _onDragMoveOverBody(DragTargetDetails<String> d) {
    _lastDragMove = DateTime.now();
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !_scroll.hasClients) return;
    final local = box.globalToLocal(d.offset);
    final h = box.size.height;
    const edge = 88.0;
    var speed = 0.0;
    if (local.dy < edge) {
      speed = -4 - ((edge - local.dy).clamp(0, edge * 3) / edge) * 18;
    } else if (local.dy > h - edge) {
      speed = 4 + ((local.dy - (h - edge)).clamp(0, edge * 3) / edge) * 18;
    }
    _autoScrollSpeed = speed;
    if (speed != 0) {
      _autoScrollTimer ??=
          Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scroll.hasClients) {
          _stopAutoScroll();
          return;
        }
        // Перетаскивание завершено (флаг снят обработчиком карточки),
        // а таймер остался — гасим его. Пока палец держат у края
        // неподвижно, флаг жив и прокрутка продолжается.
        if (!_dragActive) {
          _stopAutoScroll();
          return;
        }
        final pos = _scroll.position;
        final target = (pos.pixels + _autoScrollSpeed)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if (target != pos.pixels) pos.jumpTo(target);
      });
    } else {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollSpeed = 0;
  }

  /// Свайп влево по карточке: перенос задачи на следующий календарный
  /// день. Диалог предлагает указать причину переноса — можно
  /// «Пропустить» (перенос без причины). Всегда возвращает false:
  /// карточку из списка убирает сам стор — дедлайн уезжает на завтра,
  /// и задача исчезает из списка дня после перестроения.
  Future<bool> _confirmPostpone(
      BuildContext context, AppStore store, Task t) async {
    final reasonC = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перенести на завтра?'),
        content: TextField(
          controller: reasonC,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
              hintText: 'Причина переноса (необязательно)'),
          onSubmitted: (_) => Navigator.pop(ctx, 'move'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: const Text('Пропустить')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'move'),
              child: const Text('Перенести')),
        ],
      ),
    );
    if (res == 'move' || res == 'skip') {
      final msg = await store.postponeTaskToTomorrow(t.id,
          reason: res == 'move' ? reasonC.text : '');
      reasonC.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return false;
    }
    reasonC.dispose();
    return false;
  }

  /// Режим «выходной»: пляж на весь экран, управление — три точки
  /// в правом нижнем углу (выйти отдохнувшим или кайфовать ещё день).
  Widget _buildDayOff(BuildContext context, AppStore store) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/beach_dayoff.png', fit: BoxFit.cover),
          // Мягкое затемнение снизу — чтобы кнопка читалась на любом фоне.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: PopupMenuButton<String>(
              tooltip: 'Выход из режима «выходной»',
              icon: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.card.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.more_vert, color: AppTheme.text),
              ),
              onSelected: (v) async {
                if (v == 'rested') {
                  await store.exitDayOff();
                } else if (v == 'chill') {
                  // Кайфуем ещё день: все задачи и события снова
                  // сдвигаются на +1 календарный день.
                  final msg = await store.shiftPlansForward();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'rested',
                  child: Text('Всё я отдохнул и полон сил, вперёд к совершениям!!!'),
                ),
                PopupMenuItem(
                  value: 'chill',
                  child: Text('сегодня снова не день Бэкхема, я буду кайфовать'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final dayEvents = store.eventsForDay(now);
    final dayTasks = store.tasksForDay(now);

    // Режим «выходной»: полноэкранный пляж, выход — через три точки
    // в правом нижнем углу.
    if (store.dayOffMode) return _buildDayOff(context, store);

    // Внешний DragTarget накрывает ВЕСЬ экран (со AppBar): раньше
    // он был только на теле, и при входе пальца в зону AppBar
    // срабатывал onLeave — прокрутка вверх гасла. Теперь край экрана
    // вверху крутит список вверх так же, как низ — вниз. Сам таргет
    // ничего не принимает — вставку/слияние обрабатывают карточки.
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onMove: _onDragMoveOverBody,
      onLeave: (_) => _stopAutoScroll(),
      onAcceptWithDetails: (_) => _stopAutoScroll(),
      builder: (context, candidates, rejected) => Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Сегодня'),
            Text(fmtDate(now),
                style: const TextStyle(fontSize: 12, color: AppTheme.textDim, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.beach_access_outlined,
                size: 20, color: AppTheme.textDim),
            tooltip: 'Выходной',
            onPressed: () async {
              final msg = await store.enterDayOff();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              }
            },
          ),
          // «Запланировать на завтра» — между зонтиком (выходной)
          // и колокольчиком (оповещения): отдельный экран со списком
          // завтрашних задач, добавленные там попадают в календарь
          // на следующий день.
          IconButton(
            icon: const Icon(Icons.event_available_outlined,
                size: 20, color: AppTheme.textDim),
            tooltip: 'Запланировать на завтра',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TomorrowScreen()),
            ),
          ),
          const FontScaleButton(),
          const AlertBell(),
        ],
      ),
      body: Column(
        children: [
          if (dayEvents.isEmpty && dayTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyHint('На сегодня планов нет'),
            )
          else
            Expanded(
              child: ListView(
                key: _listKey,
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  if (dayEvents.isNotEmpty) const SectionHeader('События'),
                  for (final e in dayEvents)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: eventPrioritySide(e)),
                      child: ListTile(
                        leading: const Icon(Icons.event, color: AppTheme.accent),
                        title: Text(e.title),
                        subtitle: Text(
                            '${fmtTime(e.start)} · ${e.durationMin} мин'
                            '${e.priority == 2 ? ' · важное' : (e.priority == 0 ? ' · неспешное' : '')}',
                            style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => showEventEditor(context, store, event: e),
                        ),
                      ),
                    ),
                  if (dayTasks.isNotEmpty) const SectionHeader('Задачи'),
                  // Полноценные карточки задач экрана «Задачи»: шаги,
                  // редактирование, связь с блоком, будильник, архив.
                  // Долгое нажатие — перетаскивание карточки:
                  //  · отпустить у КРАЯ другой карточки — встать между
                  //    задачами (порядок сохраняется в БД);
                  //  · отпустить ПОВЕРХ другой карточки (центр) —
                  //    задачи соединяются: перетаскиваемая становится
                  //    однородной внутри той, на которую её отпустили,
                  //    и исчезает из списка дня.
                  // Свайп влево — перенос задачи на следующий
                  // календарный день.
                  for (final t in dayTasks)
                    _TodayDragCard(
                      key: ValueKey('drag_${t.id}'),
                      task: t,
                      dayTasks: dayTasks,
                      onDone: () => checkDayReward(context, store),
                      onSwipeLeft: () => _confirmPostpone(context, store, t),
                      onDragStart: _onCardDragStart,
                      onDragEnd: _onCardDragEnd,
                    ),
                ],
              ),
            ),
          if (dayEvents.isEmpty && dayTasks.isEmpty) const Spacer(),
          // Быстрое добавление
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAdd,
                    decoration: const InputDecoration(hintText: 'Новая задача...'),
                    onSubmitted: (_) => _addQuick(store),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _addQuick(store),
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: AppTheme.bg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Анимированный зазор в месте вставки: соседние карточки плавно
/// разъезжаются, и перетаскиваемая карточка визуально «встраивается»
/// между ними (как в старой версии), а не показывается тонкой линией.
class _InsertGap extends StatelessWidget {
  const _InsertGap();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v,
          child: child,
        ),
      ),
      child: SizedBox(
        height: 74,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.accent.withOpacity(0.55), width: 1.4),
          ),
          child: Center(
            child: Icon(Icons.add_rounded,
                color: AppTheme.accent.withOpacity(0.9), size: 22),
          ),
        ),
      ),
    );
  }
}

/// Карточка задачи дня с перетаскиванием и свайпом.
/// Долгое нажатие — тянем карточку:
///  · отпустили у ВЕРХНЕГО/НИЖНЕГО края другой карточки — задача
///    встаёт на это место (между задачами), порядок пишется в БД;
///  · отпустили ПОВЕРХ ЦЕНТРА другой карточки — задачи соединяются:
///    перетаскиваемая становится однородной внутри целевой (бар
///    как в блоках на экране «Цели») и исчезает из списка дня.
/// Свайп влево — перенос на следующий календарный день (с диалогом
/// причины). Свайп и перетаскивание не конфликтуют: быстрый свайп
/// уходит в Dismissible, долгое нажатие — в перетаскивание.
class _TodayDragCard extends StatefulWidget {
  final Task task;
  final List<Task> dayTasks;
  final VoidCallback onDone;
  final Future<bool> Function() onSwipeLeft;

  /// Сигналы начала/конца перетаскивания — экран держит по ним
  /// автопрокрутку живой, даже когда палец неподвижен у края.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _TodayDragCard({
    super.key,
    required this.task,
    required this.dayTasks,
    required this.onDone,
    required this.onSwipeLeft,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<_TodayDragCard> createState() => _TodayDragCardState();
}

class _TodayDragCardState extends State<_TodayDragCard> {
  /// Зона сброса: 'above' / 'below' — вставка между задачами,
  /// 'merge' — слияние с задачей, поверх которой отпустили.
  String? _zone;

  void _updateZone(DragTargetDetails<String> d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(d.offset);
    final h = box.size.height;
    final z = local.dy < h * 0.32
        ? 'above'
        : (local.dy > h * 0.68 ? 'below' : 'merge');
    if (z != _zone) setState(() => _zone = z);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final t = widget.task;
    final card = TaskTile(task: t, onDone: widget.onDone, diaryEntryPoint: true);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != t.id,
      onMove: _updateZone,
      onLeave: (_) {
        if (_zone != null) setState(() => _zone = null);
      },
      onAcceptWithDetails: (d) async {
        final zone = _zone ?? 'merge';
        if (_zone != null) setState(() => _zone = null);
        if (zone == 'merge') {
          // Слияние: перетаскиваемая задача становится однородной
          // внутри целевой и исчезает с экрана «Сегодня».
          final msg = await store.mergeTaskInto(d.data, t.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
          }
        } else {
          // Вставка между задачами: порядок сохраняется в БД.
          final ids = widget.dayTasks.map((x) => x.id).toList();
          ids.remove(d.data);
          var at = ids.indexOf(t.id);
          if (at < 0) at = zone == 'above' ? 0 : ids.length;
          if (zone == 'below') at += 1;
          if (at > ids.length) at = ids.length;
          ids.insert(at, d.data);
          store.reorderTodayTasks(ids);
        }
      },
      builder: (ctx, candidates, rejected) {
        final hover = candidates.isNotEmpty;
        return Column(
          children: [
            // Зазор вставки: карточки плавно разъезжаются, освобождая
            // место перетаскиваемой (вместо тонкой линии-индикатора).
            if (hover && _zone == 'above') const _InsertGap(),
            LongPressDraggable<String>(
              data: t.id,
              delay: const Duration(milliseconds: 280),
              onDragStarted: widget.onDragStart,
              onDragCompleted: widget.onDragEnd,
              onDragEnd: (_) => widget.onDragEnd?.call(),
              feedback: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(ctx).size.width - 24),
                  child: Card(
                    color: AppTheme.card,
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_indicator,
                              size: 18, color: AppTheme.textDim),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: card),
              child: Dismissible(
                key: ValueKey('postpone_${t.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.warn.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('на завтра',
                          style:
                              TextStyle(color: AppTheme.warn, fontSize: 12)),
                      SizedBox(width: 6),
                      Icon(Icons.redo, color: AppTheme.warn, size: 20),
                    ],
                  ),
                ),
                confirmDismiss: (_) => widget.onSwipeLeft(),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    // Подсветка слияния: отпускание в центре карточки
                    // соединит задачи в иерархию.
                    border: hover && _zone == 'merge'
                        ? Border.all(color: AppTheme.accent, width: 2)
                        : null,
                  ),
                  child: card,
                ),
              ),
            ),
            if (hover && _zone == 'below') const _InsertGap(),
          ],
        );
      },
    );
  }
}
