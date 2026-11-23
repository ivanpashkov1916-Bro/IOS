/// Облачная LLM по OpenAI-совместимому API (chat/completions).
///
/// Ключ НЕ зашит в коде: его вводит пользователь в настройках
/// ассистента, хранится только на устройстве (SharedPreferences).
/// Модель по умолчанию подобрана под задачу — разбор сумбурного
/// голосового ввода и структурирование его в задачи/события/цели.
/// Базовый URL можно сменить на любой совместимый сервис.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ollama_service.dart';

/// Одна распознанная запись планировщика из сумбурного текста.
class ParsedItem {
  String type; // 'task' | 'event' | 'goal'
  String title;
  String? date; // YYYY-MM-DD
  String? time; // HH:MM
  int estimateMin;
  int durationMin;
  String priority; // 'low' | 'medium' | 'high'
  String block; // название блока (для целей/связей)
  List<String> steps;

  ParsedItem({
    this.type = 'task',
    this.title = '',
    this.date,
    this.time,
    this.estimateMin = 30,
    this.durationMin = 60,
    this.priority = 'medium',
    this.block = '',
    List<String>? steps,
  }) : steps = steps ?? [];

  /// JSON в формате команд ассистента (store.handleAssistantJson).
  Map<String, dynamic> toCommandJson() {
    final action = switch (type) {
      'event' => 'add_event',
      'goal' => 'add_goal',
      _ => 'add_task',
    };
    return {
      'action': action,
      'title': title,
      if (date != null && date!.isNotEmpty) 'date': date,
      if (time != null && time!.isNotEmpty) 'time': time,
      'estimate_min': estimateMin,
      'duration_min': durationMin,
      'priority': priority,
      if (block.isNotEmpty) 'block': block,
    };
  }
}

class ApiLlmService {
  /// OpenAI-совместимый endpoint (можно сменить в настройках).
  static String baseUrl = 'https://api.openai.com/v1';

  /// Модель по умолчанию: быстрая и точно следует формату JSON —
  /// хорошо структурирует сумбурный голосовой ввод.
  static String model = 'gpt-4o-mini';

