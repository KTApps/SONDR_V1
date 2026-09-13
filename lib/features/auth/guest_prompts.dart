import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
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
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                navigator.push(MaterialPageRoute(
                  builder: (_) => const AuthScreen(startInSignUp: true),
                ));
              },
              style: FilledButton.styleFrom(
                backgroundColor: tokens.ringFillOuter,
                foregroundColor: tokens.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: theme.textTheme.labelLarge,
              ),
              child: const Text('Create account'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(sheet).pop(),
              style: TextButton.styleFrom(foregroundColor: tokens.textSecondary),
              child: const Text('Not now'),
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
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: tokens.surface,
      title: const Text('Replace guest progress?'),
      content: Text(
        'You have ${DurationFormat.hm(tracked)} tracked as a guest. Signing in '
        'will replace it with your existing account, and this guest progress '
        'will be lost.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('Sign in anyway'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
