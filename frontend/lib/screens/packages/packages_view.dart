import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../api.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class PackagesView extends StatelessWidget {
  final Api api;
  final bool admin;
  final bool member;
  final bool busy;
  final List<dynamic> packageProducts;
  final List<dynamic> packages;
  final String currency;
  final String timezone;
  final String? bankInstructions;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final Future<void> Function(Map<String, dynamic> product) onPurchasePackage;
  final Future<void> Function(String proofId) onViewProof;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const PackagesView({
    super.key,
    required this.api,
    required this.admin,
    required this.member,
    required this.busy,
    required this.packageProducts,
    required this.packages,
    required this.currency,
    required this.timezone,
    this.bankInstructions,
    required this.onAction,
    required this.onForm,
    required this.onPurchasePackage,
    required this.onViewProof,
    required this.onFormatDate,
  });

  String _money(dynamic n) => '$n $currency';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        studioHeading(
          context,
          'PACKAGES & PASSES',
          admin ? 'Studio class packages.' : 'Class packages & passes.',
          admin
              ? 'Manage catalog offerings and review member package purchases.'
              : 'Purchase bundled class credits or view your package status.',
          button: admin
              ? FilledButton.icon(
                  onPressed: () => onForm(
                    'Create Package Product',
                    const [
                      FieldSpec('name', 'Package name (e.g. 8-Class Flow Pass)'),
                      FieldSpec('description', 'Description (optional)',
                          multiline: true, optional: true),
                      FieldSpec('credits', 'Number of credits (e.g. 4 or 8)',
                          number: true, initial: '4'),
                      FieldSpec('price', 'Price in MMK',
                          number: true, initial: '90000'),
                      FieldSpec('validityDays', 'Validity in days (e.g. 30, 60)',
                          number: true, initial: '30'),
                    ],
                    'admin/packages/products',
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create package'),
                )
              : null,
        ),

        // Available Package Products
        Text(
          'Available Packages',
          style: GoogleFonts.cinzel(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 14),
        if (packageProducts.isEmpty)
          studioEmpty('No packages currently offered.', Icons.card_membership_outlined),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 750;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (int i = 0; i < packageProducts.length; i++) ...[
                Builder(builder: (context) {
                  final p = packageProducts[i];
                  final itemWidth = isWide ? (constraints.maxWidth - 16) / 2 : double.infinity;
                  return Container(
                    width: itemWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sageBorder.withValues(alpha: 0.8)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: ink,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sageGreen,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${p['credits']} Credits',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _money(p['price']),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: plum,
                              ),
                            ),
                            Text(
                              '· Valid ${p['validityDays']} days',
                              style: const TextStyle(
                                fontSize: 13,
                                color: muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (p['description'] != null &&
                            (p['description'] as String).isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            p['description'] as String,
                            style: const TextStyle(color: muted, fontSize: 13, height: 1.3),
                          ),
                        ],
                        if (member) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: busy ? null : () => onPurchasePackage(p as Map<String, dynamic>),
                              icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                              label: const Text('Buy Package'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        }),

        const SizedBox(height: 36),

        // Member Packages / Purchases Queue
        Text(
          admin ? 'Member Package Purchases' : 'My Purchased Packages',
          style: GoogleFonts.cinzel(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 14),
        if (packages.isEmpty)
          studioEmpty(
            admin
                ? 'No package orders submitted yet.'
                : 'You haven’t bought any packages yet.',
            Icons.receipt_outlined,
          ),
        for (int idx = 0; idx < packages.length; idx++)
          LayoutBuilder(builder: (context, constraints) {
            final mp = packages[idx];
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
                        // Header: Title on left, Status Badge on right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                mp['packageProduct']?['name']?.toString() ?? 'Class Package',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(mp['status'] as String),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Member details if admin
                        if (admin && mp['user'] != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.person_outline, size: 14, color: muted),
                              const SizedBox(width: 4),
                              Text(
                                '${mp['user']['name']} (${mp['user']['email']})',
                                style: const TextStyle(fontSize: 13, color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Credits Remaining & Price Metadata Row
                        Wrap(
                          spacing: 12,
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
                                '${mp['creditsRemaining']} / ${mp['creditsTotal']} credits left',
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.payments_outlined, size: 13, color: plum),
                                  const SizedBox(width: 4),
                                  Text(
                                    _money(mp['pricePaid']),
                                    style: const TextStyle(
                                      color: plum,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (mp['expiresAt'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.event_outlined, size: 13, color: muted),
                              const SizedBox(width: 4),
                              Text(
                                'Expires: ${onFormatDate(mp['expiresAt'])}',
                                style: const TextStyle(color: muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                        if (mp['rejectionReason'] != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Rejection reason: ${mp['rejectionReason']}',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),

                        // Actions Row aligned to the end
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              if (mp['proofId'] != null)
                                OutlinedButton.icon(
                                  onPressed: () => onViewProof(mp['proofId'] as String),
                                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                                  label: const Text('Payment proof'),
                                ),
                              if (admin && mp['status'] == 'PENDING_REVIEW') ...[
                                FilledButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await confirm(
                                            context,
                                            'Activate package?',
                                            'Confirm that you verified payment against bank records. Approving will activate the package and grant ${mp['creditsTotal']} credits to ${mp['user']?['name']}.',
                                          )) {
                                            await onAction(
                                              'packages/${mp['id']}/approve',
                                              success: 'Package activated and credits issued!',
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.check, size: 15),
                                  label: const Text('Approve & Activate'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => onForm(
                                            'Reject package purchase',
                                            const [
                                              FieldSpec('reason', 'Reason for rejection',
                                                  multiline: true)
                                            ],
                                            'packages/${mp['id']}/reject',
                                            submit: 'Reject package',
                                          ),
                                  icon: const Icon(Icons.close, size: 15),
                                  label: const Text('Reject'),
                                ),
                              ],
                            ],
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
      ),
    );
  }
}
