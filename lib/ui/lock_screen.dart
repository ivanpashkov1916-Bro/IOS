/// Блок пароля при входе в приложение.
/// Включается и отключается в настройках ассистента («Безопасность»).
/// На случай забытого пароля — два контрольных вопроса: ответив на оба,
/// пользователь видит установленный пароль и может оставить его или
/// сменить. Пароль и ответы хранятся локально на устройстве
/// (SharedPreferences), никуда не отправляются.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

class LockGate {
  LockGate._();

  static const _kEnabled = 'lockEnabled';
  static const _kPassword = 'lockPassword';
  static const _kQ1 = 'lockQ1';
  static const _kA1 = 'lockA1';
  static const _kQ2 = 'lockQ2';
  static const _kA2 = 'lockA2';

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return (p.getBool(_kEnabled) ?? false) &&
        (p.getString(_kPassword) ?? '').isNotEmpty;
  }

  static Future<bool> checkPassword(String value) async {
    final p = await SharedPreferences.getInstance();
    return value == (p.getString(_kPassword) ?? '');
  }

  static String _norm(String s) => s.trim().toLowerCase();

  /// Оба контрольных ответа верны?
  static Future<bool> checkAnswers(String a1, String a2) async {
    final p = await SharedPreferences.getInstance();
    return _norm(a1) == _norm(p.getString(_kA1) ?? '') &&
        _norm(a1).isNotEmpty &&
        _norm(a2) == _norm(p.getString(_kA2) ?? '') &&
        _norm(a2).isNotEmpty;
  }

  static Future<String> currentPassword() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPassword) ?? '';
  }

  static Future<List<String>> questions() async {
    final p = await SharedPreferences.getInstance();
    return [p.getString(_kQ1) ?? '', p.getString(_kQ2) ?? ''];
  }

  static Future<void> save(
      {required String password,
      required String q1,
      required String a1,
      required String q2,
      required String a2}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPassword, password);
    await p.setString(_kQ1, q1);
    await p.setString(_kA1, a1);
    await p.setString(_kQ2, q2);
    await p.setString(_kA2, a2);
    await p.setBool(_kEnabled, true);
  }

  static Future<void> disable() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, false);
  }
}

/// Диалог настроек безопасности (из шапки настроек ассистента).
Future<void> showSecuritySettings(BuildContext context) async {
  final enabled = await LockGate.isEnabled();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Безопасность', style: TextStyle(fontSize: 16)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            enabled
                ? 'Пароль при входе включён.'
                : 'Пароль при входе выключен. При включении зададите '
                    'пароль и два контрольных вопроса — по ним пароль '
                    'можно будет восстановить.',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ),
        if (!enabled)
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await _setupPassword(context);
            },
            child: const Text('Включить пароль',
                style: TextStyle(color: AppTheme.accent)),
          ),
        if (enabled) ...[
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await _changePassword(context);
            },
            child: const Text('Сменить пароль',
                style: TextStyle(color: AppTheme.accent)),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await _disablePassword(context);
            },
            child: const Text('Выключить пароль',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// Поля пароля и двух контрольных вопросов — общая форма.
Future<List<String>?> _askPasswordAndQuestions(BuildContext context,
    {String title = 'Новый пароль'}) async {
  final passC = TextEditingController();
  final pass2C = TextEditingController();
  final q1C = TextEditingController();
  final a1C = TextEditingController();
  final q2C = TextEditingController();
  final a2C = TextEditingController();
  String? error;
  final res = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passC,
                obscureText: true,
                decoration:
                    const InputDecoration(hintText: 'Пароль'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pass2C,
                obscureText: true,
                decoration:
                    const InputDecoration(hintText: 'Пароль ещё раз'),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Контрольные вопросы (для восстановления)',
                    style:
                        TextStyle(color: AppTheme.textDim, fontSize: 11)),
              ),
              const SizedBox(height: 6),
              TextField(
                  controller: q1C,
                  decoration:
                      const InputDecoration(hintText: 'Вопрос 1')),
              TextField(
                  controller: a1C,
                  decoration: const InputDecoration(hintText: 'Ответ 1')),
              const SizedBox(height: 8),
              TextField(
                  controller: q2C,
                  decoration:
                      const InputDecoration(hintText: 'Вопрос 2')),
              TextField(
                  controller: a2C,
                  decoration: const InputDecoration(hintText: 'Ответ 2')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style:
                        const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final p1 = passC.text;
              if (p1.length < 4) {
                setS(() => error = 'Пароль — минимум 4 символа');
                return;
              }
              if (p1 != pass2C.text) {
                setS(() => error = 'Пароли не совпадают');
                return;
              }
              if (q1C.text.trim().isEmpty ||
                  a1C.text.trim().isEmpty ||
                  q2C.text.trim().isEmpty ||
                  a2C.text.trim().isEmpty) {
                setS(() => error =
                    'Заполните оба вопроса и оба ответа — иначе пароль не восстановить');
                return;
              }
              Navigator.pop(ctx, [
                p1,
                q1C.text.trim(),
                a1C.text.trim(),
                q2C.text.trim(),
                a2C.text.trim(),
              ]);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  return res;
}

Future<void> _setupPassword(BuildContext context) async {
  final r = await _askPasswordAndQuestions(context);
  if (r == null) return;
  await LockGate.save(password: r[0], q1: r[1], a1: r[2], q2: r[3], a2: r[4]);
  if (context.mounted) {
    SystemSound.play(SystemSoundType.click);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Пароль включён — спросит при следующем входе')));
  }
}

/// Смена пароля: сначала текущий пароль (или контрольные вопросы),
/// затем новый с вопросами.
Future<void> _changePassword(BuildContext context) async {
  final ok = await _askCurrentPassword(context);
  if (ok != true || !context.mounted) return;
  await _setupPassword(context);
}

Future<void> _disablePassword(BuildContext context) async {
  final ok = await _askCurrentPassword(context);
  if (ok != true) return;
  await LockGate.disable();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль выключен')));
  }
}

