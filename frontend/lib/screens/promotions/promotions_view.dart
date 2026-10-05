import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class PromotionsView extends StatelessWidget {
  final bool busy;
  final List<dynamic> promos;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const PromotionsView({
    super.key,
    required this.busy,
    required this.promos,
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
          'A LITTLE EXTRA MAGIC',
          'Studio promotions.',
          'Percentage discounts for bank-transfer bookings.',
          button: FilledButton.icon(
            onPressed: () => onForm(
              'Create promotion',
              const [
                FieldSpec('code', 'Promotion code'),
                FieldSpec('percent', 'Discount percentage (1–100)',
                    number: true),
                FieldSpec('expiresAt', 'Expires at', dateTime: true),
              ],
              'promotions',
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create promotion'),
          ),
        ),
        if (promos.isEmpty)
          studioEmpty('Create your first studio offer.', Icons.local_offer_outlined),
        for (final p in promos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: SwitchListTile(
                title: Text('${p['code']} · ${p['percent']}% off'),
                subtitle: Text('Expires ${onFormatDate(p['expiresAt'])}'),
                value: p['active'] as bool,
                onChanged: busy
                    ? null
                    : (v) => onAction(
                          'promotions/${p['id']}',
                          method: 'PATCH',
                          body: {'active': v},
                        ),
              ),
            ),
          ),
        const SizedBox(height: 30),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share something new.',
                  style: GoogleFonts.cinzel(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Publish an in-app campaign notification to every member.',
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => onForm(
                    'Notify all members',
                    const [
                      FieldSpec('title', 'Campaign title'),
                      FieldSpec('body', 'Message', multiline: true),
                    ],
                    'campaigns',
                    submit: 'Publish notification',
                    note:
                        'This message will appear in every member’s notification inbox.',
                  ),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('New campaign'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
