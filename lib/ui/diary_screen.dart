/// Дневник: единая точка входа и все экраны записей.
///
/// Три ветки:
///  · «Итоги дня» — свободная запись, привязанная к дате; открывается
///    также со значка дневника на задачах «итоги дня» (по названию
///    или по флагу в редакторе задачи);
///  · «Практики» — семь пошаговых мастеров (экран practices_screen);
///  · «Дневник наблюдений» — сессия с собеседником-наблюдателем:
///    гибрид банка вопросов (обновляемого, в JSON-выгрузке) и активной
///    модели ассистента; промпт-психолог включён ТОЛЬКО здесь.
///
/// Все записи — DiaryEntry, видны на экране «Заметки», входят
/// в полную выгрузку/загрузку JSON.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/psy_service.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import 'edit_dialogs.dart';
import 'practices_screen.dart';

DiaryEntry? _findEntry(AppStore store, String id) {
  for (final e in store.diaryEntries) {
    if (e.id == id) return e;
  }
  return null;
}

/// Точка входа в дневник (значок на экране «Заметки» и на задачах
/// «итоги дня»): ручной выбор ветки.
Future<void> showDiaryEntryPoint(BuildContext context, {DateTime? day}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textDim.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Дневник',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.summarize_outlined, color: AppTheme.accent),
            title: const Text('Итоги дня'),
            subtitle: const Text('Свободная запись о дне',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              showDayReviewEditor(context, day: day);
            },
          ),
          ListTile(
            leading: const Icon(Icons.self_improvement_outlined, color: AppTheme.accent),
            title: const Text('Практики'),
            subtitle: const Text('Семь пошаговых практик в четырёх стилях',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PracticesScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.psychology_outlined, color: AppTheme.accent),
            title: const Text('Дневник наблюдений'),
            subtitle: const Text('Диалог с внимательным собеседником',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ObservationSessionScreen()));
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

/// Редактор «Итогов дня»: одна запись на дату. Если за этот день
/// уже есть итоги — открываем её на правку, а не плодим дубликаты.
Future<void> showDayReviewEditor(BuildContext context, {DateTime? day}) async {
  final store = context.read<AppStore>();
  final d = day ?? DateTime.now();
  DiaryEntry? existing;
  for (final e in store.diaryForDay(d)) {
    if (e.kind == 'day_review') {
      existing = e;
      break;
    }
  }
  final textC = TextEditingController(text: existing?.text ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Итоги дня · ${fmtDate(d)}',
          style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: textC,
          maxLines: 9,
          minLines: 6,
          autofocus: existing == null,
          decoration: const InputDecoration(
            hintText:
                'Как прошёл день? Что получилось, что нет? За что благодарен(на)?',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(existing == null ? 'Сохранить' : 'Обновить'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final text = textC.text.trim();
  if (text.isEmpty) return;
  if (existing != null) {
    existing.text = text;
    await store.updateDiaryEntry(existing);
  } else {
    await store.addDiaryEntry(DiaryEntry(
      kind: 'day_review',
      day: d,
      title: 'Итоги дня',
      text: text,
    ));
  }
  if (context.mounted) {
    SystemSound.play(SystemSoundType.click);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Запись в дневник за ${fmtDate(d)} сохранена')),
    );
  }
}

String _kindLabel(DiaryEntry e) {
  switch (e.kind) {
    case 'observation':
      return 'Дневник наблюдений';
    case 'practice':
      return 'Практика';
    default:
      return 'Итоги дня';
  }
}

IconData _kindIcon(DiaryEntry e) {
  switch (e.kind) {
    case 'observation':
      return Icons.psychology_outlined;
    case 'practice':
      return Icons.self_improvement_outlined;
    default:
      return Icons.summarize_outlined;
  }
}

/// Карточка записи дневника для общего списка на экране «Заметки»:
/// «запись в дневник такого-то числа, итоги дня».
class DiaryEntryCard extends StatelessWidget {
  final DiaryEntry entry;
  const DiaryEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final snippet = entry.text.length > 60
        ? '${entry.text.substring(0, 60)}…'
        : entry.text;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DiaryEntryViewScreen(entryId: entry.id)),
        ),
        leading: Icon(_kindIcon(entry), color: AppTheme.accent),
        title: Text(entry.title.isEmpty ? _kindLabel(entry) : entry.title),
        subtitle: Text(
          [
            if (snippet.isNotEmpty) snippet,
            'запись в дневник за ${fmtDate(entry.day)}',
          ].join(' · '),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
      ),
    );
  }
}

