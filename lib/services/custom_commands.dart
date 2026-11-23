/// Пользовательские команды ассистента: свои фразы-триггеры,
/// привязанные к действиям планировщика. Хранятся в SharedPreferences.
/// Проверяются ДО встроенного парсера — свою команду можно
/// переопределить поверх встроенной.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Одна пользовательская команда: словосочетание-действие
/// (например, «удалить задачу») + код действия планировщика.
/// Остаток фразы после команды трактуется как название цели —
/// задачи/цели/события, которые нужно найти в списках.
class CustomCommand {
  String id;
  String trigger; // фраза-триггер, напр. «удалить задачу»
  String action; // код действия (см. availableActions)
  CustomCommand({String? id, required this.trigger, required this.action})
      : id = id ?? newId();

  Map<String, dynamic> toJson() =>
      {'id': id, 'trigger': trigger, 'action': action};

  static CustomCommand fromJson(Map<String, dynamic> j) => CustomCommand(
        id: (j['id'] ?? '').toString(),
        trigger: (j['trigger'] ?? '').toString(),
        action: (j['action'] ?? '').toString(),
      );
}

/// Действия, доступные для пользовательских команд
/// (код -> описание для выпадающего списка).
/// В список входят ВСЕ встроенные действия ассистента — любую
/// встроенную команду можно переопределить своей фразой.
const Map<String, String> availableActions = {
  'add_task': 'Создать новую задачу',
  'add_event': 'Создать новое событие',
  'add_goal': 'Создать новую цель',
  'add_note': 'Создать заметку',
  'delete_task': 'Удалить задачу (в архив)',
  'complete_task': 'Отметить задачу выполненной',
  'cancel_task': 'Снять выполнение задачи',
  'edit_task': 'Исправить задачу (название/срок)',
  'schedule_task': 'Перепланировать задачу',
  'link_task': 'Привязать задачу к блоку',
  'delete_goal': 'Удалить цель (в архив)',
  'complete_goal': 'Отметить цель достигнутой',
  'delete_event': 'Удалить событие (в архив)',
  'delete_note': 'Удалить заметку (в архив)',
  'split_goal': 'Разбить цель на задачи',
  'split_task': 'Разбить задачу на шаги',
  'split_event': 'Разбить событие на задачи подготовки',
  'pin_habit': 'Закрепить привычку (ежедневная)',
  'list_today': 'Показать план на сегодня',
  'list_overdue': 'Показать просроченные задачи',
};

/// Встроенные команды — показываются в списке для справки.
/// Тап по встроенной команде создаёт её редактируемую копию
/// (пользовательская имеет приоритет при разборе фразы).
const List<({String trigger, String action, String example})> builtinCommands =
    [
  (
    trigger: 'добавь задачу',
    action: 'add_task',
    example: 'добавь задачу распланировать день на завтра'
  ),
  (
    trigger: 'добавь событие',
    action: 'add_event',
    example: 'добавь событие «выход на Wildberries» завтра в 15:00'
  ),
  (
    trigger: 'добавь цель',
    action: 'add_goal',
    example: 'добавь цель «подтянуть английский» в блок учёба'
  ),
  (
    trigger: 'добавь заметку',
    action: 'add_note',
    example: 'добавь заметку купить молоко'
  ),
  (
    trigger: 'удали задачу',
    action: 'delete_task',
    example: 'удали задачу распланировать день'
  ),
  (
    trigger: 'выполни задачу',
    action: 'complete_task',
    example: 'выполни задачу оплатить счёт'
  ),
  (
    trigger: 'отмени выполнение задачи',
    action: 'cancel_task',
    example: 'отмени выполнение задачи оплатить счёт'
  ),
  (
    trigger: 'исправь задачу',
    action: 'edit_task',
    example: 'исправь задачу «распланировать день» на завтра'
  ),
  (
    trigger: 'удали цель',
    action: 'delete_goal',
    example: 'удали цель английский'
  ),
  (
    trigger: 'удали событие',
    action: 'delete_event',
    example: 'удали событие звонок другу'
  ),
  (
    trigger: 'разбей цель',
    action: 'split_goal',
    example: 'разбей цель «подтянуть английский» на задачи'
  ),
  (
    trigger: 'разбей задачу',
    action: 'split_task',
    example: 'разбей задачу «ремонт отопления» на шаги'
  ),
  (
    trigger: 'разбей событие',
    action: 'split_event',
    example: 'разбей событие «переезд» на задачи'
  ),
  (
    trigger: 'свяжи задачу',
    action: 'link_task',
    example: 'свяжи задачу ремонт отопления с блоком финансы'
  ),
  (
    trigger: 'что у меня сегодня',
    action: 'list_today',
    example: 'что у меня сегодня?'
  ),
  (
    trigger: 'что просрочено',
    action: 'list_overdue',
    example: 'что просрочено?'
  ),
];

class CustomCommands {
  CustomCommands._();

  static List<CustomCommand> list = [];

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('customCommands');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        list = decoded
            .whereType<Map>()
            .map((e) => CustomCommand.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.trigger.isNotEmpty && c.action.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // битые данные команд — не мешают запуску приложения
    }
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'customCommands', jsonEncode(list.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> add(CustomCommand c) async {
    list.add(c);
    await _save();
  }

  static Future<void> update(CustomCommand c) async {
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == c.id) {
        list[i] = c;
        break;
      }
    }
    await _save();
  }

  static Future<void> remove(String id) async {
    list.removeWhere((c) => c.id == id);
    await _save();
  }

  /// Стем слова: первые 5 букв (русская морфология: «удалить» и
  /// «удали» имеют общий стем «удали»).
  static String _stem(String w) => w.length <= 5 ? w : w.substring(0, 5);

  /// Проверяет фразу на пользовательские команды.
  /// Возвращает JSON-интент для AppStore.handleAssistantJson или null.
  static Map<String, dynamic>? match(String rawText) {
    if (list.isEmpty) return null;
    final lower = rawText.toLowerCase();
    final words = lower
        .split(RegExp(r'[\s,.!?;:«»"“”„()\-—]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;

    // Длинные триггеры проверяем первыми — «отмени выполнение задачи»
    // не должно съедаться более коротким «выполни задачу».
    final sorted = list.toList()
      ..sort((a, b) => b.trigger.length.compareTo(a.trigger.length));

    for (final cmd in sorted) {
      final tWords = cmd.trigger
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (tWords.isEmpty) continue;
      final usedIdx = <int>{};
      var ok = true;
      for (final tw in tWords) {
        final stem = _stem(tw);
        var found = false;
        for (var i = 0; i < words.length; i++) {
          if (usedIdx.contains(i)) continue;
          if (words[i].startsWith(stem)) {
            usedIdx.add(i);
            found = true;
            break;
          }
        }
        if (!found) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;

      // Цель команды — остаток фразы без слов триггера. Текст
      // в кавычках имеет приоритет: это готовое название.
      final qm = RegExp(r'[«"“„]([^»"“”„]+)[»"“”]').firstMatch(rawText);
      String title;
      if (qm != null && qm.group(1)!.trim().isNotEmpty) {
        title = qm.group(1)!.trim();
      } else {
        final rest = <String>[];
        for (var i = 0; i < words.length; i++) {
          if (!usedIdx.contains(i)) rest.add(words[i]);
        }
        title = rest.join(' ').trim();
      }
      if (title.isEmpty) title = rawText.trim();
      return <String, dynamic>{
        'action': cmd.action,
        'title': title,
        'text': rawText,
      };
    }
    return null;
  }
}
