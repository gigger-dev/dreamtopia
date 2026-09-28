import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:dreamtopia/api.dart';
import 'package:dreamtopia/theme.dart';
import 'package:dreamtopia/screens/login.dart';
import 'package:dreamtopia/screens/booking.dart';
import 'package:dreamtopia/screens/studio.dart';

class FakeApi extends Api {
  final String role;
  FakeApi({this.role = 'MEMBER'});
  final List<Map<String, dynamic>> writes = [];
  @override
  Future<dynamic> call(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    if (method != 'GET') {
      writes.add({'path': path, 'body': body});
      return <String, dynamic>{};
    }
    if (path == 'me') {
      return {
        'id': 'member-id',
        'name': 'Maya',
        'role': role,
        'classesTaught': 5,
        'instructor': {'autoAccept': false},
        'email': 'maya@example.test',
        'credits': 4
      };
    }
    if (path == 'settings') {
      return {
        'timezone': 'Asia/Yangon',
        'currency': 'MMK',
        'bankInstructions': 'Test bank'
      };
    }
    if (path.startsWith('sessions?')) {
      return [
        {
          'id': 'class-id',
          'title': 'Pole foundations',
          'type': 'POLE_CLASS',
          'price': 35000,
          'capacity': 6,
          'spotsLeft': 4,
          'level': 'All levels',
          'status': 'SCHEDULED',
          'instructor': {'name': 'Studio teacher'},
          'startsAt': DateTime.now().toUtc().toIso8601String(),
          'endsAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String()
        }
      ];
    }
    return <dynamic>[];
  }
}

void main() {
  setUp(tzdata.initializeTimeZones);
  testWidgets(
      'sign-in validates missing credentials and registration asks for a name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: dreamTheme(),
        home: LoginScreen(api: FakeApi(), onSignedIn: () {})));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use 8–72 characters'), findsOneWidget);
    await tester.ensureVisible(find.text('New here? Create your account'));
    await tester.tap(find.text('New here? Create your account'));
    await tester.pump();
    expect(find.text('Your name'), findsOneWidget);
  });
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('member calendar renders without layout errors at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: dreamTheme(),
          home: StudioScreen(api: FakeApi(), onSignOut: () async {})));
      await tester.pumpAndSettle();
      expect(find.text('Make time for you.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final role in ['ADMIN', 'INSTRUCTOR']) {
    testWidgets('$role screens render and expose their own actions',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: dreamTheme(),
          home:
              StudioScreen(api: FakeApi(role: role), onSignOut: () async {})));
      await tester.pumpAndSettle();
      expect(
          find.text(
              role == 'ADMIN' ? 'Create session' : 'Your teaching calendar.'),
          findsOneWidget);
      if (role == 'ADMIN') {
        await tester.tap(find.text('Promotions'));
        await tester.pumpAndSettle();
        expect(find.text('Create promotion'), findsOneWidget);
      } else {
        await tester.tap(find.text('Availability'));
        await tester.pumpAndSettle();
        expect(find.text('Automatically accept new classes'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('bank-transfer booking cannot submit without proof',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(
        theme: dreamTheme(),
        home: Scaffold(
            body: BookingDialog(
                api: api,
                session: {
                  'id': 'class-id',
                  'title': 'Pole foundations',
                  'type': 'POLE_CLASS',
                  'price': 35000,
                  'description': 'Start here'
                },
                settings: {'currency': 'MMK', 'bankInstructions': 'Test bank'},
                credits: 0))));
    await tester.tap(find.text('Request booking'));
    await tester.pump();
    expect(find.text('Upload your payment screenshot first.'), findsOneWidget);
    expect(api.writes, isEmpty);
  });
}