  /// Ключ API. Вводится только в настройках, в коде не хранится.
  static String apiKey = '';

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  /// Рекомендованные модели (быстрый выбор в настройках).
  static const List<String> suggestedModels = [
    'gpt-4o-mini',
    'gpt-4o',
    'gpt-4.1-mini',
    'gpt-4.1',
  ];

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      baseUrl = prefs.getString('apiBaseUrl') ?? baseUrl;
      model = prefs.getString('apiModel') ?? model;
      apiKey = prefs.getString('apiKey') ?? '';
    } catch (_) {}
  }

  static Future<void> save({String? url, String? modelName, String? key}) async {
    if (url != null && url.trim().isNotEmpty) baseUrl = url.trim();
    if (modelName != null && modelName.trim().isNotEmpty) {
      model = modelName.trim();
    }
    if (key != null) apiKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('apiBaseUrl', baseUrl);
      await prefs.setString('apiModel', model);
      await prefs.setString('apiKey', apiKey);
    } catch (_) {}
  }

  Uri get _endpoint {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return Uri.parse('$b/chat/completions');
  }

  Future<String> _chat(String systemPrompt, String userText,
      {double temperature = 0.1, int maxTokens = 1200}) async {
    final resp = await http
        .post(
          _endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          body: jsonEncode({
            'model': model,
            'temperature': temperature,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userText},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      // Ошибку показываем честно: код + краткое тело ответа.
      var body = utf8.decode(resp.bodyBytes);
      if (body.length > 300) body = '${body.substring(0, 300)}…';
      throw Exception('HTTP ${resp.statusCode}: $body');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final msg = choices.first is Map ? choices.first['message'] : null;
      if (msg is Map && msg['content'] != null) {
        return msg['content'].toString();
      }
    }
    return '';
  }

  /// Обычная команда (режим «Команды») — тот же JSON-контракт,
  /// что у Ollama/встроенной модели.
  Future<OllamaResult> send(String userText) async {
    try {
      final content = await _chat(OllamaService.systemPromptFull, userText);
      return OllamaResult(json: OllamaService.extractJson(content), rawText: content);
    } catch (e) {
      return OllamaResult(error: e.toString());
    }
  }

  /// Свободный диалог (режим «Диалог»).
  Future<OllamaResult> sendChat(String userText) async {
    try {
      final content = await _chat(OllamaService.chatPromptFull, userText,
          temperature: 0.7);
      return OllamaResult(rawText: content);
    } catch (e) {
      return OllamaResult(error: e.toString());
    }
  }

  /// Запрос с произвольным системным промптом (дневник наблюдений,
  /// практики): промпт действует только на этот запрос.
  Future<OllamaResult> sendWithPrompt(
      String userText, String systemPromptText) async {
    try {
      final content = await _chat(systemPromptText, userText,
          temperature: 0.7);
      return OllamaResult(rawText: content);
    } catch (e) {
      return OllamaResult(error: e.toString());
    }
  }

  /// Промпт структурирования сумбурного (например, надиктованного
  /// голосом) текста в список записей планировщика.
  static String get _parsePrompt {
    final n = DateTime.now();
    final today =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return 'Ты — структуризатор планировщика. Пользователь надиктовал '
        'сумбурный текст (возможно, голосом, с ошибками распознавания). '
        'Сегодня $today; все относительные даты («завтра», «в пятницу») '
        'считай от неё. '
        'Выдели из текста ВСЕ поручения и верни СТРОГО один JSON-объект '
        'без пояснений и markdown: '
        '{"items":[{"type":"task|event|goal","title":"короткое ясное '
        'название","date":"YYYY-MM-DD или null","time":"HH:MM или null",'
        '"estimate_min":число,"duration_min":число,'
        '"priority":"low|medium|high","block":"название блока или null",'
        '"steps":["шаг 1","шаг 2"]}]}. '
        'Правила: встреча/звонок/визит — event; большая долгая цель — goal; '
        'остальное — task. Если в поручении перечисляются действия — '
        'разложи их в steps. Никогда не выдумывай факты, которых нет в '
        'тексте. Если поручений нет — верни {"items":[]}.';
  }

  /// Разбор сумбурного текста в список записей. Ошибки не прячем —
  /// возвращаем текст ошибки для показа пользователю.
  Future<({List<ParsedItem> items, String? error})> parseItems(
      String userText,
      {String retryHint = ''}) async {
    try {
      final prompt = retryHint.isEmpty
          ? userText
          : '$userText\n\n(Прошлый вариант не подошёл: $retryHint. '
              'Разбери иначе и внимательнее.)';
      final content = await _chat(_parsePrompt, prompt, maxTokens: 2000);
      final json = OllamaService.extractJson(content);
      if (json == null) {
        return (
          items: <ParsedItem>[],
          error: 'Модель ответила не JSON: '
              '${content.length > 200 ? '${content.substring(0, 200)}…' : content}'
        );
      }
      final rawItems = json['items'];
      final items = <ParsedItem>[];
      if (rawItems is List) {
        for (final e in rawItems) {
          if (e is! Map) continue;
          final title = (e['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;
          final steps = <String>[];
          final rawSteps = e['steps'];
          if (rawSteps is List) {
            for (final s in rawSteps) {
              final st = s.toString().trim();
              if (st.length > 1) steps.add(st);
            }
          }
          items.add(ParsedItem(
            type: (e['type'] ?? 'task').toString().toLowerCase().trim(),
            title: title,
            date: (e['date'] ?? '').toString().trim().isEmpty
                ? null
                : e['date'].toString().trim(),
            time: (e['time'] ?? '').toString().trim().isEmpty
                ? null
                : e['time'].toString().trim(),
            estimateMin:
                int.tryParse('${e['estimate_min'] ?? 30}') ?? 30,
            durationMin:
                int.tryParse('${e['duration_min'] ?? 60}') ?? 60,
            priority: (e['priority'] ?? 'medium').toString(),
            block: (e['block'] ?? '').toString().trim(),
            steps: steps,
          ));
        }
      }
      return (items: items, error: null);
    } catch (e) {
      return (items: <ParsedItem>[], error: e.toString());
    }
  }
}
