import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class InstructorsView extends StatelessWidget {
  final bool busy;
  final List<dynamic> instructors;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;

  const InstructorsView({
    super.key,
    required this.busy,
    required this.instructors,
    required this.onAction,
    required this.onForm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'THE PEOPLE BEHIND YOUR PRACTICE',
          'Meet your instructors.',
          'Manage profiles and link verified instructor accounts.',
          button: FilledButton.icon(
            onPressed: () => onForm(
              'Add instructor',
              const [
                FieldSpec('name', 'Full name'),
                FieldSpec('phone', 'Phone number'),
                FieldSpec('email', 'Account email'),
                FieldSpec('specialty', 'Specialty'),
                FieldSpec('bio', 'Description (optional)',
                    multiline: true, optional: true),
              ],
              'instructors',
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add instructor'),
          ),
        ),
        if (instructors.isEmpty)
          studioEmpty(
            'Add your first instructor to create yoga classes.',
            Icons.people_outline,
          ),
        for (final i in instructors)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i['name'] as String,
                      style: GoogleFonts.cinzel(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      i['specialty'] as String,
                      style: const TextStyle(color: plum),
                    ),
                    if (i['phone'] != null && (i['phone'] as String).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 16, color: muted),
                          const SizedBox(width: 6),
                          Text(
                            i['phone'] as String,
                            style: const TextStyle(fontSize: 14, color: ink),
                          ),
                        ],
                      ),
                    ],
                    if (i['bio'] != null && (i['bio'] as String).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(i['bio'] as String),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '${i['classesTaught']} classes taught · ${i['autoAccept'] == true ? 'Auto-accept on' : 'Manual acceptance'}',
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      i['email'] as String,
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (i['userId'] == null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (await confirm(
                                  context,
                                  'Link instructor account?',
                                  'Verify that the registered account ${i['email']} belongs to this instructor. Linking gives that account instructor access.',
                                )) {
                                  await onAction('instructors/${i['id']}/link');
                                }
                              },
                        child: const Text('Link registered account'),
                      )
                    else
                      const Text(
                        'Account linked',
                        style: TextStyle(color: plum, fontSize: 13),
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
