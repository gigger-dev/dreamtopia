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
import 'booking.dart';

// ignore: unused_element
TextStyle _cinzel(double size,
        {FontWeight fw = FontWeight.w600, Color? color}) =>
    GoogleFonts.cinzel(fontSize: size, fontWeight: fw, color: color ?? ink);

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
  String page = 'Schedule', filter = 'ALL';
  String bookingFilter = 'ALL';
  String viewMode = 'WEEK'; // 'WEEK', 'MONTH', 'DAY'
  String? selectedInstructorId;
  String searchQuery = '';
  final searchController = TextEditingController();
  String? error;
  bool loading = true, busy = false;
  late DateTime week;
  late DateTime selectedDate;
  Timer? timer;
  int loadVersion = 0;
  Api get api => widget.api;
  bool get admin => me?['role'] == 'ADMIN';
  bool get teacher => me?['role'] == 'INSTRUCTOR';
  bool get member => me?['role'] == 'MEMBER';
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
    searchController.dispose();
    timer?.cancel();
    super.dispose();
  }

  String when(dynamic iso, [String pattern = 'EEE, d MMM · HH:mm']) =>
      DateFormat(pattern)
          .format(tz.TZDateTime.from(DateTime.parse(iso as String), zone));
  String money(dynamic n) =>
      '${NumberFormat.decimalPattern().format(n)} ${settings['currency']}';
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
    } catch (_) {
      /* Full refresh surfaces connectivity errors without interrupting forms. */
    }
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
  List<(String, IconData)> get menu => [
        ('Schedule', Icons.calendar_month_outlined),
        ('Bookings', Icons.confirmation_number_outlined),
        if (member || admin) ('Packages', Icons.card_membership_outlined),
        if (member) ('My practice', Icons.self_improvement),
        if (admin) ...[
          ('Instructors', Icons.people_outline),
          ('Members', Icons.groups_outlined),
          ('Promotions', Icons.local_offer_outlined)
        ],
        if (teacher) ('Availability', Icons.event_busy_outlined),
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
    return Scaffold(
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
                                'Schedule' => schedule(),
                                'Bookings' => bookingList(),
                                'Packages' => packagesSection(),
                                'My practice' => practice(),
                                'Instructors' => instructorList(),
                                'Members' => memberList(),
                                'Promotions' => promotions(),
                                'Availability' => availability(),
                                'Requests' => requestList(),
                                _ => notifications()
                              },
                            ])))),
          ]))
        ]));
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
  Widget heading(String eyebrow, String title, String subtitle,
          {Widget? button}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: LayoutBuilder(builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 600;
            return isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(eyebrow,
                                style: GoogleFonts.lato(
                                    letterSpacing: 2.5,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: sageGreen)),
                            const SizedBox(height: 10),
                            Text(title,
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 10),
                            Text(subtitle,
                                style:
                                    const TextStyle(color: muted, fontSize: 14))
                          ])),
                      if (button != null)
                        Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: button)
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(eyebrow,
                          style: GoogleFonts.lato(
                              letterSpacing: 2.5,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: sageGreen)),
                      const SizedBox(height: 10),
                      Text(title,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      Text(subtitle,
                          style: const TextStyle(color: muted, fontSize: 14)),
                      if (button != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(width: double.infinity, child: button)
                      ]
                    ],
                  );
          }));
  Widget empty(String text, IconData icon) => Card(
      child: Padding(
          padding: const EdgeInsets.all(34),
          child: Center(
              child: Column(children: [
            Icon(icon, size: 34, color: plum),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted))
          ]))));
  Widget stat(String title, String value, String subtitle,
          {bool tinted = false}) =>
      LayoutBuilder(builder: (context, constraints) {
        return Container(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
            child: Card(
                color: tinted ? sageLight : null,
                child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style:
                                  const TextStyle(color: muted, fontSize: 13)),
                          const SizedBox(height: 14),
                          Text(value,
                              style: TextStyle(
                                  fontSize: 26,
                                  color: tinted ? plum : ink,
                                  fontFamily: tinted
                                      ? GoogleFonts.cinzel().fontFamily
                                      : GoogleFonts.lato().fontFamily)),
                          const SizedBox(height: 10),
                          Text(subtitle,
                              style:
                                  const TextStyle(color: muted, fontSize: 13))
                        ]))));
      });
  Widget schedule() {
    final now = tz.TZDateTime.now(zone);
    final filtered = sessions.where((s) {
      if (filter != 'ALL' && s['type'] != filter) return false;
      if (selectedInstructorId != null &&
          s['instructor']?['id'] != selectedInstructorId) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final title = (s['title'] as String? ?? '').toLowerCase();
        final instructorName =
            (s['instructor']?['name'] as String? ?? '').toLowerCase();
        final desc = (s['description'] as String? ?? '').toLowerCase();
        if (!title.contains(q) &&
            !instructorName.contains(q) &&
            !desc.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final confirmed = bookings
        .where((b) =>
            b['status'] == 'CONFIRMED' &&
            DateTime.parse(b['session']['startsAt'] as String)
                .isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => (a['session']['startsAt'] as String)
          .compareTo(b['session']['startsAt'] as String));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading(
          'FIND YOUR FLOW',
          admin
              ? 'Your studio, in balance.'
              : teacher
                  ? 'Your teaching calendar.'
                  : 'Make time for you.',
          'A little movement, a little magic.',
          button: admin
              ? FilledButton.icon(
                  onPressed: busy ? null : createClass,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create session'))
              : member
                  ? FilledButton.icon(
                      onPressed: requestTime,
                      icon: const Icon(Icons.north_east, size: 18),
                      label: const Text('Request a timeslot'))
                  : null),
      Wrap(spacing: 16, runSpacing: 16, children: [
        stat(
            member
                ? 'Classes remaining'
                : teacher
                    ? 'Classes taught'
                    : 'Awaiting confirmation',
            member
                ? '${me!['credits']}'
                : teacher
                    ? '${me!['classesTaught']}'
                    : '${bookings.where((b) => b['status'] == 'PENDING').length}',
            member
                ? 'Available class credits'
                : teacher
                    ? 'Completed teaching sessions'
                    : 'Bookings ready for review'),
        stat(
            member ? 'Your next class' : 'This week',
            member
                ? (confirmed.isEmpty
                    ? 'Let’s get moving'
                    : when(
                        confirmed.first['session']['startsAt'], 'EEE, d MMM'))
                : '${sessions.where((s) => s['status'] == 'SCHEDULED').length} sessions',
            member
                ? (confirmed.isEmpty
                    ? 'Find your next class below'
                    : confirmed.first['session']['title'] as String)
                : 'Scheduled in the studio'),
        stat('SEVEN COLORS. ONE YOU.', 'Find your balance.',
            'Own your strength.',
            tinted: true)
      ]),
      const SizedBox(height: 32),

      // Advanced Search & Filter Bar
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_outlined, color: plum, size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text('Search & Filters',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        if (searchQuery.isNotEmpty ||
                            filter != 'ALL' ||
                            selectedInstructorId != null)
                          TextButton.icon(
                              onPressed: () => setState(() {
                                    searchQuery = '';
                                    searchController.clear();
                                    filter = 'ALL';
                                    selectedInstructorId = null;
                                  }),
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text('Reset filters')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(spacing: 14, runSpacing: 14, children: [
                      SizedBox(
                          width: 260,
                          child: TextField(
                              controller: searchController,
                              onChanged: (v) =>
                                  setState(() => searchQuery = v.trim()),
                              decoration: InputDecoration(
                                  labelText: 'Search class or instructor',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 18),
                                  isDense: true,
                                  suffixIcon: searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.close, size: 16),
                                          onPressed: () => setState(() {
                                                searchController.clear();
                                                searchQuery = '';
                                              }))
                                      : null))),
                      if (instructors.isNotEmpty)
                        SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String?>(
                                value: selectedInstructorId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Filter by Instructor',
                                    isDense: true),
                                items: [
                                  const DropdownMenuItem(
                                      value: null,
                                      child: Text('All Instructors')),
                                  for (final ins in instructors)
                                    DropdownMenuItem(
                                        value: ins['id'] as String,
                                        child: Text(ins['name'] as String))
                                ],
                                onChanged: (v) =>
                                    setState(() => selectedInstructorId = v))),
                    ]),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final entry
                          in {'ALL': 'All sessions', ...sessionTypes}.entries)
                        ChoiceChip(
                            label: Text(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                              ),
                            ),
                            selected: filter == entry.key,
                            onSelected: (_) =>
                                setState(() => filter = entry.key))
                    ])
                  ]))),
      const SizedBox(height: 24),

      // Calendar Navigation & View Mode Toggle (Day / Week / Month)
      Wrap(
          spacing: 18,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('The studio schedule',
                style: GoogleFonts.cinzel(
                    fontSize: 22, fontWeight: FontWeight.w600, color: ink)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in const {
                'DAY': 'Day',
                'WEEK': 'Week',
                'MONTH': 'Month'
              }.entries)
                ChoiceChip(
                    label: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                    selected: viewMode == entry.key,
                    onSelected: (_) => setState(() => viewMode = entry.key))
            ])
          ]),
      const SizedBox(height: 14),

      // Date Header & Stepper
      SizedBox(
        width: double.infinity,
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                          switch (viewMode) {
                            'MONTH' => DateFormat('MMMM yyyy').format(week),
                            'DAY' => DateFormat('EEEE, d MMMM yyyy')
                                .format(selectedDate),
                            _ =>
                              '${DateFormat('d MMM').format(week)} – ${DateFormat('d MMM yyyy').format(week.add(const Duration(days: 6)))}'
                          },
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                onPressed: () => changePeriod(-1),
                                icon: const Icon(Icons.chevron_left),
                                tooltip: 'Previous'),
                            TextButton(
                                onPressed: () {
                                  final today = tz.TZDateTime.now(zone);
                                  selectedDate =
                                      DateTime(today.year, today.month, today.day);
                                  week = selectedDate
                                      .subtract(Duration(days: today.weekday - 1));
                                  load();
                                },
                                child: const Text('Today')),
                            IconButton(
                                onPressed: () => changePeriod(1),
                                icon: const Icon(Icons.chevron_right),
                                tooltip: 'Next'),
                          ]),
                    ]))),
      ),
      const SizedBox(height: 16),

      // Active Calendar View
      switch (viewMode) {
        'DAY' => dayView(filtered, now),
        'MONTH' => monthView(filtered, now),
        _ => LayoutBuilder(builder: (context, c) {
            final desktop = c.maxWidth >= 900;
            return desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                        7,
                        (i) => Expanded(
                            child: Padding(
                                padding: EdgeInsets.only(right: i == 6 ? 0 : 9),
                                child: dayColumn(i, filtered, now)))))
                : Column(
                    children:
                        List.generate(7, (i) => dayColumn(i, filtered, now)));
          })
      },
      const SizedBox(height: 18),
      const Text(
          'Bookings are confirmed after studio review. Bank transfers are verified manually.',
          style: TextStyle(fontSize: 13, color: muted)),
    ]);
  }

  void changePeriod(int dir) {
    setState(() {
      if (viewMode == 'MONTH') {
        week = DateTime(week.year, week.month + dir, 1);
      } else if (viewMode == 'DAY') {
        selectedDate = selectedDate.add(Duration(days: dir));
        week = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
      } else {
        week = week.add(Duration(days: dir * 7));
      }
    });
    load();
  }

  Widget dayView(List<dynamic> data, DateTime now) {
    final d = selectedDate;
    final rows = data.where((s) {
      final dt =
          tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), zone);
      return dt.year == d.year && dt.month == d.month && dt.day == d.day;
    }).toList();

    return Card(
        child: Container(
            height: 600,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: SingleChildScrollView(
                child: Column(
                    children: List.generate(24, (hour) {
              final hourLabel = hour == 0
                  ? '00:00'
                  : hour < 12
                      ? '${hour.toString().padLeft(2, '0')}:00 AM'
                      : hour == 12
                          ? '12:00 PM'
                          : '${(hour - 12).toString().padLeft(2, '0')}:00 PM';

              final matchingSessions = rows.where((s) {
                final startDt = tz.TZDateTime.from(
                    DateTime.parse(s['startsAt'] as String), zone);
                return startDt.hour == hour;
              }).toList();

              return Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: sageBorder, width: 0.5))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 75,
                            child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(hourLabel,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: muted)))),
                        Container(width: 1, height: 64, color: sageBorder),
                        const SizedBox(width: 12),
                        Expanded(
                            child: matchingSessions.isEmpty
                                ? const SizedBox(height: 64)
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                        for (final s in matchingSessions)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4, bottom: 4),
                                              child: sessionCard(
                                                  Map<String, dynamic>.from(s),
                                                  hour % chakra.length))
                                      ]))
                      ]));
            })))));
  }

  Widget monthView(List<dynamic> data, DateTime now) {
    final firstOfMonth = DateTime(week.year, week.month, 1);
    final daysInMonth = DateTime(week.year, week.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday; // 1 = Mon, 7 = Sun

    final gridCells = <Widget>[];

    // Headers
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (final h in days) {
      gridCells.add(Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          child: Text(h,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: muted))));
    }

    // Empty lead-in spaces
    for (int i = 1; i < startWeekday; i++) {
      gridCells.add(const SizedBox());
    }

    // Month days
    for (int dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      final d = DateTime(week.year, week.month, dayNum);
      final daySessions = data.where((s) {
        final dt =
            tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), zone);
        return dt.year == d.year && dt.month == d.month && dt.day == d.day;
      }).toList();
      final isToday =
          d.year == now.year && d.month == now.month && d.day == now.day;

      gridCells.add(InkWell(
          onTap: () => setState(() {
                selectedDate = d;
                viewMode = 'DAY';
              }),
          child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: isToday ? sageLight : Colors.white,
                  border: Border.all(color: sageBorder.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$dayNum',
                        style: TextStyle(
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                            color: isToday ? sageGreen : ink,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    for (final s in daySessions.take(2))
                      Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                              color: sageGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(2)),
                          child: Text(s['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: sageGreen))),
                    if (daySessions.length > 2)
                      Text('+${daySessions.length - 2} more',
                          style: const TextStyle(
                              fontSize: 9,
                              color: muted,
                              fontWeight: FontWeight.bold))
                  ]))));
    }

    return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        childAspectRatio: 1.1,
        children: gridCells);
  }

  Widget dayColumn(int day, List<dynamic> data, DateTime now) {
    final d = week.add(Duration(days: day));
    final rows = data.where((s) {
      final dt =
          tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), zone);
      return dt.year == d.year && dt.month == d.month && dt.day == d.day;
    }).toList();
    final today =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: today ? sageLight : Colors.white,
              borderRadius: BorderRadius.circular(4)),
          child: Text(DateFormat('EEE  d').format(d),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: today ? plum : muted,
                  fontWeight: today ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14))),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No sessions',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12))),
      for (final s in rows) sessionCard(Map<String, dynamic>.from(s), day),
      const SizedBox(height: 16)
    ]);
  }

  Widget sessionCard(Map<String, dynamic> s, int color) {
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: chakra[color].withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(4),
            border: Border(top: BorderSide(color: chakra[color], width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${when(s['startsAt'], 'HH:mm')} – ${when(s['endsAt'], 'HH:mm')}',
              style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 12),
          Text(s['title'] as String,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(s['instructor']?['name']?.toString() ?? 'Your studio time',
              style: const TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 7),
          Text(s['level'] as String,
              style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 14),
          Text('${s['spotsLeft']} / ${s['capacity']} places left',
              style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 8),
          Text(money(s['price']),
              style: const TextStyle(fontSize: 13, color: plum)),
          const SizedBox(height: 12),
          if (!member) StatusBadge(s['status'] as String),
          if (member)
            TextButton(
                onPressed: (s['spotsLeft'] as int) > 0 &&
                        DateTime.parse(s['startsAt'] as String)
                            .isAfter(DateTime.now())
                    ? () async {
                        final result = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => BookingDialog(
                                api: api,
                                session: s,
                                settings: settings,
                                credits: me!['credits'] as int));
                        if (result == true) {
                          await load();
                          message('Booking submitted for confirmation');
                        }
                      }
                    : null,
                child: const Text('Book session ↗')),
          if (teacher && s['status'] == 'PENDING_INSTRUCTOR')
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: busy
                      ? null
                      : () => action('sessions/${s['id']}/accept',
                          success: 'Class accepted'),
                  child: const Text('Accept class')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final reasonCtrl = TextEditingController();
                          final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                    title: const Text('Decline Class Invitation'),
                                    content: TextField(
                                      controller: reasonCtrl,
                                      decoration: const InputDecoration(
                                          labelText: 'Reason for declining (optional)'),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel')),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Decline')),
                                    ],
                                  ));
                          if (confirmed == true) {
                            await action('sessions/${s['id']}/decline',
                                body: {'reason': reasonCtrl.text.trim()},
                                success: 'Class declined');
                          }
                        },
                  child: const Text('Decline', style: TextStyle(color: Colors.red))),
            ]),
          if ((admin || teacher) &&
              s['status'] == 'SCHEDULED' &&
              DateTime.parse(s['endsAt'] as String).isBefore(DateTime.now()))
            TextButton(
                onPressed: busy
                    ? null
                    : () => action('sessions/${s['id']}/complete',
                        success: 'Class completed'),
                child: const Text('Mark taught')),
          if (admin && s['status'] != 'COMPLETED')
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: busy
                      ? null
                      : () => form(
                            'Edit session',
                            [
                              FieldSpec('title', 'Session name', initial: s['title'] as String),
                              FieldSpec('type', 'Session type',
                                  initial: s['type'] as String, options: sessionTypes),
                              FieldSpec('bookingMode', 'Allowed booking modes',
                                  initial: (s['bookingMode'] as String?) ?? 'BOTH',
                                  options: {
                                    'BOTH': 'Both (Package credits or Walk-in)',
                                    'PACKAGE_ONLY': 'Package credits only',
                                    'WALK_IN_ONLY': 'Walk-in only (Bank transfer)'
                                  }),
                              FieldSpec('creditCost', 'Credit cost (for package booking)',
                                  number: true, initial: '${s['creditCost'] ?? 1}'),
                              FieldSpec('startsAt', 'Starts at',
                                  dateTime: true,
                                  initial: DateFormat('yyyy-MM-dd HH:mm').format(
                                      tz.TZDateTime.from(
                                          DateTime.parse(s['startsAt'] as String), zone))),
                              FieldSpec('endsAt', 'Ends at',
                                  dateTime: true,
                                  initial: DateFormat('yyyy-MM-dd HH:mm').format(
                                      tz.TZDateTime.from(
                                          DateTime.parse(s['endsAt'] as String), zone))),
                              FieldSpec('capacity', 'Number of places',
                                  number: true, initial: '${s['capacity']}'),
                              FieldSpec('price', 'Walk-in Price (${settings['currency']})',
                                  number: true, initial: '${s['price']}'),
                              FieldSpec('level', 'Level', initial: s['level'] as String),
                              FieldSpec('instructorId', 'Instructor',
                                  optional: true,
                                  initial: (s['instructor']?['id'] as String?) ?? '',
                                  options: {
                                    for (final i in instructors)
                                      i['id'] as String: i['name'] as String
                                  }),
                              FieldSpec('description', 'About this session',
                                  multiline: true,
                                  optional: true,
                                  initial: (s['description'] as String?) ?? ''),
                            ],
                            'sessions/${s['id']}',
                            method: 'PATCH',
                            note:
                                'Material schedule updates notify enrolled members. Capacity cannot be reduced below active bookings.',
                          ),
                  child: const Text('Edit')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm(context, 'Cancel session?',
                              'Bookings will be cancelled and reserved credits returned. Bank-transfer refunds must be handled by the studio.')) {
                            await action('sessions/${s['id']}/cancel');
                          }
                        },
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm(context, 'Delete session?',
                              'Remove it from the calendar and cancel its bookings? History is retained.')) {
                            await action('sessions/${s['id']}',
                                method: 'DELETE');
                          }
                        },
                  child: const Text('Delete'))
            ])
        ]));
  }

  Widget bookingList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(
            'YOUR STUDIO SPACE',
            admin
                ? 'Booking desk.'
                : teacher
                    ? 'Class attendance.'
                    : 'Your next moments.',
            '${bookings.length} bookings · ${admin ? 'Review payments and confirm places' : teacher ? 'Record attendance after class starts' : 'Manage your sessions and attendance'}'),
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
                onSelected: (_) =>
                    setState(() => bookingFilter = entry.key))
        ]),
        const SizedBox(height: 16),
        if (bookings.where((b) => bookingFilter == 'ALL' || b['status'] == bookingFilter).isEmpty)
          empty('No bookings found matching filter.',
              Icons.confirmation_number_outlined),
        for (final b in bookings.where((b) => bookingFilter == 'ALL' || b['status'] == bookingFilter))
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: 12, runSpacing: 10, children: [
                              Text(b['session']['title'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 18)),
                              StatusBadge(b['status'] as String),
                              StatusBadge(b['attendance'] as String)
                            ]),
                            const SizedBox(height: 10),
                            Text(when(b['session']['startsAt']),
                                style: const TextStyle(
                                    color: muted, fontSize: 14)),
                            if (!member) Text(b['member']['name'] as String),
                            const SizedBox(height: 8),
                            Text(
                                b['paymentMethod'] == 'CREDITS'
                                    ? '1 class credit'
                                    : money(b['amount']),
                                style:
                                    const TextStyle(color: plum, fontSize: 14)),
                            if (b['rejectionReason'] != null)
                              Text(b['rejectionReason'] as String),
                            if (b['overrideReason'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Note: ${b['overrideReason']}',
                                    style: const TextStyle(fontSize: 13, color: muted)),
                              ),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (b['proofId'] != null && (admin || member))
                                OutlinedButton.icon(
                                    onPressed: () =>
                                        viewProof(b['proofId'] as String),
                                    icon: const Icon(
                                        Icons.receipt_long_outlined,
                                        size: 17),
                                    label: const Text('Payment proof')),
                              if (admin && b['status'] == 'PENDING') ...[
                                FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            if (await confirm(
                                                context,
                                                'Confirm this booking?',
                                                b['paymentMethod'] == 'CREDITS'
                                                    ? 'Confirm this member’s reserved class credit?'
                                                    : 'Confirm only after you have verified the payment screenshot against your bank records.')) {
                                              await action(
                                                  'bookings/${b['id']}/approve',
                                                  success: 'Booking confirmed');
                                            }
                                          },
                                    child: const Text('Confirm')),
                                OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => form(
                                            'Reject booking',
                                            const [
                                              FieldSpec('reason',
                                                  'Reason for rejection',
                                                  multiline: true)
                                            ],
                                            'bookings/${b['id']}/reject',
                                            submit: 'Reject booking'),
                                    child: const Text('Reject'))
                              ],
                              if (admin && b['status'] == 'PAID_AWAITING_RESOLUTION') ...[
                                FilledButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => form(
                                              'Reassign to Session',
                                              [
                                                FieldSpec('targetSessionId', 'Select alternative session',
                                                    options: {
                                                      for (final s in sessions.where((x) =>
                                                          x['status'] == 'SCHEDULED' &&
                                                          DateTime.parse(x['startsAt'] as String)
                                                              .isAfter(DateTime.now()) &&
                                                          (x['spotsLeft'] as int) > 0 &&
                                                          x['id'] != b['sessionId']))
                                                        s['id'] as String:
                                                            '${s['title']} (${when(s['startsAt'], 'EEE d MMM HH:mm')})'
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
                                    label: const Text('Reassign Session')),
                                OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => form(
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
                                    label: const Text('Complete Refund')),
                              ],
                              if (admin &&
                                  ['PENDING', 'CONFIRMED', 'PAID_AWAITING_RESOLUTION']
                                      .contains(b['status']))
                                OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => form(
                                            'Cancel Booking (Admin Override)',
                                            const [
                                              FieldSpec('reason',
                                                  'Audit reason for override cancellation',
                                                  multiline: true)
                                            ],
                                            'admin/bookings/${b['id']}/cancel',
                                            submit: 'Cancel booking',
                                            note:
                                                'Admin override cancellation releases the seat and restores member credits regardless of 24h cutoff.'),
                                    child: const Text('Admin Cancel')),
                              if (member &&
                                  ['PENDING', 'CONFIRMED']
                                      .contains(b['status']))
                                OutlinedButton(
                                    onPressed: busy ||
                                            DateTime.parse(b['session']
                                                        ['startsAt'] as String)
                                                    .difference(
                                                        DateTime.now()) <=
                                                const Duration(hours: 24)
                                        ? null
                                        : () async {
                                            if (await confirm(
                                                context,
                                                'Cancel this booking?',
                                                'Your place will be released. Class credits are returned; contact the studio for bank-transfer refunds.')) {
                                              await action(
                                                  'bookings/${b['id']}/cancel',
                                                  success: 'Booking cancelled');
                                            }
                                          },
                                    child: const Text('Cancel booking')),
                              if (!member &&
                                  b['status'] == 'CONFIRMED' &&
                                  DateTime.parse(
                                          b['session']['startsAt'] as String)
                                      .isBefore(DateTime.now())) ...[
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => action(
                                            'bookings/${b['id']}/attendance',
                                            method: 'PATCH',
                                            body: {'attendance': 'PRESENT'}),
                                    child: const Text('Present')),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => action(
                                            'bookings/${b['id']}/attendance',
                                            method: 'PATCH',
                                            body: {'attendance': 'ABSENT'}),
                                    child: const Text('Absent')),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => action(
                                            'bookings/${b['id']}/attendance',
                                            method: 'PATCH',
                                            body: {'attendance': 'UNMARKED'}),
                                    child: const Text('Clear'))
                              ],
                            ]),
                            if (member &&
                                ['PENDING', 'CONFIRMED'].contains(b['status']))
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Cancellation closes 24 hours before the session.',
                                      style: TextStyle(
                                          fontSize: 12, color: muted)))
                          ]))))
      ]);
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

  Widget practice() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('KEEP GROWING', 'Your practice, at a glance.',
            'Every class is a step forward.'),
        Wrap(spacing: 16, runSpacing: 16, children: [
          stat('Classes remaining', '${me!['credits']}', 'Available to book'),
          stat(
              'Classes attended',
              '${bookings.where((b) => b['attendance'] == 'PRESENT').length}',
              'Your recorded attendance'),
          stat('Active packages', '${packages.where((p) => p['status'] == 'ACTIVE').length}',
              'Valid passes with credits',
              tinted: true)
        ]),
        const SizedBox(height: 28),
        Text('My package passes',
            style: GoogleFonts.cinzel(
                fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
        const SizedBox(height: 16),
        if (packages.isEmpty)
          empty('No active or previous packages found.', Icons.card_membership_outlined)
        else
          for (final p in packages)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.card_membership, color: plum),
                title: Text(p['packageProduct']?['name'] ?? 'Class Package',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${p['creditsRemaining']} of ${p['creditsTotal']} credits left · ${p['expiresAt'] != null ? 'Expires ${when(p['expiresAt'], 'd MMM yyyy')}' : 'Pending activation'}'),
                trailing: StatusBadge(p['status'] as String),
              ),
            ),
        const SizedBox(height: 28),
        Text('Class credit history',
            style: GoogleFonts.cinzel(
                fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
        const SizedBox(height: 16),
        if (ledger.isEmpty)
          empty('Ask the studio to add your class package.',
              Icons.local_activity_outlined),
        for (final l in ledger)
          Card(
              child: ListTile(
                  title: Text(l['reason'] as String),
                  subtitle: Text(when(l['createdAt'])),
                  trailing: Text(
                      '${(l['delta'] as int) > 0 ? '+' : ''}${l['delta']}',
                      style: const TextStyle(color: plum, fontSize: 20)))),
        const SizedBox(height: 26),
        Text('Attendance',
            style: GoogleFonts.cinzel(
                fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
        const SizedBox(height: 14),
        if (!bookings.any((b) => b['attendance'] != 'UNMARKED'))
          empty('Attendance appears after your instructor records it.',
              Icons.fact_check_outlined),
        for (final b in bookings.where((b) => b['attendance'] != 'UNMARKED'))
          Card(
              child: ListTile(
                  title: Text(b['session']['title'] as String),
                  subtitle: Text(when(b['session']['startsAt'])),
                  trailing: StatusBadge(b['attendance'] as String)))
      ]);
  Widget instructorList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('THE PEOPLE BEHIND YOUR PRACTICE', 'Meet your instructors.',
            'Manage profiles and link verified instructor accounts.',
            button: FilledButton.icon(
                onPressed: () => form(
                    'Add instructor',
                    const [
                      FieldSpec('name', 'Full name'),
                      FieldSpec('phone', 'Phone number'),
                      FieldSpec('email', 'Account email'),
                      FieldSpec('specialty', 'Specialty'),
                      FieldSpec('bio', 'Description (optional)',
                          multiline: true, optional: true)
                    ],
                    'instructors'),
                icon: const Icon(Icons.add),
                label: const Text('Add instructor'))),
        if (instructors.isEmpty)
          empty('Add your first instructor to create yoga classes.',
              Icons.people_outline),
        for (final i in instructors)
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i['name'] as String,
                                style: GoogleFonts.cinzel(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: ink)),
                            const SizedBox(height: 8),
                            Text(i['specialty'] as String,
                                style: const TextStyle(color: plum)),
                            if (i['phone'] != null &&
                                (i['phone'] as String).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(children: [
                                const Icon(Icons.phone_outlined,
                                    size: 16, color: muted),
                                const SizedBox(width: 6),
                                Text(i['phone'] as String,
                                    style: const TextStyle(
                                        fontSize: 14, color: ink)),
                              ]),
                            ],
                            if (i['bio'] != null &&
                                (i['bio'] as String).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(i['bio'] as String),
                            ],
                            const SizedBox(height: 16),
                            Text(
                                '${i['classesTaught']} classes taught · ${i['autoAccept'] == true ? 'Auto-accept on' : 'Manual acceptance'}',
                                style: const TextStyle(
                                    fontSize: 14, color: muted)),
                            const SizedBox(height: 10),
                            Text(i['email'] as String,
                                style: const TextStyle(fontSize: 14)),
                            if (i['userId'] == null)
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await confirm(
                                              context,
                                              'Link instructor account?',
                                              'Verify that the registered account ${i['email']} belongs to this instructor. Linking gives that account instructor access.')) {
                                            await action(
                                                'instructors/${i['id']}/link');
                                          }
                                        },
                                  child: const Text('Link registered account'))
                            else
                              const Text('Account linked',
                                  style: TextStyle(color: plum, fontSize: 13))
                          ]))))
      ]);
  Widget memberList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('YOUR COMMUNITY', 'Studio members.',
            'Add package credits after verifying package payment.'),
        if (members.isEmpty)
          empty('Members appear after they create an account.',
              Icons.groups_outlined),
        for (final m in members)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      title: Text(m['name'] as String),
                      subtitle: Text(
                          '${m['email']}\n${m['credits']} credits left · ${m['_count']['bookings']} classes attended'),
                      isThreeLine: true,
                      trailing: TextButton(
                          onPressed: () => form(
                              'Add class credits',
                              const [
                                FieldSpec('amount', 'Number of credits',
                                    number: true),
                                FieldSpec(
                                    'reason', 'Package / payment reference')
                              ],
                              'members/${m['id']}/credits',
                              note:
                                  'Credits are added to the member’s available balance immediately.'),
                          child: const Text('Add credits')))))
      ]);
  Widget promotions() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('A LITTLE EXTRA MAGIC', 'Studio promotions.',
            'Percentage discounts for bank-transfer bookings.',
            button: FilledButton.icon(
                onPressed: () => form(
                    'Create promotion',
                    const [
                      FieldSpec('code', 'Promotion code'),
                      FieldSpec('percent', 'Discount percentage (1–100)',
                          number: true),
                      FieldSpec('expiresAt', 'Expires at', dateTime: true)
                    ],
                    'promotions'),
                icon: const Icon(Icons.add),
                label: const Text('Create promotion'))),
        if (promos.isEmpty)
          empty('Create your first studio offer.', Icons.local_offer_outlined),
        for (final p in promos)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: SwitchListTile(
                      title: Text('${p['code']} · ${p['percent']}% off'),
                      subtitle: Text('Expires ${when(p['expiresAt'])}'),
                      value: p['active'] as bool,
                      onChanged: busy
                          ? null
                          : (v) => action('promotions/${p['id']}',
                              method: 'PATCH', body: {'active': v})))),
        const SizedBox(height: 30),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share something new.',
                          style: GoogleFonts.cinzel(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: ink)),
                      const SizedBox(height: 12),
                      const Text(
                          'Publish an in-app campaign notification to every member.'),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                          onPressed: () => form(
                              'Notify all members',
                              const [
                                FieldSpec('title', 'Campaign title'),
                                FieldSpec('body', 'Message', multiline: true)
                              ],
                              'campaigns',
                              submit: 'Publish notification',
                              note:
                                  'This message will appear in every member’s notification inbox.'),
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('New campaign'))
                    ])))
      ]);
  Widget availability() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('MAKE SPACE FOR YOU', 'Your availability.',
            'Blocks keep unavailable time out of the studio schedule.',
            button: FilledButton.icon(
                onPressed: () => form(
                    'Block unavailable time',
                    const [
                      FieldSpec('startsAt', 'Unavailable from', dateTime: true),
                      FieldSpec('endsAt', 'Unavailable until', dateTime: true),
                      FieldSpec('reason', 'Reason')
                    ],
                    'instructor/blocks'),
                icon: const Icon(Icons.add),
                label: const Text('Block time'))),
        Card(
            child: SwitchListTile(
                title: const Text('Automatically accept new classes'),
                subtitle: const Text(
                    'New admin-approved assignments are accepted immediately. Existing invitations still need your response.'),
                value: me!['instructor']?['autoAccept'] == true,
                onChanged: busy
                    ? null
                    : (v) => action('instructor/settings',
                        method: 'PATCH', body: {'autoAccept': v}))),
        const SizedBox(height: 24),
        if (blocks.isEmpty)
          empty('No unavailable time added.', Icons.event_available_outlined),
        for (final b in blocks)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: ListTile(
                      title: Text(b['reason'] as String),
                      subtitle: Text(
                          '${when(b['startsAt'])}\nUntil ${when(b['endsAt'])}'),
                      isThreeLine: true,
                      trailing: IconButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await confirm(
                                      context,
                                      'Remove this block?',
                                      'The studio will be able to assign classes during this time.')) {
                                    await action('instructor/blocks/${b['id']}',
                                        method: 'DELETE');
                                  }
                                },
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove block'))))
      ]);
  Widget requestList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(
            'FIND YOUR TIME',
            'Preferred timeslots.',
            admin
                ? 'Review member requests and create a session when it works.'
                : 'Ask the studio for a time that fits your day.',
            button: member
                ? FilledButton.icon(
                    onPressed: requestTime,
                    icon: const Icon(Icons.add),
                    label: const Text('Request a time'))
                : null),
        if (requests.isEmpty)
          empty('No timeslot requests yet.', Icons.schedule_outlined),
        for (final r in requests)
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: 12, runSpacing: 8, children: [
                              Text(sessionTypes[r['type']] ?? '',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                              StatusBadge(r['status'] as String)
                            ]),
                            const SizedBox(height: 12),
                            Text(
                                '${when(r['startsAt'])} – ${when(r['endsAt'], 'HH:mm')}'),
                            if (admin)
                              Text(r['member']['name'] as String,
                                  style: const TextStyle(color: muted)),
                            const SizedBox(height: 12),
                            Text(r['note'] as String),
                            if (r['response'] != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text('Studio: ${r['response']}',
                                      style: const TextStyle(color: plum))),
                            if (admin && r['status'] == 'PENDING')
                              TextButton(
                                  onPressed: () => form(
                                      'Respond to request',
                                      const [
                                        FieldSpec('status', 'Response',
                                            options: {
                                              'REVIEWED':
                                                  'Reviewed — follow up / create session',
                                              'DECLINED':
                                                  'Unable to accommodate'
                                            }),
                                        FieldSpec(
                                            'response', 'Message to member',
                                            multiline: true)
                                      ],
                                      'requests/${r['id']}',
                                      method: 'PATCH',
                                      note:
                                          'Reviewing does not automatically create a class. Create it in the schedule, then invite the member to book.'),
                                  child: const Text('Respond'))
                          ]))))
      ]);
  Widget notifications() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading('STAY IN THE LOOP', 'Your studio inbox.',
            'Booking updates, class reminders, and a little inspiration.'),
        if (notices.isEmpty)
          empty('You’re all caught up.', Icons.notifications_none),
        for (final n in notices)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  color: n['readAt'] == null
                      ? const Color(0xFFF0EDE6)
                      : Colors.white,
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
                      leading: Icon(
                          n['readAt'] == null
                              ? Icons.mark_email_unread_outlined
                              : Icons.drafts_outlined,
                          color: plum),
                      title: Text(n['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child:
                              Text('${n['body']}\n\n${when(n['createdAt'])}')),
                      onTap: n['readAt'] == null
                          ? () => action('notifications/${n['id']}/read',
                              method: 'PATCH', success: 'Marked as read')
                          : null)))
      ]);

  // --- Package Catalog & Management (SBQS_V1 FR02, FR04, FR10, AC03) ---

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
                          'Price: ${money(product['price'])} · Valid for ${product['validityDays']} days after studio approval.',
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

  Widget packagesSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            'PACKAGES & PASSES',
            admin ? 'Studio class packages.' : 'Class packages & passes.',
            admin
                ? 'Manage catalog offerings and review member package purchases.'
                : 'Purchase bundled class credits or view your package status.',
            button: admin
                ? FilledButton.icon(
                    onPressed: () => form(
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
          Text('Available Packages',
              style: GoogleFonts.cinzel(
                  fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
          const SizedBox(height: 14),
          if (packageProducts.isEmpty)
            empty('No packages currently offered.', Icons.card_membership_outlined),
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
                            Text(p['name'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 18)),
                            const SizedBox(height: 6),
                            Text(
                              '${p['credits']} credits · ${money(p['price'])} · Valid ${p['validityDays']} days',
                              style: const TextStyle(color: plum, fontWeight: FontWeight.w600),
                            ),
                            if (p['description'] != null &&
                                (p['description'] as String).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(p['description'] as String,
                                  style: const TextStyle(color: muted, fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                      if (member)
                        FilledButton(
                          onPressed: busy ? null : () => purchasePackageFlow(p),
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
                fontSize: 20, fontWeight: FontWeight.w600, color: ink),
          ),
          const SizedBox(height: 14),
          if (packages.isEmpty)
            empty(
                admin
                    ? 'No package orders submitted yet.'
                    : 'You haven’t bought any packages yet.',
                Icons.receipt_outlined),
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
                              fontWeight: FontWeight.w600, fontSize: 18),
                        ),
                        StatusBadge(mp['status'] as String),
                      ]),
                      const SizedBox(height: 10),
                      if (admin && mp['user'] != null)
                        Text('Member: ${mp['user']['name']} (${mp['user']['email']})',
                            style: const TextStyle(color: muted, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        'Credits: ${mp['creditsRemaining']} / ${mp['creditsTotal']} remaining · Paid: ${money(mp['pricePaid'])}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (mp['expiresAt'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Expires: ${when(mp['expiresAt'])}',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                      if (mp['rejectionReason'] != null) ...[
                        const SizedBox(height: 6),
                        Text('Rejection reason: ${mp['rejectionReason']}',
                            style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (mp['proofId'] != null)
                          OutlinedButton.icon(
                            onPressed: () => viewProof(mp['proofId'] as String),
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
                                      await action(
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
                                : () => form(
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
