import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_loading.dart';
import '../../core/utils/figma_scale.dart';
import 'apple_sign_in_button.dart';
import 'auth_repository.dart';
import 'auth_screen.dart';
import 'handle_screen.dart';
import 'legal_lines.dart';
import 'profile_repository.dart';
import 'more_sheet.dart';

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

    // No padding and no scroll view of its own: this is the last SECTION of
    // the profile page, which supplies the gutter and does the scrolling. The
    // guest view used to carry a SingleChildScrollView because the page was a
    // fixed Column that it did not fit inside; nested in a scrolling page that
    // would be a viewport with no bounded height.
    return isGuest ? _GuestView() : _SignedInView(email: user.email ?? '');
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
        // What creating an account agrees to. LAST, under both buttons and
        // the Apple one, because adding it had to move nothing: every
        // element above it is exactly where it was.
        SizedBox(height: kSpacingBase * scale),
        const TermsNotice(),
        // A guest's More: the three pages and nothing else. Below the
        // sentence, so every row above it is exactly where it was.
        const Center(child: _MoreWord(signedIn: false)),
        // Breathing room above the tab bar — the button sat jammed against it.
        SizedBox(height: kSpacingBase * scale),
      ],
    );
  }
}

/// The account block's one action.
///
/// Stateful for one reason: the sheet behind it can come back with
/// something to say — a sign-out that could not save the session, a
/// deletion that stopped partway — and that line belongs under the word
/// that opened it, not on a floating surface.
class _MoreWord extends ConsumerStatefulWidget {
  const _MoreWord({required this.signedIn});

  final bool signedIn;

  @override
  ConsumerState<_MoreWord> createState() => _MoreWordState();
}

class _MoreWordState extends ConsumerState<_MoreWord> {
  String? _error;
  bool _busy = false;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final said = await showMoreSheet(
      context,
      ref,
      signedIn: widget.signedIn,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = said;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SondrAction(
          label: 'More',
          supporting: true,
          onPressed: _busy ? null : _open,
        ),
        if (error != null) ...[
          SizedBox(height: kSpacingPair * scale),
          SondrError(error, textAlign: TextAlign.center),
        ],
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

        // The handle is shown in the hero at the top of the page now, so it
        // is not repeated here. What stays is the way to SET one when there
        // isn't yet a handle for the hero to show — without this there would
        // be no entrance to the handle screen at all.
        profile.when(
          loading: () => const SondrLoading(),
          error: (_, _) => const SizedBox.shrink(),
          data: (p) {
            if (p != null && p.username.isNotEmpty) {
              return const SizedBox.shrink();
            }
            return Center(
              child: SondrAction(
                label: 'Set your handle',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HandleScreen()),
                ),
              ),
            );
          },
        ),
        // No declared gap: SondrAction's own 12 of padding IS the gap. Against
        // the plain "@handle" row that renders 12 (base); against the padded
        // "Set your handle" action it renders 24 (the stacked-action floor).
        // Both on-tier, both the tightest the 44 tap target allows, and the
        // footer no longer jumps between the two handle states.
        //
        // ONE word now, where Sign out used to be and in its style. Sign
        // out, the three pages and Debug all moved behind it: five words in
        // a row needed 372 of the 345 this block has at the default text
        // size, and a sixth was about to be asked for.
        const Center(child: _MoreWord(signedIn: true)),
        // The footer's own bottom margin, clearing the tab bar. The page no
        // longer adds padding here — this is the one thing setting it. Base
        // tier rather than a section break: the tab bar's own 40 already
        // separates this from the edge, and the page has no room to spare.
        SizedBox(height: kSpacingBase * scale),
      ],
    );
  }
}


