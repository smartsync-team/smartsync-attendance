import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty || (_signUp && _name.text.trim().isEmpty)) {
      toast(context, 'Fill in all fields.');
      return;
    }
    if (_signUp && AppConfig.allowedEmailDomain.isNotEmpty &&
        !email.toLowerCase().endsWith('@${AppConfig.allowedEmailDomain}')) {
      toast(context, 'Use your @${AppConfig.allowedEmailDomain} email.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signUp) {
        final res = await Api.db.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': _name.text.trim()},
        );
        if (res.session == null && mounted) {
          toast(context, 'Account created. Check your email to confirm it, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await Api.db.auth.signInWithPassword(email: email, password: password);
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 48, 22, 24),
          children: [
            Icon(Icons.fingerprint, size: 60, color: c.brand),
            const SizedBox(height: 12),
            const Text('Attendance', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Muted(_signUp
                ? 'Create your account. Students register for courses after signing in.'
                : 'Sign in to mark, view and export attendance.'),
            const SizedBox(height: 22),
            if (_signUp) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'University email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_signUp ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
              child: Text(_signUp ? 'I already have an account' : 'New here? Create an account'),
            ),
            const SizedBox(height: 10),
            const Muted('New accounts are students. An admin can upgrade lecturer accounts.',
                align: TextAlign.center, size: 12),
          ],
        ),
      ),
    );
  }
}