/// Полный просмотр записи дневника: правка текста и удаление.
class DiaryEntryViewScreen extends StatelessWidget {
  final String entryId;
  const DiaryEntryViewScreen({super.key, required this.entryId});

  Future<void> _editText(BuildContext context, AppStore store, DiaryEntry e) async {
    final c = TextEditingController(text: e.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.title.isEmpty ? _kindLabel(e) : e.title,
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            maxLines: 12,
            minLines: 6,
            decoration: const InputDecoration(hintText: 'Текст записи'),
          ),
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
    if (ok == true && c.text.trim().isNotEmpty) {
      e.text = c.text.trim();
      await store.updateDiaryEntry(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final e = _findEntry(store, entryId);
    if (e == null) {
      // Запись удалена — мягко закрываем экран.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(e.title.isEmpty ? _kindLabel(e) : e.title,
            style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Править',
            onPressed: () => _editText(context, store, e),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Удалить запись',
            onPressed: () async {
              final ok = await confirmDeleteForever(
                  context, '${_kindLabel(e)} за ${fmtDate(e.day)}');
              if (ok) await store.deleteDiaryEntry(e.id);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(
            [
              'запись в дневник за ${fmtDate(e.day)}',
              if (e.mood.isNotEmpty) 'настроение: ${e.mood}',
            ].join(' · '),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SelectableText(e.text,
              style: const TextStyle(fontSize: 15, height: 1.45)),
        ],
      ),
    );
  }
}

// ---------- Дневник наблюдений ----------

const _kMoods = <(String, IconData)>[
  ('тяжёлое', Icons.sentiment_very_dissatisfied_outlined),
  ('так себе', Icons.sentiment_dissatisfied_outlined),
  ('ровное', Icons.sentiment_neutral_outlined),
  ('хорошее', Icons.sentiment_satisfied_outlined),
  ('отличное', Icons.sentiment_very_satisfied_outlined),
];

/// Сессия дневника наблюдений: выбор настроения и формата, затем
/// диалог. «Короткая сессия» — 3–5 вопросов банка и мягкое
/// завершение; «Свободный диалог» — до кнопки «Завершить».
/// Движок — активный движок ассистента; при любой его ошибке
/// сессия продолжается на банке вопросов.
class ObservationSessionScreen extends StatefulWidget {
  const ObservationSessionScreen({super.key});

  @override
  State<ObservationSessionScreen> createState() =>
      _ObservationSessionScreenState();
}

class _ObservationSessionScreenState extends State<ObservationSessionScreen> {
  static const int _shortMin = 3; // после стольких ответов можно завершить
  static const int _shortMax = 5; // после стольких — завершаем сами

  final _inputC = TextEditingController();
  final _scrollC = ScrollController();
  final List<({bool fromUser, String text})> _msgs = [];
  final Set<String> _usedIds = {};

  String _engine = 'local';
  String _mood = '';
  String _format = ''; // '' — выбор, 'short' | 'free'
  int _answered = 0;
  bool _busy = false;
  bool _finished = false;
  // Режим «банк без модели» — по умолчанию ВКЛЮЧЁН (модель выкл):
  // на слабом железе встроенная модель вылетает по памяти, а банк
  // вопросов работает всегда. Включается вручную на экране старта.
  bool _useModel = false;

  @override
  void initState() {
    super.initState();
    PsyService.activeEngine().then((e) {
      if (mounted) setState(() => _engine = e);
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _useModel = p.getBool('psyUseModel') ?? false);
      }
    });
  }

