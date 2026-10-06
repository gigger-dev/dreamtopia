import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

const requestSessionTypes = {
  'POLE_CLASS': 'Pole classes',
  'TRIAL': 'Trial classes',
  'PRACTICE': 'Pole practice',
  'RENTAL': 'Studio rental',
};

class RequestsView extends StatelessWidget {
  final bool admin;
  final bool member;
  final List<dynamic> requests;
  final VoidCallback onRequestTime;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const RequestsView({
    super.key,
    required this.admin,
    required this.member,
    required this.requests,
    required this.onRequestTime,
    required this.onForm,
    required this.onFormatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'FIND YOUR TIME',
          'Preferred timeslots.',
          admin
              ? 'Review member requests and create a session when it works.'
              : 'Ask the studio for a time that fits your day.',
          button: member
              ? FilledButton.icon(
                  onPressed: onRequestTime,
                  icon: const Icon(Icons.add),
                  label: const Text('Request a time'),
                )
              : null,
        ),
        if (requests.isEmpty)
          studioEmpty('No timeslot requests yet.', Icons.schedule_outlined),
        for (int idx = 0; idx < requests.length; idx++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final r = requests[idx];
                final accentColor = chakra[idx % chakra.length];
                final cardWidth = constraints.maxWidth >= 700
                    ? constraints.maxWidth * (2 / 3)
                    : double.infinity;

                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: cardWidth,
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
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accentColor, width: 4),
                          ),
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header: Session Type on left, Status on right
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  requestSessionTypes[r['type']] ?? '',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: ink,
                                  ),
                                ),
                                StatusBadge(r['status'] as String),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Time & member info
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 14, color: accentColor),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${onFormatDate(r['startsAt'])} – ${onFormatDate(r['endsAt'], 'HH:mm')}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                                if (admin && r['member'] != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person_outline,
                                          size: 14, color: muted),
                                      const SizedBox(width: 4),
                                      Text(
                                        r['member']['name'] as String,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),

                            if (r['note'] != null &&
                                (r['note'] as String).isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                r['note'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: ink,
                                  height: 1.4,
                                ),
                              ),
                            ],

                            if (r['response'] != null &&
                                (r['response'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: plum.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Studio: ${r['response']}',
                                  style: const TextStyle(
                                    color: plum,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],

                            if (admin && r['status'] == 'PENDING') ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () => onForm(
                                    'Respond to request',
                                    const [
                                      FieldSpec('status', 'Response', options: {
                                        'REVIEWED':
                                            'Reviewed — follow up / create session',
                                        'DECLINED': 'Unable to accommodate',
                                      }),
                                      FieldSpec('response', 'Message to member',
                                          multiline: true),
                                    ],
                                    'requests/${r['id']}',
                                    method: 'PATCH',
                                    note:
                                        'Reviewing does not automatically create a class. Create it in the schedule, then invite the member to book.',
                                  ),
                                  child: const Text('Respond'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
