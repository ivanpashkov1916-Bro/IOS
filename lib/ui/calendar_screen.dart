/// Экран «Календарь»: сетка иконок дней месяца (4 в ряд — каждая иконка
/// занимает ~1/16 экрана). Задачи разложены по датам дедлайна: тап на
/// иконку дня открывает список задач этого дня (сверху ежедневные зелёные,
/// затем ключевые краткосрочные, краткосрочные, ключевые среднесрочные,
/// среднесрочные). События сохранены списком ниже.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'archive_screen.dart';
import 'common.dart';
import 'daily_diag.dart';
import 'edit_dialogs.dart';

/// Порядок задач внутри дня: закреплённые ежедневные -> закреплённые
/// краткосрочные -> прочие закреплённые -> ежедневные -> ключевые
/// краткосрочные -> краткосрочные -> ключевые среднесрочные ->
/// среднесрочные -> остальные (совпадает с порядком экрана «Сегодня»).
int dayTaskRank(Task t) {
  final daily = t.recurDaily || t.horizon == 'daily';
  if (t.isPinned && daily) return 0;
  if (t.isPinned && t.horizon == 'short') return 1;
  if (t.isPinned) return 2;
  if (daily) return 3;
  if (t.isKeyAction && t.horizon != 'medium') return 4;
  if (t.horizon == 'short') return 5;
  if (t.isKeyAction && t.horizon == 'medium') return 6;
  if (t.horizon == 'medium') return 7;
  return 8;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final evts = store.activeEvents
      ..sort((a, b) => a.start.compareTo(b.start));
    const monthNames = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    // Короткие названия дней недели (понедельник = 1).
    const weekdayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              visualDensity: VisualDensity.compact,
              onPressed: () => _shiftMonth(-1),
            ),
            Expanded(
              child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(fontSize: 17)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              visualDensity: VisualDensity.compact,
              onPressed: () => _shiftMonth(1),
            ),
          ],
        ),
        actions: [
          // Диагностика ежедневных задач (разбор задвоений): отчёт
          // копируется и присылается разработчику.
          IconButton(
            icon: const Icon(Icons.fact_check_outlined,
                color: AppTheme.accent),
            tooltip: 'Диагностика ежедневных задач',
            onPressed: () => showDailyDiagDialog(context, store),
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
          // Сетка иконок дней: 4 в ряд.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemCount: daysInMonth,
            itemBuilder: (ctx, i) {
              final day = DateTime(_month.year, _month.month, i + 1);
              final dayTasks = store.tasksForDay(day);
              final dayEvts = store.eventsForDay(day);
              final isToday = isSameDay(day, now);
              // Чекпоинты: ОДИН кружок на каждую задачу дня (и на каждую
              // ежедневную привычку — каждый день). Отметка о выполнении
              // ставится индивидуально на кружок своей задачи.
              final cps = store.calendarCheckpoints(day);
              const maxDots = 8;
              final shown = cps.take(maxDots).toList();
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DayTasksScreen(day: day)),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isToday ? AppTheme.accent : Colors.transparent,
                      width: 1.4,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  // Сезонная подложка (приятный рисунок месяца) под
                  // содержимым: отметки задач/событий остаются видны.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _SeasonPainter(
                                month: _month.month, seed: i + 1),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Число дня слева, день недели — в правом
                            // верхнем углу карточки.
                            Row(
                              children: [
                                Text('${i + 1}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: isToday
                                          ? AppTheme.accent
                                          : AppTheme.text,
                                    )),
                                const Spacer(),
                                Text(weekdayNames[day.weekday - 1],
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isToday
                                          ? AppTheme.accent
                                          : AppTheme.textDim,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 3),
                            // Кружки-чекпоинты задач — прямо ПОД числом дня,
                            // по одному на каждую задачу.
                            if (shown.isNotEmpty)
                              Wrap(
                                spacing: 3,
                                runSpacing: 3,
                                children: [
                                  for (final cp in shown)
                                    _checkpoint(cp.kind, cp.done),
                                  if (cps.length > maxDots)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text('+${cps.length - maxDots}',
                                          style: const TextStyle(
                                              fontSize: 9,
                                              color: AppTheme.textDim)),
                                    ),
                                ],
                              ),
                            const Spacer(),
                            if (dayTasks.isNotEmpty || dayEvts.isNotEmpty)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                    '${dayTasks.length + dayEvts.length}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textDim)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SectionHeader('События'),
          if (evts.isEmpty)
            const EmptyHint('Событий пока нет. Добавьте первое!')
          else
            for (final e in evts)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: eventPrioritySide(e)),
                child: ListTile(
                  leading: const Icon(Icons.event, color: AppTheme.accent),
                  title: Text(e.title),
                  subtitle: Text(
                      '${fmtDateTime(e.start)} · ${e.durationMin} мин'
                      '${e.priority == 2 ? ' · важное' : (e.priority == 0 ? ' · неспешное' : '')}'
                      '${e.comment.isNotEmpty ? '\n${e.comment}' : ''}',
                      style:
                          const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () =>
                            showEventEditor(context, store, event: e),
                      ),
                      IconButton(
                        icon: const Icon(Icons.archive_outlined, size: 20),
                        tooltip: 'В архив',
                        onPressed: () {
                          store.archiveEvent(e.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Событие в архиве')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEventEditor(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Кружок-чекпоинт задачи — по одному на каждую задачу дня,
  /// прямо под числом. Цвет кружка — по типу задачи:
  /// ежедневная — зелёный, ключевая — красный, среднесрочная —
  /// песочный, краткосрочная — синий, обычная — бирюзовый.
  /// Невыполненная — цветной контур; выполненная — заливка
  /// с яркой белой отметкой: толстая галочка (обычные), звезда —
  /// «лёгкая награда» за краткосрочную, кубок — «двойная радость»
  /// за среднесрочную.
  Widget _checkpoint(String kind, bool done) {
    final color = switch (kind) {
      'daily' => AppTheme.done,
      // Закреплённая ежедневная задача с датой — белая отметка.
      'pinned' => Colors.white,
      'key' => AppTheme.critical,
      'medium' => AppTheme.warn,
      'short' => AppTheme.shortTerm,
      _ => AppTheme.accent,
    };
    // Выполненная задача — ВСЕГДА галочка (любого вида кружка):
    // число галочек в дне = числу выполненных задач этого дня
    // на экране «Сегодня». Цвет кружка — вид задачи.
    final Widget? mark = done
        ? CustomPaint(size: const Size(13, 13), painter: _ThickCheckPainter())
        : null;
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.3),
      ),
      child: mark,
    );
  }
}

