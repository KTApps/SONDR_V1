import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_loading.dart';
import '../../core/utils/figma_scale.dart';
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
      padding: EdgeInsets.symmetric(horizontal: 24 * figmaScale(context)),
      // The signed-in footer is short and sits in a fixed, non-scrolling page.
      // The guest footer is far taller — heading, two actions, a divider and
      // the Apple button — and genuinely does not fit beside the rest of
      // Profile, so it keeps a scroll view of its own until it is redesigned
      // (punchlist item 5, Auth). Scoping it here means the signed-in page has
      // no vertical scrollable at all.
      child: isGuest
          ? SingleChildScrollView(child: _GuestView())
          : _SignedInView(email: user.email ?? ''),
    );
  }
}

class _GuestView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Guest account',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 15 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(height: kSpacingPair * scale),
        // The app's only standing statement of the risk — every other carrier
        // (the first-hour nudge, the milestone prompt, the sign-in warning) is
        // a transient prompt. Kept deliberately short rather than cut.
        Text(
          'Your progress is lost if you delete the app.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13 * scale,
            color: tokens.textSecondary,
          ),
        ),
        SizedBox(height: kSpacingBase * scale),
        Center(
          child: SondrAction(
            label: 'Create account',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AuthScreen(startInSignUp: true),
            )),
          ),
        ),
        // Supporting on the LANDING only: creating an account is what this
        // screen is for, and signing in abandons the guest's data. Two
        // equally bright actions made the destructive one look as inviting
        // as the safe one. The submit action on the sign-in screen itself
        // stays white — it is the primary there.
        Center(
          child: SondrAction(
            label: 'I already have an account',
            supporting: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AuthScreen(startInSignUp: false),
            )),
          ),
        ),
        SizedBox(height: kSpacingBase * scale),
        const AppleSignInButton(),
        // Breathing room above the tab bar — the button sat jammed against it.
        SizedBox(height: kSpacingSection * scale),
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

    final scale = figmaScale(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signed in',
            style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 15 * scale, fontWeight: FontWeight.w700)),
        SizedBox(height: kSpacingPair * scale),
        Text(email,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: tokens.textSecondary)),
        SizedBox(height: kSpacingBase * scale),

        // Handle row — set it or show it.
        profile.when(
          loading: () => const SondrLoading(),
          error: (_, _) => const SizedBox.shrink(),
          data: (p) {
            if (p == null || p.username.isEmpty) {
              return Center(
                child: SondrAction(
                  label: 'Set your handle',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HandleScreen()),
                  ),
                ),
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
        // No declared gap: SondrAction's own 12 of padding IS the gap. Against
        // the plain "@handle" row that renders 12 (base); against the padded
        // "Set your handle" action it renders 24 (the stacked-action floor).
        // Both on-tier, both the tightest the 44 tap target allows, and the
        // footer no longer jumps between the two handle states.
        Center(
          child: SondrAction(
            // Sign-out starts a fresh guest session; AccountBody watches the
            // auth stream and rebuilds itself into the guest view — nothing to
            // pop now that this lives inside the Profile tab.
            label: 'Sign out',
            supporting: true,
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ),
        // The footer's own bottom margin, clearing the tab bar. The page no
        // longer adds padding here — this is the one thing setting it. Base
        // tier rather than a section break: the tab bar's own 40 already
        // separates this from the edge, and the page has no room to spare.
        SizedBox(height: kSpacingBase * scale),
      ],
    );
  }
}


