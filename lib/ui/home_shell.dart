/// Каркас приложения: нижняя навигация на 8 вкладок (как в макетах).
/// При первом запуске — приветственное окно: приложение спрашивает,
/// как к пользователю обращаться, и при неоднозначном имени уточняет род
/// обращения (от него адаптируются похвала и мотивация).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../profile.dart';
import '../store.dart';
import 'assistant_screen.dart';
import 'calendar_screen.dart';
import 'goals_screen.dart';
import 'notes_screen.dart';
import 'path_screen.dart';
import 'stats_screen.dart';
import 'tasks_screen.dart';
import 'today_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    TodayScreen(),
    NotesScreen(),
    CalendarScreen(),
    TasksScreen(),
    GoalsScreen(),
    StatsScreen(),
    PathScreen(),
    AssistantScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Приветственное окно при первом запуске после установки.
    if (!UserProfile.isSet) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _welcome());
    }
  }

  Future<void> _welcome() async {
    if (!mounted) return;
    final nameC = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Привет!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Я очень рад тому, что ты выбираешь меня. Скажи, пожалуйста, '
                'как ты хочешь, чтобы я к тебе обращался?'),
            const SizedBox(height: 14),
            TextField(
              controller: nameC,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Твоё имя'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameC.text.trim()),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await UserProfile.saveName(name);
    var gender = UserProfile.guessGender(name);
    if (gender.isEmpty && mounted) {
      // Имя не даёт однозначного рода — задаём уточняющий вопрос.
      gender = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text('Замечательно, $name!'),
              content: const Text(
                  'Ты хочешь, чтобы я обращался к тебе как к женщине '
                  'или как к мужчине?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'f'),
                  child: const Text('Как к женщине'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'm'),
                  child: const Text('Как к мужчине'),
                ),
              ],
            ),
          ) ??
          '';
    }
    await UserProfile.saveGender(gender);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Запрос навигации от других экранов (тап по задаче на экране
    // «Задачи» открывает вкладку «Цели» со шкалой шагов задачи).
    final store = context.watch<AppStore>();
    final req = store.tabRequest;
    if (req != null && req != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        store.consumeTabRequest();
        if (mounted) setState(() => _index = req);
      });
    }
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        selectedFontSize: 10,
        unselectedFontSize: 9,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.today_outlined), label: 'Сегодня'),
          BottomNavigationBarItem(icon: Icon(Icons.note_outlined), label: 'Заметки'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Календарь'),
          BottomNavigationBarItem(icon: Icon(Icons.check_circle_outline), label: 'Задачи'),
          BottomNavigationBarItem(icon: Icon(Icons.flag_outlined), label: 'Цели'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Статистика'),
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Путь'),
          BottomNavigationBarItem(icon: Icon(Icons.mic_none), label: 'Ассистент'),
        ],
      ),
    );
  }
}
