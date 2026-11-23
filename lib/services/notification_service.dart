import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(initSettings); // В v17 позиционный аргумент
  }

  Future<bool> requestPermissions() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await androidPlugin?.requestNotificationsPermission() ?? false;
  }

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    bool insistent = false,
  }) async {
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(dateTime, tz.local);
    // id канала обновлён, чтобы Android создал канал заново с явным звуком.
    // insistent: звук повторяется, пока пользователь не отреагирует —
    // «игрушечная сирена» для горящих дедлайнов (FLAG_INSISTENT = 4).
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'planner_reminders',
      'Напоминания планировщика',
      channelDescription: 'Напоминания о задачах, дедлайнах и событиях',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      additionalFlags:
          insistent ? Int32List.fromList(<int>[4]) : null,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    final NotificationDetails details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      id, // В v17 id позиционный
      title,
      body,
      scheduledDate,
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ---------- Критические напоминания (со звуком) ----------
  /// Отдельный Android-канал с максимальным приоритетом: звук + heads-up.
  static const AndroidNotificationDetails _criticalAndroid = AndroidNotificationDetails(
    'critical_alerts',
    'Критические напоминания',
    channelDescription: 'Пропущенные дедлайны, невыполненные ежедневные действия',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Немедленное уведомление со звуком (пропущен дедлайн / ежедневное действие).
  Future<void> showCriticalNow({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      const NotificationDetails details = NotificationDetails(android: _criticalAndroid);
      await _plugin.show(id, title, body, details);
    } catch (_) {
      // Уведомления — вспомогательная функция, крашить приложение нельзя.
    }
  }

  /// Запланированное критическое уведомление со звуком.
  /// [insistent] — настойчивая «сирена»: звук не смолкает до реакции.
  Future<void> scheduleCritical({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
    bool insistent = false,
  }) async {
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(dateTime, tz.local);
    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'critical_alerts',
        'Критические напоминания',
        channelDescription:
            'Пропущенные дедлайны, невыполненные ежедневные действия',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        additionalFlags:
            insistent ? Int32List.fromList(<int>[4]) : null,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // см. showCriticalNow
    }
  }
}
