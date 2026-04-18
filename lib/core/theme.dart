import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';

// Промышленная тёмная тема согласно ТЗ:
//   bg:       #050505
//   surface:  #111111
//   surface2: #1C1C1C
//   green:    #00FF88  (ГОДНО)
//   red:      #FF3355  (БРАК)
//   accent:   #6366F1  (кнопки)
//   Шрифт:    JetBrains Mono (промышленный вид)

class AppTheme {
  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.jetBrainsMonoTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppPalette.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppPalette.okGreen,
        onPrimary: AppPalette.bg,
        secondary: AppPalette.accent,
        onSecondary: Colors.white,
        surface: AppPalette.surface,
        onSurface: Colors.white,
        error: AppPalette.defectRed,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.jetBrainsMono(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppPalette.borderSoft),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.jetBrainsMono(
              fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppPalette.borderSoft),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.jetBrainsMono(
              fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.okGreen,
        foregroundColor: AppPalette.bg,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppPalette.surface,
        selectedItemColor: AppPalette.okGreen,
        unselectedItemColor: AppPalette.subtext,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.surface2,
        labelStyle: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
        side: const BorderSide(color: AppPalette.borderSoft),
      ),
      dividerColor: AppPalette.borderSoft,
    );
  }
}
