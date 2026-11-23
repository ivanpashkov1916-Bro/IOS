/// Экран «Путь»: блоки целей в виде цепочки, соединённой нитью.
///
/// Порядок блоков — ранговый: от блока с наибольшей суммой приоритетов
/// (его задачи и цели важнее всего) к блоку с наибольшим числом
/// долгосрочных целей. Значки блоков — те, что пользователь выбрал
/// на экране «Цели» («Сменить значок»): смена значка мгновенно
/// отражается и здесь, и на картинке блока.
///
/// Кнопки:
///  * «Показать путь» — весь путь списком: выполненные задачи/цели
///    с галочками и полученными наградами, невыполненные — пустыми
///    кружками;
///  * «Древо пути» — путь как растущее дерево: блоки — завязи ветвей
///    ствола, задачи — ветви, шаги — веточки. Любые изменения на
///    экранах задач/целей/событий сразу отражаются и здесь.
///
/// Тап по блоку — красочная картинка сути блока. Пока не выполнено
/// всё — картинка чёрно-белая; когда всё закрыто — цветная.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'block_icons.dart';
import 'common.dart';

/// Картинка блока по значку. Значки, близкие по смыслу, делят сцену
/// (дом и семья — уютный домик, звезда и флаг — достижение и т.д.).
String pathImageFor(String iconKey) => switch (iconKey) {
      'home' || 'family' => 'assets/path/home.jpg',
      'finance' || 'cart' => 'assets/path/finance.jpg',
      'health' || 'leaf' => 'assets/path/health.jpg',
      'work' => 'assets/path/work.jpg',
      'study' || 'book' => 'assets/path/study.jpg',
      'sport' => 'assets/path/sport.jpg',
      'travel' || 'car' => 'assets/path/travel.jpg',
      'hobby' || 'music' => 'assets/path/hobby.jpg',
      'star' || 'flag' => 'assets/path/star.jpg',
      'fire' || 'bolt' => 'assets/path/fire.jpg',
      'food' => 'assets/path/food.jpg',
      _ => 'assets/path/folder.jpg',
    };

/// Цели, относящиеся к блоку (не цели-блоки).
List<Goal> goalsForBlock(AppStore store, Goal blockGoal) {
  if (!blockGoal.externalId.startsWith('block:')) return [];
  final id = blockGoal.externalId.substring(6);
  return store.goals
      .where((g) => !g.externalId.startsWith('block:') && g.block == id)
      .toList();
}

/// Всё содержимое блока выполнено (и содержимое есть).
bool blockComplete(AppStore store, Goal blockGoal) {
  final ts = store.tasksForGoal(blockGoal);
  final gs = goalsForBlock(store, blockGoal);
  if (ts.isEmpty && gs.isEmpty) return false;
  return ts.every((t) => t.isDone) && gs.every((g) => g.isDone);
}

/// Ранг блока: сумма приоритетов задач и целей блока (главный ключ),
/// число долгосрочных целей (от года) — вторичный ключ.
int blockPriorityScore(AppStore store, Goal g) {
  var s = 0;
  for (final t in store.tasksForGoal(g)) {
    s += t.priority;
  }
  for (final x in goalsForBlock(store, g)) {
    s += x.priority;
  }
  return s;
}

int blockLongGoals(AppStore store, Goal g) =>
    goalsForBlock(store, g).where((x) => x.horizonDays >= 300).length;

/// Блоки в порядке на дереве/цепочке. Главный ключ — ручной порядок
/// (перетаскивание блоков на «Древе пути»): блоки с заданным порядком
/// идут по возрастанию manualOrder; новые блоки (manualOrder == 0)
/// растут выше них — в ранговом порядке: от максимума приоритетов
/// к максимуму долгосрочных целей.
List<Goal> rankedBlocks(AppStore store) {
  final blocks = store.blockGoals();
  int byRank(Goal a, Goal b) {
    final p = blockPriorityScore(store, b) - blockPriorityScore(store, a);
    if (p != 0) return p;
    return blockLongGoals(store, b) - blockLongGoals(store, a);
  }

  blocks.sort((a, b) {
    final ma = a.manualOrder;
    final mb = b.manualOrder;
    if (ma > 0 && mb > 0) return ma.compareTo(mb);
    if (ma > 0) return -1;
    if (mb > 0) return 1;
    return byRank(a, b);
  });
  return blocks;
}

