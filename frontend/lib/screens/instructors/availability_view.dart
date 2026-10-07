import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class AvailabilityView extends StatelessWidget {
  final Map<String, dynamic>? me;
  final bool busy;
  final List<dynamic> blocks;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const AvailabilityView({
    super.key,
    required this.me,
    required this.busy,
    required this.blocks,
    required this.onAction,
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
          'MAKE SPACE FOR YOU',
          'Your availability.',
          'Blocks keep unavailable time out of the studio schedule.',
          button: FilledButton.icon(
            onPressed: () => onForm(
              'Block unavailable time',
              const [
                FieldSpec('startsAt', 'Unavailable from', dateTime: true),
                FieldSpec('endsAt', 'Unavailable until', dateTime: true),
                FieldSpec('reason', 'Reason'),
              ],
              'instructor/blocks',
            ),
            icon: const Icon(Icons.add),
            label: const Text('Block time'),
          ),
        ),
        // Settings card: Auto-accept toggle with matching 2/3 responsive width & left accent border
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 700
                ? constraints.maxWidth * (2 / 3)
                : double.infinity;
            final isAutoAccept = me?['instructor']?['autoAccept'] == true;

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
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: sageGreen, width: 4),
                      ),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Text(
                                'Automatically accept new classes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: ink,
                                ),
                              ),
                            ),
                            Switch(
                              value: isAutoAccept,
                              activeColor: sageGreen,
                              onChanged: busy
                                  ? null
                                  : (v) => onAction(
                                        'instructor/settings',
                                        method: 'PATCH',
                                        body: {'autoAccept': v},
                                      ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'New admin-approved assignments are accepted immediately. Existing invitations still need your response.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                            height: 1.4,
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
        const SizedBox(height: 24),
        if (blocks.isEmpty)
          studioEmpty(
            'No unavailable time added.',
            Icons.event_available_outlined,
          ),
        for (int idx = 0; idx < blocks.length; idx++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final b = blocks[idx];
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
                            // Header: Reason on left, Delete action on right
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    b['reason'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await confirm(
                                            context,
                                            'Remove this block?',
                                            'The studio will be able to assign classes during this time.',
                                          )) {
                                            await onAction(
                                              'instructor/blocks/${b['id']}',
                                              method: 'DELETE',
                                            );
                                          }
                                        },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Remove block',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Date / Time badge
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: plum.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule,
                                        size: 14,
                                        color: plum,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '${onFormatDate(b['startsAt'])} – Until ${onFormatDate(b['endsAt'])}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: plum,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
