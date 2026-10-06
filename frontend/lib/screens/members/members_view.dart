import 'package:flutter/material.dart';
import '../../theme.dart';
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        for (int idx = 0; idx < members.length; idx++)
          LayoutBuilder(builder: (context, constraints) {
            final m = members[idx];
            final accentColor = chakra[idx % chakra.length];
            final cardWidth = constraints.maxWidth >= 700
                ? constraints.maxWidth * (2 / 3)
                : double.infinity;

            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: cardWidth,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sageBorder.withValues(alpha: 0.6)),
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
                        // Header: Name on left, Email on right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                m['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              m['email'] as String,
                              style: const TextStyle(color: muted, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Badges Row
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sageGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${m['credits']} credits remaining',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: sageGreen,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: plum.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${m['_count']?['bookings'] ?? 0} classes attended',
                                style: const TextStyle(
                                  color: plum,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),

                        // Trailing Action Button
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
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
                            icon: const Icon(Icons.add_circle_outline, size: 15),
                            label: const Text('Add credits'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
