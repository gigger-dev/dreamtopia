import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../theme.dart';

class BookingDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> session, settings;
  final int credits;
  const BookingDialog(
      {super.key,
      required this.api,
      required this.session,
      required this.settings,
      required this.credits});
  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  String method = 'BANK_TRANSFER';
  final promo = TextEditingController();
  String appliedPromo = '';
  Uint8List? bytes;
  String? filename, proofId, error;
  bool busy = false;
  late int amount;
  int discount = 0;
  @override
  void initState() {
    super.initState();
    amount = widget.session['price'] as int;
  }

  @override
  void dispose() {
    promo.dispose();
    super.dispose();
  }

  String money(int n) =>
      '${NumberFormat.decimalPattern().format(n)} ${widget.settings['currency']}';
  Future<void> pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          withData: true);
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 5 * 1024 * 1024 || file.bytes == null) {
        throw ApiException('Choose an image smaller than 5 MB.');
      }
      setState(() {
        bytes = file.bytes;
        filename = file.name;
        proofId = null;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> applyPromo() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final code = promo.text.trim().toUpperCase();
      final quote = await widget.api.call(
          'sessions/${widget.session['id']}/quote?code=${Uri.encodeQueryComponent(code)}');
      if (mounted) {
        setState(() {
          amount = quote['amount'] as int;
          discount = quote['discount'] as int;
          appliedPromo = code;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> book() async {
    if (method == 'BANK_TRANSFER' && bytes == null) {
      setState(() => error = 'Upload your payment screenshot first.');
      return;
    }
    if (method == 'BANK_TRANSFER' &&
        promo.text.trim().toUpperCase() != appliedPromo) {
      setState(() =>
          error = 'Apply your promotion code before booking, or clear it.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (method == 'BANK_TRANSFER') {
        proofId ??= await widget.api.upload(bytes!, filename!);
      }
      await widget.api.call('bookings', method: 'POST', body: {
        'sessionId': widget.session['id'],
        'paymentMethod': method,
        if (method == 'BANK_TRANSFER') 'proofId': proofId,
        if (method == 'BANK_TRANSFER' && appliedPromo.isNotEmpty)
          'promoCode': appliedPromo
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.session['title'] as String),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(widget.session['description']?.toString() ?? '',
                        style: const TextStyle(color: muted)),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration:
                            const InputDecoration(labelText: 'Payment method'),
                        items: [
                          const DropdownMenuItem(
                              value: 'BANK_TRANSFER',
                              child: Text('Bank transfer')),
                          if (widget.session['type'] == 'POLE_CLASS' &&
                              widget.credits > 0)
                            DropdownMenuItem(
                                value: 'CREDITS',
                                child: Text(
                                    'Class credit · ${widget.credits} remaining'))
                        ],
                        onChanged:
                            busy ? null : (v) => setState(() => method = v!)),
                    const SizedBox(height: 20),
                    if (method == 'BANK_TRANSFER') ...[
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: promo,
                                enabled: !busy,
                                decoration: const InputDecoration(
                                    labelText: 'Promotion code (optional)'))),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: busy ? null : applyPromo,
                            child: const Text('Apply'))
                      ]),
                      const SizedBox(height: 18),
                      if (discount > 0)
                        Text('Promotion applied: −${money(discount)}',
                            style: const TextStyle(color: plum)),
                      Text('Total: ${money(amount)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 22)),
                      const SizedBox(height: 14),
                      Text(widget.settings['bankInstructions']?.toString() ??
                          'Ask the studio for bank transfer details.'),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                          onPressed: busy ? null : pick,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(filename ?? 'Upload payment screenshot')),
                      const Text('PNG, JPEG or WebP · up to 5 MB',
                          style: TextStyle(fontSize: 12, color: muted)),
                      if (bytes != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(bytes!,
                                    height: 140,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Text(
                                        'Preview unavailable. Select a valid image.')))),
                    ] else
                      const Text(
                          'One class credit will be reserved now. It is returned if the studio rejects your booking or you cancel more than 24 hours before class.'),
                    const SizedBox(height: 18),
                    const Text(
                        'Your booking is pending until the studio confirms it. Member cancellations must be more than 24 hours before the session.',
                        style: TextStyle(fontSize: 14, color: muted)),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(error!,
                              style: const TextStyle(color: Colors.red))),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Back')),
            FilledButton(
                onPressed: busy ? null : book,
                child: Text(busy ? 'Submitting…' : 'Request booking'))
          ]);
}
