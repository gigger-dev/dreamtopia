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
        for (final r in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      Text(
                        requestSessionTypes[r['type']] ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      StatusBadge(r['status'] as String),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      '${onFormatDate(r['startsAt'])} – ${onFormatDate(r['endsAt'], 'HH:mm')}',
                    ),
                    if (admin)
                      Text(
                        r['member']['name'] as String,
                        style: const TextStyle(color: muted),
                      ),
                    const SizedBox(height: 12),
                    Text(r['note'] as String),
                    if (r['response'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Studio: ${r['response']}',
                          style: const TextStyle(color: plum),
                        ),
                      ),
                    if (admin && r['status'] == 'PENDING')
                      TextButton(
                        onPressed: () => onForm(
                          'Respond to request',
                          const [
                            FieldSpec('status', 'Response', options: {
                              'REVIEWED': 'Reviewed — follow up / create session',
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
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
