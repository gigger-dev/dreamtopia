import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:dreamtopia/api.dart';
import 'package:dreamtopia/theme.dart';
import 'package:dreamtopia/screens/packages/packages_view.dart';
import 'package:dreamtopia/screens/bookings/bookings_view.dart';
import 'package:dreamtopia/screens/instructors/instructors_view.dart';
import 'package:dreamtopia/screens/instructors/availability_view.dart';
import 'package:dreamtopia/screens/members/members_view.dart';
import 'package:dreamtopia/screens/promotions/promotions_view.dart';
import 'package:dreamtopia/screens/requests/requests_view.dart';
import 'package:dreamtopia/screens/notifications/notifications_view.dart';
import 'package:dreamtopia/screens/practice/practice_view.dart';

class StubApi extends Api {
  final List<String> calls = [];
  @override
  Future<dynamic> call(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    calls.add('$method:$path');
    return <dynamic>[];
  }
}

void main() {
  setUp(tzdata.initializeTimeZones);

  testWidgets('PackagesView renders products and triggers purchase', (tester) async {
    final api = StubApi();
    bool purchaseTriggered = false;

    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: PackagesView(
          api: api,
          admin: false,
          member: true,
          busy: false,
          packageProducts: [
            {
              'id': 'pack-1',
              'name': '10-Class Flow Pack',
              'credits': 10,
              'price': 300000,
              'validityDays': 60,
              'description': 'Valid for all pole classes.'
            }
          ],
          packages: [
            {
              'id': 'pkg-inst',
              'status': 'ACTIVE',
              'creditsRemaining': 8,
              'creditsTotal': 10,
              'pricePaid': 300000,
              'packageProduct': {'name': '10-Class Flow Pack'}
            }
          ],
          currency: 'MMK',
          timezone: 'Asia/Yangon',
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
          onPurchasePackage: (_) async {
            purchaseTriggered = true;
          },
          onViewProof: (_) async {},
          onFormatDate: (iso, [String? pat]) => '2026-10-10',
        ),
      ),
    ));

    expect(find.text('10-Class Flow Pack'), findsNWidgets(2));
    expect(find.text('Buy Package'), findsOneWidget);
    await tester.tap(find.text('Buy Package'));
    await tester.pump();
    expect(purchaseTriggered, isTrue);
  });

  testWidgets('BookingsView renders booking chips and details', (tester) async {
    final api = StubApi();
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: BookingsView(
          api: api,
          admin: true,
          teacher: false,
          member: false,
          busy: false,
          bookings: [
            {
              'id': 'b-1',
              'status': 'CONFIRMED',
              'attendance': 'PRESENT',
              'paymentMethod': 'CREDITS',
              'amount': 35000,
              'member': {'name': 'Alice'},
              'session': {
                'title': 'Evening Spin Flow',
                'startsAt': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
              }
            }
          ],
          sessions: const [],
          currency: 'MMK',
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
          onViewProof: (_) async {},
          onFormatDate: (iso, [String? pat]) => 'Today, 18:00',
        ),
      ),
    ));

    expect(find.text('Evening Spin Flow'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('All bookings'), findsOneWidget);
    expect(find.text('1 class credit'), findsOneWidget);
  });

  testWidgets('InstructorsView and AvailabilityView render properly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: InstructorsView(
          busy: false,
          instructors: [
            {
              'id': 'inst-1',
              'name': 'Elena Rostova',
              'specialty': 'Exotic Flow & Low Flow',
              'email': 'elena@studio.test',
              'classesTaught': 14,
              'autoAccept': true,
              'userId': 'user-1'
            }
          ],
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
        ),
      ),
    ));

    expect(find.text('Elena Rostova'), findsOneWidget);
    expect(find.text('Exotic Flow & Low Flow'), findsOneWidget);
    expect(find.text('Account linked'), findsOneWidget);

    // Test Availability
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: AvailabilityView(
          me: {
            'instructor': {'autoAccept': true}
          },
          busy: false,
          blocks: [
            {
              'id': 'blk-1',
              'reason': 'Physiotherapy appointment',
              'startsAt': '2026-10-10T10:00:00Z',
              'endsAt': '2026-10-10T12:00:00Z',
            }
          ],
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
          onFormatDate: (iso, [String? pat]) => '10 Oct',
        ),
      ),
    ));

    expect(find.text('Physiotherapy appointment'), findsOneWidget);
    expect(find.text('Automatically accept new classes'), findsOneWidget);
  });

  testWidgets('PromotionsView and RequestsView render accurately', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: PromotionsView(
          busy: false,
          promos: [
            {
              'id': 'pr-1',
              'code': 'AUTUMN20',
              'percent': 20,
              'active': true,
              'expiresAt': '2026-11-01T00:00:00Z',
            }
          ],
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
          onFormatDate: (iso, [String? pat]) => '1 Nov 2026',
        ),
      ),
    ));

    expect(find.text('AUTUMN20 · 20% off'), findsOneWidget);
    expect(find.text('New campaign'), findsOneWidget);

    // Test RequestsView
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: RequestsView(
          admin: true,
          member: false,
          requests: [
            {
              'id': 'req-1',
              'type': 'POLE_CLASS',
              'status': 'PENDING',
              'startsAt': '2026-10-14T08:00:00Z',
              'endsAt': '2026-10-14T09:00:00Z',
              'member': {'name': 'Sophia'},
              'note': 'Can we get an early morning pole spin class?',
            }
          ],
          onRequestTime: () {},
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
          onFormatDate: (iso, [String? pat]) => 'Wed 14 Oct',
        ),
      ),
    ));

    expect(find.text('Pole classes'), findsOneWidget);
    expect(find.text('Sophia'), findsOneWidget);
    expect(find.text('Can we get an early morning pole spin class?'), findsOneWidget);
    expect(find.text('Respond'), findsOneWidget);
  });

  testWidgets('PracticeView, MembersView and NotificationsView render correctly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: PracticeView(
          me: {'credits': 5},
          bookings: [
            {
              'attendance': 'PRESENT',
              'session': {'title': 'Heels Flow', 'startsAt': '2026-10-01T12:00:00Z'}
            }
          ],
          ledger: [
            {
              'delta': 10,
              'reason': 'Purchased 10-Class Flow Pack',
              'createdAt': '2026-10-01T10:00:00Z'
            }
          ],
          onFormatDate: (iso, [String? pat]) => '01 Oct 2026',
        ),
      ),
    ));

    expect(find.text('Classes remaining'), findsOneWidget);
    expect(find.text('Purchased 10-Class Flow Pack'), findsOneWidget);
    expect(find.text('+10'), findsOneWidget);

    // Test MembersView
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: MembersView(
          busy: false,
          members: [
            {
              'id': 'm-1',
              'name': 'Htet Aung',
              'email': 'htet@example.test',
              'credits': 6,
              '_count': {'bookings': 4}
            }
          ],
          onForm: (_, __, ___, {method = 'POST', note, submit = 'Save'}) async {},
        ),
      ),
    ));

    expect(find.text('Htet Aung'), findsOneWidget);
    expect(find.text('Add credits'), findsOneWidget);

    // Test NotificationsView
    await tester.pumpWidget(MaterialApp(
      theme: dreamTheme(),
      home: Scaffold(
        body: NotificationsView(
          notices: [
            {
              'id': 'n-1',
              'title': 'New Weekend Workshop',
              'body': 'Check out our new Aerial Hammock class this Saturday!',
              'readAt': null,
              'createdAt': '2026-10-05T09:00:00Z'
            }
          ],
          onAction: (_, {body, method = 'POST', success = 'Saved'}) async {},
          onFormatDate: (iso, [String? pat]) => '5 Oct 2026',
        ),
      ),
    ));

    expect(find.text('New Weekend Workshop'), findsOneWidget);
    expect(find.text('Check out our new Aerial Hammock class this Saturday!\n\n5 Oct 2026'), findsOneWidget);
  });
}