/// Проверка текущего пароля перед сменой/отключением.
Future<bool?> _askCurrentPassword(BuildContext context) async {
  final c = TextEditingController();
  String? error;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Текущий пароль', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Пароль'),
              onSubmitted: (_) async {
                if (await LockGate.checkPassword(c.text)) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setS(() => error = 'Неверный пароль');
                }
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (await LockGate.checkPassword(c.text)) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                setS(() => error = 'Неверный пароль');
              }
            },
            child: const Text('Дальше'),
          ),
        ],
      ),
    ),
  );
}

/// Экран блокировки при входе в приложение.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passC = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passC.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (await LockGate.checkPassword(_passC.text)) {
      SystemSound.play(SystemSoundType.click);
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Неверный пароль');
    }
  }

  /// Восстановление: два контрольных вопроса → показ пароля →
  /// «оставить» (войти) или «сменить».
  Future<void> _recover() async {
    final qs = await LockGate.questions();
    if (!mounted) return;
    if (qs[0].isEmpty || qs[1].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Контрольные вопросы не заданы')));
      return;
    }
    final a1C = TextEditingController();
    final a2C = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Восстановление пароля',
              style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(qs[0], style: const TextStyle(fontSize: 13)),
                TextField(
                    controller: a1C,
                    decoration: const InputDecoration(hintText: 'Ответ')),
                const SizedBox(height: 10),
                Text(qs[1], style: const TextStyle(fontSize: 13)),
                TextField(
                    controller: a2C,
                    decoration: const InputDecoration(hintText: 'Ответ')),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: AppTheme.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                if (await LockGate.checkAnswers(a1C.text, a2C.text)) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setS(() => error = 'Ответы не совпадают');
                }
              },
              child: const Text('Проверить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final password = await LockGate.currentPassword();
    if (!mounted) return;
    // Ответы верны: показываем пароль и предлагаем оставить или сменить.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ваш пароль', style: TextStyle(fontSize: 16)),
        content: SelectableText(password,
            style: const TextStyle(fontSize: 18, color: AppTheme.accent)),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final r = await _askPasswordAndQuestions(this.context);
              if (r != null) {
                await LockGate.save(
                    password: r[0], q1: r[1], a1: r[2], q2: r[3], a2: r[4]);
              }
              if (mounted) widget.onUnlocked();
            },
            child: const Text('Сменить'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onUnlocked();
            },
            child: const Text('Оставить и войти'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 56, color: AppTheme.accent),
                const SizedBox(height: 14),
                const Text('PASHKOV PLANER',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Введите пароль для входа',
                    style:
                        TextStyle(color: AppTheme.textDim, fontSize: 13)),
                const SizedBox(height: 18),
                TextField(
                  controller: _passC,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _tryUnlock(),
                  decoration: const InputDecoration(hintText: 'Пароль'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppTheme.danger, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _tryUnlock,
                    child: const Text('Войти'),
                  ),
                ),
                TextButton(
                  onPressed: _recover,
                  child: const Text('Забыли пароль? Ответьте на вопросы',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
