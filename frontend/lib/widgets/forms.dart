import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class FieldSpec {
  final String keyName, title;
  final String initial;
  final Map<String, String>? options;
  final bool number, dateTime, optional, multiline;
  const FieldSpec(this.keyName, this.title,
      {this.initial = '',
      this.options,
      this.number = false,
      this.dateTime = false,
      this.optional = false,
      this.multiline = false});
}

Future<bool?> showStudioForm(BuildContext context,
        {required String title,
        required List<FieldSpec> fields,
        required Future<void> Function(Map<String, dynamic>) save,
        String submitLabel = 'Save',
        String? note,
        String timezone = 'Asia/Yangon'}) =>
    showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioForm(
            title: title,
            fields: fields,
            save: save,
            submitLabel: submitLabel,
            note: note,
            timezone: timezone));

class StudioForm extends StatefulWidget {
  final String title, submitLabel, timezone;
  final String? note;
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, dynamic>) save;
  const StudioForm(
      {super.key,
      required this.title,
      required this.fields,
      required this.save,
      required this.submitLabel,
      required this.timezone,
      this.note});
  @override
  State<StudioForm> createState() => _StudioFormState();
}

class _StudioFormState extends State<StudioForm> {
  final key = GlobalKey<FormState>();
  late Map<String, TextEditingController> controllers;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        f.keyName: TextEditingController(text: f.initial)
    };
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(FieldSpec f) async {
    final now = tz.TZDateTime.now(tz.getLocation(widget.timezone));
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime(now.year, now.month, now.day),
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year + 2));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: now.hour, minute: 0));
    if (time == null || !mounted) return;
    controllers[f.keyName]!.text = DateFormat('yyyy-MM-dd HH:mm').format(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = <String, dynamic>{};
      for (final f in widget.fields) {
        final v = controllers[f.keyName]!.text.trim();
        if (v.isEmpty && f.optional) continue;
        if (f.dateTime) {
          final d = DateFormat('yyyy-MM-dd HH:mm').parseStrict(v);
          data[f.keyName] = tz.TZDateTime(tz.getLocation(widget.timezone),
                  d.year, d.month, d.day, d.hour, d.minute)
              .toUtc()
              .toIso8601String();
        } else {
          data[f.keyName] = f.number ? int.parse(v) : v;
        }
      }
      await widget.save(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 470,
              child: SingleChildScrollView(
                  child: Form(
                      key: key,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.note != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Text(widget.note!)),
                        for (final f in widget.fields)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: f.options != null
                                  ? DropdownButtonFormField<String>(
                                      initialValue:
                                          controllers[f.keyName]!.text.isEmpty
                                              ? null
                                              : controllers[f.keyName]!.text,
                                      isExpanded: true,
                                      decoration:
                                          InputDecoration(labelText: f.title),
                                      items: f.options!.entries
                                          .map((e) => DropdownMenuItem(
                                              value: e.key,
                                              child: Text(e.value)))
                                          .toList(),
                                      onChanged: busy
                                          ? null
                                          : (v) => controllers[f.keyName]!
                                              .text = v ?? '',
                                      validator: (v) =>
                                          (v == null || v.isEmpty) &&
                                                  !f.optional
                                              ? 'Choose an option'
                                              : null)
                                  : TextFormField(
                                      controller: controllers[f.keyName],
                                      enabled: !busy,
                                      readOnly: f.dateTime,
                                      onTap: f.dateTime ? () => pick(f) : null,
                                      maxLines: f.multiline ? 3 : 1,
                                      keyboardType: f.number
                                          ? TextInputType.number
                                          : TextInputType.text,
                                      decoration: InputDecoration(
                                          labelText: f.title,
                                          suffixIcon: f.dateTime
                                              ? const Icon(
                                                  Icons.calendar_today_outlined)
                                              : null),
                                      validator: (v) {
                                        if ((v?.trim().isEmpty ?? true) &&
                                            !f.optional) {
                                          return 'This field is required';
                                        }
                                        if (f.number &&
                                            int.tryParse(v ?? '') == null) {
                                          return 'Enter a whole number';
                                        }
                                        return null;
                                      })),
                        if (error != null)
                          Text(error!,
                              style: const TextStyle(color: Colors.red)),
                      ])))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : widget.submitLabel))
          ]);
}

Future<bool> confirm(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (c) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Keep it')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Confirm'))
            ])) ??
    false;
