import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ZyiarahTheme {
  static const Color brand = Color(0xFF5D1B5E);
  static const Color brandLight = Color(0xFF8B3D8C);
  static const Color brandDark = Color(0xFF3D1040);
  static const Color accent = Color(0xFFE8427A);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color inkFaint = Color(0xFFCBD5E1);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  static ThemeData get light {
    final base = ColorScheme.fromSeed(
      seedColor: brand,
      surface: surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: surface,

      textTheme: GoogleFonts.tajawalTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: ink, fontWeight: FontWeight.w800),
          displayMedium: TextStyle(color: ink, fontWeight: FontWeight.w700),
          headlineLarge: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 26),
          headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 22),
          headlineSmall: TextStyle(color: ink, fontWeight: FontWeight.bold, fontSize: 18),
          titleLarge: TextStyle(color: ink, fontWeight: FontWeight.bold, fontSize: 16),
          titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 14),
          titleSmall: TextStyle(color: inkMuted, fontWeight: FontWeight.w500, fontSize: 13),
          bodyLarge: TextStyle(color: ink, fontSize: 15, height: 1.6),
          bodyMedium: TextStyle(color: inkMuted, fontSize: 13, height: 1.5),
          bodySmall: TextStyle(color: inkMuted, fontSize: 11),
          labelLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white.withValues(alpha: 0.85),
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.tajawal(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: ink),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: const BorderSide(color: brand, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.tajawal(color: inkFaint, fontSize: 14),
        labelStyle: GoogleFonts.tajawal(color: inkMuted, fontSize: 14),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: Color(0xFFCBD5E1),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5F9),
        selectedColor: brand.withValues(alpha: 0.12),
        labelStyle: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFFF1F5F9),
        thickness: 1,
        space: 0,
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: GoogleFonts.tajawal(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: Color(0xFFEDE1ED),
      ),

      iconTheme: const IconThemeData(color: inkMuted, size: 22),
    );
  }
}
