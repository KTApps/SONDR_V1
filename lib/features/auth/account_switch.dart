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

@immutable
class AccountSwitchState {
  const AccountSwitchState({required this.fromUid, required this.changing});

  /// Whose data was on screen when the change began.
  final String? fromUid;

  /// Whether the change itself — the auth call — is still running.
  final bool changing;

  AccountSwitchState changed() => AccountSwitchState(fromUid: fromUid, changing: false);
}

class AccountSwitch extends Notifier<AccountSwitchState?> {
  Timer? _timeout;

  @override
  AccountSwitchState? build() {
    ref.onDispose(() => _timeout?.cancel());
    return null;
  }

  void begin(String? fromUid) {
    state = AccountSwitchState(fromUid: fromUid, changing: true);
    _timeout?.cancel();
    _timeout = Timer(kAccountSwitchTimeout, end);
  }

  void changed() {
    final s = state;
    if (s != null) state = s.changed();
  }

  void end() {
    _timeout?.cancel();
    state = null;
  }
}

final accountSwitchProvider = NotifierProvider<AccountSwitch, AccountSwitchState?>(AccountSwitch.new);

/// Whether the account's surfaces must stay blank: the change is still
/// running, the auth has not moved on from the old account yet, or the
/// new account's data is still loading. Once nothing is, the switch is
/// over and the surfaces draw.
final accountSwitchingProvider = Provider<bool>((ref) {
  final s = ref.watch(accountSwitchProvider);
  if (s == null) return false;
  final uid = ref.watch(currentUidProvider);
  if (s.changing || uid == s.fromUid) return true;
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
  if (loading.any((l) => l)) return true;
  // Everything is in for the new account: the switch is over — said
  // after this read, not inside it.
  Future.microtask(() => ref.read(accountSwitchProvider.notifier).end());
  return false;
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
Future<T> switchAccount<T>(WidgetRef ref, Future<T> Function() change) async {
  final notifier = ref.read(accountSwitchProvider.notifier);
  notifier.begin(ref.read(currentUidProvider));
  try {
    final result = await change();
    invalidateAccountViews(ref);
    notifier.changed();
    return result;
  } catch (e) {
    notifier.end();
    rethrow;
  }
}
