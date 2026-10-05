import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

Widget studioHeading(
  BuildContext context,
  String eyebrow,
  String title,
  String subtitle, {
  Widget? button,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= 600;
      return isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: GoogleFonts.lato(
                          letterSpacing: 2.5,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: sageGreen,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                if (button != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: button,
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  eyebrow,
                  style: GoogleFonts.lato(
                    letterSpacing: 2.5,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: sageGreen,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
                if (button != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: button),
                ],
              ],
            );
    }),
  );
}

Widget studioEmpty(String text, IconData icon) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 34, color: plum),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget studioStat(
  String title,
  String value,
  String subtitle, {
  bool tinted = false,
}) {
  return LayoutBuilder(builder: (context, constraints) {
    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
      child: Card(
        color: tinted ? sageLight : null,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  color: tinted ? plum : ink,
                  fontFamily: tinted
                      ? GoogleFonts.cinzel().fontFamily
                      : GoogleFonts.lato().fontFamily,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  });
}
