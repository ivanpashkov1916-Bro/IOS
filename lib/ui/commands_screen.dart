/// Экран «Мои команды»: полный список команд ассистента.
/// Сверху — пользовательские команды (тап — правка фразы и действия,
/// корзина — удаление), ниже — встроенные для справки: тап по ним
/// создаёт редактируемую копию. Плюс в AppBar — новая команда.
/// Пример работы: добавили «удалить задачу» -> фраза «удали задачу
/// оплатить счёт» находит задачу «оплатить счёт» и убирает в архив.
library;

import 'package:flutter/material.dart';

import '../services/custom_commands.dart';
import '../theme.dart';
import 'common.dart';

class CommandsScreen extends StatefulWidget {
  const CommandsScreen({super.key});

  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  /// Диалог создания/правки команды: фраза-триггер + действие.
  Future<void> _edit(
      {CustomCommand? existing, String? presetTrigger, String? presetAction}) async {
    final triggerC =
        TextEditingController(text: existing?.trigger ?? presetTrigger ?? '');
    var action = existing?.action ?? presetAction ?? availableActions.keys.first;
    if (!availableActions.containsKey(action)) {
      action = availableActions.keys.first;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Новая команда' : 'Правка команды'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: triggerC,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Фраза-команда',
                  hintText: 'например: удалить задачу',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: action,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Действие'),
                items: [
                  for (final e in availableActions.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (v) => setD(() => action = v ?? action),
              ),
              const SizedBox(height: 10),
              const Text(
                'Остаток фразы после команды — название цели: «удали задачу '
                'оплатить счёт» найдёт задачу «оплатить счёт» и уберёт её '
                'в архив.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && triggerC.text.trim().isNotEmpty) {
      if (existing == null) {
        await CustomCommands.add(
            CustomCommand(trigger: triggerC.text.trim(), action: action));
      } else {
        existing.trigger = triggerC.text.trim();
        existing.action = action;
        await CustomCommands.update(existing);
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = CustomCommands.list;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои команды'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Новая команда',
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          SectionHeader(
            'Свои команды',
            subtitle: custom.isEmpty
                ? 'Пока нет — добавьте плюсом справа сверху'
                : 'Тап — правка, корзина — удаление',
            color: AppTheme.accent,
          ),
          if (custom.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Своя команда переопределяет встроенную: например, добавьте '
                '«удалить задачу» — и фраза «удали задачу X» найдёт задачу '
                'X в списках и уберёт её в архив.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            )
          else
            for (final c in custom)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppTheme.accent, width: 1),
                ),
                child: ListTile(
                  onTap: () => _edit(existing: c),
                  leading: const Icon(Icons.campaign_outlined,
                      color: AppTheme.accent),
                  title: Text('«${c.trigger}»'),
                  subtitle: Text(
                    availableActions[c.action] ?? c.action,
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: AppTheme.textDim),
                    tooltip: 'Удалить команду',
                    onPressed: () async {
                      await CustomCommands.remove(c.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
          const SectionHeader(
            'Встроенные команды',
            subtitle: 'Тап — создать редактируемую копию в «Своих»',
          ),
          for (final b in builtinCommands)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                onTap: () =>
                    _edit(presetTrigger: b.trigger, presetAction: b.action),
                leading: const Icon(Icons.bolt,
                    size: 20, color: AppTheme.textDim),
                title: Text('«${b.trigger}»',
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  'например: ${b.example}',
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
