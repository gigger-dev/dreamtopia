import 'package:flutter/material.dart';
import '../../api.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';

class BookingsView extends StatefulWidget {
  final Api api;
  final bool admin;
  final bool teacher;
  final bool member;
  final bool busy;
  final List<dynamic> bookings;
  final List<dynamic> sessions;
  final String currency;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final Future<void> Function(String proofId) onViewProof;
  final String Function(dynamic iso, [String pattern]) onFormatDate;

  const BookingsView({
    super.key,
    required this.api,
    required this.admin,
    required this.teacher,
    required this.member,
    required this.busy,
    required this.bookings,
    required this.sessions,
    required this.currency,
    required this.onAction,
    required this.onForm,
    required this.onViewProof,
    required this.onFormatDate,
  });

  @override
  State<BookingsView> createState() => _BookingsViewState();
}

class _BookingsViewState extends State<BookingsView> {
  String bookingFilter = 'ALL';

  String _money(dynamic n) => '$n ${widget.currency}';

  @override
  Widget build(BuildContext context) {
    final filteredBookings = widget.bookings.where((b) {
      if (bookingFilter == 'ALL') return true;
      return b['status'] == bookingFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'YOUR STUDIO SPACE',
          widget.admin
              ? 'Booking desk.'
              : widget.teacher
                  ? 'Class attendance.'
                  : 'Your next moments.',
          '${widget.bookings.length} bookings · ${widget.admin ? 'Review payments and confirm places' : widget.teacher ? 'Record attendance after class starts' : 'Manage your sessions and attendance'}',
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in const {
            'ALL': 'All bookings',
            'PENDING': 'Pending Review',
            'PAID_AWAITING_RESOLUTION': 'Needs Resolution',
            'CONFIRMED': 'Confirmed',
            'CANCELLED': 'Cancelled',
          }.entries)
            ChoiceChip(
              label: Text(
                entry.value,
                style: const TextStyle(fontSize: 12, color: Colors.black),
              ),
              selected: bookingFilter == entry.key,
              onSelected: (_) => setState(() => bookingFilter = entry.key),
            ),
        ]),
        const SizedBox(height: 16),
        if (filteredBookings.isEmpty)
          studioEmpty(
            'No bookings found matching filter.',
            Icons.confirmation_number_outlined,
          ),
        for (final b in filteredBookings)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 12, runSpacing: 10, children: [
                      Text(
                        b['session']['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                      StatusBadge(b['status'] as String),
                      StatusBadge(b['attendance'] as String),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      widget.onFormatDate(b['session']['startsAt']),
                      style: const TextStyle(color: muted, fontSize: 14),
                    ),
                    if (!widget.member) Text(b['member']['name'] as String),
                    const SizedBox(height: 8),
                    Text(
                      b['paymentMethod'] == 'CREDITS'
                          ? '1 class credit'
                          : _money(b['amount']),
                      style: const TextStyle(color: plum, fontSize: 14),
                    ),
                    if (b['rejectionReason'] != null)
                      Text(b['rejectionReason'] as String),
                    if (b['overrideReason'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Note: ${b['overrideReason']}',
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (b['proofId'] != null && (widget.admin || widget.member))
                        OutlinedButton.icon(
                          onPressed: () => widget.onViewProof(b['proofId'] as String),
                          icon: const Icon(Icons.receipt_long_outlined, size: 17),
                          label: const Text('Payment proof'),
                        ),
                      if (widget.admin && b['status'] == 'PENDING') ...[
                        FilledButton(
                          onPressed: widget.busy
                              ? null
                              : () async {
                                  if (await confirm(
                                    context,
                                    'Confirm this booking?',
                                    b['paymentMethod'] == 'CREDITS'
                                        ? 'Confirm this member’s reserved class credit?'
                                        : 'Confirm only after you have verified the payment screenshot against your bank records.',
                                  )) {
                                    await widget.onAction(
                                      'bookings/${b['id']}/approve',
                                      success: 'Booking confirmed',
                                    );
                                  }
                                },
                          child: const Text('Confirm'),
                        ),
                        OutlinedButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onForm(
                                    'Reject booking',
                                    const [
                                      FieldSpec('reason', 'Reason for rejection',
                                          multiline: true)
                                    ],
                                    'bookings/${b['id']}/reject',
                                    submit: 'Reject booking',
                                  ),
                          child: const Text('Reject'),
                        ),
                      ],
                      if (widget.admin && b['status'] == 'PAID_AWAITING_RESOLUTION') ...[
                        FilledButton.icon(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onForm(
                                    'Reassign to Session',
                                    [
                                      FieldSpec('targetSessionId', 'Select alternative session',
                                          options: {
                                            for (final s in widget.sessions.where((x) =>
                                                x['status'] == 'SCHEDULED' &&
                                                DateTime.parse(x['startsAt'] as String)
                                                    .isAfter(DateTime.now()) &&
                                                (x['spotsLeft'] as int) > 0 &&
                                                x['id'] != b['sessionId']))
                                              s['id'] as String:
                                                  '${s['title']} (${widget.onFormatDate(s['startsAt'], 'EEE d MMM HH:mm')})'
                                          }),
                                      const FieldSpec('note', 'Reassignment note (optional)',
                                          optional: true),
                                    ],
                                    'admin/bookings/${b['id']}/resolve',
                                    submit: 'Reassign booking',
                                    note:
                                        'The payment was already verified. The member will be enrolled into the new session without charging again.',
                                  ),
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Reassign Session'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onForm(
                                    'Complete Refund',
                                    const [
                                      FieldSpec('note', 'Refund transaction reference / note',
                                          multiline: true),
                                    ],
                                    'admin/bookings/${b['id']}/resolve',
                                    submit: 'Complete refund',
                                    note:
                                        'Mark the bank-transfer refund as processed. The booking will transition to Cancelled and the member will be notified.',
                                  ),
                          icon: const Icon(Icons.money_off, size: 16),
                          label: const Text('Complete Refund'),
                        ),
                      ],
                      if (widget.admin &&
                          ['PENDING', 'CONFIRMED', 'PAID_AWAITING_RESOLUTION']
                              .contains(b['status']))
                        OutlinedButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onForm(
                                    'Cancel Booking (Admin Override)',
                                    const [
                                      FieldSpec('reason',
                                          'Audit reason for override cancellation',
                                          multiline: true)
                                    ],
                                    'admin/bookings/${b['id']}/cancel',
                                    submit: 'Cancel booking',
                                    note:
                                        'Admin override cancellation releases the seat and restores member credits regardless of 24h cutoff.',
                                  ),
                          child: const Text('Admin Cancel'),
                        ),
                      if (widget.member &&
                          ['PENDING', 'CONFIRMED'].contains(b['status']))
                        OutlinedButton(
                          onPressed: widget.busy ||
                                  DateTime.parse(b['session']['startsAt'] as String)
                                          .difference(DateTime.now()) <=
                                      const Duration(hours: 24)
                              ? null
                              : () async {
                                  if (await confirm(
                                    context,
                                    'Cancel this booking?',
                                    'Your place will be released. Class credits are returned; contact the studio for bank-transfer refunds.',
                                  )) {
                                    await widget.onAction(
                                      'bookings/${b['id']}/cancel',
                                      success: 'Booking cancelled',
                                    );
                                  }
                                },
                          child: const Text('Cancel booking'),
                        ),
                      if (!widget.member &&
                          b['status'] == 'CONFIRMED' &&
                          DateTime.parse(b['session']['startsAt'] as String)
                              .isBefore(DateTime.now())) ...[
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onAction(
                                    'bookings/${b['id']}/attendance',
                                    method: 'PATCH',
                                    body: {'attendance': 'PRESENT'},
                                  ),
                          child: const Text('Present'),
                        ),
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onAction(
                                    'bookings/${b['id']}/attendance',
                                    method: 'PATCH',
                                    body: {'attendance': 'ABSENT'},
                                  ),
                          child: const Text('Absent'),
                        ),
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onAction(
                                    'bookings/${b['id']}/attendance',
                                    method: 'PATCH',
                                    body: {'attendance': 'UNMARKED'},
                                  ),
                          child: const Text('Clear'),
                        ),
                      ],
                    ]),
                    if (widget.member &&
                        ['PENDING', 'CONFIRMED'].contains(b['status']))
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Cancellation closes 24 hours before the session.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
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
