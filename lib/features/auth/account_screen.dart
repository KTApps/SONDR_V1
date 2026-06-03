import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import 'auth_repository.dart';
import 'auth_screen.dart';
import 'handle_screen.dart';
import 'profile_repository.dart';

/// Account hub. For a guest it offers creating an account or signing in; for a
/// permanent account it shows the email, the handle (or a prompt to set one),
/// and sign-out. Temporary home for this — it moves into the Profile tab in
/// step 2.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on sign in/out/link.
    ref.watch(authUserProvider);
    final auth = ref.read(authRepositoryProvider);
    final user = auth.currentUser;
    final isGuest = user == null || user.isAnonymous;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Account'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: isGuest
              ? _GuestView()
              : _SignedInView(email: user.email ?? ''),
        ),
      ),
    );
  }
}

class _GuestView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Guest account', style: theme.textTheme.titleLarge),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Signed in', style: theme.textTheme.titleLarge),
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
                Text('Handle', style: theme.textTheme.bodyLarge),
                const Spacer(),
                Text('@${p.username}',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: tokens.textSecondary)),
              ],
            );
          },
        ),
        const Spacer(),
        TextButton(
          onPressed: () async {
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) Navigator.of(context).maybePop();
          },
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
