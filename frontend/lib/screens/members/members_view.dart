import 'package:flutter/material.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class MembersView extends StatelessWidget {
  final bool busy;
  final List<dynamic> members;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;

  const MembersView({
    super.key,
    required this.busy,
    required this.members,
    required this.onForm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'YOUR COMMUNITY',
          'Studio members.',
          'Add package credits after verifying package payment.',
        ),
        if (members.isEmpty)
          studioEmpty(
            'Members appear after they create an account.',
            Icons.groups_outlined,
          ),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                title: Text(
                  m['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${m['email']}\n${m['credits']} credits remaining · ${m['_count']?['bookings'] ?? 0} classes attended',
                ),
                isThreeLine: true,
                trailing: FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => onForm(
                            'Grant credits',
                            const [
                              FieldSpec('credits', 'Credits to add (1–50)',
                                  number: true, initial: '1'),
                              FieldSpec('reason', 'Reason',
                                  initial: '10-class pack payment verified')
                            ],
                            'members/${m['id']}/credits',
                            note:
                                'Only grant credits after you have checked the member’s transfer or cash payment.',
                          ),
                  child: const Text('Add credits'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
