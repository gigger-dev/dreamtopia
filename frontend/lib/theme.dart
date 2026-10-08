import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Classical Yoga Palette ──────────────────────────────────────────────────
// Warm parchment / earthy sage tones inspired by traditional yoga aesthetics
const chakra = [
  Color(0xFF7C9E8B), // muted sage
  Color(0xFF9DB89A), // soft jade
  Color(0xFFB8C99A), // warm lime-sage
  Color(0xFF8B7355), // warm brown
  Color(0xFFA8956E), // parchment gold
  Color(0xFFB5A08A), // warm sand
  Color(0xFFCAB8A2), // light parchment
];

// Primary — warm forest sage green
const sageGreen = Color(0xFF3D6B4F);
// Light sage background tint (warm, parchment-tinged)
const sageLight = Color(0xFFF0EDE6);
// Border colour — warm taupe/sage
const sageBorder = Color(0xFFD8CFC0);
// Text ink — warm dark brown, not harsh black
const ink = Color(0xFF2A2217);
const charcoal = Color(0xFF2A2217);
// Gold accent for highlights and rankings
const gold = Color(0xFFB8860B);
// Muted text — earthy grey-brown
const muted = Color(0xFF6B5F50);
// Alias kept for backward-compat
const plum = sageGreen;

ThemeData dreamTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: sageGreen,
          surface: const Color(0xFFFAF8F4)),
      scaffoldBackgroundColor: const Color(0xFFFAF8F4),
      // Body: elegant humanist sans; headings: classical serif (Cinzel)
      fontFamily: GoogleFonts.lato().fontFamily,
      textTheme: TextTheme(
          bodyMedium: GoogleFonts.lato(fontSize: 16, color: ink),
          bodySmall: GoogleFonts.lato(fontSize: 13, color: muted),
          labelMedium: GoogleFonts.lato(fontSize: 13, color: muted),
          titleLarge: GoogleFonts.cinzel(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: ink,
              letterSpacing: 0.8),
          headlineMedium: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: ink,
              letterSpacing: 1.2)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: sageBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: sageBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: sageGreen, width: 1.5)),
          labelStyle: GoogleFonts.lato(color: muted, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: sageGreen,
              foregroundColor: Colors.white,
              textStyle: GoogleFonts.lato(
                  fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: sageGreen,
              side: const BorderSide(color: sageBorder),
              textStyle: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: sageGreen,
              textStyle: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w500))),
      dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFFAF8F4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: sageBorder))),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: sageBorder))),
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          elevation: 0,
          shadowColor: sageBorder,
          titleTextStyle: GoogleFonts.cinzel(
              fontSize: 18, fontWeight: FontWeight.w600, color: sageGreen)),
      dividerColor: sageBorder,
      chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: sageBorder)),
          backgroundColor: Colors.white,
          selectedColor: sageLight,
          labelStyle: GoogleFonts.lato(fontSize: 13)),
    );

// ── Decorative chakra / rainbow line ───────────────────────────────────────
class ChakraLine extends StatelessWidget {
  const ChakraLine({super.key});
  @override
  Widget build(BuildContext context) => Row(
      children: chakra
          .map((c) => Expanded(
              child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(1)))))
          .toList());
}

// ── Utility: SNAKE_CASE → Title Case ───────────────────────────────────────
String label(dynamic s) => s
    .toString()
    .toLowerCase()
    .split('_')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

// ── Status badge ───────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final good = ['CONFIRMED', 'SCHEDULED', 'PRESENT', 'COMPLETED', 'REVIEWED', 'ACTIVE']
        .contains(status);
    final bad =
        ['REJECTED', 'CANCELLED', 'ABSENT', 'NO_SHOW', 'DECLINED', 'EXHAUSTED', 'EXPIRED'].contains(status);
    final color = good
        ? const Color(0xFF2E6B42)
        : bad
            ? const Color(0xFF8B3A3A)
            : const Color(0xFF7A6340);
    String text = label(status);
    if (status == 'NO_SHOW') {
      text = 'No-Show';
    } else if (status == 'PENDING_INSTRUCTOR') {
      text = 'Pending Instructor';
    } else if (status == 'SCHEDULED') {
      text = 'Confirmed / Scheduled';
    } else if (status == 'PAID_AWAITING_RESOLUTION') {
      text = 'Paid · Awaiting Resolution';
    } else if (status == 'PENDING_REVIEW') {
      text = 'Pending Review';
    }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.20))),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: color,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600)));
  }
}
