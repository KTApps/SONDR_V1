import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/presence/friends_in_session.dart';
import 'package:sondr/features/presence/presence_repository.dart';
import 'package:sondr/features/presence/presence_writer.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// "In a session", for friends: the record is written when a session
/// begins, deleted when it ends, and counted by friends while it is fresh.
void main() {
  late _Backend backend;
  late _Flag flag;
  late DateTime now;
  late ProviderContainer c;

  ProviderContainer make({
    bool guest = false,
    List<String> friends = const [],
    PresenceBackend? withBackend,
    bool noBackend = false,
  }) {
    c = ProviderContainer(overrides: [
      timerControllerProvider.overrideWith(_Timer.new),
      presenceBackendProvider.overrideWithValue(noBackend ? null : (withBackend ?? backend)),
      presenceFlagProvider.overrideWithValue(flag),
      isGuestProvider.overrideWithValue(guest),
      currentUidProvider.overrideWithValue('me'),
      nowProvider.overrideWithValue(() => now),
      friendsProvider.overrideWithValue([for (final f in friends) _friend(f)]),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  _Timer timer() => c.read(timerControllerProvider.notifier) as _Timer;
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> become(TimerStatus status) async {
    timer().set(TimerState(status: status));
    await settle();
  }

  setUp(() {
    backend = _Backend();
    flag = _Flag();
    now = DateTime(2026, 11, 24, 9);
  });

  group('the writer', () {
    Future<PresenceWriter> writer({bool guest = false}) async {
      make(guest: guest);
      // As main() holds it: on the container, never paused.
      c.listen(presenceWriterProvider, (_, _) {});
      final w = c.read(presenceWriterProvider);
      await settle();
      return w;
    }

    test('Start writes; Pause and Resume do not; Stop deletes', () async {
      await writer();
      expect(backend.log, isEmpty, reason: 'idle: nothing');
      await become(TimerStatus.running);
      expect(backend.log, ['write']);
      expect(flag.value, 'me', reason: 'so a launch can clear it up');
      await become(TimerStatus.paused);
      await become(TimerStatus.running);
      await become(TimerStatus.paused);
      expect(backend.log, ['write'], reason: 'paused is still in a session');
      await become(TimerStatus.idle);
      expect(backend.log, ['write', 'clear']);
      expect(flag.value, isNull);
    });

    test('a restored session — active from the start — writes', () async {
      make();
      timer().set(const TimerState(status: TimerStatus.paused));
      c.listen(presenceWriterProvider, (_, _) {});
      await settle();
      expect(backend.log, ['write']);
    });

    test('the setting off: nothing written; turned off mid-session, deleted at once; on again, written', () async {
      backend.showInSession = false;
      await writer();
      await become(TimerStatus.running);
      expect(backend.log, isEmpty);
      backend.setShow(true);
      await settle();
      expect(backend.log, ['write']);
      backend.setShow(false);
      await settle();
      expect(backend.log, ['write', 'clear']);
      await become(TimerStatus.idle);
      expect(backend.log, ['write', 'clear'], reason: 'nothing left to delete');
    });

    test('a guest writes nothing', () async {
      await writer(guest: true);
      await become(TimerStatus.running);
      await become(TimerStatus.idle);
      expect(backend.log, isEmpty);
    });

    test('no backend: nothing, and no flag read', () async {
      make(noBackend: true);
      c.listen(presenceWriterProvider, (_, _) {});
      await settle();
      timer().set(const TimerState(status: TimerStatus.running));
      await settle();
      expect(flag.reads, 0);
    });

    test('a refresh waits an hour; the "Still going?" answer does not', () async {
      final w = await writer();
      await become(TimerStatus.running);
      now = now.add(const Duration(minutes: 59));
      w.touch();
      expect(backend.log, ['write']);
      now = now.add(const Duration(minutes: 2));
      w.touch();
      await settle();
      expect(backend.log, ['write', 'write']);
      w.touch(force: true);
      await settle();
      expect(backend.log, ['write', 'write', 'write']);
      await become(TimerStatus.idle);
      w.touch(force: true);
      await settle();
      expect(backend.log.last, 'clear', reason: 'no session, no refresh');
    });

    test('the timer\'s signal reaches it: on the way back in, and on "Still going?"', () async {
      await writer();
      await become(TimerStatus.running);
      final touch = c.read(presenceTouchProvider.notifier);
      touch.touch();
      await settle();
      expect(backend.log, ['write'], reason: 'not an hour yet');
      touch.touch(force: true);
      await settle();
      expect(backend.log, ['write', 'write']);
      now = now.add(const Duration(hours: 2));
      touch.touch();
      await settle();
      expect(backend.log, ['write', 'write', 'write']);
    });

    test('settle hands back the delete, for signing out to wait on', () async {
      final w = await writer();
      await become(TimerStatus.running);
      backend.hold = Completer<void>();
      timer().set(const TimerState());
      var done = false;
      unawaited(w.settle().then((_) => done = true));
      await settle();
      expect(done, isFalse, reason: 'the delete has not landed');
      backend.hold!.complete();
      await settle();
      expect(done, isTrue);
      expect(backend.log, ['write', 'clear']);
    });

    group('a launch with no session', () {
      test('deletes what this phone wrote and never saw go', () async {
        flag.value = 'me';
        await writer();
        expect(backend.log, ['clear']);
        expect(flag.value, isNull);
      });

      test('does nothing when the flag is clear — no paid write per launch', () async {
        await writer();
        expect(backend.log, isEmpty);
      });

      test('does nothing for another account\'s record', () async {
        flag.value = 'someone-else';
        await writer();
        expect(backend.log, isEmpty);
      });
    });
  });

  group('the count', () {
    int count() => c.read(friendsInSessionProvider);

    Future<void> start({List<String> friends = const ['a', 'b', 'c'], bool guest = false}) async {
      make(friends: friends, guest: guest);
      c.listen(friendsInSessionProvider, (_, _) {});
      await settle();
    }

    test('idle: nothing attached, nothing counted', () async {
      await start();
      backend.record('a', now);
      await settle();
      expect(count(), 0);
      expect(backend.listening, isEmpty);
    });

    test('in a session: one listener per friend, fresh records counted', () async {
      await start();
      await become(TimerStatus.running);
      expect(backend.listening, {'a', 'b', 'c'});
      backend.record('a', now.subtract(const Duration(minutes: 5)));
      backend.record('b', now.subtract(const Duration(hours: 11, minutes: 59)));
      backend.record('c', null);
      await settle();
      expect(count(), 2);
      backend.record('a', null);
      await settle();
      expect(count(), 1);
    });

    test('older than 12 hours is not counted', () async {
      await start();
      await become(TimerStatus.running);
      backend.record('a', now.subtract(const Duration(hours: 12)));
      backend.record('b', now.subtract(const Duration(hours: 13)));
      await settle();
      expect(count(), 0);
    });

    test('paused still counts the friends', () async {
      await start();
      await become(TimerStatus.running);
      backend.record('a', now);
      await settle();
      await become(TimerStatus.paused);
      expect(count(), 1);
      expect(backend.listening, {'a', 'b', 'c'});
    });

    test('a refused listener (an unfriend between) is not in a session', () async {
      await start();
      await become(TimerStatus.running);
      backend.record('a', now);
      backend.record('b', now);
      await settle();
      expect(count(), 2);
      backend.refuse('a');
      await settle();
      expect(count(), 1);
    });

    test('the session ends: every listener detached', () async {
      await start();
      await become(TimerStatus.running);
      backend.record('a', now);
      await settle();
      await become(TimerStatus.idle);
      expect(backend.listening, isEmpty);
      expect(count(), 0);
    });

    test('a guest, and someone with no friends, attach nothing', () async {
      await start(guest: true);
      await become(TimerStatus.running);
      expect(backend.listening, isEmpty);
      c.dispose();
      backend = _Backend();
      await start(friends: const []);
      await become(TimerStatus.running);
      expect(backend.listening, isEmpty);
    });

    test('at most 100 friends are listened to', () async {
      await start(friends: [for (var i = 0; i < 120; i++) 'f${i.toString().padLeft(3, '0')}']);
      await become(TimerStatus.running);
      expect(backend.listening.length, kPresenceListenCap);
      expect(kPresenceListenCap, 100);
    });

    test('a pending request arriving does not re-attach the listeners', () async {
      make(friends: const ['a', 'b']);
      c.listen(friendsInSessionProvider, (_, _) {});
      await become(TimerStatus.running);
      final before = backend.attaches;
      // The same friends, in a new list.
      c.updateOverrides([
        timerControllerProvider.overrideWith(_Timer.new),
        presenceBackendProvider.overrideWithValue(backend),
        presenceFlagProvider.overrideWithValue(flag),
        isGuestProvider.overrideWithValue(false),
        currentUidProvider.overrideWithValue('me'),
        nowProvider.overrideWithValue(() => now),
        friendsProvider.overrideWithValue([_friend('b'), _friend('a')]),
      ]);
      await settle();
      expect(backend.attaches, before);
    });
  });

  group('the words', () {
    test('singular, plural, and nothing at 0', () {
      expect(friendsInSessionLine(0), isNull);
      expect(friendsInSessionLine(1), '1 friend is in a session');
      expect(friendsInSessionLine(2), '2 friends are in a session');
      expect(friendsInSessionLine(50), '50 friends are in a session');
    });

    test('the constants the design names', () {
      expect(kPresenceCutoff, const Duration(hours: 12));
      expect(kPresenceRefreshAfter, const Duration(hours: 1));
      expect(kPresenceLifetime, const Duration(hours: 24));
    });
  });

  group('the Firestore backend', () {
    late FakeFirebaseFirestore db;
    late FirestorePresenceBackend me;

    setUp(() {
      db = FakeFirebaseFirestore();
      me = FirestorePresenceBackend(db: db, uid: 'me');
    });

    test('writes exactly the two fields, and deletes', () async {
      await me.write();
      final doc = await db.doc('presence/me').get();
      expect(doc.data()!.keys.toSet(), {'updatedAt', 'expiresAt'});
      final expires = (doc.data()!['expiresAt'] as Timestamp).toDate();
      expect(expires.difference(DateTime.now()).inHours, inInclusiveRange(23, 24));
      await me.clear();
      expect((await db.doc('presence/me').get()).exists, isFalse);
      await me.clear();
    });

    test('a friend\'s record reads as when it was written, or null', () async {
      final seen = <DateTime?>[];
      final sub = me.watch('friend').listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      final at = DateTime(2026, 11, 24, 8);
      await db.doc('presence/friend').set({'updatedAt': Timestamp.fromDate(at), 'expiresAt': Timestamp.fromDate(at)});
      await Future<void>.delayed(Duration.zero);
      await db.doc('presence/friend').delete();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [null, at, null]);
    });

    test('the setting: missing is on; stored in users/{uid}/meta/settings', () async {
      expect(await me.watchShowInSession().first, isTrue);
      await me.setShowInSession(false);
      expect((await db.doc('users/me/meta/settings').get()).data(), {'showInSession': false});
      expect(await me.watchShowInSession().first, isFalse);
      await me.setShowInSession(true);
      expect(await me.watchShowInSession().first, isTrue);
    });
  });
}

Friendship _friend(String uid) => Friendship(
  id: Friendship.pairId('me', uid),
  users: (['me', uid]..sort()),
  requestedBy: 'me',
  status: FriendshipStatus.accepted,
  profiles: const {},
);

class _Timer extends TimerController {
  @override
  TimerState build() => const TimerState();

  @override
  Future<void> get restored => Future<void>.value();

  void set(TimerState next) => state = next;
}

class _Flag implements PresenceFlag {
  String? value;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> set(String? uid) async => value = uid;
}

class _Backend implements PresenceBackend {
  final List<String> log = [];
  bool showInSession = true;
  Completer<void>? hold;
  int attaches = 0;

  final Map<String, StreamController<DateTime?>> _friends = {};
  final StreamController<bool> _show = StreamController<bool>.broadcast();

  Set<String> get listening => {
    for (final e in _friends.entries)
      if (e.value.hasListener) e.key,
  };

  @override
  String get uid => 'me';

  @override
  Future<void> write() async => log.add('write');

  @override
  Future<void> clear() async {
    log.add('clear');
    await hold?.future;
  }

  StreamController<DateTime?> _controller(String friend) =>
      _friends.putIfAbsent(friend, () => StreamController<DateTime?>.broadcast());

  @override
  Stream<DateTime?> watch(String friendUid) {
    attaches++;
    return _controller(friendUid).stream;
  }

  void record(String friend, DateTime? at) => _controller(friend).add(at);
  void refuse(String friend) => _controller(friend).addError(StateError('permission-denied'));

  @override
  Stream<bool> watchShowInSession() async* {
    yield showInSession;
    yield* _show.stream;
  }

  void setShow(bool on) {
    showInSession = on;
    _show.add(on);
  }

  @override
  Future<void> setShowInSession(bool on) async => setShow(on);
}