/// Толстая яркая галочка для чекпоинтов календаря — рисуется
/// кистью с округлыми концами, заметнее стандартной иконки
/// на маленьком кружке.
class _ThickCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.54)
      ..lineTo(size.width * 0.44, size.height * 0.76)
      ..lineTo(size.width * 0.82, size.height * 0.26);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ThickCheckPainter old) => false;
}

/// Сезонная подложка ячейки дня: ноябрь — осенние листья, май —
/// весеннее цветение, лето — солнце, зима — снежинки. Рисунок
/// полупрозрачный, чтобы отметки задач и событий оставались видны.
class _SeasonPainter extends CustomPainter {
  final int month;
  final int seed;
  const _SeasonPainter({required this.month, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed * 7919 + month * 131);
    Offset at() => Offset(rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height);

    if (month >= 9 && month <= 11) {
      // Осень: падающие листья (тёплые охристые овалы под наклоном).
      final paint = Paint()..color = const Color(0xFFD8956C).withOpacity(0.16);
      for (var k = 0; k < 3; k++) {
        final p = at();
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(rnd.nextDouble() * math.pi);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 22, height: 10), paint);
        canvas.drawLine(Offset.zero, const Offset(11, 0),
            paint..strokeWidth = 1.2);
        canvas.restore();
      }
    } else if (month >= 3 && month <= 5) {
      // Весна: цветение — нежно-розовые «пятилепестковые» точки.
      final paint = Paint()..color = const Color(0xFFE5A9C6).withOpacity(0.18);
      for (var k = 0; k < 2; k++) {
        final p = at();
        for (var petal = 0; petal < 5; petal++) {
          final a = petal * 2 * math.pi / 5;
          canvas.drawCircle(
              Offset(p.dx + 7 * math.cos(a), p.dy + 7 * math.sin(a)), 4, paint);
        }
        canvas.drawCircle(
            p, 2.6, Paint()..color = const Color(0xFFF3E2A9).withOpacity(0.35));
      }
    } else if (month >= 6 && month <= 8) {
      // Лето: солнышко в углу + пара травинок.
      final sun = Paint()..color = const Color(0xFFE8D08C).withOpacity(0.16);
      final c = Offset(size.width * 0.8, size.height * 0.22);
      canvas.drawCircle(c, 10, sun);
      for (var ray = 0; ray < 8; ray++) {
        final a = ray * math.pi / 4;
        canvas.drawLine(
            Offset(c.dx + 12 * math.cos(a), c.dy + 12 * math.sin(a)),
            Offset(c.dx + 17 * math.cos(a), c.dy + 17 * math.sin(a)),
            sun..strokeWidth = 1.6);
      }
      final grass = Paint()
        ..color = const Color(0xFF9BC78C).withOpacity(0.15)
        ..strokeWidth = 1.6;
      for (var k = 0; k < 3; k++) {
        final p = Offset(rnd.nextDouble() * size.width, size.height - 4);
        canvas.drawLine(
            p, Offset(p.dx + 4 - rnd.nextDouble() * 8, p.dy - 12), grass);
      }
    } else {
      // Зима: снежинки (три перекрещивающиеся линии) — холодный голубой.
      final paint = Paint()
        ..color = const Color(0xFFBFD8E5).withOpacity(0.2)
        ..strokeWidth = 1.4;
      for (var k = 0; k < 3; k++) {
        final p = at();
        for (var arm = 0; arm < 3; arm++) {
          final a = arm * math.pi / 3;
          canvas.drawLine(
              Offset(p.dx - 8 * math.cos(a), p.dy - 8 * math.sin(a)),
              Offset(p.dx + 8 * math.cos(a), p.dy + 8 * math.sin(a)),
              paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SeasonPainter old) =>
      old.month != month || old.seed != seed;
}

/// Список задач конкретного дня (тап по иконке дня).
/// Ежедневные привычки (зелёные) и действия показываются каждый день;
/// в их выпадающем меню — «Выходной» и комментарий / причина пропуска.
class DayTasksScreen extends StatelessWidget {
  final DateTime day;
  const DayTasksScreen({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final dayTasks = store.tasksForDay(day)
      ..sort((a, b) => dayTaskRank(a).compareTo(dayTaskRank(b)));
    final dayEvts = store.eventsForDay(day);
    // Ежедневные привычки-цели показываются каждый день.
    final habits = store.activeGoals.where((g) => g.recurDaily).toList();

    // Прошедший день: показываем, что было сделано и что осталось
    // невыполненным (иначе карточки прошлых дней выглядят пустыми —
    // выполненные задачи уходят в архив). Невыполненное можно
    // принудительно убрать в архив, чтобы не висело грузом.
    final now = DateTime.now();
    final day0 = DateTime(day.year, day.month, day.day);
    final isPast = day0.isBefore(DateTime(now.year, now.month, now.day));
    final past = isPast ? store.pastDayTasks(day) : null;

    return Scaffold(
      appBar: AppBar(title: Text(fmtDate(day))),
      body: dayTasks.isEmpty &&
              dayEvts.isEmpty &&
              habits.isEmpty &&
              (past == null ||
                  (past.done.isEmpty &&
                      past.missed.isEmpty &&
                      past.pinnedDone.isEmpty))
          ? const EmptyHint('На этот день планов нет')
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (dayEvts.isNotEmpty) const SectionHeader('События'),
                for (final e in dayEvts)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: const Icon(Icons.event, color: AppTheme.accent),
                      title: Text(e.title),
                      subtitle: Text(
                          '${fmtTime(e.start)} · ${e.durationMin} мин',
                          style: const TextStyle(
                              color: AppTheme.textDim, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () =>
                            showEventEditor(context, store, event: e),
                      ),
                    ),
                  ),
                // Прошедший день: три секции вместо живого списка.
                if (isPast && past != null) ...[
                  if (past.missed.isNotEmpty)
                    const SectionHeader('Не выполнено', color: AppTheme.danger),
                  for (final t in past.missed)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side:
                            const BorderSide(color: AppTheme.danger, width: 1),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.radio_button_unchecked,
                            color: AppTheme.danger),
                        title: Text(t.title),
                        subtitle: Text(
                          [
                            'не выполнено',
                            if (t.horizon == 'daily' || t.recurDaily)
                              'ежедневная',
                            if (t.horizon == 'short') 'краткосрочная',
                            if (t.horizon == 'medium') 'среднесрочная',
                          ].join(' · '),
                          style: const TextStyle(
                              color: AppTheme.textDim, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 20, color: AppTheme.done),
                              tooltip: 'Всё-таки выполнено',
                              onPressed: () =>
                                  completeTaskWithFeedback(context, store, t),
                            ),
                            IconButton(
                              icon: const Icon(Icons.archive_outlined,
                                  size: 20, color: AppTheme.textDim),
                              tooltip: 'Принудительно в архив',
                              onPressed: () {
                                store.archiveTask(t.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '«${t.title}» убрана в архив')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (past.done.isNotEmpty)
                    const SectionHeader('Выполнено', color: AppTheme.done),
                  for (final t in past.done)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: const Icon(Icons.check_circle,
                            color: AppTheme.done, size: 20),
                        title: Text(t.title,
                            style: const TextStyle(color: AppTheme.textDim)),
                      ),
                    ),
                  if (past.pinnedDone.isNotEmpty)
                    const SectionHeader('Закреплённые: выполнено',
                        color: AppTheme.daily),
                  for (final title in past.pinnedDone)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.push_pin_outlined,
                            color: AppTheme.daily, size: 18),
                        title: Text(title,
                            style: const TextStyle(
                                color: AppTheme.textDim, fontSize: 13)),
                      ),
                    ),
                ],
                // Ежедневные привычки — зелёным, каждый день, с меню
                // «Выходной» / «Комментарий / причина пропуска».
                if (!isPast && habits.isNotEmpty)
                  const SectionHeader('Ежедневные привычки',
                      color: AppTheme.done),
                if (!isPast)
                  for (final g in habits)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: AppTheme.done, width: 1),
                    ),
                    child: ListTile(
                      leading: IconButton(
                        icon: Icon(
                          g.isDone
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: AppTheme.done,
                        ),
                        tooltip: 'Отметить выполнение сегодня',
                        onPressed: () => store.toggleGoalDone(g.id),
                      ),
                      title: Text(g.title),
                      subtitle: Text(
                        [
                          'ежедневная привычка',
                          if (g.isDone) 'сделано сегодня',
                          if (g.missedCount > 0)
                            'пропусков: ${g.missedCount}',
                          if (g.dayOffDates.isNotEmpty)
                            'выходных: ${g.dayOffDates.length}',
                        ].join(' · '),
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert,
                            size: 20, color: AppTheme.textDim),
                        tooltip: 'Выходной / комментарий',
                        onSelected: (v) {
                          if (v == 'dayoff') {
                            store.markGoalDayOff(g.id, day);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '${fmtDate(day)} отмечено как выходной — пропуск не засчитается')),
                            );
                          }
                          if (v == 'comment') {
                            askCommentDialog(context, g.title, (text) {
                              g.comment = g.comment.isEmpty
                                  ? text
                                  : '${g.comment}\n$text';
                              store.updateGoal(g);
                              store.addFeedback(
                                  text.contains('ричин')
                                      ? 'late_reason'
                                      : 'comment',
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
                              leading:
                                  Icon(Icons.beach_access_outlined, size: 20),
                              title: Text('Выходной'),
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
                    ),
                  ),
                if (!isPast && dayTasks.isNotEmpty) const SectionHeader('Задачи дня'),
                if (!isPast)
                for (final t in dayTasks)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: taskUrgencyColor(t) != null
                          ? BorderSide(
                              color: taskUrgencyColor(t)!,
                              width: taskUrgencyColor(t) == AppTheme.critical
                                  ? 1.6
                                  : 1)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      leading: IconButton(
                        icon: const Icon(Icons.radio_button_unchecked,
                            color: AppTheme.textDim),
                        tooltip: 'Выполнить',
                        onPressed: () =>
                            completeTaskWithFeedback(context, store, t),
                      ),
                      title: Row(
                        children: [
                          if (t.isKeyAction)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.key,
                                  size: 15, color: AppTheme.warn),
                            ),
                          Expanded(child: Text(t.title)),
                        ],
                      ),
                      subtitle: deadlineInfoText(t, extra: [
                        if (t.recurDaily || t.horizon == 'daily')
                          'ежедневная',
                        if (t.horizon == 'short') 'краткосрочная',
                        if (t.horizon == 'medium') 'среднесрочная',
                        if (t.isKeyAction) 'ключевое действие',
                        if (t.recurDaily && t.pctStep < 100)
                          '${t.progressPct}%',
                      ]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t.recurDaily || t.horizon == 'daily')
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  size: 19, color: AppTheme.textDim),
                              tooltip: 'Выходной / комментарий',
                              onSelected: (v) {
                                if (v == 'dayoff') {
                                  store.markTaskDayOff(t.id, day);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '${fmtDate(day)} отмечено как выходной — пропуск не засчитается')),
                                  );
                                }
                                if (v == 'comment') {
                                  askCommentDialog(
                                      context,
                                      t.title,
                                      (text) => store.appendTaskComment(
                                          t.id, text));
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'dayoff',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        Icons.beach_access_outlined,
                                        size: 20),
                                    title: Text('Выходной'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'comment',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        Icon(Icons.comment_outlined, size: 20),
                                    title: Text(
                                        'Комментарий / причина пропуска'),
                                  ),
                                ),
                              ],
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () =>
                                showTaskEditor(context, store, task: t),
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
