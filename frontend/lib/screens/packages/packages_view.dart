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
    return Column(
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
        for (final p in packageProducts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${p['credits']} credits · ${_money(p['price'])} · Valid ${p['validityDays']} days',
                            style: const TextStyle(
                              color: plum,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (p['description'] != null &&
                              (p['description'] as String).isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              p['description'] as String,
                              style: const TextStyle(color: muted, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (member)
                      FilledButton(
                        onPressed: busy ? null : () => onPurchasePackage(p as Map<String, dynamic>),
                        child: const Text('Buy Package'),
                      ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 32),

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
        for (final mp in packages)
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
                        mp['packageProduct']?['name']?.toString() ?? 'Class Package',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                      StatusBadge(mp['status'] as String),
                    ]),
                    const SizedBox(height: 10),
                    if (admin && mp['user'] != null)
                      Text(
                        'Member: ${mp['user']['name']} (${mp['user']['email']})',
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Credits: ${mp['creditsRemaining']} / ${mp['creditsTotal']} remaining · Paid: ${_money(mp['pricePaid'])}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (mp['expiresAt'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expires: ${onFormatDate(mp['expiresAt'])}',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                    if (mp['rejectionReason'] != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Rejection reason: ${mp['rejectionReason']}',
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (mp['proofId'] != null)
                        OutlinedButton.icon(
                          onPressed: () => onViewProof(mp['proofId'] as String),
                          icon: const Icon(Icons.receipt_long_outlined, size: 17),
                          label: const Text('Payment proof'),
                        ),
                      if (admin && mp['status'] == 'PENDING_REVIEW') ...[
                        FilledButton(
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
                          child: const Text('Approve & Activate'),
                        ),
                        OutlinedButton(
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
                          child: const Text('Reject'),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
