import 'package:flutter/material.dart';
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 700
                    ? constraints.maxWidth * (2 / 3)
                    : double.infinity;
                const accentColor = plum;

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
                            // Header: Name on left, Email on right
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    i['name'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  i['email'] as String,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 13,
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: plum.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    i['specialty'] as String,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: plum,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sageGreen.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${i['classesTaught']} classes taught · ${i['autoAccept'] == true ? 'Auto-accept on' : 'Manual acceptance'}',
                                    style: const TextStyle(
                                      color: sageGreen,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (i['phone'] != null &&
                                    (i['phone'] as String).isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.phone_outlined,
                                          size: 13,
                                          color: muted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          i['phone'] as String,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            if (i['bio'] != null &&
                                (i['bio'] as String).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                i['bio'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: ink,
                                  height: 1.4,
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Trailing Action Button / Linked Status
                            Align(
                              alignment: Alignment.centerRight,
                              child: i['userId'] == null
                                  ? FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                      ),
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              if (await confirm(
                                                context,
                                                'Link instructor account?',
                                                'Verify that the registered account ${i['email']} belongs to this instructor. Linking gives that account instructor access.',
                                              )) {
                                                await onAction(
                                                  'instructors/${i['id']}/link',
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.link, size: 16),
                                      label: const Text(
                                        'Link registered account',
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sageGreen.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 14,
                                            color: sageGreen,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            'Account linked',
                                            style: TextStyle(
                                              color: sageGreen,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
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
