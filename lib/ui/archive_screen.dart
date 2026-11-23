/// Экран «Архив»: все заархивированные сущности + восстановление
/// и удаление навсегда (с подтверждением). При удалении задачи
/// отдельно спрашивается, удалять ли её вместе с деревом связей
/// (шаги и ресурсы): отметки прошлых дней в календаре и прогресс
/// блока сохраняются в любом случае.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'common.dart';
import 'edit_dialogs.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final notes = store.archivedNotes;
    final tasks = store.archivedTasks;
    final goals = store.archivedGoals;
    final events = store.archivedEvents;
    final empty = notes.isEmpty && tasks.isEmpty && goals.isEmpty && events.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: empty
          ? const EmptyHint('Архив пуст')
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (tasks.isNotEmpty) const SectionHeader('Задачи'),
                for (final t in tasks)
                  _ArchiveTile(
                    title: t.title,
                    subtitle: [
                      if (t.isDone) 'выполнена',
                      if (t.doneAt != null) fmtDate(t.doneAt!),
                    ].join(' · '),
                    onRestore: () => store.restoreTask(t.id),
                    onDelete: () => store.deleteTaskForever(t.id),
                    // У задачи — свой диалог: «удалить вместе с деревом
                    // связей?» (см. _deleteTaskFlow).
                    onDeletePressed: (ctx) => _deleteTaskFlow(ctx, store, t),
                  ),
                if (goals.isNotEmpty) const SectionHeader('Цели'),
                for (final g in goals)
                  _ArchiveTile(
                    title: g.title,
                    subtitle: g.isDone ? 'достигнута' : 'в архиве',
                    onRestore: () => store.restoreGoal(g.id),
                    onDelete: () => store.deleteGoalForever(g.id),
                  ),
                if (notes.isNotEmpty) const SectionHeader('Заметки'),
                for (final n in notes)
                  _ArchiveTile(
                    title: n.title,
                    subtitle: fmtDate(n.createdAt),
                    onRestore: () => store.restoreNote(n.id),
                    onDelete: () => store.deleteNoteForever(n.id),
                  ),
                if (events.isNotEmpty) const SectionHeader('События'),
                for (final e in events)
                  _ArchiveTile(
                    title: e.title,
                    subtitle: fmtDateTime(e.start),
                    onRestore: () => store.restoreEvent(e.id),
                    onDelete: () => store.deleteEventForever(e.id),
                  ),
              ],
            ),
    );
  }
}

/// Удаление задачи из архива: спрашиваем, удалить ли задачу вместе
/// с деревом связей (шаги и ресурсы). В ОБОИХ случаях отметки прошлых
/// дней в календаре и прогресс блока НЕ откатываются — удаляются
/// только сами связи.
Future<void> _deleteTaskFlow(
    BuildContext context, AppStore store, Task t) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить навсегда?'),
      content: Text(
          'Удалить задачу «${t.title}» вместе с деревом связей '
          '(шаги и ресурсы)?\n\nОтметки прошлых дней в календаре '
          'и прогресс блока сохранятся в любом случае.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'task'),
          child: const Text('Нет, только задачу'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.warn),
          onPressed: () => Navigator.pop(ctx, 'tree'),
          child: const Text('Да, полностью'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  await store.deleteTaskForever(t.id, withTree: choice == 'tree');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Удалено навсегда')),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;

  /// Если задано — кнопка удаления вызывает этот обработчик вместо
  /// стандартного подтверждения (он сам показывает свои диалоги).
  final Future<void> Function(BuildContext context)? onDeletePressed;

  const _ArchiveTile({
    required this.title,
    required this.subtitle,
    required this.onRestore,
    required this.onDelete,
    this.onDeletePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: AppTheme.textDim)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.unarchive_outlined, size: 20, color: AppTheme.accent),
              tooltip: 'Вернуть из архива',
              onPressed: () async {
                await onRestore();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Возвращено из архива')),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined, size: 20, color: AppTheme.warn),
              tooltip: 'Удалить навсегда',
              onPressed: () async {
                // Для задач — специальный диалог (дерево связей),
                // для остальных — стандартное подтверждение.
                if (onDeletePressed != null) {
                  await onDeletePressed!(context);
                  return;
                }
                final ok = await confirmDeleteForever(context, title);
                if (!ok) return;
                await onDelete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Удалено навсегда')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
