/// Движок «Дневника наблюдений» — гибрид:
///  · ОСНОВА — обновляемый банк вопросов (таблица psy_questions):
///    работает всегда, полностью офлайн, вопросы правятся в приложении
///    и переносятся с полной выгрузкой;
///  · УСИЛЕНИЕ — активная модель ассистента (Ollama / встроенная /
///    облачная): мягко адаптирует формулировку банковского вопроса
///    под записи дневника и ведёт свободный диалог. Недоступна —
///    сессия продолжается на голом банке, ничего не ломается.
///
/// Промпт собеседника-наблюдателя включается ТОЛЬКО на время сессии
/// дневника и нигде больше (остальные режимы ассистента не затронуты).
/// Роль — внимательный собеседник-наблюдатель с мягким дисклеймером,
/// без имитации терапии и диагнозов.
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../store.dart';
import 'api_llm_service.dart';
import 'local_llm_service.dart';
import 'ollama_service.dart';

class PsyService {
  /// Системный промпт сессии. Включается только здесь и только на
  /// время диалога дневника наблюдений.
  static const String observerPrompt =
      'Ты — внимательный собеседник-наблюдатель в личном дневнике '
      'пользователя. Твоя роль: мягко помогать ему замечать своё '
      'состояние, эмоции, инсайты и атрибутику его жизни — через '
      'короткие тёплые открытые вопросы, по одному за раз. '
      'Правила: отражай сказанное («слышу, что…»), задавай вопросы, '
      'вызывающие эмоциональный отклик (образы, мелочи, ощущения); '
      'не давай советов, не оценивай, не ставь диагнозов, не читай '
      'нотаций. Ты не врач и не психотерапевт — если звучит кризис '
      'или опасность, мягко скажи, что лучше поговорить со '
      'специалистом. Пиши по-русски, тепло и коротко: 1–3 предложения. '
      'Никакого JSON и markdown — просто текст.';

  /// Промпт адаптации банковского вопроса под контекст дневника:
  /// модель НЕ выдумывает вопрос с нуля, а бережно перефразирует
  /// готовый (так формулировки не «уплывают»).
  static String adaptPrompt(PsyQuestion q) =>
      'Переформулируй вопрос для дневника наблюдений чуть иначе — '
      'тепло, лично, можно чуть образно, но сохрани смысл и краткость '
      '(одно предложение). Верни ТОЛЬКО текст вопроса, без кавычек и '
      'пояснений. Вопрос: «${q.text}»';

  /// Мягкое завершение короткой сессии.
  static const String softEnding =
      'Спасибо, что поделился(ась). Пусть вечер будет тёплым — '
      'записи сохранены в дневнике.';

  /// Тёплые короткие «отражения» для режима без модели: в свободном
  /// диалоге придают ощущение собеседника, не притворяясь анализом.
  static const List<String> softReflections = [
    'Слышу тебя.',
    'Спасибо, что делишься — это важно.',
    'Понимаю, это правда ощутимо.',
    'Звучит непросто — и очень по-человечески.',
    'Запоминаю это для дневника.',
    'Хорошо, что ты это заметил(а).',
    'Это многое говорит о твоём дне.',
    'Принято — спасибо за честность.',
  ];

  /// Случайное «отражение» из списка выше.
  static String reflection() =>
      softReflections[Random().nextInt(softReflections.length)];

