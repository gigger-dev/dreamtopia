import 'package:flutter/material.dart';

const chakra = [
  Color(0xFFE66D85),
  Color(0xFFEEA15F),
  Color(0xFFD8BE4A),
  Color(0xFF72AD8A),
  Color(0xFF62A6CB),
  Color(0xFF797DBB),
  Color(0xFF9C6DBB)
];
const plum = Color(0xFF8055A3);
const ink = Color(0xFF33283F);
const muted = Color(0xFF80748B);
ThemeData dreamTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: plum, surface: Colors.white),
      scaffoldBackgroundColor: const Color(0xFFFAF8FC),
      textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: ink),
          bodySmall: TextStyle(fontSize: 13, color: muted),
          titleLarge: TextStyle(fontSize: 24, color: ink),
          headlineMedium:
              TextStyle(fontSize: 34, fontFamily: 'serif', color: ink)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9F6FC),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE7DEEF))),
          contentPadding: const EdgeInsets.all(16)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: plum,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFEAE3F0)))),
      dividerColor: const Color(0xFFEAE3F0),
    );

class ChakraLine extends StatelessWidget {
  const ChakraLine({super.key});
  @override
  Widget build(BuildContext context) => Row(
      children: chakra
          .map((c) => Expanded(
              child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(4)))))
          .toList());
}

String label(dynamic s) => s
    .toString()
    .toLowerCase()
    .split('_')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final good = ['CONFIRMED', 'SCHEDULED', 'PRESENT', 'COMPLETED', 'REVIEWED']
        .contains(status);
    final bad =
        ['REJECTED', 'CANCELLED', 'ABSENT', 'DECLINED'].contains(status);
    final color = good
        ? const Color(0xFF38724D)
        : bad
            ? const Color(0xFFAA3E56)
            : plum;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(7)),
        child: Text(label(status),
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)));
  }
}
