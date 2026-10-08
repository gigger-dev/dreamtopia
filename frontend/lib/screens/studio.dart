import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../api.dart';
import '../theme.dart';
import '../widgets/forms.dart';

// Modular view imports
import 'bookings/bookings_view.dart';
import 'instructors/availability_view.dart';
import 'instructors/instructors_view.dart';
import 'members/members_view.dart';
import 'notifications/notifications_view.dart';
import 'packages/packages_view.dart';
import 'practice/practice_view.dart';
import 'promotions/promotions_view.dart';
import 'requests/requests_view.dart';
import 'schedule/schedule_view.dart';
import 'chat/chat_widget.dart';
import 'chat/admin_chat_view.dart';

const sessionTypes = {
  'POLE_CLASS': 'Pole classes',
  'TRIAL': 'Trial classes',
  'PRACTICE': 'Pole practice',
  'RENTAL': 'Studio rental'
};

class StudioScreen extends StatefulWidget {
  final Api api;
  final Future<void> Function() onSignOut;
  const StudioScreen({super.key, required this.api, required this.onSignOut});
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  Map<String, dynamic>? me;
  Map<String, dynamic> settings = {
    'timezone': 'Asia/Yangon',
    'currency': 'MMK'
  };
  List<dynamic> sessions = [],
      bookings = [],
      notices = [],
      instructors = [],
      members = [],
      promos = [],
      requests = [],
      blocks = [],
      ledger = [],
      packages = [],
      packageProducts = [];
  String page = 'Schedule';
  String? error;
  bool loading = true, busy = false;
  late DateTime week;
  late DateTime selectedDate;
  Timer? timer;
  int loadVersion = 0;

  Api get api => widget.api;
  bool get admin => me?['role']?.toString().toUpperCase() == 'ADMIN';
  bool get teacher =>
      me?['role']?.toString().toUpperCase() == 'INSTRUCTOR' ||
      me?['instructor'] != null;
  bool get member =>
      me?['role']?.toString().toUpperCase() == 'MEMBER' && !teacher && !admin;
  tz.Location get zone => tz.getLocation(settings['timezone'] as String);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedDate = DateTime(now.year, now.month, now.day);
    week = selectedDate.subtract(Duration(days: now.weekday - 1));
    load();
    timer =
        Timer.periodic(const Duration(seconds: 60), (_) => refreshNotices());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String when(dynamic iso, [String pattern = 'EEE, d MMM · HH:mm']) =>
      DateFormat(pattern)
          .format(tz.TZDateTime.from(DateTime.parse(iso as String), zone));

  String get rangeQuery {
    final start = tz.TZDateTime(zone, week.year, week.month, week.day);
    final end = tz.TZDateTime(zone, week.year, week.month, week.day + 7);
    return 'from=${Uri.encodeQueryComponent(start.toUtc().toIso8601String())}&to=${Uri.encodeQueryComponent(end.toUtc().toIso8601String())}';
  }

  Future<void> refreshNotices() async {
    if (me == null) return;
    try {
      final data = await api.call('notifications') as List;
      if (mounted) setState(() => notices = data);
    } catch (_) {}
  }

