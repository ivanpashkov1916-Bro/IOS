/// Экран «Статистика»: полоски прогресса (День/Неделя/Месяц/Квартал/Год)
/// для задач и целей + круговая диаграмма продуктивности (fl_chart).
/// Вторая вкладка — «Стратегия на год» (загрузка tasks.json).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'block_icons.dart';
import 'common.dart';
import 'finance_screen.dart';
import 'strategy_screen.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Статистика'),
          actions: [
            const FontScaleButton(),
            const AlertBell(),
            // Финансовый учёт: источники доходов/расходов и их
            // распределение по блокам годового плана.
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Финансовый учёт',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FinanceScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Выгрузить все данные (JSON)',
              onPressed: () => _showFullExport(context),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Экспорт отчёта',
              onPressed: () => _showReport(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Стратегия на год'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StatsOverview(),
            StrategyScreen(),
          ],
        ),
      ),
    );
  }
}

/// Шторка «Пропущено всего»: раскрывающийся список пропущенных
/// задач, привычек и событий. Тап по пункту открывает экран, где
/// он живёт, и сразу предлагает оставить комментарий — причину
/// пропуска (сохраняется в карточке и в журнале обратной связи).
Future<void> _showMissedSheet(BuildContext context, AppStore store) async {
  final items = store.missedItems();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Пропущенные задачи и события',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final it in items)
                  ListTile(
                    leading: Icon(
                      it.kind == 'event'
                          ? Icons.event
                          : (it.kind == 'goal'
                              ? Icons.flag_outlined
                              : Icons.task_alt),
                      color: AppTheme.danger,
                      size: 20,
                    ),
                    title: Text(it.title, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(it.detail,
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 11)),
                    trailing: const Icon(Icons.comment_outlined,
                        size: 18, color: AppTheme.textDim),
                    onTap: () {
                      Navigator.pop(ctx);
                      // Переходим на экран, где живёт этот пункт…
                      store.requestTab(it.tab);
                      // …и сразу спрашиваем причину пропуска.
                      askCommentDialog(context, it.title, (text) {
                        switch (it.kind) {
                          case 'event':
                            store.appendEventComment(it.id, text);
                          case 'goal':
                            store.appendGoalComment(it.id, text);
                          default:
                            store.appendTaskComment(it.id, text);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final periods = statPeriods();

    final active = store.tasks.where((t) => !t.isArchived && !t.isDone).length;
    final done = store.tasks.where((t) => t.isDone).length;
    final archived = store.tasks.where((t) => t.isArchived && !t.isDone).length;
    // Аналитика пропусков: накопленные пропуски ежедневных задач и привычек.
    final missedTotal =
        store.tasks.fold<int>(0, (s, t) => s + t.missedCount) +
            store.goals.fold<int>(0, (s, g) => s + g.missedCount);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Поле обратной связи: все причины пропусков собраны для аудита.
        if (store.feedback.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTheme.accent, width: 1),
              ),
              child: ExpansionTile(
                leading: const Icon(Icons.fact_check_outlined,
                    color: AppTheme.accent),
                title: Text(
                    'Журнал обратной связи (${store.feedback.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Причины пропусков и комментарии — для аудита планирования',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Выгрузить всё'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: store.buildFeedbackExport()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Журнал скопирован — отправьте Кими на аудит')),
                          );
                        }
                      },
                    ),
                  ),
                  for (final e in store.feedback.take(10))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        // Каждая запись привязана к календарной дате,
                        // в которую была совершена.
                        child: Text(
                          '· [${fmtDate(e.createdAt)}] ${e.itemTitle}: ${e.text}',
                          style: const TextStyle(
                              color: AppTheme.textDim, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (missedTotal > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTheme.danger, width: 1),
              ),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: AppTheme.danger),
                title: Text('Пропущено всего: $missedTotal',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Нажмите — раскроется список пропущенных задач и событий; '
                  'тап по пункту откроет его экран и предложит оставить '
                  'комментарий (причину пропуска).',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                trailing: const Icon(Icons.expand_more,
                    color: AppTheme.textDim, size: 20),
                onTap: () => _showMissedSheet(context, store),
              ),
            ),
          ),
        // Дерево связей: блоки годового плана и привязанные к ним задачи.
        const _LinkTree(),
        const SectionHeader('Задачи'),
        for (final p in periods)
          _ProgressRow(
            label: 'Задачи ${p.name}',
            stat: store.taskStat(p.from, p.to),
          ),
        const SectionHeader('Цели'),
        for (final p in periods)
          _ProgressRow(
            label: 'Цели ${p.name}',
            stat: store.goalStat(p.from, p.to),
          ),
        const SectionHeader('Продуктивность', subtitle: 'Активные / выполненные / в архиве'),
        if (store.tasks.isEmpty)
          const EmptyHint('Пока нет задач для диаграммы')
        else
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: [
                  if (active > 0)
                    PieChartSectionData(
                      value: active.toDouble(),
                      color: AppTheme.accent,
                      title: '$active',
                      radius: 52,
                      titleStyle: const TextStyle(
                          color: AppTheme.bg, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  if (done > 0)
                    PieChartSectionData(
                      value: done.toDouble(),
                      color: AppTheme.done,
                      title: '$done',
                      radius: 52,
                      titleStyle: const TextStyle(
                          color: AppTheme.bg, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  if (archived > 0)
                    PieChartSectionData(
                      value: archived.toDouble(),
                      color: AppTheme.textDim,
                      title: '$archived',
                      radius: 52,
                      titleStyle: const TextStyle(
                          color: AppTheme.bg, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                ],
              ),
            ),
          ),
        if (store.tasks.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LegendDot(color: AppTheme.accent, label: 'Активные'),
                _LegendDot(color: AppTheme.done, label: 'Выполненные'),
                _LegendDot(color: AppTheme.textDim, label: 'В архиве'),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final PeriodStat stat;
  const _ProgressRow({required this.label, required this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$label: ${stat.percent}% (${stat.done}/${stat.total})'
                  '${stat.missed > 0 ? ' · пропущено: ${stat.missed}' : ''}',
                  style: const TextStyle(color: AppTheme.text, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: stat.ratio,
            minHeight: 7,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

/// Бар дней ежедневной задачи в дереве связей: отметка за каждый
/// день интервала задачи (год — 365 отметок). Зелёная галочка —
/// успешный день, красный крест — пропущенный, синяя заливка —
/// выходной, серый контур — день ещё не наступил. Справа — счёт
/// дней и процент (дублирует количество отметок).
class _DailyDaysBar extends StatelessWidget {
  final Task task;
  final AppStore store;
  const _DailyDaysBar({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final days = store.dailyDayBar(task);
    final done = days.where((d) => d.done == true).length;
    final missed = days.where((d) => d.done == false).length;
    final pct = days.isEmpty ? 0 : (done * 100 / days.length).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.repeat, size: 13, color: AppTheme.done),
            const SizedBox(width: 8),
            Expanded(
              child: Text(task.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textDim)),
            ),
            const SizedBox(width: 6),
            Text('$done/${days.length} дн. · $pct%',
                style:
                    const TextStyle(fontSize: 10, color: AppTheme.textDim)),
          ],
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [for (final d in days) _dayCell(d.done)],
          ),
        ),
        if (missed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('пропущено дней: $missed',
                style:
                    const TextStyle(fontSize: 10, color: AppTheme.danger)),
          ),
      ],
    );
  }

  Widget _dayCell(bool? done) {
    final Widget? mark;
    final Color? fill;
    final Color border;
    if (done == true) {
      fill = AppTheme.done;
      border = AppTheme.done;
      mark = const Icon(Icons.check, size: 8, color: AppTheme.bg);
    } else if (done == false) {
      fill = AppTheme.critical;
      border = AppTheme.critical;
      mark = const Icon(Icons.close, size: 8, color: Colors.white);
    } else {
      // null: выходной (синяя заливка) или будущий день (контур).
      fill = null;
      border = AppTheme.textDim.withOpacity(0.4);
      mark = null;
    }
    return Container(
      width: 11,
      height: 11,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border, width: 1),
      ),
      child: mark,
    );
  }
}

