import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onSignedIn;
  final String? initialError;
  const LoginScreen(
      {super.key,
      required this.api,
      required this.onSignedIn,
      this.initialError});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    error = widget.initialError;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.authenticate(email.text, password.text,
          name: register ? name.text : null);
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Form(
                              key: form,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Icon(Icons.auto_awesome_outlined,
                                        color: plum, size: 38),
                                    const SizedBox(height: 14),
                                    Text('Dreamtopia',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.cinzel(
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                            color: plum)),
                                    const SizedBox(height: 8),
                                    Text('Yoga & Movement Studio',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.lato(
                                            fontSize: 11,
                                            letterSpacing: 1.6,
                                            fontWeight: FontWeight.w600,
                                            color: muted)),
                                    const SizedBox(height: 24),
                                    const ChakraLine(),
                                    const SizedBox(height: 28),
                                    Text(
                                        register
                                            ? 'Begin your practice.'
                                            : 'Welcome to your studio.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 24),
                                    if (register) ...[
                                      TextFormField(
                                          controller: name,
                                          decoration: const InputDecoration(
                                              labelText: 'Your name'),
                                          validator: (v) =>
                                              (v?.trim().length ?? 0) < 2
                                                  ? 'Enter your name'
                                                  : null),
                                      const SizedBox(height: 16)
                                    ],
                                    TextFormField(
                                        controller: email,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.email
                                        ],
                                        decoration: const InputDecoration(
                                            labelText: 'Email'),
                                        validator: (v) => v != null &&
                                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                                    .hasMatch(v.trim())
                                            ? null
                                            : 'Enter a valid email'),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: password,
                                        obscureText: true,
                                        autofillHints: [
                                          register
                                              ? AutofillHints.newPassword
                                              : AutofillHints.password
                                        ],
                                        decoration: const InputDecoration(
                                            labelText: 'Password',
                                            helperText: '8–72 characters'),
                                        validator: (v) =>
                                            (v?.length ?? 0) < 8 ||
                                                    (v?.length ?? 0) > 72
                                                ? 'Use 8–72 characters'
                                                : null,
                                        onFieldSubmitted: (_) {
                                          if (!busy) submit();
                                        }),
                                    const SizedBox(height: 20),
                                    if (error != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 16),
                                          child: Text(error!,
                                              style: const TextStyle(
                                                  color: Colors.red))),
                                    FilledButton(
                                        onPressed: busy ? null : submit,
                                        child: Text(busy
                                            ? 'Please wait…'
                                            : register
                                                ? 'Create account'
                                                : 'Sign in')),
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => setState(() {
                                                  register = !register;
                                                  error = null;
                                                }),
                                        child: Text(register
                                            ? 'Already a member? Sign in'
                                            : 'New here? Create your account')),
                                  ]))))))));
}