  @override
  void dispose() {
    _inputC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) {
        _scrollC.animateTo(_scrollC.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _addMsg(bool fromUser, String text) {
    setState(() => _msgs.add((fromUser: fromUser, text: text)));
    _scrollDown();
  }

  Future<void> _askNext() async {
    final store = context.read<AppStore>();
    if (!_useModel) {
      // Банковый режим без модели: ничего не грузим в память, вылетов
      // нет. В свободном диалоге перед вопросом — тёплое «отражение»,
      // чтобы сохранить ощущение собеседника.
      final q = PsyService.pickBankQuestion(store, _usedIds);
      if (q == null) {
        // Банк исчерпан — мягко завершаем.
        await _finish();
        return;
      }
      _usedIds.add(q.id);
      _addMsg(false, _format == 'free'
          ? '${PsyService.reflection()}\n${q.text}'
          : q.text);
      return;
    }
    setState(() => _busy = true);
    final q = await PsyService.nextQuestion(store, _usedIds,
        engine: _engine, mood: _mood);
    if (!mounted) return;
    setState(() => _busy = false);
    if (q.text.isEmpty) {
      // Банк исчерпан и модель молчит — мягко завершаем.
      await _finish();
    } else {
      _addMsg(false, q.text);
    }
  }

  Future<void> _start(String format) async {
    setState(() => _format = format);
    _addMsg(false, _mood.isEmpty
        ? 'Хорошо, начнём. Что сейчас происходит внутри?'
        : 'Слышу: настроение «$_mood». Расскажи, что сейчас происходит внутри?');
    if (format == 'short') await _askNext();
  }

  Future<void> _send() async {
    final text = _inputC.text.trim();
    if (text.isEmpty || _busy || _finished) return;
    _inputC.clear();
    _addMsg(true, text);
    _answered++;
    if (_format == 'short') {
      if (_answered >= _shortMax) {
        await _finish();
        return;
      }
      await _askNext();
    } else if (!_useModel) {
      // Свободный диалог без модели: отражение + следующий вопрос банка.
      await _askNext();
    } else {
      final store = context.read<AppStore>();
      setState(() => _busy = true);
      final reply = await PsyService.reply(store,
          engine: _engine, history: List.of(_msgs), mood: _mood);
      if (!mounted) return;
      setState(() => _busy = false);
      if (reply != null) {
        _addMsg(false, reply);
      } else {
        // Модель недоступна — продолжаем вопросом из банка.
        await _askNext();
      }
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    final store = context.read<AppStore>();
    _addMsg(false, PsyService.softEnding);
    if (_msgs.any((m) => m.fromUser)) {
      final b = StringBuffer();
      if (_mood.isNotEmpty) b.writeln('Настроение в начале сессии: $_mood');
      b.writeln('Формат: ${_format == 'short' ? 'короткая сессия' : 'свободный диалог'}');
      for (final m in _msgs) {
        b.writeln(m.fromUser ? 'Я: ${m.text}' : 'Собеседник: ${m.text}');
      }
      await store.addDiaryEntry(DiaryEntry(
        kind: 'observation',
        day: DateTime.now(),
        title: 'Дневник наблюдений',
        text: b.toString().trim(),
        mood: _mood,
      ));
      if (mounted) {
        SystemSound.play(SystemSoundType.click);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сессия сохранена в дневнике')));
      }
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дневник наблюдений', style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz_outlined),
            tooltip: 'Банк вопросов',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PsyQuestionsScreen())),
          ),
          if (_format.isNotEmpty && !_finished)
            TextButton(
              onPressed: (_format == 'short' && _answered < _shortMin)
                  ? null
                  : _finish,
              child: const Text('Завершить'),
            ),
        ],
      ),
      body: _format.isEmpty ? _buildSetup() : _buildSession(),
    );
  }

  // --- Этап настройки: настроение + формат ---
  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Какое сейчас состояние?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final m in _kMoods)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    setState(() => _mood = _mood == m.$1 ? '' : m.$1);
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: _mood == m.$1
                              ? AppTheme.accent.withOpacity(0.22)
                              : AppTheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _mood == m.$1
                                ? AppTheme.accent
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Icon(m.$2,
                            size: 26,
                            color: _mood == m.$1
                                ? AppTheme.accent
                                : AppTheme.textDim),
                      ),
                      const SizedBox(height: 4),
                      Text(m.$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10,
                              color: _mood == m.$1
                                  ? AppTheme.accent
                                  : AppTheme.textDim)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Формат сессии',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _formatCard(
          icon: Icons.timelapse_outlined,
          title: 'Короткая сессия',
          desc: '3–5 вопросов из банка и мягкое завершение',
          onTap: () => _start('short'),
        ),
        const SizedBox(height: 10),
        _formatCard(
          icon: Icons.forum_outlined,
          title: 'Свободный диалог',
          desc: 'Говорим, сколько захочется — до кнопки «Завершить»',
          onTap: () => _start('free'),
        ),
        const SizedBox(height: 10),
        // Усиление моделью — по желанию. По умолчанию выключено:
        // на слабом железе встроенная модель вылетает по памяти,
        // а банк вопросов работает всегда.
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Усиление моделью', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
              'вкл — живая адаптация вопросов и реплики собеседника '
              '(нужна память телефона); выкл — только банк вопросов, '
              'ничего не вылетает',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
          value: _useModel,
          activeColor: AppTheme.accent,
          onChanged: (v) async {
            setState(() => _useModel = v);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('psyUseModel', v);
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Собеседник — не врач и не психотерапевт, а внимательный '
            'наблюдатель: помогает замечать состояние, чувства и инсайты. '
            'Если тяжело или кризис — лучше поговорить со специалистом.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _formatCard({
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.accent.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textDim),
          ],
        ),
      ),
    );
  }

  // --- Этап диалога ---
  Widget _buildSession() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollC,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            itemCount: _msgs.length + (_busy ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _msgs.length) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              final m = _msgs[i];
              return Align(
                alignment:
                    m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(ctx).size.width * 0.82),
                  decoration: BoxDecoration(
                    color: m.fromUser
                        ? AppTheme.accent.withOpacity(0.18)
                        : AppTheme.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(m.fromUser ? 14 : 4),
                      bottomRight: Radius.circular(m.fromUser ? 4 : 14),
                    ),
                    border: m.fromUser
                        ? null
                        : Border.all(color: AppTheme.accent.withOpacity(0.25)),
                  ),
                  child: Text(m.text,
                      style: const TextStyle(fontSize: 14.5, height: 1.35)),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputC,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_finished,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _finished ? 'Сессия завершена' : 'Написать…',
                      filled: true,
                      fillColor: AppTheme.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: (_busy || _finished) ? null : _send,
                  icon: const Icon(Icons.send_rounded, color: AppTheme.accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Банк вопросов ----------

const _kPsyCategories = <String, String>{
  'state': 'Состояние',
  'day': 'День',
  'feelings': 'Чувства',
  'dreams': 'Мечты',
  'values': 'Ценности',
};

/// Обновляемый банк вопросов дневника наблюдений: добавление, правка,
/// включение/выключение, удаление. Вопросы входят в полную
/// JSON-выгрузку и загрузку (раздел psy_questions).
class PsyQuestionsScreen extends StatelessWidget {
  const PsyQuestionsScreen({super.key});

  Future<void> _edit(BuildContext context, AppStore store,
      {PsyQuestion? q}) async {
    final textC = TextEditingController(text: q?.text ?? '');
    String category = q?.category ?? 'state';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(q == null ? 'Новый вопрос' : 'Править вопрос',
              style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textC,
                maxLines: 3,
                minLines: 2,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Тёплый открытый вопрос для дневника…'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(hintText: 'Категория'),
                items: [
                  for (final c in _kPsyCategories.entries)
                    DropdownMenuItem(value: c.key, child: Text(c.value)),
                ],
                onChanged: (v) => setS(() => category = v ?? 'state'),
              ),
            ],
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
      ),
    );
    if (ok != true) return;
    final text = textC.text.trim();
    if (text.isEmpty) return;
    if (q == null) {
      await store.addPsyQuestion(text, category: category);
    } else {
      q.text = text;
      q.category = category;
      await store.updatePsyQuestion(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final qs = List<PsyQuestion>.of(store.psyQuestions)
      ..sort((a, b) => a.ord != b.ord
          ? a.ord.compareTo(b.ord)
          : a.createdAt.compareTo(b.createdAt));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Банк вопросов', style: TextStyle(fontSize: 18)),
      ),
      body: qs.isEmpty
          ? const Center(
              child: Text('Банк пуст. Добавьте первый вопрос!',
                  style: TextStyle(color: AppTheme.textDim)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: qs.length,
              itemBuilder: (ctx, i) {
                final q = qs[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    title: Text(q.text,
                        style: TextStyle(
                            fontSize: 14,
                            color: q.isActive
                                ? AppTheme.text
                                : AppTheme.textDim)),
                    subtitle: Text(
                      _kPsyCategories[q.category] ?? q.category,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: q.isActive,
                          activeColor: AppTheme.accent,
                          onChanged: (v) {
                            q.isActive = v;
                            store.updatePsyQuestion(q);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _edit(context, store, q: q),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final ok =
                                await confirmDeleteForever(context, q.text);
                            if (ok) await store.deletePsyQuestion(q.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, store),
        child: const Icon(Icons.add),
      ),
    );
  }
}
