/// Дизайн-токены приложения (строго по ТЗ):
/// фон #1E1E24, карточки #2B2B36, текст #E0E0E0, акцент — приглушённая бирюза.
library;

import 'package:flutter/material.dart';

class AppTheme {
  static const Color bg = Color(0xFF1E1E24);
  static const Color bgDeep = Color(0xFF18181E);
  static const Color card = Color(0xFF2B2B36);
  static const Color text = Color(0xFFE0E0E0);
  static const Color textDim = Color(0xFF9A9AA5);
  static const Color accent = Color(0xFF7FC8D8);
  static const Color accentSoft = Color(0xFF9BC7D1);
  static const Color done = Color(0xFF8FCB9B);
  static const Color warn = Color(0xFFD8C08C);
  static const Color daily = Color(0xFFB39DDB); // блок «Ежедневные» (привычки)
  static const Color danger = Color(0xFFE08E8E); // просроченное / критическое
  static const Color critical = Color(0xFFE05252); // ярко-красный: критичные задачи
  static const Color shortTerm = Color(0xFF7FA8E0); // синий контур краткосрочных задач

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        primaryColor: accent,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: card,
          onSurface: text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        cardColor: card,
        tabBarTheme: const TabBarTheme(
          labelColor: accent,
          unselectedLabelColor: textDim,
          indicatorColor: accent,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: bg,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgDeep,
          selectedItemColor: accent,
          unselectedItemColor: textDim,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          hintStyle: const TextStyle(color: textDim),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        dialogTheme: DialogTheme(
          backgroundColor: card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: const TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: card,
          contentTextStyle: TextStyle(color: text),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: accent,
          linearTrackColor: card,
        ),
        listTileTheme: const ListTileThemeData(textColor: text, iconColor: textDim),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: text),
          bodyLarge: TextStyle(color: text),
          titleMedium: TextStyle(color: text),
        ),
        useMaterial3: true,
      );
}
