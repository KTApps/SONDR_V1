import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/backend.dart';
import '../../core/debug_flags.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../shared/sondr_error.dart';
import '../../core/utils/figma_scale.dart';
import 'auth_repository.dart';
import 'guest_prompts.dart';
import 'handle_screen.dart';
import 'profile_repository.dart';

/// Sign-in itself failed: no account, nothing changed.
const String kAppleSignInFailed =
    'Could not sign in with Apple. Please try again.';

/// Sign-in SUCCEEDED and something after it did not. A different sentence,
/// because the two used to share one — a failed profile read reported itself
/// as an Apple failure, which sent the first real-device diagnosis after the
/// entitlements, the bundle id and the Firebase provider, all of which were
/// fine.
const String kAppleProfileFailed =
    'Signed in, but couldn’t load your profile. Please try again.';

/// The user-facing text, with the provider's own code appended for us.
///
/// [withCode] defaults to [kDebugTools], so a normal release build shows the
/// sentence and nothing else. Exposed because a test cannot change a const.
@visibleForTesting
String appleErrorText(
  String message,
  String? code, {
  bool withCode = kDebugTools,
}) => (withCode && code != null && code.isNotEmpty)
    ? '$message ($code)'
    : message;

/// The provider's own code, where the error carries one — prefixed with the
/// step, when the error knows which step it came from.
String? _codeOf(Object error) {
  if (error is AppleStepException) {
    return '${error.stepName}: ${error.code ?? error.cause.runtimeType}';
  }
  if (error is SignInWithAppleAuthorizationException) return '${error.code}';
  if (error is FirebaseAuthException) return error.code;
  if (error is FirebaseException) return error.code;
  return null;
}

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

  /// If provided, errors are reported here so the host screen can place them;
  /// otherwise the button shows them beneath itself. User cancellation is
  /// always silent.
  final void Function(String message)? onError;

  @override
  ConsumerState<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends ConsumerState<AppleSignInButton> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      // TWO phases, and two different failures. Authenticating is Apple's and
      // Firebase's; everything after it is ours, and reporting ours as theirs
      // is how a Firestore read came to say "could not sign in with Apple".
      final AppleSignInResult result;
      try {
        final auth = ref.read(authRepositoryProvider);
        result = await auth.signInWithApple(
          confirmReplaceGuest: () => confirmReplaceGuestData(context, ref),
        );
      } on SignInWithAppleAuthorizationException catch (e) {
        // The user backing out of the Apple sheet is not an error.
        if (e.code != AuthorizationErrorCode.canceled) {
          debugPrint('SONDR apple error: ${e.code} :: ${e.message}');
          _report(kAppleSignInFailed, code: '${e.code}');
        }
        return;
      } catch (e, stack) {
        debugPrint(
          'SONDR apple error: ${e.runtimeType} :: ${_codeOf(e)} :: $e',
        );
        debugPrint('$stack');
        _report(kAppleSignInFailed, code: _describe(e));
        return;
      }

      if (!mounted || result.cancelled) return;

      // Signed in. From here a failure is ours to name.
      try {
        // Deterministic routing — one-shot read, never the stream-backed
        // future.
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
              afterSignUp: true,
            ),
          ));
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e, stack) {
        debugPrint(
          'SONDR apple post-auth error: ${e.runtimeType} :: ${_codeOf(e)} '
          ':: $e',
        );
        debugPrint('$stack');
        _report(kAppleProfileFailed, code: _describe(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Enough to act on: the step and the code where they are known, the type
  /// where they are not.
  String _describe(Object error) {
    final code = _codeOf(error);
    // A step-tagged error already reads "link: <code>" — the wrapper's own
    // type name would say nothing on top of that.
    if (error is AppleStepException) return code!;
    return code == null ? '${error.runtimeType}' : '${error.runtimeType} $code';
  }

  void _report(String message, {String? code}) {
    if (!mounted) return;
    final message_ = appleErrorText(message, code);
    if (widget.onError != null) {
      widget.onError!(message_);
    } else {
      // No host to report to (the guest landing) — the button carries its
      // own failure directly beneath itself.
      setState(() => _error = message_);
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
    final capsule = Opacity(
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

    if (_error == null) return capsule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        capsule,
        SizedBox(height: kSpacingBase * scale),
        SondrError(_error!, textAlign: TextAlign.center),
      ],
    );
  }
}