/// Бар дней закреплённой (пин) задачи: отметка за каждый день —
/// данные из посуточного журнала pin_log. Зелёная галочка — выполнена,
/// красный крест — пропущена, серый контур — день не наступил
/// или «выходной».
class _PinDaysBar extends StatelessWidget {
  final Task task;
  final AppStore store;
  const _PinDaysBar({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final days = store.pinDayBar(task);
    final done = days.where((d) => d.done == true).length;
    final missed = days.where((d) => d.done == false).length;
    final pct = days.isEmpty ? 0 : (done * 100 / days.length).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.push_pin, size: 13, color: AppTheme.daily),
            const SizedBox(width: 8),
            Expanded(
              child: Text(task.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textDim)),
            ),
            const SizedBox(width: 6),
            Text('$done/${days.length} дн. · $pct%',
                style:
                    const TextStyle(fontSize: 10, color: AppTheme.textDim)),
          ],
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [for (final d in days) _pinDayCell(d.done)],
          ),
        ),
        if (missed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('пропущено дней: $missed',
                style:
                    const TextStyle(fontSize: 10, color: AppTheme.danger)),
          ),
      ],
    );
  }

  static Widget _pinDayCell(bool? done) {
    final Widget? mark;
    final Color? fill;
    final Color border;
    if (done == true) {
      fill = AppTheme.done;
      border = AppTheme.done;
      mark = const Icon(Icons.check, size: 8, color: AppTheme.bg);
    } else if (done == false) {
      fill = AppTheme.critical;
      border = AppTheme.critical;
      mark = const Icon(Icons.close, size: 8, color: Colors.white);
    } else {
      fill = null;
      border = AppTheme.textDim.withOpacity(0.4);
      mark = null;
    }
    return Container(
      width: 11,
      height: 11,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border, width: 1),
      ),
      child: mark,
    );
  }
}

