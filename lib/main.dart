/// Планировщик с голосовым ассистентом (Ollama). Offline-first.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile.dart';
import 'store.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Профиль пользователя (имя, род, имя ассистента) — для
  // персонализации похвалы и обращений системы.
  await UserProfile.load();
  runApp(const PlannerApp());
}

class PlannerApp extends StatefulWidget {
  const PlannerApp({super.key});

  @override
  State<PlannerApp> createState() => _PlannerAppState();
}

class _PlannerAppState extends State<PlannerApp> {
  final store = AppStore();
  // Блок пароля при входе: null — ещё проверяем, включён ли;
  // true — приложение заперто, показываем LockScreen.
  bool? _locked;

  @override
  void initState() {
    super.initState();
    // Уведомления -> загрузка БД -> перепланирование напоминаний.
    store.notifications.init().then((_) async {
      await store.load();
      await store.rescheduleAllReminders();
    });
    LockGate.isEnabled().then((v) {
      if (mounted) setState(() => _locked = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        title: 'PASHKOV PLANER',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // Глобальный масштаб шрифта (значок «размер шрифта» в AppBar
        // каждого экрана): все надписи приложения растут/уменьшаются
        // пропорционально выбранной градации, поверх системной настройки.
        builder: (context, child) {
          final scale = context.watch<AppStore>().fontScale;
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
                textScaler: TextScaler.linear(
                    mq.textScaler.scale(1.0) * scale)),
            child: child ?? const SizedBox(),
          );
        },
        // Пока проверяем настройку пароля — пустой экран темы;
        // если пароль включён и не введён — экран блокировки.
        home: _locked == null
            ? const Scaffold(body: SizedBox.shrink())
            : (_locked!
                ? LockScreen(
                    onUnlocked: () => setState(() => _locked = false))
                : const HomeShell()),
      ),
    );
  }
}
