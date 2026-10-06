import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import 'auth_repository.dart';
import 'guest_prompts.dart';
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
      final result = await auth.signInWithApple(
        confirmReplaceGuest: () => confirmReplaceGuestData(context, ref),
      );
      if (!mounted || result.cancelled) return;

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
    final enabled = widget.enabled && !_busy;

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final height = 44 * scale;
    final fontSize = 15 * scale;

    // Sondr-toned, not Apple's black: a surface-tone capsule matching the
    // Sondr fields and the Friends row, so it reads as part of the app rather
    // than a black block dropped into it.
    //
    // Apple's OFFICIAL mark is kept — AppleLogoPainter from the
    // sign_in_with_apple package, never Material's Icons.apple, which is not
    // Apple's mark — along with the approved wording. Only the fill and the
    // metrics are ours. Reverting to the official black style is a one-line
    // change if App Review ever objects (see DESIGN-PUNCHLIST).
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _signIn : null,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16 * scale),
          ),
          child: Center(
            child: _busy
                // Text, not a spinner — the capsule, the logo rule and the
                // metrics are untouched; only what sits inside it changes.
                ? Text(
                    'Signing in…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Same proportions the official button uses.
                      Padding(
                        padding: EdgeInsets.only(bottom: (4 / 44) * height),
                        child: SizedBox(
                          width: fontSize * (25 / 31),
                          height: fontSize,
                          child: CustomPaint(
                            painter: AppleLogoPainter(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Text(
                        'Sign in with Apple',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