/// Дерево связей: блоки годового плана -> привязанные задачи.
/// Привязка делается из меню задачи («С каким блоком связать?»)
/// или голосом через ассистента («свяжи задачу X с блоком Y»).
/// Задачи без привязки автоматически собираются в блоке «Попутные»;
/// как только задачу распределяют в блок — она переквалифицируется
/// и переходит в него из «Попутных».
class _LinkTree extends StatefulWidget {
  const _LinkTree();

  @override
  State<_LinkTree> createState() => _LinkTreeState();
}

class _LinkTreeState extends State<_LinkTree> {
  /// Раскрытые ежедневные серии (тап по строке показывает бар дней).
  final Set<String> _expanded = {};

  /// Строки задач блока. Ежедневные серии не дублируются: одна строка
  /// на серию; тап раскрывает/сворачивает бар дней с отметками
  /// «выполнено/пропущено». Одинаковые дубли задач не показываются.
  List<Widget> _taskRows(AppStore store, Goal g) {
    final blockId = g.externalId.substring(6);
    final all = store.tasks.where((t) => t.block == blockId).toList();
    final rows = <Widget>[];
    final seenDaily = <String>{};
    final seenPlain = <String>{};
    for (final t in all) {
      final daily = t.recurDaily || t.horizon == 'daily';
      if (daily) {
        final key = '${t.title}|${t.externalId}';
        if (!seenDaily.add(key)) continue;
        final series = all
            .where((x) => '${x.title}|${x.externalId}' == key)
            .toList()
          ..sort((a, b) => (a.deadline ?? a.createdAt)
              .compareTo(b.deadline ?? b.createdAt));
        // Представитель серии: ближайшая невыполненная, иначе последняя.
        final rep = series.firstWhere((x) => !x.isDone,
            orElse: () => series.last);
        final open = _expanded.contains(key);
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (open) {
                    _expanded.remove(key);
                  } else {
                    _expanded.add(key);
                  }
                }),
                child: Row(
                  children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 13, color: AppTheme.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${rep.title} · ежедневно',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textDim)),
                    ),
                  ],
                ),
              ),
              if (open) _DailyDaysBar(task: rep, store: store),
            ],
          ),
        ));
      } else if (t.isPinned) {
        // Закреплённая ежедневная задача: одна строка на задачу,
        // тап раскрывает посуточный бар отметок (pin_log) —
        // видно, выполнена она или нет в каждый из дней.
        final key = 'pin|${t.id}';
        if (!seenPlain.add(key)) continue;
        final open = _expanded.contains(key);
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (open) {
                    _expanded.remove(key);
                  } else {
                    _expanded.add(key);
                  }
                }),
                child: Row(
                  children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 13, color: AppTheme.textDim),
                    const SizedBox(width: 8),
                    Icon(
                      t.isDone
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 13,
                      color: t.isDone ? AppTheme.done : AppTheme.textDim,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${t.title} · ежедневная (закреп)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textDim)),
                    ),
                  ],
                ),
              ),
              if (open) _PinDaysBar(task: t, store: store),
            ],
          ),
        ));
      } else {
        if (!seenPlain.add(t.title)) continue;
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Row(
            children: [
              Icon(
                t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 13,
                color: t.isDone ? AppTheme.done : AppTheme.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textDim)),
              ),
            ],
          ),
        ));
      }
    }
    return rows;
  }

  /// Строки блока «Попутные»: задачи без привязки к какому-либо блоку
  /// (block/цель/связь пусты). Ежедневные серии и закреплённые
  /// раскрываются с барами дней, как в обычных блоках. При распределении
  /// задачи в блок она автоматически уходит из «Попутных».
  List<Widget> _poputRows(AppStore store) {
    final all = store.activeTasks
        .where((t) =>
            t.block.isEmpty && t.goalId.isEmpty && t.linkedBlock.isEmpty)
        .toList();
    final rows = <Widget>[];
    final seen = <String>{};
    for (final t in all) {
      final daily = t.recurDaily || t.horizon == 'daily';
      if (daily) {
        final key = 'poput-daily|${t.title}|${t.externalId}';
        if (!seen.add(key)) continue;
        final open = _expanded.contains(key);
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (open) {
                    _expanded.remove(key);
                  } else {
                    _expanded.add(key);
                  }
                }),
                child: Row(
                  children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 13, color: AppTheme.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${t.title} · ежедневно',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textDim)),
                    ),
                  ],
                ),
              ),
              if (open) _DailyDaysBar(task: t, store: store),
            ],
          ),
        ));
      } else if (t.isPinned) {
        final key = 'poput-pin|${t.id}';
        if (!seen.add(key)) continue;
        final open = _expanded.contains(key);
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (open) {
                    _expanded.remove(key);
                  } else {
                    _expanded.add(key);
                  }
                }),
                child: Row(
                  children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 13, color: AppTheme.textDim),
                    const SizedBox(width: 8),
                    Icon(
                      t.isDone
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 13,
                      color: t.isDone ? AppTheme.done : AppTheme.textDim,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${t.title} · ежедневная (закреп)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textDim)),
                    ),
                  ],
                ),
              ),
              if (open) _PinDaysBar(task: t, store: store),
            ],
          ),
        ));
      } else {
        if (!seen.add(t.title)) continue;
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Row(
            children: [
              Icon(
                t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 13,
                color: t.isDone ? AppTheme.done : AppTheme.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textDim)),
              ),
            ],
          ),
        ));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final blocks = store.blockGoals().where((g) => !g.isArchived).toList();
    // Непривязанные = без блока импорта, без цели и без ручной связи.
    final unlinked = store.activeTasks
        .where((t) =>
            t.block.isEmpty && t.goalId.isEmpty && t.linkedBlock.isEmpty)
        .length;
    // Дерево видно, если есть блоки ИЛИ непривязанные задачи
    // (они соберутся в блоке «Попутные»).
    if (blocks.isEmpty && unlinked == 0) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.accent, width: 1),
        ),
        child: ExpansionTile(
          leading:
              const Icon(Icons.account_tree_outlined, color: AppTheme.accent),
          title: const Text('Дерево связей',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Блоков: ${blocks.length}'
            '${unlinked > 0 ? ' · непривязанных задач: $unlinked' : ''}',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final g in blocks) ...[
              Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              ..._taskRows(store, g),
              const SizedBox(height: 8),
            ],
            // «Попутные»: все задачи без привязки к блоку собираются
            // здесь автоматически. Распределили задачу в блок — она
            // переквалифицируется и переходит в свой блок.
            if (unlinked > 0) ...[
              const Row(
                children: [
                  Icon(Icons.alt_route, size: 16, color: AppTheme.textDim),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Попутные',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDim)),
                  ),
                ],
              ),
              ..._poputRows(store),
              const Padding(
                padding: EdgeInsets.only(left: 24, top: 4),
                child: Text(
                    'Распределить: меню задачи → «С каким блоком связать?»',
                    style: TextStyle(fontSize: 10, color: AppTheme.textDim)),
              ),
              const SizedBox(height: 8),
            ],
            // Визуализация связей: нити между блоками (число — сколько
            // задач одного блока связано с другим). Блоки расположены
            // по кругу так, чтобы нити пересекались минимально.
            if (store.blockLinks().isNotEmpty) ...[
              const Divider(height: 20),
              const Text('Нити связей между блоками',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textDim,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _LinkGraph(store: store),
            ],
          ],
        ),
      ),
    );
  }
}

