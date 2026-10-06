import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../core/utils/duration_format.dart';
import '../profile/profile_providers.dart';
import 'auth_screen.dart';

/// Lifetime tracked time at which a guest is nudged to create an account.
const int kGuestNudgeSeconds = 3600;

/// A bottom sheet nudging a guest to create an account — "Create account"
/// opens sign-up (which links the guest in place, so nothing is lost), "Not
/// now" dismisses.
Future<void> showCreateAccountPrompt(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final tokens = GreyscaleTokens.of(context);
  final theme = Theme.of(context);
  final navigator = Navigator.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: kSpacingBase * figmaScale(context) / 2),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
            SizedBox(height: kSpacingBase * figmaScale(context)),
            Center(
              child: SondrAction(
                label: 'Create account',
                onPressed: () {
                  Navigator.of(sheet).pop();
                  navigator.push(MaterialPageRoute(
                    builder: (_) => const AuthScreen(startInSignUp: true),
                  ));
                },
              ),
            ),
            Center(
              child: SondrAction(
                label: 'Not now',
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Social features (handle, friends, posting) need a permanent account. Returns
/// true when the user has one; for a guest shows the prompt and returns false.
bool requireAccount(
  BuildContext context,
  WidgetRef ref, {
  required String message,
}) {
  if (!ref.read(isGuestProvider)) return true;
  showCreateAccountPrompt(
    context,
    title: 'Create an account',
    message: message,
  );
  return false;
}

/// Before a guest signs into an *existing* account — which switches to that
/// account and abandons the guest's data — confirm if they've tracked anything.
/// Returns true to go ahead.
Future<bool> confirmReplaceGuestData(BuildContext context, WidgetRef ref) async {
  if (!ref.read(isGuestProvider)) return true;
  final tracked = ref.read(lifetimeDurationProvider);
  if (tracked.inSeconds <= 0) return true;

  final tokens = GreyscaleTokens.of(context);
  final theme = Theme.of(context);
  final scale = figmaScale(context);

  // A Sondr sheet, not Material's AlertDialog — same surface, radius and
  // spacing as every other prompt in the app.
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: tokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24 * scale)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: EdgeInsets.all(kSpacingSection * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Replace guest progress?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            Text(
              'You have ${DurationFormat.hm(tracked)} tracked as a guest. '
              'Signing in replaces it, and this progress is lost.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SondrAction(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(sheet).pop(false),
                ),
                SizedBox(width: kSpacingBase * scale),
                SondrAction(
                  label: 'Sign in anyway',
                  onPressed: () => Navigator.of(sheet).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