  Future<void> load() async {
    final version = ++loadVersion;
    final firstLoad = me == null;
    try {
      final initial = await Future.wait([api.call('me'), api.call('settings')]);
      if (!mounted || version != loadVersion) return;
      me = Map<String, dynamic>.from(initial[0]);
      settings = Map<String, dynamic>.from(initial[1]);
      if (firstLoad) {
        final today = tz.TZDateTime.now(zone);
        week = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: today.weekday - 1));
      }
      final paths = [
        'sessions?$rangeQuery',
        'bookings',
        'notifications',
        if (admin) ...[
          'instructors',
          'members',
          'promotions',
          'requests',
          'packages',
          'admin/packages/products'
        ],
        if (teacher) 'instructor/blocks',
        if (member) ...['requests', 'credits', 'packages', 'packages/products']
      ];
      final values = await Future.wait(paths.map((p) => api.call(p)));
      if (!mounted || version != loadVersion) return;
      setState(() {
        sessions = values[0] as List;
        bookings = values[1] as List;
        notices = values[2] as List;
        if (admin) {
          instructors = values[3] as List;
          members = values[4] as List;
          promos = values[5] as List;
          requests = values[6] as List;
          packages = values[7] as List;
          packageProducts = values[8] as List;
        }
        if (teacher) blocks = values[3] as List;
        if (member) {
          requests = values[3] as List;
          ledger = values[4] as List;
          packages = values[5] as List;
          packageProducts = values[6] as List;
        }
        error = null;
        loading = false;
      });
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        await widget.onSignOut();
        return;
      }
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> action(String path,
      {String method = 'POST',
      Map<String, dynamic>? body,
      String success = 'Saved'}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.call(path, method: method, body: body);
      await load();
      message(success);
    } catch (e) {
      message(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> form(String title, List<FieldSpec> fields, String path,
      {String method = 'POST', String? note, String submit = 'Save'}) async {
    final result = await showStudioForm(context,
        title: title,
        fields: fields,
        timezone: settings['timezone'] as String,
        note: note,
        submitLabel: submit, save: (data) async {
      await api.call(path, method: method, body: data);
    });
    if (result == true) {
      await load();
      message('Saved');
    }
  }

  Future<void> createClass() => form(
      'Create a studio session',
      [
        const FieldSpec('title', 'Session name'),
        const FieldSpec('type', 'Session type',
            initial: 'POLE_CLASS', options: sessionTypes),
        const FieldSpec('bookingMode', 'Allowed booking modes',
            initial: 'BOTH',
            options: {
              'BOTH': 'Both (Package credits or Walk-in)',
              'PACKAGE_ONLY': 'Package credits only',
              'WALK_IN_ONLY': 'Walk-in only (Bank transfer)'
            }),
        const FieldSpec('creditCost', 'Credit cost (for package booking)',
            number: true, initial: '1'),
        const FieldSpec('startsAt', 'Starts at', dateTime: true),
        const FieldSpec('endsAt', 'Ends at', dateTime: true),
        const FieldSpec('capacity', 'Number of places',
            number: true, initial: '6'),
        FieldSpec('price', 'Walk-in Price (${settings['currency']})',
            number: true, initial: '35000'),
        const FieldSpec('level', 'Level', initial: 'All levels'),
        FieldSpec('instructorId', 'Instructor (required for classes)',
            optional: true,
            options: {
              for (final i in instructors)
                i['id'] as String: i['name'] as String
            }),
        const FieldSpec(
          'requireConfirmation',
          'Require instructor confirmation\n(uncheck for auto-scheduled)',
          boolean: true,
          initial: 'true',
        ),
        const FieldSpec('description', 'About this session',
            multiline: true, optional: true),
      ],
      'sessions',
      note:
          'Times are in ${settings['timezone']}. A rental reserves the whole studio. Classes with confirmation enabled are published after instructor acceptance.');

  Future<void> requestTime() => form(
      'Your preferred timeslot',
      const [
        FieldSpec('type', 'Session type',
            initial: 'POLE_CLASS', options: sessionTypes),
        FieldSpec('startsAt', 'Preferred start', dateTime: true),
        FieldSpec('endsAt', 'Preferred end', dateTime: true),
        FieldSpec('note', 'Tell us what works for you', multiline: true)
      ],
      'requests',
      note:
          'A request is not a booking. The studio will review it and notify you.');

  Future<void> viewProof(String id) async {
    try {
      final bytes = await api.proof(id);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Payment proof'),
                  content: SizedBox(
                      width: 600,
                      child: InteractiveViewer(
                          child: Image.memory(bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Text(
                                  'Image could not be decoded. Ask the member to provide a valid screenshot.')))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'))
                  ]));
    } catch (e) {
      message(e.toString());
    }
  }

  Future<void> purchasePackageFlow(Map<String, dynamic> product) async {
    Uint8List? proofBytes;
    String? proofFilename;
    String? dialogError;
    bool dialogBusy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('Purchase ${product['name']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sageLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sageBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${product['credits']} Class Credits',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Price: ${product['price']} ${settings['currency']} · Valid for ${product['validityDays']} days after studio approval.',
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    settings['bankInstructions']?.toString() ??
                        'Please transfer to studio bank account and upload screenshot.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: dialogBusy
                        ? null
                        : () async {
                            try {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                                withData: true,
                              );
                              if (result == null) return;
                              final file = result.files.single;
                              if (file.size > 5 * 1024 * 1024 || file.bytes == null) {
                                throw ApiException('Choose an image smaller than 5 MB.');
                              }
                              setDlgState(() {
                                proofBytes = file.bytes;
                                proofFilename = file.name;
                                dialogError = null;
                              });
                            } catch (e) {
                              setDlgState(() => dialogError = e.toString());
                            }
                          },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(proofFilename ?? 'Upload payment screenshot'),
                  ),
                  const Text('PNG, JPEG or WebP · up to 5 MB',
                      style: TextStyle(fontSize: 12, color: muted)),
                  if (proofBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          proofBytes!,
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(dialogError!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogBusy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: dialogBusy
                  ? null
                  : () async {
                      if (proofBytes == null) {
                        setDlgState(() =>
                            dialogError = 'Please upload your payment screenshot first.');
                        return;
                      }
                      setDlgState(() {
                        dialogBusy = true;
                        dialogError = null;
                      });
                      try {
                        final proofId =
                            await api.upload(proofBytes!, proofFilename!);
                        await api.call('packages/purchase', method: 'POST', body: {
                          'packageProductId': product['id'],
                          'proofId': proofId,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        await load();
                        message('Package purchase submitted for studio review!');
                      } catch (e) {
                        setDlgState(() {
                          dialogBusy = false;
                          dialogError = e.toString();
                        });
                      }
                    },
              child: Text(dialogBusy ? 'Submitting…' : 'Submit payment'),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, IconData)> get menu => [
        ('Schedule', Icons.calendar_month_outlined),
        ('Bookings', Icons.confirmation_number_outlined),
        if (member || admin) ('Packages', Icons.card_membership_outlined),
        if (member) ('My practice', Icons.self_improvement),
        if (admin) ...[
          ('Instructors', Icons.people_outline),
          ('Members', Icons.groups_outlined),
          ('Promotions', Icons.local_offer_outlined),
          ('Customer Chats', Icons.chat_outlined),
        ],
        if (teacher) ...[
          ('Customer Chats', Icons.chat_outlined),
          ('Availability', Icons.event_busy_outlined),
        ],
        if (!teacher) ('Requests', Icons.schedule_outlined),
        ('Notifications', Icons.notifications_none)
      ];

  @override
  Widget build(BuildContext context) {
    if (me == null) {
      return Scaffold(
          body: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error ?? 'Could not load the studio.'),
                      TextButton(
                          onPressed: load, child: const Text('Try again')),
                      TextButton(
                          onPressed: widget.onSignOut,
                          child: const Text('Sign out'))
                    ])));
    }
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Stack(children: [
      Scaffold(
        appBar: wide
            ? null
            : AppBar(
                title: Text('Dreamtopia',
                    style: GoogleFonts.cinzel(
                        color: plum, fontWeight: FontWeight.w600)),
                actions: [
                    IconButton(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh')
                  ]),
        drawer: wide ? null : Drawer(child: sidebar()),
        body: Row(children: [
          if (wide) SizedBox(width: 250, child: sidebar()),
          Expanded(
              child: Column(children: [
            if (wide)
              Container(
                  height: 78,
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: sageBorder))),
                  child: Row(children: [
                    Text('Studio / $page',
                        style: const TextStyle(color: muted, fontSize: 14)),
                    const Spacer(),
                    Text('${label(me!['role'])} space',
                        style: const TextStyle(color: plum, fontSize: 14)),
                    const SizedBox(width: 18),
                    IconButton(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh'),
                    IconButton(
                        onPressed: () => setState(() => page = 'Notifications'),
                        icon: Badge(
                            isLabelVisible:
                                notices.any((n) => n['readAt'] == null),
                            child: const Icon(Icons.notifications_none)),
                        tooltip: 'Notifications')
                  ])),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
                child: RefreshIndicator(
                    onRefresh: load,
                    child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(wide ? 34 : 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (error != null)
                                Container(
                                    margin: const EdgeInsets.only(bottom: 20),
                                    padding: const EdgeInsets.all(16),
                                    color: Colors.red.shade50,
                                    child: Row(children: [
                                      Expanded(child: Text(error!)),
                                      TextButton(
                                          onPressed: load,
                                          child: const Text('Retry'))
                                    ])),
                              switch (page) {
                                'Schedule' => ScheduleView(
                                    api: api,
                                    me: me,
                                    settings: settings,
                                    admin: admin,
                                    teacher: teacher,
                                    member: member,
                                    busy: busy,
                                    sessions: sessions,
                                    bookings: bookings,
                                    instructors: instructors,
                                    week: week,
                                    selectedDate: selectedDate,
                                    zone: zone,
                                    onCreateSession: createClass,
                                    onRequestTime: requestTime,
                                    onReload: load,
                                    onPeriodChanged: (w, s) {
                                      setState(() {
                                        week = w;
                                        selectedDate = s;
                                      });
                                      load();
                                    },
                                    onAction: action,
                                    onForm: form,
                                    onFormatDate: when,
                                    onShowMessage: message,
                                  ),
                                'Bookings' => BookingsView(
                                    api: api,
                                    admin: admin,
                                    teacher: teacher,
                                    member: member,
                                    busy: busy,
                                    bookings: bookings,
                                    sessions: sessions,
                                    currency: settings['currency'] as String,
                                    onAction: action,
                                    onForm: form,
                                    onViewProof: viewProof,
                                    onFormatDate: when,
                                  ),
                                'Packages' => PackagesView(
                                    api: api,
                                    admin: admin,
                                    member: member,
                                    busy: busy,
                                    packageProducts: packageProducts,
                                    packages: packages,
                                    currency: settings['currency'] as String,
                                    timezone: settings['timezone'] as String,
                                    bankInstructions: settings['bankInstructions']?.toString(),
                                    onAction: action,
                                    onForm: form,
                                    onPurchasePackage: purchasePackageFlow,
                                    onViewProof: viewProof,
                                    onFormatDate: when,
                                  ),
                                'My practice' => PracticeView(
                                    me: me!,
                                    bookings: bookings,
                                    ledger: ledger,
                                    onFormatDate: when,
                                  ),
                                'Instructors' => InstructorsView(
                                    busy: busy,
                                    instructors: instructors,
                                    onAction: action,
                                    onForm: form,
                                  ),
                                'Members' => MembersView(
                                    busy: busy,
                                    members: members,
                                    onForm: form,
                                  ),
                                'Promotions' => PromotionsView(
                                    busy: busy,
                                    promos: promos,
                                    onAction: action,
                                    onForm: form,
                                    onFormatDate: when,
                                  ),
                                'Availability' => AvailabilityView(
                                    me: me,
                                    busy: busy,
                                    blocks: blocks,
                                    onAction: action,
                                    onForm: form,
                                    onFormatDate: when,
                                  ),
                                'Requests' => RequestsView(
                                    admin: admin,
                                    member: member,
                                    requests: requests,
                                    onRequestTime: requestTime,
                                    onForm: form,
                                    onFormatDate: when,
                                  ),
                                'Customer Chats' => AdminChatView(
                                    api: api,
                                    instructors: instructors,
                                    onShowMessage: message,
                                    isInstructor: teacher,
                                  ),
                                _ => NotificationsView(
                                    notices: notices,
                                    onAction: action,
                                    onFormatDate: when,
                                  ),
                              },
                            ])))),
                  ])),
          ]),
      ),
      // Floating Customer Chatbot with Full Backdrop covering the entire screen & topbar
      ChatWidget(
        api: api,
        currentUser: me,
      ),
    ]);
  }

  Widget sidebar() => Material(
      color: Colors.white,
      child: Container(
          decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: sageBorder))),
          child: SafeArea(
              child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome_outlined,
                        color: plum, size: 28),
                    const SizedBox(width: 9),
                    Expanded(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Dreamtopia',
                                style: GoogleFonts.cinzel(
                                    fontSize: 27,
                                    fontWeight: FontWeight.bold,
                                    color: sageGreen))))
                  ]),
                  const SizedBox(height: 6),
                  Text('Yoga & Movement Studio',
                      style: GoogleFonts.lato(
                          fontSize: 10,
                          letterSpacing: 1.8,
                          color: muted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 22),
                  const ChakraLine()
                ])),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                  for (final item in menu)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                            selected: page == item.$1,
                            selectedColor: plum,
                            selectedTileColor: sageLight,
                            leading: Icon(item.$2, size: 21),
                            title: Text(item.$1,
                                style: const TextStyle(fontSize: 14)),
                            onTap: () {
                              setState(() => page = item.$1);
                              if (MediaQuery.sizeOf(context).width < 1050) {
                                Navigator.pop(context);
                              }
                            }))
                ])),
            Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A little stronger.\nA little more you.',
                          style: GoogleFonts.cinzel(
                              fontSize: 18,
                              color: sageGreen,
                              fontWeight: FontWeight.w500,
                              height: 1.5)),
                      const SizedBox(height: 24),
                      const Divider(),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                              backgroundColor: sageLight,
                              child: Text(
                                  (me!['name'] as String)
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(color: sageGreen))),
                          title: Text(me!['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(label(me!['role']),
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                              onPressed: widget.onSignOut,
                              icon: const Icon(Icons.logout, size: 19),
                              tooltip: 'Sign out'))
                    ]))
          ]))));
}
