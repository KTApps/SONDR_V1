import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../friends/friends_repository.dart';
import '../timer/session_store.dart';
import '../timer/timer_controller.dart';
import 'presence_repository.dart';

/// My accepted friends' uids, sorted, capped at [kPresenceListenCap] and
/// joined into one string — so a pending request arriving, or any change
/// that leaves the list as it was, does not tear down every listener and
/// pay for them again.
final presenceFriendKeyProvider = Provider<String>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return '';
  final friends = [
    for (final f in ref.watch(friendsProvider)) f.otherUid(uid),
  ]..sort();
  return friends.take(kPresenceListenCap).join(',');
});

/// How many friends are in a session, while I am in one on this phone.
///
/// One listener per friend on `presence/{friendUid}` — the rules prove
/// friendship from the path, so a query over the collection is not
/// possible and a list is not allowed. Attached only while a session is
/// active here, and all detached when it ends. A guest, or someone with no
/// friends, attaches nothing.
class FriendsInSession extends Notifier<int> {
  final Map<String, DateTime?> _seen = {};

  @override
  int build() {
    final active = ref.watch(
      timerControllerProvider.select((t) => t.isActive),
    );
    final backend = ref.watch(presenceBackendProvider);
    final guest = ref.watch(isGuestProvider);
    final key = ref.watch(presenceFriendKeyProvider);
    _seen.clear();
    if (!active || backend == null || guest || key.isEmpty) return 0;

    final subs = <StreamSubscription<DateTime?>>[];
    for (final friend in key.split(',')) {
      subs.add(
        backend
            .watch(friend)
            .listen(
              (at) {
                _seen[friend] = at;
                _recount();
              },
              // Refused — an unfriend landed between — is not in a session.
              onError: (Object _) {
                _seen.remove(friend);
                _recount();
              },
            ),
      );
    }
    // A record can age past the cutoff with nothing written to it.
    final tick = Timer.periodic(const Duration(minutes: 5), (_) => _recount());
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
      tick.cancel();
    });
    return 0;
  }

  void _recount() {
    state = countFresh(_seen.values, ref.read(nowProvider)());
  }
}

/// The records written within [kPresenceCutoff] of [now].
int countFresh(Iterable<DateTime?> updatedAts, DateTime now) => updatedAts
    .where((at) => at != null && now.difference(at) < kPresenceCutoff)
    .length;

final friendsInSessionProvider = NotifierProvider<FriendsInSession, int>(
  FriendsInSession.new,
);

/// "1 friend is in a session", "4 friends are in a session"; nothing at 0.
String? friendsInSessionLine(int count) => switch (count) {
  <= 0 => null,
  1 => '1 friend is in a session',
  _ => '$count friends are in a session',
};
