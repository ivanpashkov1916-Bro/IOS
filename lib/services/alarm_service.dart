/// Системный будильник телефона как резервный канал оповещений
/// о дедлайнах: если push-уведомление по какой-то причине не сработало
/// (ограничения прошивки, «засыпание» приложения), сработает штатный
/// будильник из приложения «Часы». Ставится через системный интент
/// ACTION_SET_ALARM (android_intent_plus), отдельной «своей» сирены
/// и фонового процесса не требуется.
library;

import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';

class AlarmService {
  AlarmService._();

  /// Системные интенты существуют только на Android; на iOS все методы
  /// тихо возвращают false (уведомления там и так работают).
  static bool get _supported => Platform.isAndroid;

  /// Установить системный будильник на [at] с подписью [label].
  /// SKIP_UI: будильник создаётся молча, без открытия «Часов».
  /// Возвращает true, если интент был передан системе.
  static Future<bool> setAlarm(DateTime at, String label) async {
    if (!_supported) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.HOUR': at.hour,
          'android.intent.extra.alarm.MINUTES': at.minute,
          'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Удалить (отключить) системный будильник с подписью [label].
  /// ACTION_DISMISS_ALARM с поиском по метке: система ищет будильник,
  /// чья подпись содержит [label], и снимает его. Разовый будильник
  /// при этом фактически удаляется — больше никогда не прозвонит.
  /// SKIP_UI: снятие МОЛЧА, без переброски пользователя в приложение
  /// «Часы» (раньше отметка «выполнено» выкидывала в будильники).
  /// Ограничение ОС: снять можно только предстоящий или звонящий
  /// прямо сейчас будильник; уже отзвонивший разовый будильник
  /// приложение «Часы» обычно отключает само.
  static Future<bool> dismissAlarm(String label) async {
    if (!_supported) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.DISMISS_ALARM',
        // FLAG_ACTIVITY_NEW_TASK: снятие может быть вызвано в момент,
        // когда приложение свёрнуто (перенос дедлайна при запуске,
        // фоновая обработка) — без флага интент не стартует.
        flags: <int>[0x10000000],
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.SEARCH_MODE': 'android.label',
          'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Открыть системный таймер на [minutes] минут (запасной вариант).
  static Future<bool> setTimer(int minutes, String label) async {
    if (!_supported) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_TIMER',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.LENGTH': minutes * 60,
          'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }
}
