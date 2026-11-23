/// Экран «Запланировать на завтра» (иконка между зонтиком и
/// колокольчиком на экране «Сегодня»).
/// Список задач с дедлайном на завтра + быстрое добавление:
/// добавленная здесь задача сразу получает дедлайн завтрашнего дня
/// и появляется в календаре на следующий день.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'common.dart';
import 'edit_dialogs.dart';
import 'tasks_screen.dart';

class TomorrowScreen extends StatefulWidget {
  const TomorrowScreen({super.key});

  @override
  State<TomorrowScreen> createState() => _TomorrowScreenState();
}

class _TomorrowScreenState extends State<TomorrowScreen> {
  final _quickAdd = TextEditingController();

  static DateTime get _tomorrow {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  Future<void> _addQuick(AppStore store) async {
    final title = _quickAdd.text.trim();
    if (title.isEmpty) return;
    _quickAdd.clear();
    final d = _tomorrow;
    await store.addTask(Task(
      title: title,
      deadline: DateTime(d.year, d.month, d.day, 10),
    ));
  }

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final tomorrow = _tomorrow;
    final tasks = store.activeTasks
        .where((t) => t.deadline != null && isSameDay(t.deadline!, tomorrow))
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    final events = store.eventsForDay(tomorrow);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Запланировать на завтра'),
            Text(fmtDate(tomorrow),
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDim,
                    fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (events.isNotEmpty) const SectionHeader('События завтра'),
                for (final e in events)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: eventPrioritySide(e)),
                    child: ListTile(
                      leading:
                          const Icon(Icons.event, color: AppTheme.accent),
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
                const SectionHeader('Задачи на завтра'),
                if (tasks.isEmpty)
                  const EmptyHint(
                      'На завтра пока ничего не запланировано — '
                      'добавьте задачу ниже')
                else
                  // В меню каждой задачи (три точки) — «Выполнить
                  // сегодня»: задача отмечается выполненной прямо
                  // сейчас и уходит в архив сегодняшним днём.
                  for (final t in tasks) TaskTile(task: t, showDoneToday: true),
              ],
            ),
          ),
          // Быстрое добавление задачи на завтра: дедлайн ставится
          // автоматически — задача сразу видна в календаре на
          // следующий день.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAdd,
                    decoration: const InputDecoration(
                        hintText: 'Задача на завтра...'),
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
                    decoration: const BoxDecoration(
                        color: AppTheme.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: AppTheme.bg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