  /// Какой движок сейчас активен в ассистенте (тот же работает
  /// и в дневнике наблюдений): 'local' | 'ollama' | 'api'.
  static Future<String> activeEngine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('assistantEngine') ?? 'local';
    } catch (_) {
      return 'local';
    }
  }

  /// Запрос к активному движку с произвольным системным промптом.
  /// Любой сбой — OllamaResult с error (вызывающий код откатывается
  /// на банк вопросов, сессия не прерывается).
  static Future<OllamaResult> _sendWithEngine(
      String engine, String userText, String systemPrompt) async {
    try {
      switch (engine) {
        case 'ollama':
          return await OllamaService().sendWithPrompt(userText, systemPrompt);
        case 'api':
          if (!ApiLlmService.isConfigured) {
            return OllamaResult(error: 'Облачная модель не настроена');
          }
          return await ApiLlmService().sendWithPrompt(userText, systemPrompt);
        default:
          return await LocalLlmService()
              .sendWithPrompt(userText, systemPrompt);
      }
    } catch (e) {
      return OllamaResult(error: e.toString());
    }
  }

  /// Случайный вопрос из активного банка, без повторов уже заданных
  /// в этой сессии ([usedIds]). null — банк пуст или всё задано.
  static PsyQuestion? pickBankQuestion(AppStore store, Set<String> usedIds) {
    final pool = store.activePsyQuestions
        .where((q) => !usedIds.contains(q.id))
        .toList();
    if (pool.isEmpty) return null;
    return pool[Random().nextInt(pool.length)];
  }

  /// Гибридный следующий вопрос: банк + (по возможности) мягкая
  /// адаптация формулировки активной моделью под записи дневника.
  /// Возвращает (текст вопроса, запись банка или null при генерации).
  static Future<({String text, PsyQuestion? bank})> nextQuestion(
    AppStore store,
    Set<String> usedIds, {
    required String engine,
    String mood = '',
  }) async {
    final q = pickBankQuestion(store, usedIds);
    if (q == null) {
      // Банк исчерпан: просим модель придумать вопрос по контексту;
      // без модели — честное завершение.
      final ctx = store.buildPsyContext();
      final res = await _sendWithEngine(
        engine,
        '${mood.isNotEmpty ? 'Настроение в начале сессии: $mood. ' : ''}'
        'Придумай ещё один тёплый открытый вопрос для дневника '
        'наблюдений (одно предложение). Верни только текст вопроса.',
        '$observerPrompt\n\n$ctx',
      );
      if (res.error == null && res.rawText.trim().length > 4) {
        return (text: _clean(res.rawText), bank: null);
      }
      return (text: '', bank: null);
    }
    usedIds.add(q.id);
    // Адаптация моделью — только если движок живой; при сбое
    // отдаём банковскую формулировку как есть.
    final ctx = store.buildPsyContext(maxEntries: 5);
    final res = await _sendWithEngine(engine, adaptPrompt(q), ctx.isEmpty
        ? 'Ты бережно перефразируешь вопросы дневника.'
        : 'Контекст записей дневника:\n$ctx\n\n'
            'Ты бережно перефразируешь вопросы дневника.');
    if (res.error == null) {
      final adapted = _clean(res.rawText);
      if (adapted.length > 6 && adapted.contains('?')) {
        return (text: adapted, bank: q);
      }
    }
    return (text: q.text, bank: q);
  }

  /// Ответ собеседника в свободном диалоге: реплика модели по
  /// контексту дневника и последним сообщениям сессии. null —
  /// модель недоступна (UI подставит следующий вопрос банка).
  static Future<String?> reply(
    AppStore store, {
    required String engine,
    required List<({bool fromUser, String text})> history,
    String mood = '',
  }) async {
    final ctx = store.buildPsyContext();
    final b = StringBuffer();
    if (mood.isNotEmpty) b.writeln('Настроение в начале сессии: $mood.');
    b.writeln('Диалог сессии:');
    for (final m in history.take(16)) {
      b.writeln(m.fromUser ? 'Пользователь: ${m.text}' : 'Ты: ${m.text}');
    }
    b.writeln('Ответь на последнюю реплику пользователя: отрази её '
        'и задай один следующий вопрос.');
    final res = await _sendWithEngine(
        engine, b.toString(), '$observerPrompt\n\n$ctx');
    if (res.error != null) return null;
    final text = _clean(res.rawText);
    return text.length > 2 ? text : null;
  }

  /// Чистка ответа модели: обрезка кавычек, префиксов «Вопрос:»,
  /// переводов строк — в сессию уходит одна строка.
  static String _clean(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^[\s"*«»]+'), '').replaceAll(RegExp(r'[\s"*«»]+$'), '');
    s = s.replaceFirst(RegExp(r'^(вопрос|ответ)\s*[:—-]\s*', caseSensitive: false), '');
    final nl = s.indexOf('\n');
    if (nl > 0) s = s.substring(0, nl).trim();
    return s;
  }
}
