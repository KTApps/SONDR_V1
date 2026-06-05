import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import 'auth_repository.dart';
import 'handle_screen.dart';
import 'profile_repository.dart';

/// "Continue with Apple" — one button covering both new and returning users.
/// Drops in beneath the email form on the auth screen and on the guest view of
/// the account screen.
///
/// After the auth mutation it routes **deterministically** with a one-shot
/// profile read rather than awaiting the stream-backed `currentProfileProvider`
/// (which the mutation would perturb, deadlocking the future): no handle yet →
/// [HandleScreen], otherwise back to Home.
class AppleSignInButton extends ConsumerStatefulWidget {
  const AppleSignInButton({super.key, this.enabled = true, this.onError});

  /// Disabled while a sibling action (e.g. the email form) is busy.
  final bool enabled;

  /// If provided, errors are reported here for inline display; otherwise they
  /// surface as a SnackBar. User cancellation is always silent.
  final void Function(String message)? onError;

  @override
  ConsumerState<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends ConsumerState<AppleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final result = await auth.signInWithApple();
      if (!mounted) return;

      // Deterministic routing — one-shot read, never the stream-backed future.
      final uid = ref.read(currentUidProvider);
      final repo = ref.read(profileRepositoryProvider);
      final profile =
          (uid != null && repo != null) ? await repo.fetch(uid) : null;
      if (!mounted) return;

      final needsHandle = profile == null || profile.username.isEmpty;
      if (needsHandle) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => HandleScreen(
            suggestedDisplayName: result.displayName,
          ),
        ));
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // The user backing out of the Apple sheet is not an error.
      if (e.code != AuthorizationErrorCode.canceled) {
        _report('Could not sign in with Apple. Please try again.');
      }
    } catch (_) {
      _report('Could not sign in with Apple. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(String message) {
    if (!mounted) return;
    if (widget.onError != null) {
      widget.onError!(message);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final enabled = widget.enabled && !_busy;

    return OutlinedButton.icon(
      onPressed: enabled ? _signIn : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.ringTrack),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: theme.textTheme.labelLarge,
      ),
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.apple, color: tokens.textPrimary),
      label: const Text('Continue with Apple'),
    );
  }
}