class PathScreen extends StatelessWidget {
  const PathScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final blocks = rankedBlocks(store);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Путь'),
        actions: [
          IconButton(
            icon: const Icon(Icons.alt_route, size: 20),
            tooltip: 'Показать путь',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FullPathView()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.park_outlined, size: 20),
            tooltip: 'Древо пути',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PathTreeView()),
            ),
          ),
          const FontScaleButton(),
          const AlertBell(),
        ],
      ),
      body: blocks.isEmpty
          ? const EmptyHint(
              'Блоков пока нет. Создайте их на экране «Цели» —\n'
              'и здесь вырастет ваш путь.')
          : ListView.builder(
              // reverse: первый (самый приоритетный) блок — ВНИЗУ,
              // путь идёт снизу вверх, узлы зигзагом слева направо.
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: blocks.length,
              itemBuilder: (ctx, i) {
                final g = blocks[i];
                return _ChainRow(
                  block: g,
                  left: i.isEven,
                  prevLeft: i > 0 ? (i - 1).isEven : i.isEven,
                  isFirst: i == 0,
                  isLast: i == blocks.length - 1,
                  complete: blockComplete(store, g),
                );
              },
            ),
    );
  }
}

/// Один узел цепочки + нить к предыдущему узлу.
class _ChainRow extends StatelessWidget {
  final Goal block;
  final bool left;
  final bool prevLeft;
  final bool isFirst;
  final bool isLast;
  final bool complete;

