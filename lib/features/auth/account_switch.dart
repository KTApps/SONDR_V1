import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../feed/posts_repository.dart';
import '../friends/friends_repository.dart';
import '../habits/habits_providers.dart';
import '../notifications/notifications_repository.dart';
import '../photos/collages_repository.dart';
import '../photos/photo_refresh.dart';
import '../photos/photos_repository.dart';
import '../profile/milestone_strip.dart';
import '../tasks/tasks_providers.dart';
import 'auth_repository.dart';
import 'profile_repository.dart';

/// The account changing hands — a sign-out, a deletion, a sign-in — and
/// the rule that goes with it: no frame of the old account's data is
/// drawn after it. Every surface that shows an account's data — Home,
/// the Feed, Profile — goes blank the moment the change starts, and
/// comes back only once the new account's own data is in. Loading is not
/// empty: a figure still on its way is nothing to show, not the old one.

/// How long the surfaces wait for the new account's data before they
/// give up waiting and draw what there is.
const Duration kAccountSwitchTimeout = Duration(seconds: 8);

/// How long the new account's data must have been in, with the account
/// unchanged, before the surfaces draw: a sign-out is two auth events —
/// nobody, then a fresh guest — and between them every source answers
/// at once for nobody, with the local repository's seed. A moment's
/// hold outlasts that gap.
const Duration kAccountSwitchSettle = Duration(milliseconds: 80);

@immutable
class AccountSwitchState {
  const AccountSwitchState({required this.fromUid, required this.changing, this.toUid});

  /// Whose data was on screen when the change began.
  final String? fromUid;

  /// Whether the change itself — the auth call — is still running.
  final bool changing;

  /// Whom the auth object names once the change has run: the account the
  /// stream has to catch up with before anything is drawn.
  final String? toUid;

  AccountSwitchState changed(String? toUid) =>
      AccountSwitchState(fromUid: fromUid, changing: false, toUid: toUid);
}

class AccountSwitch extends Notifier<AccountSwitchState?> {
  Timer? _timeout;
  Timer? _settle;

  @override
  AccountSwitchState? build() {
    ref.onDispose(() {
      _timeout?.cancel();
      _settle?.cancel();
    });
    return null;
  }

  void begin(String? fromUid) {
    _settle?.cancel();
    _settle = null;
    state = AccountSwitchState(fromUid: fromUid, changing: true);
    _timeout?.cancel();
    _timeout = Timer(kAccountSwitchTimeout, end);
  }

  void changed(String? toUid) {
    final s = state;
    if (s != null) state = s.changed(toUid);
  }

  /// The new account's data is in. Held a moment: if the account moves
  /// again, or a source goes back to loading, the hold starts over.
  void readySeen() {
    _settle ??= Timer(kAccountSwitchSettle, end);
  }

  void readyLost() {
    _settle?.cancel();
    _settle = null;
  }

  void end() {
    _timeout?.cancel();
    _settle?.cancel();
    _settle = null;
    state = null;
  }
}

final accountSwitchProvider = NotifierProvider<AccountSwitch, AccountSwitchState?>(AccountSwitch.new);

/// Whether the account's surfaces must stay blank: the change is still
/// running, the stream has not caught up with the account the change
/// ended in, the new account's data is still loading, or it has only
/// just come in. Once it has been in a moment, the switch is over and
/// the surfaces draw.
final accountSwitchingProvider = Provider<bool>((ref) {
  final s = ref.watch(accountSwitchProvider);
  if (s == null) return false;
  final notifier = ref.read(accountSwitchProvider.notifier);
  final uid = ref.watch(currentUidProvider);
  if (s.changing || uid != s.toUid) {
    notifier.readyLost();
    return true;
  }
  final loading = [
    // Home: the tasks, the dial's habits.
    ref.watch(tasksProvider).isLoading,
    ref.watch(habitsProvider).isLoading,
    // The Feed: the posts, the notices.
    ref.watch(feedProvider).isLoading,
    ref.watch(myNotificationsProvider).isLoading,
    // Profile.
    ref.watch(currentProfileProvider).isLoading,
    ref.watch(galleryPreviewProvider).isLoading,
    ref.watch(milestoneStripProvider).isLoading,
    ref.watch(collagesListProvider).isLoading,
    ref.watch(friendshipsProvider).isLoading,
  ];
  if (loading.any((l) => l)) {
    notifier.readyLost();
    return true;
  }
  // Everything is in for the new account: a moment more, then the switch
  // is over — ended by the notifier, not inside this read.
  notifier.readySeen();
  return true;
});

/// Every provider that holds one account's data, told to let it go.
/// Most follow the uid on their own; these are the ones that hold what
/// they fetched, and the ones a stale read would be worst from.
void invalidateAccountViews(WidgetRef ref) {
  invalidatePhotoViews(ref);
  ref.invalidate(currentProfileProvider);
  ref.invalidate(milestoneStripProvider);
  ref.invalidate(tasksProvider);
  ref.invalidate(habitsProvider);
  ref.invalidate(friendshipsProvider);
  ref.invalidate(myNotificationsProvider);
}

/// The blank a gated surface draws while the account changes hands.
const Widget kAccountSwitchBlank = Scaffold(body: SizedBox.expand());

/// Run [change] — the auth call that moves the account — with the
/// surfaces blank from before it starts until the new account's data is
/// in. Returns what [change] returns; a failure ends the switch so the
/// surfaces come back.
///
/// [endsAs] names the account the change ends in. By default it is read
/// from the auth object, which is ahead of its own stream — the stream
/// has to catch up with it before anything is drawn. Where there is no
/// auth object (the local backend, a test), the account on record is
/// taken as it stands.
Future<T> switchAccount<T>(
  WidgetRef ref,
  Future<T> Function() change, {
  String? Function()? endsAs,
}) async {
  final notifier = ref.read(accountSwitchProvider.notifier);
  notifier.begin(ref.read(currentUidProvider));
  try {
    final result = await change();
    invalidateAccountViews(ref);
    final toUid = endsAs != null
        ? endsAs()
        : (kUseFirebase && ref.read(firebaseInitializedProvider))
            ? ref.read(authRepositoryProvider).currentUser?.uid
            : ref.read(currentUidProvider);
    notifier.changed(toUid);
    return result;
  } catch (e) {
    notifier.end();
    rethrow;
  }
}
