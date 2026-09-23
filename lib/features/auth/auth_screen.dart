import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_header.dart';
import 'apple_sign_in_button.dart';
import 'auth_repository.dart';
import 'guest_prompts.dart';
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
    if (!emailOk) return 'That email address looks invalid.';
    if (pw.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _submit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    // Signing into an existing account abandons the guest's data — confirm.
    if (!_signUp && !await confirmReplaceGuestData(context, ref)) return;
    if (!mounted) return;
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
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(String code) {
    switch (code) {
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'That email is already in use. Sign in instead.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Something went wrong. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Scaffold(
      body: SafeArea(
        // The keyboard needs room, so this screen scrolls — that is a
        // legitimate reason, unlike Profile's page scroll.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24 * scale,
            kSpacingBase * scale,
            24 * scale,
            kSpacingSection * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SondrHeader(title: _signUp ? 'Create account' : 'Sign in'),
              SizedBox(height: kSpacingBase * scale),
              SondrField(
                label: 'Email',
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: kSpacingBase * scale),
              SondrField(
                label: 'Password',
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                SizedBox(height: kSpacingBase * scale),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              // SondrAction carries 12 of its own padding (its tap target), so
              // the declared gap is the tier minus that — the gap you SEE is
              // what has to be on-tier, not the number in the source.
              SizedBox(height: kSpacingBase * scale),
              Center(
                child: _busy
                    ? SizedBox(
                        height: 20 * scale,
                        width: 20 * scale,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SondrAction(
                        label: _signUp ? 'Create account' : 'Sign in',
                        onPressed: _submit,
                      ),
              ),
              // Nothing between two stacked actions: their own paddings meet
              // at 24, which is the section unit already.
              Center(
                child: SondrAction(
                  label: _signUp
                      ? 'I already have an account'
                      : 'Create a new account',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signUp = !_signUp;
                            _error = null;
                          }),
                ),
              ),
              SizedBox(height: kSpacingBase * scale),
              AppleSignInButton(
                enabled: !_busy,
                onError: (message) => setState(() => _error = message),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
