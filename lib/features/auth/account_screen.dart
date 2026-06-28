import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import 'apple_sign_in_button.dart';
import 'auth_repository.dart';
import 'auth_screen.dart';
import 'handle_screen.dart';
import 'profile_repository.dart';

/// Account management — sign-in/out, the email, and the handle. For a guest it
/// offers creating an account or signing in; for a permanent account it shows
/// the email, the handle (or a prompt to set one), and sign-out.
///
/// As of step 2 this is **embedded in the Profile tab** rather than pushed as
/// its own screen, so it's just the body (no Scaffold/AppBar). The hosting
/// screen supplies a bounded height for the sign-out [Spacer].
class AccountBody extends ConsumerWidget {
  const AccountBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on sign in/out/link.
    ref.watch(authUserProvider);
    final auth = ref.read(authRepositoryProvider);
    final user = auth.currentUser;
    final isGuest = user == null || user.isAnonymous;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child:
          isGuest ? _GuestView() : _SignedInView(email: user.email ?? ''),
    );
  }
}

class _GuestView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Guest account',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Your tasks and habits are saved to this device as a guest. Create an '
          'account to keep them safe and to add friends later.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AuthScreen(startInSignUp: true),
          )),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.ringFillOuter,
            foregroundColor: tokens.background,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: theme.textTheme.labelLarge,
          ),
          child: const Text('Create account'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AuthScreen(startInSignUp: false),
          )),
          style: TextButton.styleFrom(foregroundColor: tokens.textPrimary),
          child: const Text('I already have an account'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: tokens.ringTrack)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textSecondary)),
            ),
            Expanded(child: Divider(color: tokens.ringTrack)),
          ],
        ),
        const SizedBox(height: 16),
        const AppleSignInButton(),
      ],
    );
  }
}

class _SignedInView extends ConsumerWidget {
  const _SignedInView({required this.email});
  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Signed in',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(email,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: tokens.textSecondary)),
        const SizedBox(height: 28),

        // Handle row — set it or show it.
        profile.when(
          loading: () => const _Loading(),
          error: (_, _) => const SizedBox.shrink(),
          data: (p) {
            if (p == null || p.username.isEmpty) {
              return OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HandleScreen(),
                )),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  side: BorderSide(color: tokens.ringTrack),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Set your handle'),
              );
            }
            return Row(
              children: [
                Text('Handle',
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
                const Spacer(),
                Text('@${p.username}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15, color: tokens.textSecondary)),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
        TextButton(
          // Sign-out starts a fresh guest session; AccountBody watches the auth
          // stream and rebuilds itself into the guest view — nothing to pop now
          // that this lives inside the Profile tab.
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          style: TextButton.styleFrom(foregroundColor: tokens.textSecondary),
          child: const Text('Sign out'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
}
