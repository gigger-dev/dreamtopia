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
        for (int idx = 0; idx < promos.length; idx++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final p = promos[idx];
                final accentColor = chakra[idx % chakra.length];
                final cardWidth = constraints.maxWidth >= 700
                    ? constraints.maxWidth * (2 / 3)
                    : double.infinity;
                final isActive = p['active'] as bool;

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
                            // Header: Promo Code & percent on left, Switch on right
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${p['code']} · ${p['percent']}% off',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.3,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeColor: sageGreen,
                                  onChanged: busy
                                      ? null
                                      : (v) => onAction(
                                            'promotions/${p['id']}',
                                            method: 'PATCH',
                                            body: {'active': v},
                                          ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Subtitle / Details row
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.event_outlined,
                                      size: 14,
                                      color: muted,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Expires ${onFormatDate(p['expiresAt'])}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isActive ? sageGreen : muted)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isActive ? sageGreen : muted,
                                    ),
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
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
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
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: sageGreen, width: 4),
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Share something new.',
                          style: GoogleFonts.cinzel(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Publish an in-app campaign notification to every member.',
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
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
                            icon: const Icon(Icons.campaign_outlined, size: 17),
                            label: const Text('New campaign'),
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
      ],
    );
  }
}
