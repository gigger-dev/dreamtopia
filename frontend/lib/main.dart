import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'api.dart';
import 'theme.dart';
import 'screens/login.dart';
import 'screens/studio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  // Restore saved token from FlutterSecureStorage before starting the UI
  final api = Api();
  await api.restore();

  runApp(const DreamtopiaApp());
}

class DreamtopiaApp extends StatefulWidget {
  const DreamtopiaApp({super.key});
  @override
  State<DreamtopiaApp> createState() => _DreamtopiaAppState();
}

class _DreamtopiaAppState extends State<DreamtopiaApp> {
  final api = Api();
  bool ready = false;
  String? error;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      await api.restore();
    } catch (_) {
      error =
          'Secure sign-in storage is unavailable. Sign in again to continue.';
    }
    if (mounted) setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Dreamtopia Studio',
      debugShowCheckedModeBanner: false,
      theme: dreamTheme(),
      home: !ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : api.token == null
              ? 
              LoginScreen(
                  api: api,
                  initialError: error,
                  onSignedIn: () => setState(() {}))
              : StudioScreen(
                  api: api,
                  onSignOut: () async {
                    await api.signOut();
                    if (mounted) setState(() {});
                  }));
}
