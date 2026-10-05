import 'package:flutter/material.dart';
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
        Card(
          child: SwitchListTile(
            title: const Text('Automatically accept new classes'),
            subtitle: const Text(
              'New admin-approved assignments are accepted immediately. Existing invitations still need your response.',
            ),
            value: me?['instructor']?['autoAccept'] == true,
            onChanged: busy
                ? null
                : (v) => onAction(
                      'instructor/settings',
                      method: 'PATCH',
                      body: {'autoAccept': v},
                    ),
          ),
        ),
        const SizedBox(height: 24),
        if (blocks.isEmpty)
          studioEmpty('No unavailable time added.', Icons.event_available_outlined),
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                title: Text(b['reason'] as String),
                subtitle: Text(
                  '${onFormatDate(b['startsAt'])}\nUntil ${onFormatDate(b['endsAt'])}',
                ),
                isThreeLine: true,
                trailing: IconButton(
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
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove block',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
