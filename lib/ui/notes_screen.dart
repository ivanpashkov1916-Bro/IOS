/// Экран «Заметки»: поиск, кнопка «Архив», CRUD, архивация вместо удаления.
/// Сверху в списке — записи дневника (итоги дня, наблюдения, практики),
/// значок дневника в шапке открывает точку входа.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'archive_screen.dart';
import 'common.dart';
import 'diary_screen.dart';
import 'edit_dialogs.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.activeNotes;
    final q = _query.toLowerCase();
    final items = q.isEmpty
        ? all
        : all
            .where((n) => n.title.toLowerCase().contains(q) || n.text.toLowerCase().contains(q))
            .toList();
    // Записи дневника — в общем списке, поиск идёт и по их тексту.
    final diary = store.diaryEntries
        .where((e) =>
            q.isEmpty ||
            e.title.toLowerCase().contains(q) ||
            e.text.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.day.compareTo(a.day));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Заметки'),
            Text('${all.length} заметок · ${store.diaryEntries.length} записей дневника',
                style: const TextStyle(fontSize: 12, color: AppTheme.textDim, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined, color: AppTheme.accent),
            tooltip: 'Дневник',
            onPressed: () => showDiaryEntryPoint(context),
          ),
          const FontScaleButton(),
          const AlertBell(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(hintText: 'Поиск...'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.card,
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Архив'),
                ),
              ],
            ),
          ),
          Expanded(
            child: (items.isEmpty && diary.isEmpty)
                ? const EmptyHint('Нет заметок. Добавьте первую!')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: diary.length + items.length,
                    itemBuilder: (ctx, i) {
                      if (i < diary.length) {
                        return DiaryEntryCard(entry: diary[i]);
                      }
                      final n = items[i - diary.length];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          onTap: () => showNoteEditor(context, store, note: n),
                          title: Text(n.title),
                          subtitle: Text(
                            [
                              if (n.text.isNotEmpty)
                                n.text.length > 60 ? '${n.text.substring(0, 60)}…' : n.text,
                              fmtDate(n.createdAt),
                            ].join(' · '),
                            style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  n.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                  size: 20,
                                  color: n.isPinned ? AppTheme.daily : AppTheme.textDim,
                                ),
                                tooltip: n.isPinned ? 'Открепить' : 'Закрепить в «Ежедневные»',
                                onPressed: () => store.togglePinNote(n.id),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => showNoteEditor(context, store, note: n),
                              ),
                              IconButton(
                                icon: const Icon(Icons.archive_outlined, size: 20),
                                tooltip: 'В архив',
                                onPressed: () {
                                  store.archiveNote(n.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Заметка в архиве')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showNoteEditor(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }
}
