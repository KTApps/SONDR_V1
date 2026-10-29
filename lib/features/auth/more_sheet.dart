import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/debug_tools.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/blur_sheet.dart';
import '../../shared/legal.dart';
import '../debug/debug_panel.dart';
import 'delete_account.dart';
import 'sign_out_action.dart';

/// What the More sheet offers.
///
/// The three pages first — the App Store wants them reachable from inside
/// the app, and they are the ones most likely to be wanted. Then, under a
/// rule, the two that act on the account itself. Debug is QA-only and sits
/// last, just above Cancel, where it cannot be mistaken for either group.
enum MoreChoice {
  support,
  privacy,
  terms,
  signOut,
  deleteAccount,
  debug;

  String get label => switch (this) {
    MoreChoice.support => 'Support',
    MoreChoice.privacy => 'Privacy',
    MoreChoice.terms => 'Terms',
    MoreChoice.signOut => 'Sign out',
    MoreChoice.deleteAccount => 'Delete account',
    MoreChoice.debug => 'Debug',
  };

  String? get url => switch (this) {
    MoreChoice.support => kSupportUrl,
    MoreChoice.privacy => kPrivacyUrl,
    MoreChoice.terms => kTermsUrl,
    _ => null,
  };
}

/// The three pages, which a guest sees as well.
const List<MoreChoice> kMorePages = [
  MoreChoice.support,
  MoreChoice.privacy,
  MoreChoice.terms,
];

/// What the sheet offers, by who is asking.
///
/// A guest has no account to sign out of and nothing to delete, so they are
/// offered the pages alone. Debug is for the listed test account in a
/// DEBUG_TOOLS build and nobody else — see [debugToolsProvider].
List<MoreChoice> moreChoicesFor({required bool signedIn, bool debug = false}) => [
  ...kMorePages,
  if (signedIn) MoreChoice.signOut,
  if (signedIn) MoreChoice.deleteAccount,
  if (debug) MoreChoice.debug,
];

/// The one word in the account block, and everything behind it.
///
/// Returns the line to show under it, or null when there is nothing to say
/// — which is every case but a sign-out that could not save and a deletion
/// that stopped partway.
Future<String?> showMoreSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool signedIn,
}) async {
  String? said;
  final debug = ref.read(debugToolsProvider);

  await showBlurSheet(context, (handle) {
    Future<void> choose(MoreChoice chosen) async {
      final url = chosen.url;
      if (url != null) {
        handle.close();
        await ref.read(legalPagesProvider).open(url);
        return;
      }
      switch (chosen) {
        case MoreChoice.signOut:
          // Inside the same blur: a running session's prompt cross-fades
          // in place rather than lifting the blur and bringing it back.
          final result = await runSignOut(context, ref, within: handle);
          said = result.error;
          // Whatever happened, the flow is over. close() is a no-op on a
          // sheet that has already gone — which it has, if the person
          // cancelled or the flow closed it on its way to doing work.
          handle.close();
        case MoreChoice.deleteAccount:
          final outcome = await deleteAccount(context, ref, within: handle);
          said = outcome == DeleteAccountOutcome.failed
              ? (lastDeleteError ?? kDeleteAccountFailed)
              : null;
          handle.close();
        case MoreChoice.debug:
          handle.close();
          if (context.mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugPanel()),
            );
          }
        case MoreChoice.support:
        case MoreChoice.privacy:
        case MoreChoice.terms:
          handle.close();
      }
    }

    return BlurView(
      // The build, at the very bottom, for anyone writing to us about it.
      footer: const AppVersionLine(),
      items: [
        for (final choice in moreChoicesFor(signedIn: signedIn, debug: debug))
          BlurItem(
            label: choice.label,
            // The two that act on the account, and Debug with them: the
            // not-done grey, against the three pages' white.
            quiet: choice == MoreChoice.signOut ||
                choice == MoreChoice.deleteAccount ||
                choice == MoreChoice.debug,
            onTap: () => choose(choice),
          ),
      ],
    );
  });

  return said;
}

/// "sondr 1.0 (98)": 12, quiet, not a tap target. Nothing until the
/// bundle has answered, which it has by the time anyone reads it.
class AppVersionLine extends ConsumerWidget {
  const AppVersionLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = ref.watch(appVersionLineProvider).value;
    if (line == null) return const SizedBox.shrink();
    final tokens = GreyscaleTokens.of(context);
    return Text(
      line,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 12 * figmaScale(context),
        color: tokens.textTertiary,
      ),
    );
  }
}