  const _ChainRow({
    required this.block,
    required this.left,
    required this.prevLeft,
    required this.isFirst,
    required this.isLast,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final ts = store.tasksForGoal(block);
    final gs = goalsForBlock(store, block);
    // carryDone/carryTotal — вклад задач, удалённых из архива:
    // удаление задачи не откатывает прогресс блока на дереве пути.
    final total = ts.length + gs.length + block.carryTotal;
    final done = ts.where((t) => t.isDone).length +
        gs.where((g) => g.isDone).length +
        block.carryDone;
    final color = complete ? AppTheme.done : AppTheme.accent;

    return SizedBox(
      height: 132,
      child: Stack(
        children: [
          // Нить связи к предыдущему (нижнему) узлу.
          if (!isFirst)
            Positioned.fill(
              child: CustomPaint(
                painter: _ThreadPainter(
                  thisLeft: left,
                  prevLeft: prevLeft,
                  color: AppTheme.textDim.withOpacity(0.5),
                ),
              ),
            ),
          Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showBlockPicture(context, store, block),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.25),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: blockIconWidget(
                          block.icon.isEmpty ? 'folder' : block.icon,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 110,
                      child: Text(
                        block.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Text(
                      total == 0
                          ? 'пусто'
                          : (complete
                              ? 'всё выполнено ✓'
                              : '$done/$total'),
                      style: TextStyle(
                          fontSize: 10,
                          color: complete ? AppTheme.done : AppTheme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Нить между соседними узлами цепочки — мягкая пунктирная кривая.
class _ThreadPainter extends CustomPainter {
  final bool thisLeft;
  final bool prevLeft;
  final Color color;

  _ThreadPainter(
      {required this.thisLeft, required this.prevLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // Узел этого ряда — сверху (центр круга y=32), предыдущего — снизу
    // (за нижней кромкой ряда: круг предыдущего ряда на y=h+32-132).
    final x1 = thisLeft ? size.width * 0.5 - 110 + 72 : size.width * 0.5 + 110 - 72;
    final x0 = prevLeft ? size.width * 0.5 - 110 + 72 : size.width * 0.5 + 110 - 72;
    final start = Offset(x1, 32);
    final end = Offset(x0, size.height + 8);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx,
        start.dy + 40,
        end.dx,
        end.dy - 40,
        end.dx,
        end.dy,
      );
    // Пунктир: идём по метрикам кривой короткими штрихами.
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + 6, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.thisLeft != thisLeft || old.prevLeft != prevLeft;
}

/// Ч/б фильтр для картинки невыполненного блока.
const ColorFilter kGrayscaleFilter = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Картинка блока: суть по его значку. Пока блок не закрыт целиком —
/// чёрно-белая; когда всё выполнено — цветная. При смене значка на
/// экране «Цели» картинка меняется и здесь.
void showBlockPicture(BuildContext context, AppStore store, Goal g) {
  final complete = blockComplete(store, g);
  final key = blockIconKey(g.icon.isEmpty ? 'folder' : g.icon);
  final asset = pathImageFor(key);
  final ts = store.tasksForGoal(g);
  final gs = goalsForBlock(store, g);
  final total = ts.length + gs.length + g.carryTotal;
  final done = ts.where((t) => t.isDone).length +
      gs.where((x) => x.isDone).length +
      g.carryDone;

  Widget picture = ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Image.asset(
      asset,
      height: 220,
      width: double.maxFinite,
      fit: BoxFit.cover,
      // Ассет ещё не добавлен — показываем живую сцену нативными
      // виджетами, диалог не ломается.
      errorBuilder: (_, __, ___) => Container(
        height: 220,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withOpacity(0.55),
              AppTheme.card,
            ],
          ),
        ),
        child: Center(
          child: Icon(blockIconOf(g.icon), size: 96, color: Colors.white70),
        ),
      ),
    ),
  );
  if (!complete) {
    picture = ColorFiltered(colorFilter: kGrayscaleFilter, child: picture);
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      title: Row(
        children: [
          blockIconWidget(g.icon, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Text(g.title, style: const TextStyle(fontSize: 16))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          picture,
          const SizedBox(height: 10),
          Text(
            total == 0
                ? 'В блоке пока нет задач и целей.'
                : 'Выполнено $done из $total'
                    '${complete ? ' — блок закрыт, картинка цветная!' : ''}',
            style: TextStyle(
                fontSize: 12,
                color: complete ? AppTheme.done : AppTheme.textDim),
          ),
          if (!complete && total > 0)
            const Text(
              'Картинка станет цветной, когда будут выполнены все '
              'задачи и цели блока.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          if (g.reward.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Награда блока: ${g.reward}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.warn)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// «Показать путь»: весь путь списком — выполненные задачи и цели
/// с галочками (и наградами, если пользователь их выбирал),
/// оставшиеся — пустыми кружками. Сверху — награды за дни.
class FullPathView extends StatelessWidget {
  const FullPathView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final blocks = rankedBlocks(store);
    final rewards = store.dayRewards;

    return Scaffold(
      appBar: AppBar(title: const Text('Показать путь')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (rewards.isNotEmpty) ...[
            const SectionHeader('Полученные награды'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rewards.take(10))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              r.skipped
                                  ? Icons.remove_circle_outline
                                  : Icons.card_giftcard,
                              size: 16,
                              color: r.skipped
                                  ? AppTheme.textDim
                                  : AppTheme.warn,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${fmtDate(r.day)} — ${r.skipped ? 'награду пропустил(а)' : r.reward} '
                                '(${(r.pct * 100).round()}%)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          for (final g in blocks) _FullPathBlock(block: g),
          if (blocks.isEmpty)
            const EmptyHint('Блоков нет — создайте их на экране «Цели»'),
        ],
      ),
    );
  }
}

class _FullPathBlock extends StatelessWidget {
  final Goal block;
  const _FullPathBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final ts = store.tasksForGoal(block);
    final gs = goalsForBlock(store, block);
    final done = blockComplete(store, block);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: done ? AppTheme.done : AppTheme.accent.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                blockIconWidget(block.icon,
                    color: done ? AppTheme.done : AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(block.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                if (done)
                  const Icon(Icons.verified, color: AppTheme.done, size: 18),
              ],
            ),
            if (block.reward.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Награда блока: ${block.reward}',
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.warn)),
              ),
            const SizedBox(height: 6),
            if (ts.isEmpty && gs.isEmpty)
              const Text('Пока пусто',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            for (final t in ts)
              _PathItemRow(
                done: t.isDone,
                title: t.title,
                kind: 'задача',
              ),
            for (final x in gs)
              _PathItemRow(
                done: x.isDone,
                title: x.title,
                kind: 'цель',
                reward: x.isDone ? x.reward : '',
              ),
          ],
        ),
      ),
    );
  }
}

class _PathItemRow extends StatelessWidget {
  final bool done;
  final String title;
  final String kind;
  final String reward;

  const _PathItemRow({
    required this.done,
    required this.title,
    required this.kind,
    this.reward = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: done ? AppTheme.done : AppTheme.textDim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: done ? AppTheme.text : AppTheme.textDim,
                    decoration:
                        done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (reward.isNotEmpty)
                  Text('награда: $reward',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.warn)),
              ],
            ),
          ),
          Text(kind,
              style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}

/// «Древо пути»: весь путь как растущее дерево. Ствол — сам путь,
/// блоки — завязи ветвей на стволе (в порядке rankedBlocks
/// снизу вверх), задачи — ветви, шаги — маленькие веточки,
/// сросшиеся со своими ветвями.
/// Выполненное — зелёное, оставшееся — приглушённое. Данные берутся
/// из живого стора: любые изменения задач/целей/шагов на других
/// экранах сразу перерисовывают дерево.
///
/// Блоки перетаскиваются по стволу вверх/вниз: долгое нажатие на
/// завязь блока и перенос — порядок сохраняется в БД (manualOrder)
/// и работает для блоков, добавленных или удалённых позже.
class PathTreeView extends StatefulWidget {
  const PathTreeView({super.key});

  @override
  State<PathTreeView> createState() => _PathTreeViewState();
}

class _PathTreeViewState extends State<PathTreeView> {
  /// Матрица панорамы/масштаба дерева: дерево тянется пальцем во все
  /// стороны (вниз, влево, вправо) и зумится щипком или кнопками.
  final TransformationController _tc = TransformationController();
  bool _initialSet = false;
  Size _viewport = Size.zero;
  double _lastHeight = 420;

  /// Перетаскивание блока по стволу: id перетаскиваемого блока,
  /// исходная и текущая (подсвеченная) позиции.
  String? _dragBlockId;
  int _dragFrom = -1;
  int _dragHover = -1;

  /// Расстояние между завязями блоков на стволе (px) — как у рисовалки.
  static const double _spacing = 240.0;

  /// Ширина полотна дерева (px) — как у рисовалки и кнопки «целиком».
  static const double _width = 620.0;

  static const double _minScale = 0.3;
  static const double _maxScale = 3.0;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// Завязь блока i на полотне: центр ствола по x, высота по позиции i.
  Offset _budAt(int i, double height) =>
      Offset(_width / 2, height - 60 - 100 - i * _spacing);

  /// Долгое нажатие: палец попал в завязь блока — начинаем перенос.
  void _onTreeLongStart(
      LongPressStartDetails d, double height, List<_TreeBlock> data) {
    for (var i = 0; i < data.length; i++) {
      if ((d.localPosition - _budAt(i, height)).distance <= 36) {
        setState(() {
          _dragBlockId = data[i].block.id;
          _dragFrom = i;
          _dragHover = i;
        });
        return;
      }
    }
  }

  /// Перенос: ближайшая позиция на стволе подсвечивается кольцом.
  void _onTreeLongMove(
      LongPressMoveUpdateDetails d, double height, int count) {
    if (_dragBlockId == null || count == 0) return;
    final groundY = height - 60;
    final idx = ((groundY - 100 - d.localPosition.dy) / _spacing)
        .round()
        .clamp(0, count - 1);
    if (idx != _dragHover) setState(() => _dragHover = idx);
  }

  /// Отпустили: блок встаёт на подсвеченную позицию, порядок
  /// сохраняется в БД. Отпуск на месте — без изменений.
  void _onTreeLongEnd(List<_TreeBlock> data) {
    if (_dragBlockId != null &&
        _dragHover >= 0 &&
        _dragFrom >= 0 &&
        _dragHover != _dragFrom) {
      final ids = data.map((e) => e.block.id).toList();
      final id = ids.removeAt(_dragFrom);
      ids.insert(_dragHover, id);
      context.read<AppStore>().reorderBlockGoals(ids);
    }
    setState(() {
      _dragBlockId = null;
      _dragFrom = -1;
      _dragHover = -1;
    });
  }

  /// Начальный вид: низ дерева (земля, первые блоки) по центру экрана —
  /// раньше дерево обрезалось и до низа было не добраться.
  void _setInitial(double width, double height) {
    if (_viewport == Size.zero) return;
    final dx = (_viewport.width - width) / 2;
    final dy = height > _viewport.height ? _viewport.height - height : 0.0;
    _tc.value = Matrix4.translationValues(dx, dy, 0);
  }

  /// Программный зум кнопками +/- — вокруг центра видимой области.
  void _zoomBy(double factor) {
    if (_viewport == Size.zero) return;
    final current = _tc.value;
    final scale = current.getMaxScaleOnAxis();
    final target = (scale * factor).clamp(_minScale, _maxScale);
    final f = target / scale;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    final m = Matrix4.identity()
      ..translate(c.dx, c.dy)
      ..scale(f)
      ..translate(-c.dx, -c.dy);
    setState(() => _tc.value = m.multiplied(current));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final blocks = rankedBlocks(store);
    // Раскладка: блок каждые 240px ствола (ветви «дышат», не липнут
    // друг к другу), задачи — ветви влево/вправо.
    final data = <_TreeBlock>[];
    for (final b in blocks) {
      final raw = store.tasksForGoal(b);
      // Ежедневная задача — ОДНА ветвь с узлом-названием: каждый
      // выполненный день отображается маленькой веточкой у этого
      // узла, а НЕ добавляется как ещё один такой же узел-цель.
      // Представитель серии — активный экземпляр (или свежий из
      // выполненных), веточки — число выполненных экземпляров.
      String? seriesKeyOf(Task t) =>
          (t.recurDaily || t.horizon == 'daily')
              ? 'daily:${t.title.trim().toLowerCase()}'
              : null;
      final repOfSeries = <String, Task>{};
      final seriesOrder = <String>[];
      final seriesDone = <String, int>{};
      final ts = <Task>[];
      for (final t in raw) {
        final sk = seriesKeyOf(t);
        if (sk == null) {
          ts.add(t);
          continue;
        }
        if (!seriesOrder.contains(sk)) seriesOrder.add(sk);
        if (t.isDone) seriesDone[sk] = (seriesDone[sk] ?? 0) + 1;
        final cur = repOfSeries[sk];
        if (cur == null ||
            (!t.isDone && cur.isDone) ||
            (t.isDone == cur.isDone &&
                t.createdAt.isAfter(cur.createdAt))) {
          repOfSeries[sk] = t;
        }
      }
      final dailyDone = <String, int>{};
      for (final sk in seriesOrder) {
        final rep = repOfSeries[sk]!;
        ts.add(rep);
        dailyDone[rep.id] = seriesDone[sk] ?? 0;
      }
      final steps = <String, List<TaskStep>>{};
      var maxSteps = 0;
      for (final t in ts) {
        final s = store.stepsForTask(t.id);
        steps[t.id] = s;
        if (s.length > maxSteps) maxSteps = s.length;
      }
      data.add(_TreeBlock(
        block: b,
        tasks: ts,
        steps: steps,
        complete: blockComplete(store, b),
        dailyDone: dailyDone,
      ));
    }
    // Живое перетаскивание блока по стволу: пока палец движется,
    // блок рисуется на новой позиции вместе со своими ветвями —
    // связи блок → чекпоинты не рвутся.
    var display = data;
    if (_dragBlockId != null &&
        _dragFrom >= 0 &&
        _dragHover >= 0 &&
        _dragHover != _dragFrom &&
        _dragFrom < data.length &&
        _dragHover < data.length) {
      display = [...data];
      final moved = display.removeAt(_dragFrom);
      display.insert(_dragHover, moved);
    }
    final height = math.max(420.0, 160.0 + data.length * _spacing);
    const width = _width;
    _lastHeight = height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Древо пути'),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_map, size: 20),
            tooltip: 'Показать целиком',
            onPressed: () => setState(() {
              if (_viewport == Size.zero) return;
              final s = (_viewport.width / width)
                  .clamp(_minScale, _maxScale)
                  .toDouble();
              final sh = (_viewport.height / _lastHeight)
                  .clamp(_minScale, _maxScale)
                  .toDouble();
              final scale = math.min(s, sh);
              final dx = (_viewport.width - width * scale) / 2;
              final dy = (_viewport.height - _lastHeight * scale) / 2;
              _tc.value = Matrix4.identity()
                ..translate(dx, dy)
                ..scale(scale);
            }),
          ),
        ],
      ),
      body: blocks.isEmpty
          ? const EmptyHint('Блоков нет — дереву не из чего расти.\n'
              'Создайте блоки на экране «Цели».')
          : LayoutBuilder(
              builder: (ctx, cons) {
                _viewport = Size(cons.maxWidth, cons.maxHeight);
                if (!_initialSet) {
                  _initialSet = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _setInitial(width, height);
                  });
                }
                // constrained: false — ключевой момент: реальный размер
                // дерева больше экрана, InteractiveViewer даёт свободно
                // тянуть его вниз/влево/вправо и зумить щипком.
                return InteractiveViewer(
                  transformationController: _tc,
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  boundaryMargin: const EdgeInsets.all(500),
                  child: SizedBox(
                    width: width,
                    height: height,
                    // Долгое нажатие на завязь блока — перенос блока
                    // по стволу вверх/вниз (порядок хранится в БД).
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (d) =>
                          _onTreeLongStart(d, height, data),
                      onLongPressMoveUpdate: (d) =>
                          _onTreeLongMove(d, height, data.length),
                      onLongPressEnd: (_) => _onTreeLongEnd(data),
                      onLongPressCancel: () => setState(() {
                        _dragBlockId = null;
                        _dragFrom = -1;
                        _dragHover = -1;
                      }),
                      child: CustomPaint(
                        size: Size(width, height),
                        painter: _TreePainter(
                          display,
                          width,
                          height,
                          dragId: _dragBlockId,
                          hoverIndex: _dragHover,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      // Кнопки зума: приблизить / отдалить (дополняют щипок).
      floatingActionButton: blocks.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  tooltip: 'Приблизить',
                  onPressed: () => _zoomBy(1.25),
                  child: const Icon(Icons.zoom_in),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  tooltip: 'Отдалить',
                  onPressed: () => _zoomBy(0.8),
                  child: const Icon(Icons.zoom_out),
                ),
              ],
            ),
    );
  }
}

class _TreeBlock {
  final Goal block;
  final List<Task> tasks;
  final Map<String, List<TaskStep>> steps;
  final bool complete;

