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
  final Future<void> Function(String path,
      {String method, Map<String, dynamic>? body, String success}) onAction;
  final Future<void> Function(String title, List<FieldSpec> fields, String path,
      {String method, String? note, String submit}) onForm;
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
  bool showAdvancedSearch = false;
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
    if (oldWidget.week != widget.week ||
        oldWidget.selectedDate != widget.selectedDate) {
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
        currentWeek = currentSelectedDate
            .subtract(Duration(days: currentSelectedDate.weekday - 1));
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
        // 3 stat cards spanning the full width
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 768;

            final stat1Title = widget.member
                ? 'Classes remaining'
                : widget.teacher
                    ? 'Classes taught'
                    : 'Awaiting confirmation';
            final stat1Value = widget.member
                ? '${widget.me?['credits'] ?? 0}'
                : widget.teacher
                    ? '${widget.me?['classesTaught'] ?? 0}'
                    : '${widget.bookings.where((b) => b['status'] == 'PENDING').length}';
            final stat1Sub = widget.member
                ? 'Available class credits'
                : widget.teacher
                    ? 'Completed teaching sessions'
                    : 'Bookings ready for review';

            final stat2Title = widget.member ? 'Your next class' : 'This week';
            final stat2Value = widget.member
                ? (confirmed.isEmpty
                    ? 'Let’s get moving'
                    : widget.onFormatDate(
                        confirmed.first['session']['startsAt'], 'EEE, d MMM'))
                : '${widget.sessions.where((s) => s['status'] == 'SCHEDULED').length} sessions';
            final stat2Sub = widget.member
                ? (confirmed.isEmpty
                    ? 'Find your next class below'
                    : confirmed.first['session']['title'] as String)
                : 'Scheduled in the studio';

            const stat3Title = 'SEVEN COLORS. ONE YOU.';
            const stat3Value = 'Find your balance.';
            const stat3Sub = 'Own your strength.';

            Widget buildCard({
              required String title,
              required String value,
              required String subtitle,
              required Color accentColor,
              bool isAccent = false,
            }) {
              return Container(
                width: double.infinity,
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
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: accentColor, width: 4),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: isAccent ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: isAccent ? sageGreen : ink,
                            fontFamily: isAccent
                                ? GoogleFonts.cinzel().fontFamily
                                : GoogleFonts.lato().fontFamily,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(color: muted, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final card1 = buildCard(
              title: stat1Title,
              value: stat1Value,
              subtitle: stat1Sub,
              accentColor: sageGreen,
            );

            final card2 = buildCard(
              title: stat2Title,
              value: stat2Value,
              subtitle: stat2Sub,
              accentColor: chakra[1],
            );

            final card3 = buildCard(
              title: stat3Title,
              value: stat3Value,
              subtitle: stat3Sub,
              accentColor: chakra[3],
              isAccent: true,
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                  const SizedBox(width: 14),
                  Expanded(child: card3),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  card1,
                  const SizedBox(height: 12),
                  card2,
                  const SizedBox(height: 12),
                  card3,
                ],
              );
            }
          },
        ),
        const SizedBox(height: 32),

        // Calendar Navigation & View Mode Toggle (Day / Week / Month) + Advanced Search Toggle
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final leftSection = Wrap(
              spacing: 14,
              runSpacing: 8,
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
                FilterChip(
                  showCheckmark: false,
                  avatar: Icon(
                    showAdvancedSearch ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 16,
                    color: showAdvancedSearch ? plum : muted,
                  ),
                  label: Text(
                    'Search & Filters',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: showAdvancedSearch
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: showAdvancedSearch ? plum : ink,
                    ),
                  ),
                  selected: showAdvancedSearch,
                  selectedColor: sageLight,
                  onSelected: (val) => setState(() => showAdvancedSearch = val),
                ),
              ],
            );

            final rightSection = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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
              ],
            );

            return isWide
                ? SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(child: leftSection),
                        const SizedBox(width: 16),
                        rightSection,
                      ],
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leftSection,
                        const SizedBox(height: 12),
                        rightSection,
                      ],
                    ),
                  );
          },
        ),
        const SizedBox(height: 14),

        // Collapsible Advanced Search & Filter Bar
        if (showAdvancedSearch) ...[
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
                          Icon(Icons.search, color: plum, size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Filter Sessions',
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
                  LayoutBuilder(builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 600;
                    return isDesktop
                        ? Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: searchController,
                                  onChanged: (v) =>
                                      setState(() => searchQuery = v.trim()),
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
                              if (widget.instructors.isNotEmpty) ...[
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 2,
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
                              ],
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: searchController,
                                onChanged: (v) =>
                                    setState(() => searchQuery = v.trim()),
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
                              if (widget.instructors.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String?>(
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
                              ],
                            ],
                          );
                  }),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in {
                      'ALL': 'All sessions',
                      ...scheduleSessionTypes,
                    }.entries)
                      ChoiceChip(
                        label: Text(
                          entry.value,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black),
                        ),
                        selected: filter == entry.key,
                        onSelected: (_) => setState(() => filter = entry.key),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

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
                      'DAY' => DateFormat('EEEE, d MMMM yyyy')
                          .format(currentSelectedDate),
                      _ =>
                        '${DateFormat('d MMM').format(currentWeek)} – ${DateFormat('d MMM yyyy').format(currentWeek.add(const Duration(days: 6)))}',
                    },
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
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
                            currentSelectedDate =
                                DateTime(today.year, today.month, today.day);
                            currentWeek = currentSelectedDate
                                .subtract(Duration(days: today.weekday - 1));
                          });
                          widget.onPeriodChanged(
                              currentWeek, currentSelectedDate);
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
    final daySessions = data.where((s) {
      final dt = tz.TZDateTime.from(
          DateTime.parse(s['startsAt'] as String), widget.zone);
      return dt.year == d.year && dt.month == d.month && dt.day == d.day;
    }).toList()
      ..sort((a, b) => (a['startsAt'] as String).compareTo(b['startsAt'] as String));

    // Build timeline events/intervals for the day
    // We break the day into chronological slots based on standard hours and session boundaries,
    // but suppress any slots that fall strictly inside an active session's running window
    // (e.g. for a 10:00 AM - 1:00 PM session, the card is at 10:00 AM, and 11:00 AM, 12:00 PM, 1:00 PM are skipped,
    // resuming at the next slot such as 2:00 PM).
    final sessionIntervals = daySessions.map((s) {
      final startDt = tz.TZDateTime.from(
          DateTime.parse(s['startsAt'] as String), widget.zone);
      final endDt = tz.TZDateTime.from(
          DateTime.parse(s['endsAt'] as String), widget.zone);
      return (
        start: startDt.hour * 60 + startDt.minute,
        end: endDt.hour * 60 + endDt.minute,
        session: s,
      );
    }).toList();

    final rawPoints = <int>{};
    for (int h = 7; h <= 21; h++) {
      rawPoints.add(h * 60);
    }
    for (final inter in sessionIntervals) {
      rawPoints.add(inter.start);
      // Include the exact end time of the session on the timeline (e.g. 2:30 PM)
      if (inter.end <= 22 * 60) {
        rawPoints.add(inter.end);
      }
    }

    // Filter points:
    // 1. Keep session start times and session end times.
    // 2. Suppress any points that fall strictly INSIDE a running session: (start < pt < end).
    final validPoints = rawPoints.where((pt) {
      // If a session starts or ends at pt, always keep it
      if (sessionIntervals.any((si) => si.start == pt || si.end == pt)) {
        return true;
      }
      // If pt is strictly inside an ongoing session, suppress it
      final isInsideOngoing = sessionIntervals.any((si) => pt > si.start && pt < si.end);
      return !isInsideOngoing;
    }).toSet();

    final sortedPoints = validPoints.toList()..sort();

    String formatMinutes(int totalMins) {
      final hour = (totalMins ~/ 60) % 24;
      final minute = totalMins % 60;
      final minStr = minute.toString().padLeft(2, '0');
      if (hour == 0) return '12:$minStr AM';
      if (hour < 12) return '$hour:$minStr AM';
      if (hour == 12) return '12:$minStr PM';
      return '${hour - 12}:$minStr PM';
    }

    return Card(
      child: Container(
        height: 600,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: daySessions.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_busy, size: 40, color: muted),
                      const SizedBox(height: 12),
                      Text(
                        'No sessions scheduled for ${DateFormat('d MMMM yyyy').format(d)}',
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  children: List.generate(sortedPoints.length, (index) {
                    final currentMins = sortedPoints[index];

                    // Sessions that start at this specific time point
                    final startingHere = daySessions.where((s) {
                      final startDt = tz.TZDateTime.from(
                          DateTime.parse(s['startsAt'] as String), widget.zone);
                      return (startDt.hour * 60 + startDt.minute) == currentMins;
                    }).toList();

                    // Show if a session starts here, if it is a session end boundary, or standard hour marker
                    final isHourMarker = currentMins % 60 == 0;
                    final isSessionBoundary = sessionIntervals.any((si) => si.end == currentMins);
                    if (startingHere.isEmpty && !isHourMarker && !isSessionBoundary) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: sageBorder, width: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time side (no timezone text, clean local time)
                          SizedBox(
                            width: 80,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                formatMinutes(currentMins),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: startingHere.isNotEmpty ? FontWeight.bold : FontWeight.w500,
                                  color: startingHere.isNotEmpty ? plum : muted,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            constraints: const BoxConstraints(minHeight: 56),
                            color: sageBorder,
                          ),
                          const SizedBox(width: 14),
                          // Content side
                          Expanded(
                            child: startingHere.isEmpty
                                ? const SizedBox(height: 56)
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      for (final s in startingHere)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: _buildSessionCard(
                                            Map<String, dynamic>.from(s),
                                            (currentMins ~/ 60) % chakra.length,
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
    final daysInMonth =
        DateTime(currentWeek.year, currentWeek.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday;

    final gridCells = <Widget>[];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (int i = 1; i < startWeekday; i++) {
      gridCells.add(const SizedBox());
    }

    for (int dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      final d = DateTime(currentWeek.year, currentWeek.month, dayNum);
      final daySessions = data.where((s) {
        final dt = tz.TZDateTime.from(
            DateTime.parse(s['startsAt'] as String), widget.zone);
        return dt.year == d.year && dt.month == d.month && dt.day == d.day;
      }).toList();
      final isToday =
          d.year == now.year && d.month == now.month && d.day == now.day;

      gridCells.add(
        InkWell(
          onTap: () => setState(() {
            currentSelectedDate = d;
            viewMode = 'DAY';
            widget.onPeriodChanged(currentWeek, currentSelectedDate);
          }),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isToday ? sageGreen.withValues(alpha: 0.12) : Colors.white,
              border: Border.all(
                color: isToday ? sageGreen : sageBorder.withValues(alpha: 0.5),
                width: isToday ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isToday ? sageGreen : ink,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (daySessions.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: sageGreen.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sageGreen.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${daySessions.length}',
                        style: const TextStyle(
                          color: sageGreen,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Weekday column headers styled identically to the week view dayColumn header card
    final todayWeekday = now.weekday; // 1 = Mon, 7 = Sun
    final headerRow = Row(
      children: List.generate(7, (i) {
        final isTodayColumn = (i + 1) == todayWeekday &&
            currentWeek.year == now.year &&
            currentWeek.month == now.month;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 6 ? 0 : 6),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isTodayColumn ? sageGreen : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isTodayColumn ? sageGreen : sageBorder.withValues(alpha: 0.6),
                width: isTodayColumn ? 1.5 : 1.0,
              ),
              boxShadow: isTodayColumn
                  ? [
                      BoxShadow(
                        color: sageGreen.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              days[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isTodayColumn ? Colors.white : muted,
                fontWeight: isTodayColumn ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        );
      }),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final cellAspectRatio = isMobile ? 0.82 : 1.15;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerRow,
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              childAspectRatio: cellAspectRatio,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: gridCells,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayColumn(int day, List<dynamic> data, DateTime now) {
    final d = currentWeek.add(Duration(days: day));
    final rows = data.where((s) {
      final dt = tz.TZDateTime.from(
          DateTime.parse(s['startsAt'] as String), widget.zone);
      return dt.year == d.year && dt.month == d.month && dt.day == d.day;
    }).toList();
    final today =
        d.year == now.year && d.month == now.month && d.day == now.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: today ? sageGreen : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: today ? sageGreen : sageBorder.withValues(alpha: 0.6),
              width: today ? 1.5 : 1.0,
            ),
            boxShadow: today
                ? [
                    BoxShadow(
                      color: sageGreen.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            DateFormat('EEE  d').format(d),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: today ? Colors.white : muted,
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
        for (final s in rows)
          _buildSessionCard(Map<String, dynamic>.from(s), day),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> s, int color) {
    final borderColor = chakra[color];
    final spotsLeft = (s['spotsLeft'] ?? s['capacity'] ?? 0) as int;
    final capacity = (s['capacity'] ?? 0) as int;
    final isFull = spotsLeft <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.schedule, size: 14, color: borderColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${widget.onFormatDate(s['startsAt'], 'HH:mm')} – ${widget.onFormatDate(s['endsAt'], 'HH:mm')}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ink.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (!widget.member && s['status'] != null) ...[
                const SizedBox(height: 5),
                StatusBadge(s['status'] as String),
              ],
              const SizedBox(height: 8),

              // Title (standardized 2-line height so 1-line and 2-line titles yield identical card height)
              SizedBox(
                height: 38,
                child: Text(
                  s['title'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: ink,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),

              // Instructor & Level
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline, size: 13, color: muted),
                      const SizedBox(width: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          s['instructor']?['name']?.toString() ?? 'Studio Session',
                          style: const TextStyle(fontSize: 12, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: sageLight,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      s['level'] as String? ?? 'All levels',
                      style: const TextStyle(fontSize: 10, color: sageGreen, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Spots & Price Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFull ? Icons.group_off_outlined : Icons.group_outlined,
                          size: 13,
                          color: isFull ? Colors.red : muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFull ? 'Full' : '$spotsLeft/$capacity',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isFull ? Colors.red : muted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _money(s['price']),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: plum,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Action Buttons
              if (widget.member)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: spotsLeft > 0 &&
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
                    child: Text(
                      isFull ? 'Session Full' : 'Book Session ↗',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),

              if (widget.teacher && s['status'] == 'PENDING_INSTRUCTOR') ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: widget.busy
                          ? null
                          : () => widget.onAction(
                                'sessions/${s['id']}/accept',
                                success: 'Class accepted',
                              ),
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text('Accept', style: TextStyle(fontSize: 11)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: Colors.red,
                      ),
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
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('Decline', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],

              if ((widget.admin || widget.teacher) &&
                  s['status'] == 'SCHEDULED' &&
                  DateTime.parse(s['endsAt'] as String).isBefore(DateTime.now())) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => widget.onAction(
                              'sessions/${s['id']}/complete',
                              success: 'Class completed',
                            ),
                    icon: const Icon(Icons.check_circle_outline, size: 15, color: sageGreen),
                    label: const Text('Mark taught', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],

              if (widget.admin && s['status'] != 'COMPLETED') ...[
                const SizedBox(height: 6),
                const Divider(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
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
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Edit', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: Colors.orange.shade800,
                      ),
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
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text('Cancel', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: Colors.red,
                      ),
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
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('Delete', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
