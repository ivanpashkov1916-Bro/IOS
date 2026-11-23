/// Клиент Ollama (локальная LLM). Аудио и переписка не сохраняются —
/// в чат уходит только текстовая команда пользователя.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../profile.dart';

class OllamaResult {
  final Map<String, dynamic>? json;
  final String rawText;
  final String? error;
  const OllamaResult({this.json, this.rawText = '', this.error});
}

class OllamaService {
  static const String baseUrl = 'http://127.0.0.1:11434';

  /// Активная модель Ollama (выбирается в приложении из списка /api/tags).
  static String model = 'qwen2.5:0.5b';

  /// Список моделей, установленных в Ollama (например, из Termux).
  /// Пустой список — сервер недоступен или моделей нет.
  Future<List<String>> listModels() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      final models = decoded is Map ? decoded['models'] : null;
      if (models is List) {
        return models
            .map((m) => m is Map ? (m['name'] ?? '').toString() : '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static const String systemPrompt =
      'Ты — ассистент планировщика задач с полным доступом к спискам. '
      'Разбери команду пользователя и верни СТРОГО один JSON-объект без '
      'пояснений и без markdown. Поля: '
      'action (add_task, add_note, add_goal, add_event, complete_task, '
      'complete_goal, delete_task, delete_note, delete_goal, delete_event, '
      'edit_task, schedule_task, cancel_task, link_task, '
      'pin_habit, list_today, list_overdue, none), '
      'title (строка — название существующей или новой записи из команды), '
      'new_title (новое название при edit_task), '
      'text (строка для заметки), date (YYYY-MM-DD), time (HH:MM), '
      'deadline_days (число), duration_min (число), estimate_min (число), '
      'priority (low, medium, high), block (название блока при link_task). '
      'Правила: «откорректируй/измени/внеси изменения» -> edit_task; '
      '«запланируй/перенеси» -> schedule_task; «отмени выполнение» -> cancel_task; '
      '«свяжи с блоком» -> link_task; '
      '«событие/встреча/позвонить» -> add_event (если название не выделяется, '
      'скопируй фразу пользователя в поле text). '
      'Текст в кавычках «...» — это название (title) события, задачи или цели, '
      'бери его целиком, включая слова про дату. '
      'При add_goal, если в команде упомянут блок (например «в блок финансы»), '
      'запиши его название в поле block. '
      'Никогда не выдумывай названия задач, целей и событий — бери их только из '
      'команды пользователя. Если команду нельзя понять, она не по-русски или в ней '
      'нет поручения — верни {"action":"none"}. Отвечай только JSON.';

  /// Текущие дата и время — модель в Termux не синхронизирует часы,
  /// поэтому подставляем их в промпт при каждом запросе.
  static String get _nowLine {
    final n = DateTime.now();
    final wd = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница',
        'суббота', 'воскресенье'][n.weekday - 1];
    return 'Сегодня $wd, '
        '${n.day.toString().padLeft(2, '0')}.${n.month.toString().padLeft(2, '0')}.${n.year}, '
        'сейчас ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}. '
        'Все относительные даты («завтра», «в пятницу») считай от этой даты. ';
  }

  /// Полный промпт: текущая дата/время + имя ассистента (если задано).
  static String get systemPromptFull =>
      _nowLine +
      (UserProfile.assistantName.isEmpty
              ? ''
              : 'Тебя зовут ${UserProfile.assistantName}. '
                  'Откликайся, когда к тебе обращаются по имени. ') +
      systemPrompt;

  /// Промпт свободного диалога (режим «Диалог»): обычный разговор
  /// без JSON-команд.
  static String get chatPromptFull =>
      _nowLine +
      (UserProfile.assistantName.isEmpty
              ? 'Ты — дружелюбный русскоязычный ассистент планировщика. '
              : 'Тебя зовут ${UserProfile.assistantName}. Ты — дружелюбный '
                  'русскоязычный ассистент планировщика. Откликайся на своё имя. ') +
      'Отвечай по-русски, коротко и по делу, как в обычной переписке. '
      'Никакого JSON и markdown — просто текст ответа.';

  /// КРИТИЧЕСКИ ВАЖНО: вырезает JSON из ответа LLM регулярным выражением
  /// и заменяет одинарные кавычки на двойные перед jsonDecode.
  /// При любой ошибке парсинга возвращает null (вызывающий код НЕ должен падать).
  static Map<String, dynamic>? extractJson(String text) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return null;
    final candidate = match.group(0)!.replaceAll("'", '"');
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<OllamaResult> send(String userText) =>
      _sendWith(userText, systemPromptFull);

  /// Свободный диалог (режим «Диалог») — без JSON-команд.
  Future<OllamaResult> sendChat(String userText) =>
      _sendWith(userText, chatPromptFull);

  /// Запрос с произвольным системным промптом (дневник наблюдений,
  /// практики): промпт действует только на этот запрос и нигде
  /// больше не включается.
  Future<OllamaResult> sendWithPrompt(
          String userText, String systemPromptText) =>
      _sendWith(userText, systemPromptText);

  Future<OllamaResult> _sendWith(String userText, String systemPromptText) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'stream': false,
              'options': {'temperature': 0.1},
              'messages': [
                {'role': 'system', 'content': systemPromptText},
                {'role': 'user', 'content': userText},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        return OllamaResult(error: 'HTTP ${resp.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      String content = '';
      if (decoded is Map) {
        final msg = decoded['message'];
        if (msg is Map && msg['content'] != null) {
          content = msg['content'].toString();
        } else if (decoded['response'] != null) {
          content = decoded['response'].toString();
        }
      }
      return OllamaResult(json: extractJson(content), rawText: content);
    } catch (e) {
      return OllamaResult(error: e.toString());
    }
  }
}
