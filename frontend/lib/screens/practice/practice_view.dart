import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'KEEP GROWING',
          'Your practice, at a glance.',
          'Every class is a step forward.',
        ),
        Wrap(spacing: 16, runSpacing: 16, children: [
          studioStat('Classes remaining', '${me['credits']}', 'Available to book'),
          studioStat(
            'Classes attended',
            '${bookings.where((b) => b['attendance'] == 'PRESENT').length}',
            'Sessions completed',
            tinted: true,
          ),
        ]),
        const SizedBox(height: 28),
        Text('Class credit activity', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 14),
        if (ledger.isEmpty)
          studioEmpty(
            'Credit activity will appear here as you buy passes and attend classes.',
            Icons.receipt_long_outlined,
          ),
        for (final entry in ledger)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: Icon(
                  (entry['delta'] as int) > 0
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: (entry['delta'] as int) > 0 ? sageGreen : plum,
                ),
                title: Text(entry['reason'] as String),
                subtitle: Text(onFormatDate(entry['createdAt'])),
                trailing: Text(
                  '${(entry['delta'] as int) > 0 ? '+' : ''}${entry['delta']}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (entry['delta'] as int) > 0 ? sageGreen : plum,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 28),
        Text('Attended sessions', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 14),
        for (final b in bookings.where((b) => b['attendance'] != 'UNMARKED'))
          Card(
            child: ListTile(
              title: Text(b['session']['title'] as String),
              subtitle: Text(onFormatDate(b['session']['startsAt'])),
              trailing: StatusBadge(b['attendance'] as String),
            ),
          ),
      ],
    );
  }
}
