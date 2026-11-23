/// Значки блоков годового плана. В поле goals.icon хранится строка:
/// «ключ» (обычный размер) или «mini:ключ» (минималистичный значок,
/// по размеру как иконки приоритета).
library;

import 'package:flutter/material.dart';

const Map<String, IconData> blockIconMap = {
  'folder': Icons.folder_outlined,
  'health': Icons.favorite_outline,
  'finance': Icons.account_balance_wallet_outlined,
  'work': Icons.work_outline,
  'home': Icons.home_outlined,
  'family': Icons.family_restroom_outlined,
  'study': Icons.school_outlined,
  'sport': Icons.fitness_center_outlined,
  'travel': Icons.flight_outlined,
  'hobby': Icons.palette_outlined,
  'star': Icons.star_outline,
  'fire': Icons.local_fire_department_outlined,
  'leaf': Icons.eco_outlined,
  'book': Icons.menu_book_outlined,
  'car': Icons.directions_car_outlined,
  'cart': Icons.shopping_cart_outlined,
  'bolt': Icons.bolt,
  'flag': Icons.flag_outlined,
  'music': Icons.music_note_outlined,
  'food': Icons.restaurant_outlined,
};

/// Ключ значка без префикса размера.
String blockIconKey(String raw) => raw.startsWith('mini:') ? raw.substring(5) : raw;

/// Минималистичный ли значок (маленький, как иконки приоритета).
bool blockIconIsMini(String raw) => raw.startsWith('mini:');

/// Иконка по сохранённой строке ('' -> папка по умолчанию).
IconData blockIconOf(String raw) =>
    blockIconMap[blockIconKey(raw)] ?? Icons.folder_outlined;

/// Виджет значка блока с учётом выбранного размера.
Widget blockIconWidget(String raw, {Color color = const Color(0xFF7FC8D8)}) {
  final mini = blockIconIsMini(raw);
  return Icon(blockIconOf(raw), size: mini ? 16 : 24, color: color);
}