  /// Ежедневные задачи: id представителя серии → число выполненных
  /// дней (каждый — маленькая веточка у узла, а не новый узел).
  final Map<String, int> dailyDone;

  const _TreeBlock({
    required this.block,
    required this.tasks,
    required this.steps,
    required this.complete,
    this.dailyDone = const {},
  });
}

class _TreePainter extends CustomPainter {
  final List<_TreeBlock> data;
  final double w;
  final double h;

  /// Перетаскивание блока: id перетаскиваемого (завязь светится)
  /// и позиция-кандидат (кольцо-подсветка).
  final String? dragId;
  final int hoverIndex;

  _TreePainter(this.data, this.w, this.h,
      {this.dragId, this.hoverIndex = -1});

  static const _trunk = Color(0xFF8D6E63);
  static const _done = Color(0xFF7BC47F);
  static const _todo = Color(0xFF5A5A66);
  static const _bud = Color(0xFF7FC8D8);

  /// Точка кубической кривой Безье в момент t (0..1) — чтобы веточки
  /// росли строго ИЗ ветви, а не висели рядом с ней.
  static Offset _bez(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1 - t;
    final a = u * u * u;
    final b = 3 * u * u * t;
    final c = 3 * u * t * t;
    final d = t * t * t;
    return Offset(a * p0.dx + b * p1.dx + c * p2.dx + d * p3.dx,
        a * p0.dy + b * p1.dy + c * p2.dy + d * p3.dy);
  }

