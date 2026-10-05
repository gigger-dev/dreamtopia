import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../api.dart';
import '../../theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/studio_common.dart';
import '../booking.dart';

const scheduleSessionTypes = {
  'POLE_CLASS': 'Pole classes',
  'TRIAL': 'Trial classes',
  'PRACTICE': 'Pole practice',
  'RENTAL': 'Studio rental',
};

class ScheduleView extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? me;
  final Map<String, dynamic> settings;
  final bool admin;
  final bool teacher;
  final bool member;
  final bool busy;
  final List<dynamic> sessions;
  final List<dynamic> bookings;
  final List<dynamic> instructors;
  final DateTime week;
  final DateTime selectedDate;
  final tz.Location zone;
  final VoidCallback onCreateSession;
  final VoidCallback onRequestTime;
  final VoidCallback onReload;
  final Function(DateTime newWeek, DateTime newSelectedDate) onPeriodChanged;
  final Future<void> Function(String path, {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path, {String method, String? note, String submit}) onForm;
  final String Function(dynamic iso, [String pattern]) onFormatDate;
  final void Function(String message) onShowMessage;

  const ScheduleView({
    super.key,
    required this.api,
    required this.me,
    required this.settings,
    required this.admin,
    required this.teacher,
    required this.member,
    required this.busy,
    required this.sessions,
    required this.bookings,
    required this.instructors,
    required this.week,
    required this.selectedDate,
    required this.zone,
    required this.onCreateSession,
    required this.onRequestTime,
    required this.onReload,
    required this.onPeriodChanged,
    required this.onAction,
    required this.onForm,
    required this.onFormatDate,
    required this.onShowMessage,
  });

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  String filter = 'ALL';
  String viewMode = 'WEEK'; // 'WEEK', 'MONTH', 'DAY'
  String? selectedInstructorId;
  String searchQuery = '';
  final searchController = TextEditingController();

  late DateTime currentWeek;
  late DateTime currentSelectedDate;

  @override
  void initState() {
    super.initState();
    currentWeek = widget.week;
    currentSelectedDate = widget.selectedDate;
  }

  @override
  void didUpdateWidget(covariant ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.week != widget.week || oldWidget.selectedDate != widget.selectedDate) {
      currentWeek = widget.week;
      currentSelectedDate = widget.selectedDate;
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _money(dynamic n) =>
      '${NumberFormat.decimalPattern().format(n)} ${widget.settings['currency']}';

  void _changePeriod(int dir) {
    setState(() {
      if (viewMode == 'MONTH') {
        currentWeek = DateTime(currentWeek.year, currentWeek.month + dir, 1);
      } else if (viewMode == 'DAY') {
        currentSelectedDate = currentSelectedDate.add(Duration(days: dir));
        currentWeek = currentSelectedDate.subtract(Duration(days: currentSelectedDate.weekday - 1));
      } else {
        currentWeek = currentWeek.add(Duration(days: dir * 7));
      }
    });
    widget.onPeriodChanged(currentWeek, currentSelectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final now = tz.TZDateTime.now(widget.zone);
    final filtered = widget.sessions.where((s) {
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

    final confirmed = widget.bookings
        .where((b) =>
            b['status'] == 'CONFIRMED' &&
            DateTime.parse(b['session']['startsAt'] as String)
                .isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => (a['session']['startsAt'] as String)
          .compareTo(b['session']['startsAt'] as String));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        studioHeading(
          context,
          'FIND YOUR FLOW',
          widget.admin
              ? 'Your studio, in balance.'
              : widget.teacher
                  ? 'Your teaching calendar.'
                  : 'Make time for you.',
          'A little movement, a little magic.',
          button: widget.admin
              ? FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onCreateSession,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create session'),
                )
              : widget.member
                  ? FilledButton.icon(
                      onPressed: widget.onRequestTime,
                      icon: const Icon(Icons.north_east, size: 18),
                      label: const Text('Request a timeslot'),
                    )
                  : null,
        ),
        Wrap(spacing: 16, runSpacing: 16, children: [
          studioStat(
            widget.member
                ? 'Classes remaining'
                : widget.teacher
                    ? 'Classes taught'
                    : 'Awaiting confirmation',
            widget.member
                ? '${widget.me?['credits'] ?? 0}'
                : widget.teacher
                    ? '${widget.me?['classesTaught'] ?? 0}'
                    : '${widget.bookings.where((b) => b['status'] == 'PENDING').length}',
            widget.member
                ? 'Available class credits'
                : widget.teacher
                    ? 'Completed teaching sessions'
                    : 'Bookings ready for review',
          ),
          studioStat(
            widget.member ? 'Your next class' : 'This week',
            widget.member
                ? (confirmed.isEmpty
                    ? 'Let’s get moving'
                    : widget.onFormatDate(
                        confirmed.first['session']['startsAt'], 'EEE, d MMM'))
                : '${widget.sessions.where((s) => s['status'] == 'SCHEDULED').length} sessions',
            widget.member
                ? (confirmed.isEmpty
                    ? 'Find your next class below'
                    : confirmed.first['session']['title'] as String)
                : 'Scheduled in the studio',
          ),
          studioStat(
            'SEVEN COLORS. ONE YOU.',
            'Find your balance.',
            'Own your strength.',
            tinted: true,
          ),
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
                          child: Text(
                            'Search & Filters',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                        label: const Text('Reset filters'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 14, children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: searchController,
                      onChanged: (v) => setState(() => searchQuery = v.trim()),
                      decoration: InputDecoration(
                        labelText: 'Search class or instructor',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() {
                                  searchController.clear();
                                  searchQuery = '';
                                }),
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (widget.instructors.isNotEmpty)
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        value: selectedInstructorId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Filter by Instructor',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Instructors'),
                          ),
                          for (final ins in widget.instructors)
                            DropdownMenuItem(
                              value: ins['id'] as String,
                              child: Text(ins['name'] as String),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => selectedInstructorId = v),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in {
                    'ALL': 'All sessions',
                    ...scheduleSessionTypes,
                  }.entries)
                    ChoiceChip(
                      label: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 12, color: Colors.black),
                      ),
                      selected: filter == entry.key,
                      onSelected: (_) => setState(() => filter = entry.key),
                    ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Calendar Navigation & View Mode Toggle (Day / Week / Month)
        Wrap(
          spacing: 18,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'The studio schedule',
              style: GoogleFonts.cinzel(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in const {
                'DAY': 'Day',
                'WEEK': 'Week',
                'MONTH': 'Month',
              }.entries)
                ChoiceChip(
                  label: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                  selected: viewMode == entry.key,
                  onSelected: (_) => setState(() => viewMode = entry.key),
                ),
            ]),
          ],
        ),
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
                      'MONTH' => DateFormat('MMMM yyyy').format(currentWeek),
                      'DAY' => DateFormat('EEEE, d MMMM yyyy').format(currentSelectedDate),
                      _ =>
                        '${DateFormat('d MMM').format(currentWeek)} – ${DateFormat('d MMM yyyy').format(currentWeek.add(const Duration(days: 6)))}',
                    },
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _changePeriod(-1),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous',
                      ),
                      TextButton(
                        onPressed: () {
                          final today = tz.TZDateTime.now(widget.zone);
                          setState(() {
                            currentSelectedDate = DateTime(today.year, today.month, today.day);
                            currentWeek = currentSelectedDate.subtract(Duration(days: today.weekday - 1));
                          });
                          widget.onPeriodChanged(currentWeek, currentSelectedDate);
                        },
                        child: const Text('Today'),
                      ),
                      IconButton(
                        onPressed: () => _changePeriod(1),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Active Calendar View
        switch (viewMode) {
          'DAY' => _buildDayView(filtered, now),
          'MONTH' => _buildMonthView(filtered, now),
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
                            child: _buildDayColumn(i, filtered, now),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: List.generate(
                        7,
                        (i) => _buildDayColumn(i, filtered, now),
                      ),
                    );
            }),
        },
        const SizedBox(height: 18),
        const Text(
          'Bookings are confirmed after studio review. Bank transfers are verified manually.',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      ],
    );
  }

  Widget _buildDayView(List<dynamic> data, DateTime now) {
    final d = currentSelectedDate;
    final rows = data.where((s) {
      final dt = tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), widget.zone);
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
                    DateTime.parse(s['startsAt'] as String), widget.zone);
                return startDt.hour == hour;
              }).toList();

              return Container(
                constraints: const BoxConstraints(minHeight: 64),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: sageBorder, width: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 75,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          hourLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 64, color: sageBorder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: matchingSessions.isEmpty
                          ? const SizedBox(height: 64)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final s in matchingSessions)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                                    child: _buildSessionCard(
                                      Map<String, dynamic>.from(s),
                                      hour % chakra.length,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthView(List<dynamic> data, DateTime now) {
    final firstOfMonth = DateTime(currentWeek.year, currentWeek.month, 1);
    final daysInMonth = DateTime(currentWeek.year, currentWeek.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday;

    final gridCells = <Widget>[];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (final h in days) {
      gridCells.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          child: Text(
            h,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: muted),
          ),
        ),
      );
    }

    for (int i = 1; i < startWeekday; i++) {
      gridCells.add(const SizedBox());
    }

    for (int dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      final d = DateTime(currentWeek.year, currentWeek.month, dayNum);
      final daySessions = data.where((s) {
        final dt = tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), widget.zone);
        return dt.year == d.year && dt.month == d.month && dt.day == d.day;
      }).toList();
      final isToday = d.year == now.year && d.month == now.month && d.day == now.day;

      gridCells.add(
        InkWell(
          onTap: () => setState(() {
            currentSelectedDate = d;
            viewMode = 'DAY';
            widget.onPeriodChanged(currentWeek, currentSelectedDate);
          }),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isToday ? sageLight : Colors.white,
              border: Border.all(color: sageBorder.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? sageGreen : ink,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                for (final s in daySessions.take(2))
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: sageGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      s['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: sageGreen),
                    ),
                  ),
                if (daySessions.length > 2)
                  Text(
                    '+${daySessions.length - 2} more',
                    style: const TextStyle(fontSize: 9, color: muted, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1.1,
      children: gridCells,
    );
  }

  Widget _buildDayColumn(int day, List<dynamic> data, DateTime now) {
    final d = currentWeek.add(Duration(days: day));
    final rows = data.where((s) {
      final dt = tz.TZDateTime.from(DateTime.parse(s['startsAt'] as String), widget.zone);
      return dt.year == d.year && dt.month == d.month && dt.day == d.day;
    }).toList();
    final today = d.year == now.year && d.month == now.month && d.day == now.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: today ? sageLight : Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            DateFormat('EEE  d').format(d),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: today ? plum : muted,
              fontWeight: today ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No sessions',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        for (final s in rows) _buildSessionCard(Map<String, dynamic>.from(s), day),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> s, int color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: chakra[color].withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(4),
        border: Border(top: BorderSide(color: chakra[color], width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.onFormatDate(s['startsAt'], 'HH:mm')} – ${widget.onFormatDate(s['endsAt'], 'HH:mm')}',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            s['title'] as String,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            s['instructor']?['name']?.toString() ?? 'Your studio time',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 7),
          Text(s['level'] as String, style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 14),
          Text(
            '${s['spotsLeft']} / ${s['capacity']} places left',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
          Text(_money(s['price']), style: const TextStyle(fontSize: 13, color: plum)),
          const SizedBox(height: 12),
          if (!widget.member) StatusBadge(s['status'] as String),
          if (widget.member)
            TextButton(
              onPressed: (s['spotsLeft'] as int) > 0 &&
                      DateTime.parse(s['startsAt'] as String).isAfter(DateTime.now())
                  ? () async {
                      final result = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => BookingDialog(
                          api: widget.api,
                          session: s,
                          settings: widget.settings,
                          credits: (widget.me?['credits'] ?? 0) as int,
                        ),
                      );
                      if (result == true) {
                        widget.onReload();
                        widget.onShowMessage('Booking submitted for confirmation');
                      }
                    }
                  : null,
              child: const Text('Book session ↗'),
            ),
          if (widget.teacher && s['status'] == 'PENDING_INSTRUCTOR')
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.onAction(
                          'sessions/${s['id']}/accept',
                          success: 'Class accepted',
                        ),
                child: const Text('Accept class'),
              ),
              TextButton(
                onPressed: widget.busy
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
                                labelText: 'Reason for declining (optional)',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Decline'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await widget.onAction(
                            'sessions/${s['id']}/decline',
                            body: {'reason': reasonCtrl.text.trim()},
                            success: 'Class declined',
                          );
                        }
                      },
                child: const Text('Decline', style: TextStyle(color: Colors.red)),
              ),
            ]),
          if ((widget.admin || widget.teacher) &&
              s['status'] == 'SCHEDULED' &&
              DateTime.parse(s['endsAt'] as String).isBefore(DateTime.now()))
            TextButton(
              onPressed: widget.busy
                  ? null
                  : () => widget.onAction(
                        'sessions/${s['id']}/complete',
                        success: 'Class completed',
                      ),
              child: const Text('Mark taught'),
            ),
          if (widget.admin && s['status'] != 'COMPLETED')
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.onForm(
                          'Edit session',
                          [
                            FieldSpec('title', 'Session name', initial: s['title'] as String),
                            FieldSpec('type', 'Session type',
                                initial: s['type'] as String, options: scheduleSessionTypes),
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
                                        DateTime.parse(s['startsAt'] as String), widget.zone))),
                            FieldSpec('endsAt', 'Ends at',
                                dateTime: true,
                                initial: DateFormat('yyyy-MM-dd HH:mm').format(
                                    tz.TZDateTime.from(
                                        DateTime.parse(s['endsAt'] as String), widget.zone))),
                            FieldSpec('capacity', 'Number of places',
                                number: true, initial: '${s['capacity']}'),
                            FieldSpec('price', 'Walk-in Price (${widget.settings['currency']})',
                                number: true, initial: '${s['price']}'),
                            FieldSpec('level', 'Level', initial: s['level'] as String),
                            FieldSpec('instructorId', 'Instructor',
                                optional: true,
                                initial: (s['instructor']?['id'] as String?) ?? '',
                                options: {
                                  for (final i in widget.instructors)
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
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Cancel session?',
                          'Bookings will be cancelled and reserved credits returned. Bank-transfer refunds must be handled by the studio.',
                        )) {
                          await widget.onAction('sessions/${s['id']}/cancel');
                        }
                      },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Delete session?',
                          'Remove it from the calendar and cancel its bookings? History is retained.',
                        )) {
                          await widget.onAction('sessions/${s['id']}', method: 'DELETE');
                        }
                      },
                child: const Text('Delete'),
              ),
            ]),
        ],
      ),
    );
  }
}