/// Визуализация дерева связей: блоки по кругу, связи — кривые линии
/// (безье) между ними. Число на нити — количество связанных задач.
/// Порядок блоков на круге подбирается жадно так, чтобы связанные
/// блоки стояли рядом и нити пересекались минимально.
class _LinkGraph extends StatelessWidget {
  final AppStore store;
  const _LinkGraph({required this.store});

  /// Жадное упорядочивание: следующим ставим блок, сильнее всего
  /// связанный с уже размещёнными (начинаем с самого связанного).
  static List<String> _orderBlocks(List<String> ids, Map<String, int> links) {
    int w(String a, String b) =>
        links['$a|$b'] ?? links['$b|$a'] ?? 0;
    int degree(String id) =>
        ids.fold(0, (s, other) => s + (other == id ? 0 : w(id, other)));
    final remaining = ids.toSet();
    final res = <String>[];
    var current = ids.reduce((a, b) => degree(a) >= degree(b) ? a : b);
    while (remaining.isNotEmpty) {
      res.add(current);
      remaining.remove(current);
      if (remaining.isEmpty) break;
      current = remaining.reduce((a, b) {
        final wa = w(a, res.last) * 4 +
            res.fold(0, (s, p) => s + w(a, p)) +
            degree(a);
        final wb = w(b, res.last) * 4 +
            res.fold(0, (s, p) => s + w(b, p)) +
            degree(b);
        return wa >= wb ? a : b;
      });
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = store.blockGoals();
    final links = store.blockLinks();
    final byId = <String, dynamic>{};
    for (final g in blocks) {
      byId[g.externalId.substring(6)] = g;
    }
    // Блоки, участвующие в связях.
    final usedIds = <String>{};
    for (final key in links.keys) {
      final parts = key.split('|');
      if (byId.containsKey(parts[0])) usedIds.add(parts[0]);
      if (byId.containsKey(parts[1])) usedIds.add(parts[1]);
    }
    if (usedIds.isEmpty) {
      return const Text('Связей пока нет. Привяжите задачу к блоку: '
          'Задачи → меню задачи → «С каким блоком связать?».',
          style: TextStyle(color: AppTheme.textDim, fontSize: 12));
    }
    final ordered = _orderBlocks(usedIds.toList(), links);

    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        const h = 300.0;
        final center = Offset(w / 2, h / 2 - 8);
        final radius = math.min(w, h) / 2 - 52;
        final pos = <String, Offset>{};
        for (var i = 0; i < ordered.length; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / ordered.length;
          pos[ordered[i]] = Offset(
              center.dx + radius * math.cos(a),
              center.dy + radius * math.sin(a));
        }
        return SizedBox(
          height: h,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ThreadsPainter(links: links, positions: pos),
                ),
              ),
              for (final id in ordered)
                Positioned(
                  left: pos[id]!.dx - 36,
                  top: pos[id]!.dy - 24,
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.7)),
                        ),
                        child: Center(
                          child: blockIconWidget(
                            (byId[id].icon ?? '').toString(),
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (byId[id].title ?? id).toString(),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textDim),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Рисует нити-связи: для каждой пары блоков — столько изогнутых
/// линий, сколько связано задач (несколько нитей расходятся веером,
/// чтобы не сливаться). Линии изогнуты к центру — так они реже
/// пересекают соседние нити.
class _ThreadsPainter extends CustomPainter {
  final Map<String, int> links;
  final Map<String, Offset> positions;
  const _ThreadsPainter({required this.links, required this.positions});

  @override
  void paint(Canvas canvas, Size size) {
    links.forEach((key, count) {
      final parts = key.split('|');
      final a = positions[parts[0]];
      final b = positions[parts[1]];
      if (a == null || b == null) return;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final center = Offset(size.width / 2, size.height / 2 - 8);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppTheme.accentSoft.withOpacity(0.55);
      for (var k = 0; k < count; k++) {
        // Разносим параллельные нити: смещение перпендикулярно хорде.
        final dir = Offset(b.dx - a.dx, b.dy - a.dy);
        final len = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
        if (len == 0) continue;
        final normal = Offset(-dir.dy / len, dir.dx / len);
        final spread = (k - (count - 1) / 2) * 7.0;
        // Изгиб к центру круга (умеренный) + разнос параллельных нитей.
        final ctrl = Offset(
          mid.dx + (center.dx - mid.dx) * 0.25 + normal.dx * spread * 2,
          mid.dy + (center.dy - mid.dy) * 0.25 + normal.dy * spread * 2,
        );
        final path = Path()
          ..moveTo(a.dx + normal.dx * spread, a.dy + normal.dy * spread)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy,
              b.dx + normal.dx * spread, b.dy + normal.dy * spread);
        canvas.drawPath(path, paint);
      }
      // Число связанных задач в середине хорды.
      final tp = TextPainter(
        text: TextSpan(
          text: '$count',
          style: const TextStyle(
              color: AppTheme.text,
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawCircle(
          mid, 8, Paint()..color = AppTheme.bg.withOpacity(0.85));
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
    });
  }

  @override
  bool shouldRepaint(_ThreadsPainter old) {
    if (old.links.length != links.length ||
        old.positions.length != positions.length) {
      return true;
    }
    // Число над нитью = количество связанных задач между блоками;
    // при его изменении (та же пара блоков, но больше/меньше связей)
    // перерисовываем — иначе цифра «застывала».
    for (final e in links.entries) {
      if (old.links[e.key] != e.value) return true;
    }
    return false;
  }
}

/// Диалог полной выгрузки: все задачи, цели, события, заметки, шаги,
/// журнал и посуточные отметки закрепов одним JSON. После переустановки
/// (или на другом телефоне) этот файл загружается на экране «Стратегия»
/// и восстанавливает всё 1-в-1: ежедневные остаются ежедневными.
void _showFullExport(BuildContext context) {
  final data = context.read<AppStore>().buildFullExport();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Выгрузка всех данных'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(data,
              style: const TextStyle(fontSize: 11, color: AppTheme.text)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: data));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Все данные скопированы. После переустановки загрузите '
                        'файл на экране «Стратегия» — всё восстановится 1-в-1')),
              );
            }
          },
          child: const Text('Копировать всё'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('Сохранить в файл'),
          onPressed: () async {
            // Системный диалог: пользователь сам выбирает папку,
            // файл сохраняется целиком одним .json.
            final path = await FilePicker.platform.saveFile(
              dialogTitle: 'Сохранить выгрузку всех данных',
              fileName: 'planner_export.json',
              bytes: Uint8List.fromList(utf8.encode(data)),
            );
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(path != null
                      ? 'Файл сохранён: $path'
                      : 'Сохранение отменено')));
            }
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// Диалог экспорта отчёта: просмотр и копирование в буфер обмена.
/// Отчёт нужен для аудита: при следующем планировании видно,
/// сколько времени реально уходит на похожие действия.
void _showReport(BuildContext context) {
  final report = context.read<AppStore>().buildReport();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Отчёт'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(report,
              style: const TextStyle(fontSize: 12, color: AppTheme.text)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Отчёт скопирован в буфер обмена')),
              );
            }
          },
          child: const Text('Копировать'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('Сохранить в файл'),
          onPressed: () async {
            // Отчёт — целиком одним .txt в выбранную пользователем папку.
            final path = await FilePicker.platform.saveFile(
              dialogTitle: 'Сохранить отчёт',
              fileName: 'planner_report.txt',
              bytes: Uint8List.fromList(utf8.encode(report)),
            );
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(path != null
                      ? 'Файл сохранён: $path'
                      : 'Сохранение отменено')));
            }
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}