  void _text(Canvas canvas, String s, Offset at, double fontSize, Color color,
      {double maxWidth = 120, bool bold = false, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal),
      ),
      maxLines: 2,
      ellipsis: '…',
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, align == TextAlign.right
        ? Offset(at.dx - tp.width, at.dy)
        : at);
  }

  void _icon(Canvas canvas, IconData icon, Offset center, double size,
      Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: size,
            color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = w / 2;
    // ---- Ствол: от земли до верхнего блока, мягкая кривая.
    final groundY = h - 60;
    final topY = 90.0;
    final trunkPaint = Paint()
      ..color = _trunk
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final trunk = Path()
      ..moveTo(cx, groundY)
      ..cubicTo(cx - 14, groundY - h * 0.25, cx + 14, groundY - h * 0.55,
          cx, topY);
    canvas.drawPath(trunk, trunkPaint);

    // Легенда.
    _text(canvas, 'зелёное — выполнено, серое — осталось',
        Offset(cx - 110, 20), 11, const Color(0xFF9A9AA5));

    for (var i = 0; i < data.length; i++) {
      final tb = data[i];
      final y = groundY - 100 - i * 240.0;
      // ---- Завязь блока на стволе.
      final budColor = tb.complete ? _done : _bud;
      // Подсветка при перетаскивании: перетаскиваемый блок светится,
      // позиция-кандидат — пустым кольцом.
      if (dragId == tb.block.id) {
        canvas.drawCircle(Offset(cx, y), 30,
            Paint()..color = _bud.withOpacity(0.35));
      }
      if (hoverIndex == i && dragId != null && dragId != tb.block.id) {
        canvas.drawCircle(
            Offset(cx, y),
            27,
            Paint()
              ..color = const Color(0xFFE0E0E0)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6);
      }
      canvas.drawCircle(Offset(cx, y), 22, Paint()..color = budColor.withOpacity(0.25));
      canvas.drawCircle(
          Offset(cx, y),
          22,
          Paint()
            ..color = budColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4);
      _icon(canvas, blockIconOf(tb.block.icon), Offset(cx, y), 18,
          tb.complete ? _done : budColor);
      _text(canvas, tb.block.title, Offset(cx + 30, y - 10), 12,
          const Color(0xFFE0E0E0),
          maxWidth: 130, bold: true);

      // ---- Ветви-задачи: влево и вправо от завязи. Веер разведён
      // широко и плавно — названия и ветви не пересекаются, пока
      // хватает места полотна.
      for (var j = 0; j < tb.tasks.length; j++) {
        final t = tb.tasks[j];
        final leftSide = j.isEven;
        final branchIdx = j ~/ 2;
        final endX = cx + (leftSide ? -1 : 1) * (136.0 + branchIdx * 38);
        final endY = y - 40 - branchIdx * 52;
        final col = t.isDone ? _done : _todo;
        final branchPaint = Paint()
          ..color = col
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        final p0 = Offset(cx, y);
        final p1 = Offset(cx + (leftSide ? -52 : 52), y - 10);
        final p2 = Offset(endX, endY + 26);
        final p3 = Offset(endX, endY);
        canvas.drawPath(
          Path()
            ..moveTo(p0.dx, p0.dy)
            ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy),
          branchPaint,
        );
        // Почка-задача на конце ветви.
        canvas.drawCircle(Offset(endX, endY), 6, Paint()..color = col);
        if (t.isDone) {
          // Галочка в почке.
          final check = Paint()
            ..color = const Color(0xFF1E1E24)
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke;
          canvas.drawPath(
            Path()
              ..moveTo(endX - 3, endY)
              ..lineTo(endX - 1, endY + 2.4)
              ..lineTo(endX + 3.4, endY - 2.6),
            check,
          );
        }
        _text(
          canvas,
          t.title,
          Offset(leftSide ? endX - 4 : endX + 10, endY - 8),
          10.5,
          t.isDone ? _done : const Color(0xFF9A9AA5),
          maxWidth: 110,
          align: leftSide ? TextAlign.right : TextAlign.left,
        );
        // Ежедневная задача: каждая отметка выполнения — маленькая
        // зелёная веточка веером от узла с названием (не новый узел).
        final dn = tb.dailyDone[t.id] ?? 0;
        final dirOut = leftSide ? -1.0 : 1.0;
        for (var k = 0; k < dn && k < 10; k++) {
          final bx = endX + dirOut * (10.0 + k * 3);
          final by = endY - 6 - k * 7;
          canvas.drawLine(
            Offset(endX + dirOut * 6, endY - 2),
            Offset(bx, by),
            Paint()
              ..color = _done
              ..strokeWidth = 1.2,
          );
          canvas.drawCircle(Offset(bx, by), 1.8, Paint()..color = _done);
        }
        // ---- Веточки-шаги: точки лежат строго НА кривой ветви
        // (та же кубическая Безье), поэтому веточки срослись
        // со своей ветвью, а не со стволом.
        final st = tb.steps[t.id] ?? const <TaskStep>[];
        for (var k = 0; k < st.length && k < 6; k++) {
          final frac = (k + 1) / (st.length + 1).clamp(1, 7);
          final at = _bez(p0, p1, p2, p3, frac.clamp(0.12, 0.95));
          final stepCol = st[k].isDone ? _done : _todo;
          const twigLen = 12.0;
          final dir = (k.isEven ? -1 : 1) * (leftSide ? -1 : 1);
          canvas.drawLine(
            at,
            Offset(at.dx + dir * twigLen, at.dy - twigLen),
            Paint()
              ..color = stepCol
              ..strokeWidth = 1.4,
          );
          canvas.drawCircle(Offset(at.dx + dir * twigLen, at.dy - twigLen),
              2.2, Paint()..color = stepCol);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TreePainter oldDelegate) => true;
}
