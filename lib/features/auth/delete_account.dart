import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/sondr_prompt.dart';
import '../friends/content_prune.dart';
import '../timer/home_notice.dart';
import '../timer/live_activity.dart';
import '../timer/session_store.dart';
import '../timer/timer_controller.dart';
import 'account_cascade.dart';
import 'auth_repository.dart';

/// What the question says. One sentence, naming everything that goes, and
/// the one fact that cannot be softened.
const String kDeleteAccountTitle = 'Delete your account?';
const String kDeleteAccountBody =
    'This permanently deletes your account, tracked time, photos, posts, '
    "comments and friends. It can't be undone.";
const String kDeleteAccountConfirm = 'Delete account';

/// Asked before anything is deleted, never after.
const String kPasswordPrompt = 'Enter your password to confirm';

/// Shown where the action was, and left there: a failure has something to
/// act on, so it stays until they do (see SondrError).
const String kDeleteAccountFailed =
    "Couldn't delete your account. Try again.";

/// Said once, on Home, by the fresh guest session that replaces them.
const String kAccountDeleted = 'Your account has been deleted.';

enum DeleteAccountOutcome {
  /// They changed their mind, or could not prove who they were. Nothing
  /// was deleted.
  cancelled,

  /// The account is gone and a fresh guest session has taken its place.
  deleted,

  /// It started and stopped. Whatever had already gone is gone, the
  /// account is still there, and running it again finishes the job.
  failed,
}

/// What a deletion has to clear off THIS device.
///
/// A seam: every one of these is a plugin with nothing on the other end of
/// it in a widget test, and what the test is about is that they are called
/// at all.
abstract interface class LocalCaches {
  Future<void> clear(Set<String> photoUrls);
}

class DeviceCaches implements LocalCaches {
  DeviceCaches({required this.session, required this.prunes});

  final SessionStore session;
  final PendingPrunes prunes;

  @override
  Future<void> clear(Set<String> photoUrls) async {
    // The App Group container: the running session the Live Activity reads,
    // and any prune this account never finished.
    await session.clear();
    for (final uid in await prunes.read()) {
      await prunes.remove(uid);
    }
    // The photo cache is keyed by URL, on disk and in memory. The URLs are
    // the account's own, so nothing anybody else can see is evicted.
    for (final url in photoUrls) {
      await CachedNetworkImage.evictFromCache(url);
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

final localCachesProvider = Provider<LocalCaches>(
  (ref) => DeviceCaches(
    session: ref.watch(sessionStoreProvider),
    prunes: PrefsPendingPrunes(),
  ),
);

/// Delete the signed-in account: ask, prove, then take it all down.
///
/// The order is the whole design.
///
/// 1. **Ask**, in the app's own confirm card, naming what goes.
/// 2. **Prove who is asking**, BEFORE anything is deleted — a password for
///    an email account, Apple's own sheet for an Apple one (which also
///    revokes the token Apple issued us, as 5.1.1(v) requires). Cancel or a
///    wrong password leaves everything exactly as it was.
/// 3. **Throw the running session away.** Not credited: the account it
///    would be credited to is about to stop existing. The Lock Screen card
///    goes with it.
/// 4. **The cascade**, as the account itself (see [AccountErasure]).
/// 5. **The Auth user, last.** Until that returns there is still an account
///    to retry as — which is why a failure anywhere above keeps it.
/// 6. **A fresh guest**, so the app always has a uid, and Home says the one
///    line that explains the empty screen.
///
/// Returns what happened so the caller can leave its own error line up.
Future<DeleteAccountOutcome> deleteAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final auth = ref.read(authRepositoryProvider);
  final erasure = ref.read(accountCascadeProvider);
  if (erasure == null) return DeleteAccountOutcome.failed;

  final yes = await showSondrConfirm(
    context,
    title: kDeleteAccountTitle,
    body: kDeleteAccountBody,
    confirmLabel: kDeleteAccountConfirm,
  );
  if (!yes || !context.mounted) return DeleteAccountOutcome.cancelled;

  // Step 2. Nothing below this line has run yet.
  final proved = await _prove(context, auth);
  switch (proved) {
    case _Proof.cancelled:
      return DeleteAccountOutcome.cancelled;
    case _Proof.failed:
      return DeleteAccountOutcome.failed;
    case _Proof.ok:
      break;
  }

  try {
    // Step 3. The card first, because discard() takes it down itself only
    // when there is a session to discard.
    await ref.read(liveActivityProvider).clear();
    await ref.read(timerControllerProvider.notifier).discard();

    // Step 4, then 5, then 6.
    final photoUrls = await erasure.run();
    await auth.deleteCurrentUser();
    await auth.signInAnonymously();
    await ref.read(localCachesProvider).clear(photoUrls);

    ref.read(homeNoticeProvider.notifier).say(kAccountDeleted);
    return DeleteAccountOutcome.deleted;
  } catch (e) {
    debugPrint('SONDR delete account failed: ${e.runtimeType} :: $e');
    return DeleteAccountOutcome.failed;
  }
}

enum _Proof { ok, cancelled, failed }

Future<_Proof> _prove(BuildContext context, AuthRepository auth) async {
  final providers = auth.providerIds;

  if (providers.contains('password')) {
    final password = await showSondrPrompt(
      context,
      title: kPasswordPrompt,
      confirmLabel: kDeleteAccountConfirm,
      obscure: true,
    );
    if (password == null) return _Proof.cancelled;
    try {
      await auth.reauthenticateWithPassword(password);
      return _Proof.ok;
    } catch (e) {
      debugPrint('SONDR delete re-auth failed: ${e.runtimeType}');
      return _Proof.failed;
    }
  }

  if (providers.contains('apple.com')) {
    try {
      await auth.reauthenticateWithApple();
      return _Proof.ok;
    } catch (e) {
      // Apple's sheet throws when it is dismissed, which is a no rather
      // than a failure — but the two are not distinguishable here without
      // reaching into the plugin's exception, and either way nothing has
      // been deleted. Treated as a failure so the screen says something:
      // silence after a sheet that did nothing reads as a bug.
      debugPrint('SONDR delete Apple re-auth failed: ${e.runtimeType}');
      return _Proof.failed;
    }
  }

  // No provider to prove anything with. A guest has nothing to delete and
  // never sees the action; an account with neither provider cannot be
  // re-authenticated, and deleting it without proof is not on offer.
  return _Proof.failed;
}
