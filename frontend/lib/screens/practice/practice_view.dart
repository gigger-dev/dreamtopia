import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../widgets/studio_common.dart';

class PracticeView extends StatelessWidget {
  final Map<String, dynamic> me;
  final List<dynamic> bookings;
  final List<dynamic> ledger;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const PracticeView({
    super.key,
    required this.me,
    required this.bookings,
    required this.ledger,
    required this.onFormatDate,
  });

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required Color accentColor,
    bool isAccent = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sageBorder.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: isAccent ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: isAccent ? sageGreen : ink,
                  fontFamily: isAccent
                      ? GoogleFonts.cinzel().fontFamily
                      : GoogleFonts.lato().fontFamily,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attendedCount =
        bookings.where((b) => b['attendance'] == 'PRESENT').length;

    final stat1 = _buildStatCard(
      title: 'Classes remaining',
      value: '${me['credits'] ?? 0}',
      subtitle: 'Available class credits to book',
      accentColor: sageGreen,
    );

    final stat2 = _buildStatCard(
      title: 'Classes attended',
      value: '$attendedCount',
      subtitle: 'Sessions completed',
      accentColor: chakra[1],
    );

    final stat3 = _buildStatCard(
      title: 'SEVEN COLORS. ONE YOU.',
      value: 'Find your balance.',
      subtitle: 'Own your strength.',
      accentColor: chakra[3],
      isAccent: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'KEEP GROWING',
          'Your practice, at a glance.',
          'Every class is a step forward.',
        ),
        // 3 stat cards matching Schedule screen
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 768;
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: stat1),
                  const SizedBox(width: 14),
                  Expanded(child: stat2),
                  const SizedBox(width: 14),
                  Expanded(child: stat3),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stat1,
                  const SizedBox(height: 12),
                  stat2,
                  const SizedBox(height: 12),
                  stat3,
                ],
              );
            }
          },
        ),
        const SizedBox(height: 32),

        // Class credit activity section
        Text(
          'Class credit activity',
          style: GoogleFonts.cinzel(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 14),
        if (ledger.isEmpty)
          studioEmpty(
            'Credit activity will appear here as you buy passes and attend classes.',
            Icons.receipt_long_outlined,
          ),
        for (int idx = 0; idx < ledger.length; idx++) ...[
          () {
            final entry = ledger[idx];
            final delta = (entry['delta'] as int? ?? 0);
            final isPositive = delta > 0;
            final itemAccent = isPositive ? sageGreen : chakra[0];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sageBorder.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: itemAccent, width: 4),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: itemAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 18,
                          color: itemAccent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['reason'] as String? ?? 'Credit adjustment',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              onFormatDate(entry['createdAt']),
                              style: const TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${isPositive ? '+' : ''}$delta',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPositive ? sageGreen : plum,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
        ],

        const SizedBox(height: 32),

        // Attended sessions section
        Text(
          'Attended sessions',
          style: GoogleFonts.cinzel(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 14),
        () {
          final attended = bookings
              .where((b) => b['attendance'] != null && b['attendance'] != 'UNMARKED')
              .toList();

          if (attended.isEmpty) {
            return studioEmpty(
              'No attended sessions recorded yet.',
              Icons.event_available_outlined,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < attended.length; i++) ...[
                () {
                  final b = attended[i];
                  final cardAccent = chakra[i % chakra.length];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sageBorder.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: cardAccent, width: 4),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cardAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.fitness_center,
                                size: 18,
                                color: cardAccent,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b['session']['title'] as String? ?? 'Studio Session',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    onFormatDate(b['session']['startsAt']),
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(b['attendance'] as String),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
              ],
            ],
          );
        }(),
      ],
    );
  }
}
