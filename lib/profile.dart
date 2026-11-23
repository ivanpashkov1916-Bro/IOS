/// Профиль пользователя и ассистента: имя, род обращения, имя ассистента.
/// Хранится в SharedPreferences, загружается один раз при старте приложения.
/// Используется для персонализации похвалы, мотивации и ответов системы.
library;

import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  static String name = '';
  static String gender = ''; // 'f' | 'm' | '' (не определён)
  static String assistantName = '';

  static bool get isSet => name.isNotEmpty;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('userName') ?? '';
      gender = prefs.getString('userGender') ?? '';
      assistantName = prefs.getString('assistantName') ?? '';
    } catch (_) {
      // без профиля приложение работает как раньше
    }
  }

  static Future<void> saveName(String n) async {
    name = n.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
  }

  static Future<void> saveGender(String g) async {
    gender = g;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userGender', g);
  }

  static Future<void> saveAssistantName(String n) async {
    assistantName = n.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assistantName', assistantName);
  }

  /// Эвристика рода по русскому имени:
  /// 'f' — женский, 'm' — мужской, '' — спросить уточнение.
  static String guessGender(String rawName) {
    var n = rawName.trim().toLowerCase();
    if (n.isEmpty) return '';
    // Унисекс / сокращения — лучше спросить.
    const ambiguous = {
      'саша', 'женя', 'валя', 'слава', 'ваня', 'шура', 'саня', 'сёма',
      'сема', 'лёша', 'леша', 'паша', 'миша', 'дима', 'деня', 'ренат',
    };
    // Мужские имена, оканчивающиеся на а/я.
    const maleA = {'никита', 'илья', 'кузьма', 'фома', 'савва', 'лёня', 'костя', 'мила'};
    if (ambiguous.contains(n)) return '';
    if (maleA.contains(n)) return 'm';
    // Женские имена на согласную/мягкий знак — редки, общее правило ниже.
    const femaleSoft = {'любовь', 'нинель', 'эстер', 'руфь', 'нелли', 'асоль'};
    if (femaleSoft.contains(n)) return 'f';
    final last = n[n.length - 1];
    if (last == 'а' || last == 'я') return 'f';
    if (last == 'й' || last == 'н' || last == 'р' || last == 'л' || last == 'м' ||
        last == 'д' || last == 'в' || last == 'с' || last == 'т' || last == 'г' ||
        last == 'б' || last == 'п' || last == 'к' || last == 'х' || last == 'з' ||
        last == 'ш' || last == 'щ' || last == 'ж' || last == 'ч' || last == 'ц' ||
        last == 'ф') {
      return 'm';
    }
    if (last == 'ь') return ''; // Игорь/Любовь — уточняем
    return '';
  }
}
