/// Общие виджеты: заглушка пустого списка, заголовок секции,
/// цветовая срочность задач, выполнение с похвалой и запросом причины.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../praise.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'alerts_screen.dart';
import 'fireworks.dart';

/// Колокольчик критических оповещений с бейджем — добавляется в AppBar
/// каждого экрана (actions: [const AlertBell(), ...]).
class AlertBell extends StatelessWidget {
  const AlertBell({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<AppStore>().criticalAlerts().length;
    return IconButton(
      tooltip: 'Оповещения',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppTheme.danger,
        child: Icon(
          count > 0 ? Icons.notifications_active : Icons.notifications_none,
          color: count > 0 ? AppTheme.warn : AppTheme.textDim,
        ),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AlertsScreen()),
      ),
    );
  }
}

/// Значок размера шрифта — в AppBar каждого экрана рядом с
/// колокольчиком (по аналогии с экраном ассистента). Стандартные
/// градации; выбранный масштаб применяется ко ВСЕМ надписям
/// приложения пропорционально и сохраняется между запусками.
class FontScaleButton extends StatelessWidget {
  const FontScaleButton({super.key});

  /// Стандартные градации масштаба шрифта.
  static const List<double> steps = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.8];
  static const List<String> labels = [
    '80%',
    '90%',
    '100%',
    '115%',
    '130%',
    '150%',
    '180%',
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return IconButton(
      tooltip: 'Размер шрифта (${(store.fontScale * 100).round()}%)',
      icon: const Icon(Icons.format_size, size: 20, color: AppTheme.textDim),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) {
          final cur = context.read<AppStore>().fontScale;
          return SimpleDialog(
            title: const Text('Размер шрифта'),
            children: [
              for (var i = 0; i < steps.length; i++)
                SimpleDialogOption(
                  onPressed: () {
                    context.read<AppStore>().setFontScale(steps[i]);
                    Navigator.pop(ctx);
                  },
                  child: Row(
                    children: [
                      Icon(
                        (cur - steps[i]).abs() < 0.01
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: (cur - steps[i]).abs() < 0.01
                            ? AppTheme.accent
                            : AppTheme.textDim,
                      ),
                      const SizedBox(width: 10),
                      Text(labels[i]),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final String text;
  const EmptyHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: const TextStyle(color: AppTheme.textDim, fontSize: 14)),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? color;
  const SectionHeader(this.title, {this.subtitle, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (color != null)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              Text(title,
                  style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Три иконки приоритета + молния целевого действия:
/// речные волны — низкий, восклицательный знак — средний,
/// костюм с галстуком — высокий, молния — ключевое действие.
class PriorityIcons extends StatelessWidget {
  final int priority;
  final bool isKey;
  final void Function(int) onPriority;
  final VoidCallback? onKey;
  final double size;

  const PriorityIcons({
    super.key,
    required this.priority,
    required this.onPriority,
    this.isKey = false,
    this.onKey,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, int value, Color color, String tip) {
      final selected = priority == value;
      return IconButton(
        icon: Icon(icon, size: size, color: selected ? color : AppTheme.textDim),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: () => onPriority(value),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.waves, 0, AppTheme.accent, 'Низкий приоритет'),
        btn(Icons.priority_high, 1, AppTheme.warn, 'Средний приоритет'),
        btn(Icons.work_outline, 2, AppTheme.critical, 'Высокий приоритет'),
        if (onKey != null)
          IconButton(
            icon: Icon(Icons.bolt,
                size: size, color: isKey ? AppTheme.warn : AppTheme.textDim),
            tooltip: 'Целевое действие',
            visualDensity: VisualDensity.compact,
            onPressed: onKey,
          ),
      ],
    );
  }
}

/// Цвет точки шкалы по приоритету задачи (и статусу).
Color priorityDotColor(
    {required bool isDone, required bool overdue, required int priority}) {
  if (isDone) return AppTheme.done;
  if (overdue) return AppTheme.critical;
  switch (priority) {
    case 2:
      return AppTheme.critical;
    case 0:
      return AppTheme.accent;
    default:
      return AppTheme.warn;
  }
}

/// Цветовая срочность задачи (динамический приоритет):
/// просрочена или ключевая с дедлайном < 48ч — ярко-красный;
/// среднесрочная — жёлтый; ежедневная повторяющаяся — зелёный;
/// краткосрочная — синий контур.
Color? taskUrgencyColor(Task t) {
  final now = DateTime.now();
  final dl = t.deadline;
  // Красный контур — ТОЛЬКО пропущенные дедлайны.
  if (dl != null && dl.isBefore(now) && !t.isDone) return AppTheme.critical;
  // Все остальные задачи — контур цвета СВОЕГО горизонта. Отметка
  // молнией («ключевая») цвет контура НЕ меняет: ежедневная остаётся
  // зелёной, краткосрочная — синей, среднесрочная — жёлтой.
  if (t.recurDaily || t.horizon == 'daily') return AppTheme.done;
  if (t.horizon == 'medium') return AppTheme.warn;
  if (t.horizon == 'short') return AppTheme.shortTerm;
  return null;
}

/// Рамка события по приоритету (команда «добавь событие» + «срочно»/«важно»):
/// высокий — красный контур, низкий — синий, средний — без рамки.
BorderSide eventPrioritySide(EventItem e) {
  if (e.priority == 2) return const BorderSide(color: AppTheme.critical, width: 1.4);
  if (e.priority == 0) return const BorderSide(color: AppTheme.shortTerm, width: 1);
  return BorderSide.none;
}

/// Цвет ДАТЫ дедлайна по близости срока:
/// далеко (> недели) — зелёный, около недели — синий (бирюза),
/// несколько дней — жёлтый, один день или просрочено — красный.
Color deadlineColor(DateTime dl, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (!dl.isAfter(n)) return AppTheme.critical;
  final h = dl.difference(n).inHours;
  if (h <= 24) return AppTheme.critical;
  if (h <= 24 * 3) return AppTheme.warn;
  if (h <= 24 * 7) return AppTheme.accent;
  return AppTheme.done;
}

/// Строка «дедлайн дата время»: слово приглушено, дата и время
/// выделены ярким цветом по близости срока (см. deadlineColor).
/// [dateColor] — принудительный цвет даты (например, цвет блока,
/// на экране которого показана задача: «Горящие дедлайны» и т.п.).
Widget deadlineInfoText(Task t,
    {List<String> extra = const [], Color? dateColor}) {
  final spans = <InlineSpan>[];
  if (t.deadline != null) {
    spans.add(const TextSpan(
        text: 'дедлайн ',
        style: TextStyle(color: AppTheme.textDim, fontSize: 12)));
    spans.add(TextSpan(
      text: fmtDateTime(t.deadline!),
      style: TextStyle(
        color: dateColor ?? deadlineColor(t.deadline!),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ));
    if (extra.isNotEmpty) {
      spans.add(TextSpan(
          text: ' · ${extra.join(' · ')}',
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12)));
    }
  } else {
    spans.add(TextSpan(
        text: extra.join(' · '),
        style: const TextStyle(color: AppTheme.textDim, fontSize: 12)));
  }
  return Text.rich(
    TextSpan(children: spans),
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
  );
}

/// Диалог «комментарий / причина пропуска» — вызывается из выпадающих
/// меню ежедневных привычек и задач (рядом с пунктом «Выходной»).
Future<void> askCommentDialog(
  BuildContext context,
  String itemTitle,
  void Function(String text) onSave,
) async {
  final c = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(itemTitle, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: c,
        maxLines: 3,
        decoration: const InputDecoration(
            hintText: 'Комментарий или причина пропуска'),
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
  if (saved == true && c.text.trim().isNotEmpty) {
    onSave(c.text.trim());
  }
}

/// Выполнение задачи с геймификацией: мгновенный тоггл, похвала
/// по центру с фейерверком-хлопушкой, затем вопрос «за какое время
/// фактически удалось выполнить задачу» (ответ — в карточку, графа
/// «фактически реализовано за», пункт «итого»), а при пропущенном
/// дедлайне — вопрос «Хочешь рассказать о причине?».
void completeTaskWithFeedback(BuildContext context, AppStore store, Task t,
    {VoidCallback? onAfter}) {
  final wasLate = t.deadline != null && t.deadline!.isBefore(DateTime.now());
  store.toggleTaskDone(t.id);
  // Стало ли задача полностью выполненной: снятие отметки и частичный
  // процент ежедневной задачи — без праздника и вопросов.
  var becameDone = false;
  for (final x in store.tasks) {
    if (x.id == t.id) {
      becameDone = x.isDone;
      break;
    }
  }
  if (!becameDone) {
    onAfter?.call();
    return;
  }
  PraiseOverlay.show(context, Praise.forTask(key: t.isKeyAction));
  // Сначала — фактическое время, потом (если был пропуск) — причина.
  // Награда за день (onAfter) показывается СТРОГО ПОСЛЕ закрытия всех
  // этих окон: иначе диалоги накладываются друг на друга и сообщение
  // о награде теряется под ними.
  _askActualTime(context, store, t, () {
    if (wasLate && context.mounted) {
      _askLateReason(context, store, t, onAfter: onAfter);
    } else {
      onAfter?.call();
    }
  });
}

/// Диалог «За какое время удалось выполнить задачу?»: свободный ввод
/// («полтора часа», «61 минута», «90») + быстрые чипы. Ответ пишется
/// в actualMin и отображается в карточке после слова «Итого».
void _askActualTime(
    BuildContext context, AppStore store, Task t, VoidCallback onClose) {
  final c = TextEditingController();
  String? error;
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Задача выполнена!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('За какой период времени удалось фактически '
                'реализовать задачу?'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final quick in const [
                  '15 минут',
                  '30 минут',
                  '1 час',
                  'полтора часа',
                  '2 часа',
                  '3 часа',
                ])
                  ActionChip(
                    label: Text(quick, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      c.text = quick;
                      setS(() => error = null);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'например: 61 минута или полтора часа',
                errorText: error,
              ),
              onChanged: (_) => setS(() => error = null),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Пропустить'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = parseDurationMin(c.text);
              if (minutes == null) {
                setS(() => error =
                    'Не понял время — напишите, например, «45 минут»');
                return;
              }
              store.setTaskActualMin(t.id, minutes);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                      'Записал: итого ${fmtDaysHoursMin(minutes)}'),
                ),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  ).then((_) {
    // Любое закрытие (кнопки, жест, «назад») — продолжаем цепочку
    // ровно один раз: следующий диалог/награда не теряются.
    onClose();
  });
}

/// При пропущенном дедлайне — вопрос о причине (как раньше).
/// onAfter срабатывает после закрытия диалога любым способом.
void _askLateReason(BuildContext context, AppStore store, Task t,
    {VoidCallback? onAfter}) {
    final reasonC = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Дедлайн был пропущен'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Хочешь рассказать о причине? Это поможет '
                'точнее планировать в следующий раз.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonC,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Причина (необязательно)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Пропустить'),
          ),
          FilledButton(
            onPressed: () {
              final r = reasonC.text.trim();
              if (r.isNotEmpty) {
                store.appendTaskComment(t.id, 'Причина пропуска: $r');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ).then((_) => onAfter?.call());
}

/// Тип шага для визуализации «человечками»: ключевое целевое
/// действие, ежедневный шаг или разовый шаг. Тип выводится без
/// миграции БД: из флага целевого действия, слов в названии шага
/// и признака ежедневности самой задачи.
String stepKindOf(TaskStep s, Task t) {
  if (s.isKeyAction) return 'key';
  final dailyRx = RegExp(
      r'(ежедневн|каждый день|каждое утро|каждый вечер|раз в день|х/день|в день\b)',
      caseSensitive: false);
  if (dailyRx.hasMatch(s.title) || t.recurDaily || t.horizon == 'daily') {
    return 'daily';
  }
  return 'once';
}

/// Цвет человечка по типу шага: разовый — синий, ежедневный —
/// зелёный, ключевое целевое действие — песочный + молния снизу.
Color stepKindColor(String kind) => switch (kind) {
      'key' => AppTheme.warn,
      'daily' => AppTheme.done,
      _ => AppTheme.shortTerm,
    };

/// Инлайн-панель шагов под задачей на экранах «Сегодня» и «Задачи»:
/// дорожка «весёлых человечков» (вместо точечной шкалы экрана целей)
/// + компактный список шагов с отметками. Всё сохраняется в БД.
class TaskStepsInline extends StatelessWidget {
  final Task task;
  final VoidCallback? onOpenFull;
  const TaskStepsInline({super.key, required this.task, this.onOpenFull});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final steps = store.stepsForTask(task.id);
    if (steps.isEmpty) {
      return Row(
        children: [
          const Expanded(
            child: Text('Шагов пока нет — откройте шкалу пути, '
                'чтобы разбить задачу на шаги',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
          ),
          if (onOpenFull != null)
            TextButton.icon(
              onPressed: onOpenFull,
              icon: const Icon(Icons.stairs_outlined, size: 18),
              label: const Text('Шкала пути'),
            ),
        ],
      );
    }
    final done = steps.where((s) => s.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.route, size: 14, color: AppTheme.textDim),
            const SizedBox(width: 6),
            Text('Шаги: $done/${steps.length}',
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const Spacer(),
            if (onOpenFull != null)
              InkWell(
                onTap: onOpenFull,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.open_in_new,
                      size: 16, color: AppTheme.textDim),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StepsPeopleBar(task: task, steps: steps),
        const SizedBox(height: 6),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                InkWell(
                  onTap: () => store.toggleStepDone(s.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      s.isDone
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: s.isDone
                          ? AppTheme.done
                          : stepKindColor(stepKindOf(s, task)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.title,
                    style: TextStyle(
                      fontSize: 13,
                      color: s.isDone ? AppTheme.textDim : AppTheme.text,
                      decoration:
                          s.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (s.isKeyAction)
                  const Icon(Icons.bolt, size: 14, color: AppTheme.warn),
              ],
            ),
          ),
      ],
    );
  }
}

/// Дорожка шагов «весёлые человечки»: каждый шаг — человечек на
/// линии прогресса. Выполненный радостно поднимает руки вверх,
/// невыполненный — приглушённый контур. Тап по человечку
/// переключает отметку шага.
class StepsPeopleBar extends StatelessWidget {
  final Task task;
  final List<TaskStep> steps;
  const StepsPeopleBar({super.key, required this.task, required this.steps});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Container(
                  width: 12,
                  height: 2,
                  color: steps[i].isDone && steps[i - 1].isDone
                      ? AppTheme.done
                      : AppTheme.textDim.withOpacity(0.35),
                ),
              ),
            _PersonStep(
              step: steps[i],
              kind: stepKindOf(steps[i], task),
              onTap: () => store.toggleStepDone(steps[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonStep extends StatelessWidget {
  final TaskStep step;
  final String kind;
  final VoidCallback onTap;
  const _PersonStep(
      {required this.step, required this.kind, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = stepKindColor(kind);
    return Tooltip(
      message: step.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(20, 26),
                painter: _PersonPainter(
                  color: step.isDone ? color : color.withOpacity(0.55),
                  happy: step.isDone,
                  filled: step.isDone,
                ),
              ),
              // Ключевое целевое действие — молния под человечком.
              if (kind == 'key')
                const Icon(Icons.bolt, size: 11, color: AppTheme.warn)
              else
                const SizedBox(height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

/// Весёлый человечек: круглая голова, тело, руки и ноги линиями.
/// В «счастливом» состоянии (шаг выполнен) руки подняты вверх,
/// на голове — улыбка; в ожидании — руки опущены, контур приглушён.
class _PersonPainter extends CustomPainter {
  final Color color;
  final bool happy;
  final bool filled;
  const _PersonPainter(
      {required this.color, required this.happy, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final headR = w * 0.24;
    final headCenter = Offset(cx, headR + 1);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Голова
    if (filled) {
      canvas.drawCircle(
          headCenter, headR, Paint()..color = color.withOpacity(0.9));
      // Улыбка тёмной дугой на залитой голове.
      final face = Paint()
        ..color = AppTheme.bg
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCircle(
            center: headCenter.translate(0, headR * 0.15),
            radius: headR * 0.5),
        math.pi * 0.15,
        math.pi * 0.7,
        false,
        face,
      );
    } else {
      canvas.drawCircle(headCenter, headR, stroke);
    }

    final neckY = headCenter.dy + headR + 1.5;
    final hipY = h * 0.66;
    // Тело
    canvas.drawLine(Offset(cx, neckY), Offset(cx, hipY), stroke);
    // Руки: радость — вверх, ожидание — вниз.
    final shoulder = Offset(cx, neckY + 2.5);
    if (happy) {
      canvas.drawLine(
          shoulder, Offset(cx - w * 0.34, neckY - h * 0.16), stroke);
      canvas.drawLine(
          shoulder, Offset(cx + w * 0.34, neckY - h * 0.16), stroke);
    } else {
      canvas.drawLine(
          shoulder, Offset(cx - w * 0.3, neckY + h * 0.24), stroke);
      canvas.drawLine(
          shoulder, Offset(cx + w * 0.3, neckY + h * 0.24), stroke);
    }
    // Ноги
    canvas.drawLine(Offset(cx, hipY), Offset(cx - w * 0.26, h), stroke);
    canvas.drawLine(Offset(cx, hipY), Offset(cx + w * 0.26, h), stroke);
  }

  @override
  bool shouldRepaint(_PersonPainter old) =>
      old.color != color || old.happy != happy || old.filled != filled;
}
