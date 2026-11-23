/// Круг продуктивности по блокам годового плана (экран «Цели»).
/// Каждый сектор — блок годового плана, размер сектора пропорционален
/// числу задач блока относительно других. По мере выполнения задач
/// сектор наполняется от центра к внешней окружности. Блоки разноцветные,
/// заполнение — однотонное (насыщенный цвет сектора) с пометкой процента.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

class BlockWheelData {
  final String title;
  final int total;
  final int done;
  const BlockWheelData(this.title, this.total, this.done);
  double get pct => total == 0 ? 0 : done / total;
}

/// Собирает данные круга: сектор = блок годового плана.
/// Если блоков нет — по обычным целям (прогресс цели как заполнение).
/// Вклад удалённых из архива задач (carryDone/carryTotal) учитывается:
/// удаление задачи НЕ откатывает прогресс блока.
List<BlockWheelData> buildBlockWheelData(AppStore store) {
  final blocks = store.blockGoals().where((g) => !g.isArchived).toList();
  if (blocks.isNotEmpty) {
    return [
      for (final g in blocks)
        () {
          final ts = store.tasksForGoal(g);
          return BlockWheelData(g.title, ts.length + g.carryTotal,
              ts.where((t) => t.isDone).length + g.carryDone);
        }()
    ];
  }
  final goals =
      store.activeGoals.where((g) => !g.recurDaily && !g.isPinned).toList();
  return [
    for (final g in goals)
      BlockWheelData(g.title, 100, (g.progress * 100).round())
  ];
}

class BlockProductivityWheel extends StatelessWidget {
  final List<BlockWheelData> data;
  const BlockProductivityWheel({super.key, required this.data});

  /// Разноцветные сектора: равномерный обход цветового круга.
  static Color sectorColor(int i) {
    final hue = (i * 67) % 360;
    return HSVColor.fromAHSV(1, hue.toDouble(), 0.45, 0.82).toColor();
  }

  /// Цвет блока годового плана по его коду ('block:X' или 'X').
  /// Тот же цвет, что у сектора круга «Продуктивность по блокам», —
  /// рамки задач на экране «Цели» совпадают с цветом своего блока.
  static Color blockColorOf(AppStore store, String blockCode) {
    var code = blockCode.startsWith('block:')
        ? blockCode.substring(6)
        : blockCode;
    code = code.toLowerCase().trim();
    final blocks = store.blockGoals().where((g) => !g.isArchived).toList();
    for (var i = 0; i < blocks.length; i++) {
      var bc = blocks[i].externalId.startsWith('block:')
          ? blocks[i].externalId.substring(6)
          : blocks[i].externalId;
      if (bc.toLowerCase().trim() == code) return sectorColor(i);
      // Запасной вариант: совпадение по названию блока.
      if (blocks[i].title.toLowerCase().trim() == code) return sectorColor(i);
    }
    return AppTheme.accent;
  }

  @override
  Widget build(BuildContext context) {
    final totalDone = data.fold<int>(0, (s, e) => s + e.done);
    final totalAll = data.fold<int>(0, (s, e) => s + e.total);
    final overall = totalAll == 0 ? 0 : (totalDone * 100 ~/ totalAll);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Продуктивность по блокам',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
                'Сектор — блок годового плана; наполнение идёт от центра '
                'к внешней окружности по мере выполнения задач',
                style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 210,
                height: 210,
                child: CustomPaint(
                  painter: _WheelPainter(data),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$overall%',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.text)),
                        const Text('всего',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textDim)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Легенда: цветной маркер, название блока, процент выполнения.
            for (var i = 0; i < data.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: sectorColor(i), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(data[i].title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.text)),
                    ),
                    Text(
                        '${(data[i].pct * 100).round()}% '
                        '(${data[i].done}/${data[i].total})',
                        style: TextStyle(
                            fontSize: 11,
                            color: sectorColor(i),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<BlockWheelData> data;
  _WheelPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final grand =
        data.fold<int>(0, (s, e) => s + (e.total <= 0 ? 1 : e.total));
    if (grand == 0) return;

    var start = -math.pi / 2; // старт сверху
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final share = (d.total <= 0 ? 1 : d.total) / grand;
      final sweep = share * 2 * math.pi;
      final color = BlockProductivityWheel.sectorColor(i);

      // Фон сектора — приглушённое кольцо (внешняя часть, «пустая»).
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.42
        ..color = color.withOpacity(0.22);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.79),
        start,
        sweep - 0.02,
        false,
        ringPaint,
      );

      // Заполнение от центра к внешней окружности: однотонный сектор,
      // радиус пропорционален проценту выполнения.
      final pct = d.pct.clamp(0.0, 1.0);
      if (pct > 0) {
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = color;
        final r = radius * (0.30 + 0.70 * pct);
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(Rect.fromCircle(center: center, radius: r), start,
              sweep - 0.02, false)
          ..close();
        canvas.drawPath(path, fillPaint);
      }

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => true;
}
