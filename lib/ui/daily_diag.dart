/// Диагностика ежедневных задач — для разбора задвоений.
/// Ключевой раздел — СВЕРКА: что реально показывает экран «Сегодня»
/// и что реально рисует календарь на каждый день (каждый кружок —
/// с источником: серия, привычка-цель, разовая задача, закреплённая).
/// Плюс: активные ежедневные, дубли названий и id, архивные,
/// журнал событий. Ничего никуда не отправляется: текст копируется
/// по кнопке пользователя. Открывается с экрана «Календарь» и из
/// настроек ассистента.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/diag_log.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';

bool _isDaily(Task t) => t.recurDaily || t.horizon == 'daily';

String _fmt(DateTime? d) => d == null ? '—' : fmtDateTime(d);

/// Названия задач могут содержать переводы строк — в отчёте они
/// ломают строки, заменяем на пробел.
String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Текст отчёта по ежедневным задачам.
String buildDailyDiagReport(AppStore store) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final b = StringBuffer()
    ..writeln('# Диагностика ежедневных задач')
    ..writeln('Время: $now')
    ..writeln('Схема БД: 17')
    ..writeln();

  final all = store.tasks;
  final active = all.where((t) => !t.isArchived && !t.purged).toList();
  final archived = all.where((t) => t.isArchived || t.purged).toList();
  b
    ..writeln('Всего задач в БД: ${all.length}')
    ..writeln('Активных: ${active.length} · в архиве: ${archived.length}')
    ..writeln();

  // ================= СВЕРКА «СЕГОДНЯ» ↔ «КАЛЕНДАРЬ» =================
  final todayTasks = store.tasksForDay(now);
  final todayDaily = todayTasks.where(_isDaily).length;
  final todayPinned =
      todayTasks.where((t) => t.isPinned && !_isDaily(t)).length;
  final todayPlain = todayTasks.length - todayDaily - todayPinned;
  final cps = store.calendarCheckpointDetails(now);
  int cnt(String k) => cps.where((c) => c.kind == k).length;
  final seriesToday = cnt('daily');
  final habitsToday = cnt('habit');
  final pinnedToday = cnt('pinned');
  final oneOffToday =
      cnt('key') + cnt('medium') + cnt('short') + cnt('plain');

  b
    ..writeln('## СВЕРКА «СЕГОДНЯ» ↔ «КАЛЕНДАРЬ» (${fmtDate(today)})')
    ..writeln('Экран «Сегодня» показывает задач: ${todayTasks.length} '
        '(ежедневных: $todayDaily, закреплённых: $todayPinned, '
        'разовых/просроченных: $todayPlain)')
    ..writeln('Календарь на сегодня рисует кружков: ${cps.length}:')
    ..writeln('  · ежедневные серии задач: $seriesToday')
    ..writeln('  · привычки-цели (recurDaily): $habitsToday'
        '${habitsToday > 0 ? ' ← НЕ видны на «Сегодня» как задачи!' : ''}')
    ..writeln('  · разовые задачи с дедлайном сегодня: $oneOffToday')
    ..writeln('  · закреплённые с дедлайном сегодня: $pinnedToday');
  if (habitsToday > 0 || seriesToday != todayDaily) {
    b.writeln('РАЗНИЦА объясняется: '
        '${habitsToday > 0 ? '+$habitsToday кружок(а) от привычек-целей; ' : ''}'
        '${seriesToday != todayDaily ? 'серий $seriesToday, а ежедневных задач на «Сегодня» $todayDaily (часть серий выполнена — активный экземпляр завтрашний)' : ''}');
  }
  b.writeln('Источники кружков сегодня:');
  for (final c in cps) {
    b.writeln('  · [${c.kind}${c.done ? ' ✓' : ''}] ${_oneLine(c.label)}');
  }
  b.writeln();

  // ================= Календарь по дням текущего месяца =================
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  b.writeln('## Календарь по дням (${two(now.month)}.${now.year}): '
      'кружки (серии/привычки/разовые/закрепл.) · задач дня');
  for (var d = 1; d <= daysInMonth; d++) {
    final day = DateTime(now.year, now.month, d);
    final dc = store.calendarCheckpointDetails(day);
    if (dc.isEmpty) continue;
    int k(String kk) => dc.where((c) => c.kind == kk).length;
    final oneOffs = k('key') + k('medium') + k('short') + k('plain');
    final dt = store.tasksForDay(day).length;
    final ev = store.eventsForDay(day).length;
    b.writeln('${two(d)}.${two(now.month)} — ${dc.length} '
        '(${k('daily')}/${k('habit')}/$oneOffs/${k('pinned')})'
        ' · задач: $dt${ev > 0 ? ' · событий: $ev' : ''}');
  }
  b.writeln();

  // ================= Ежедневные серии (кружок КАЖДЫЙ день) =================
  final series = <String, List<Task>>{};
  for (final t in all) {
    if (_isDaily(t)) {
      series.putIfAbsent('${t.title}|${t.externalId}', () => []).add(t);
    }
  }
  b.writeln('## Ежедневные серии: ${series.length} '
      '(каждая рисует кружок КАЖДЫЙ день интервала)');
  for (final e in series.entries) {
    final list = e.value;
    var start = list.first.createdAt;
    DateTime? latestDl;
    for (final t in list) {
      if (t.createdAt.isBefore(start)) start = t.createdAt;
      final dl = t.deadline;
      if (dl != null && (latestDl == null || dl.isAfter(latestDl!))) {
        latestDl = dl;
      }
    }
    final startDay = DateTime(start.year, start.month, start.day);
    var endDay = startDay.add(const Duration(days: 89));
    if (latestDl != null) {
      final dlDay =
          DateTime(latestDl!.year, latestDl!.month, latestDl!.day);
      if (dlDay.isAfter(endDay)) endDay = dlDay;
    }
    final act = list.where((t) => !t.isArchived && !t.purged).length;
    final title = _oneLine(e.key.substring(0, e.key.indexOf('|')));
    b.writeln('· «$title» — интервал ${fmtDate(startDay)}…${fmtDate(endDay)}, '
        'экземпляров: ${list.length}, активных: $act'
        '${act > 1 ? '  ← НЕСКОЛЬКО АКТИВНЫХ!' : ''}');
  }
  if (series.isEmpty) b.writeln('(нет)');
  b.writeln();

  // ================= Привычки-цели =================
  final habits = store.goals
      .where((g) => g.recurDaily && !g.isArchived)
      .toList();
  b.writeln('## Ежедневные привычки-цели: ${habits.length} '
      '(тоже рисуют кружок каждый день)');
  for (final g in habits) {
    b.writeln('· «${_oneLine(g.title)}»');
  }
  if (habits.isEmpty) b.writeln('(нет)');
  b.writeln();

  // ================= Активные ежедневные =================
  final dailyActive = active.where(_isDaily).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  b.writeln('## Активные ежедневные задачи (${dailyActive.length})');
  for (final t in dailyActive) {
    b.writeln('· «${_oneLine(t.title)}» id=${t.id.substring(0, 8)} '
        'дедлайн=${_fmt(t.deadline)} создана=${_fmt(t.createdAt)} '
        'пин=${t.isPinned ? 'да' : 'нет'} '
        'родитель=${t.parentTaskId.isEmpty ? '—' : t.parentTaskId.substring(0, 8)} '
        'импорт=${t.importTag.isEmpty ? '—' : t.importTag} '
        'ext=${t.externalId.isEmpty ? '—' : t.externalId}');
  }
  if (dailyActive.isEmpty) b.writeln('(нет активных ежедневных задач)');
  b.writeln();

  // ================= Дубли названий и id =================
  final byTitle = <String, List<Task>>{};
  for (final t in dailyActive) {
    byTitle.putIfAbsent(t.title, () => []).add(t);
  }
  final dups = byTitle.entries.where((e) => e.value.length > 1).toList();
  b.writeln('## ДУБЛИ названий (активные ежедневные): ${dups.length}');
  for (final e in dups) {
    b.writeln('!! «${_oneLine(e.key)}» ×${e.value.length}');
    for (final t in e.value) {
      b.writeln('   id=${t.id.substring(0, 8)} создана=${_fmt(t.createdAt)} '
          'дедлайн=${_fmt(t.deadline)} '
          'импорт=${t.importTag.isEmpty ? '—' : t.importTag}');
    }
  }
  if (dups.isEmpty) b.writeln('(нет)');
  final byId = <String, int>{};
  for (final t in all) {
    byId[t.id] = (byId[t.id] ?? 0) + 1;
  }
  final idDups = byId.entries.where((e) => e.value > 1).toList();
  b.writeln('## ДУБЛИ id во всей таблице: ${idDups.length}');
  for (final e in idDups) {
    b.writeln('!! id=${e.key.substring(0, 8)} встречается ×${e.value}');
  }
  if (idDups.isEmpty) b.writeln('(нет)');
  b.writeln();

  // ================= Архивные ежедневные =================
  final dailyArch = archived.where(_isDaily).toList()
    ..sort(
        (a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt));
  b.writeln('## Последние архивные ежедневные (до 15)');
  for (final t in dailyArch.take(15)) {
    b.writeln('· «${_oneLine(t.title)}» id=${t.id.substring(0, 8)} '
        'выполнена=${_fmt(t.doneAt)} создана=${_fmt(t.createdAt)} '
        'архив=${t.isArchived} удалена=${t.purged}');
  }
  if (dailyArch.isEmpty) b.writeln('(пока нет)');
  b.writeln();

  // ================= Журнал =================
  b.writeln('## Журнал событий (последние ${DiagLog.lines.length})');
  if (DiagLog.lines.isEmpty) {
    b.writeln('(событий пока нет — журнал пишется с этой версии)');
  } else {
    for (final l in DiagLog.lines) {
      b.writeln(l);
    }
  }
  return b.toString();
}

/// Диалог с отчётом и кнопкой «Копировать».
Future<void> showDailyDiagDialog(BuildContext context, AppStore store) async {
  final report = buildDailyDiagReport(store);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ежедневные задачи: диагностика',
          style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(report,
              style: TextStyle(fontSize: 11, color: AppTheme.text)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy_all, size: 16),
          label: const Text('Копировать'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Отчёт скопирован — пришлите его Мане')));
            }
          },
        ),
      ],
    ),
  );
}
