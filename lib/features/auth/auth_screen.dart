import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'auth_repository.dart';
import 'handle_screen.dart';

/// Email/password sign-up and sign-in. Sign-up links to a guest account in
/// place (preserving its data); on success a new account without a handle is
/// sent to [HandleScreen].
///
/// Sign in with Apple will be added beneath the form later as an alternate
/// action — the form and its flows don't need to change.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.startInSignUp});

  final bool startInSignUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _signUp = widget.startInSignUp;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    final pw = _password.text;
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!emailOk) return 'Enter a valid email address.';
    if (pw.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _submit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = ref.read(authRepositoryProvider);
    try {
      if (_signUp) {
        await auth.signUpWithEmail(_email.text, _password.text);
        if (!mounted) return;
        // A brand-new account never has a handle yet → straight to setup.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HandleScreen()),
        );
      } else {
        await auth.signInWithEmail(_email.text, _password.text);
        if (!mounted) return;
        // Land back on Home (the timer), dismissing the whole account flow.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e.code));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(String code) {
    switch (code) {
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'That email is already in use. Try signing in instead.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Could not complete that. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(_signUp ? 'Create account' : 'Sign in'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: tokens.textPrimary)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.ringFillOuter,
                  foregroundColor: tokens.background,
                  disabledBackgroundColor: tokens.ringTrack,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_signUp ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _signUp = !_signUp;
                          _error = null;
                        }),
                style: TextButton.styleFrom(foregroundColor: tokens.textSecondary),
                child: Text(_signUp
                    ? 'I already have an account'
                    : 'Create a new account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
