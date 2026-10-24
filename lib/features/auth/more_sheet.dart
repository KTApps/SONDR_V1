import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
import '../../shared/legal.dart';
import '../../shared/sondr_prompt.dart';
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
/// offered the pages alone. Debug is const-false in release builds, so that
/// branch — and DebugPanel with it — tree-shakes out entirely.
List<MoreChoice> moreChoicesFor({required bool signedIn}) => [
  ...kMorePages,
  if (signedIn) MoreChoice.signOut,
  if (signedIn) MoreChoice.deleteAccount,
  if (kDebugTools) MoreChoice.debug,
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
  final choices = moreChoicesFor(signedIn: signedIn);
  final chosen = await showSondrChoice<MoreChoice>(
    context,
    choices: [
      for (final choice in choices) (label: choice.label, value: choice),
    ],
    // The two that act on the account, and Debug with them: the supporting
    // tone at full weight, against the three pages' white.
    quiet: {MoreChoice.signOut, MoreChoice.deleteAccount, MoreChoice.debug},
  );
  if (chosen == null || !context.mounted) return null;

  final url = chosen.url;
  if (url != null) {
    await ref.read(legalPagesProvider).open(url);
    return null;
  }

  switch (chosen) {
    case MoreChoice.signOut:
      final result = await runSignOut(context, ref);
      return result.error;
    case MoreChoice.deleteAccount:
      final outcome = await deleteAccount(context, ref);
      if (outcome != DeleteAccountOutcome.failed) return null;
      // The line the flow composed: the step and the code in a DEBUG_TOOLS
      // build, "That password isn't right." in every build, and the plain
      // sentence otherwise.
      return lastDeleteError ?? kDeleteAccountFailed;
    case MoreChoice.debug:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DebugPanel()),
      );
      return null;
    case MoreChoice.support:
    case MoreChoice.privacy:
    case MoreChoice.terms:
      return null;
  }
}
