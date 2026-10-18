import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';

/// A session has to survive moving house.
///
/// It used to live in the app's own UserDefaults, which a Live Activity
/// cannot see. Moving it into the App Group container means every phone with
/// the old build installed has a session in the wrong place — including a
/// session that is running right now. Losing one would be the exact failure
/// the wall clock was built to prevent: an hour of real work gone because
/// the storage moved underneath it.
void main() {
  const key = PrefsSessionStore.key;
  final t0 = DateTime(2026, 10, 15, 9);

  late _FakePrefs group;
  late _FakePrefs legacy;

  setUp(() {
    group = _FakePrefs();
    legacy = _FakePrefs();
  });

  PrefsSessionStore store() =>
      PrefsSessionStore(group: group, legacy: legacy);

  test('a running session is moved into the group, intact', () async {
    final running = SessionClock(
      startedAt: t0,
      pausedTotal: const Duration(minutes: 4),
      taskId: 'task-7',
    );
    legacy.data[key] = running.encode();

    final restored = await store().read();

    expect(restored, isNotNull, reason: 'the running session was lost');
    expect(restored!.startedAt, t0);
    expect(restored.pausedTotal, const Duration(minutes: 4));
    expect(restored.taskId, 'task-7');
    expect(restored.isPaused, isFalse);
    expect(group.data[key], running.encode(), reason: 'not in the group');
    expect(legacy.data.containsKey(key), isFalse, reason: 'old key kept');
  });

  test('a paused session keeps the moment it was paused', () async {
    final paused = SessionClock(
      startedAt: t0,
      pausedAt: t0.add(const Duration(minutes: 30)),
      taskId: 'task-7',
    );
    legacy.data[key] = paused.encode();

    final restored = await store().read();

    expect(restored!.isPaused, isTrue);
    expect(restored.pausedAt, t0.add(const Duration(minutes: 30)));
    // Paused means the reading stops moving, whatever "now" is.
    expect(
      restored.elapsedAt(t0.add(const Duration(hours: 5))),
      const Duration(minutes: 30),
    );
    expect(legacy.data.containsKey(key), isFalse);
  });

  test('a confirmed session does not start asking again', () async {
    final confirmed = SessionClock(
      startedAt: t0,
      confirmedAt: const Duration(hours: 3),
    );
    legacy.data[key] = confirmed.encode();

    final restored = await store().read();

    expect(restored!.confirmedAt, const Duration(hours: 3));
    expect(
      restored.shouldAsk(t0.add(const Duration(hours: 4))),
      isFalse,
      reason: 'the confirmation was dropped, so it asks "Still going?" again',
    );
  });

  test('a second launch does not read the old key at all', () async {
    legacy.data[key] = SessionClock(startedAt: t0).encode();
    await store().read();
    expect(legacy.reads, 1);

    // A fresh store is what a relaunch gets: new object, same device.
    legacy.reads = 0;
    group.writes = 0;
    final second = await store().read();

    expect(second, isNotNull, reason: 'the migrated session is unreadable');
    expect(legacy.reads, 0, reason: 'the old key was consulted again');
    expect(group.writes, 0, reason: 'the session was migrated twice');
  });

  test('a second read in the same launch does not re-check the old key',
      () async {
    final one = store();
    expect(await one.read(), isNull);
    expect(legacy.reads, 1);

    expect(await one.read(), isNull);
    expect(legacy.reads, 1, reason: 'the old key is re-read on every glance');
  });

  test('with nothing stored, nothing happens', () async {
    expect(await store().read(), isNull);
    expect(group.writes, 0);
    expect(group.data, isEmpty);
    expect(legacy.removals, 0, reason: 'something was deleted for no reason');
  });

  test('a failed group write leaves the old key exactly where it was',
      () async {
    final running = SessionClock(startedAt: t0, taskId: 'task-7');
    legacy.data[key] = running.encode();
    group.failWrites = true;

    final restored = await store().read();

    expect(
      restored!.taskId,
      'task-7',
      reason: 'a session the group refused is still a session',
    );
    expect(legacy.data[key], running.encode(), reason: 'the only copy is gone');
    expect(legacy.removals, 0);
  });

  test('a group write that silently does not stick leaves the old key',
      () async {
    legacy.data[key] = SessionClock(startedAt: t0).encode();
    // iOS hands back a UserDefaults for a suite the app is not entitled to
    // and then drops what is written to it. No error, no value.
    group.swallowWrites = true;

    expect(await store().read(), isNotNull);
    expect(
      legacy.data.containsKey(key),
      isTrue,
      reason: 'the only copy of the session is gone',
    );
  });

  test('a failed move is retried on the next read', () async {
    final running = SessionClock(startedAt: t0).encode();
    legacy.data[key] = running;
    group.failWrites = true;
    await store().read();

    final one = store();
    group.failWrites = true;
    await one.read();
    group.failWrites = false;
    await one.read();

    expect(group.data[key], running);
    expect(legacy.data.containsKey(key), isFalse);
  });

  test('a session is written to the group, not the old key', () async {
    await store().write(SessionClock(startedAt: t0));

    expect(group.data[key], isNotNull);
    expect(legacy.data, isEmpty);
  });

  test('stopping before the move clears both places', () async {
    legacy.data[key] = SessionClock(startedAt: t0).encode();

    await store().clear();

    expect(
      legacy.data.containsKey(key),
      isFalse,
      reason: 'the next launch migrates the stopped session back',
    );
    expect(group.data.containsKey(key), isFalse);
  });

  test('stopping after the move does not reach for the old key', () async {
    legacy.data[key] = SessionClock(startedAt: t0).encode();
    final one = store();
    await one.read();

    legacy.removals = 0;
    await one.clear();

    expect(group.data.containsKey(key), isFalse);
    expect(legacy.removals, 0);
  });

  test('a group read that throws does not hide a session', () async {
    final running = SessionClock(startedAt: t0, taskId: 'task-7').encode();
    legacy.data[key] = running;
    group.failReads = true;

    // The write still lands; only the verifying read fails, so the old key
    // stays and the session comes back from it.
    final restored = await store().read();

    expect(restored, isNotNull);
    expect(legacy.data[key], running);
  });
}

class _FakePrefs implements SessionPrefs {
  final Map<String, String> data = <String, String>{};

  int reads = 0;
  int writes = 0;
  int removals = 0;

  /// Writes throw, the way an unreachable container does.
  bool failWrites = false;

  /// Writes are accepted and discarded, the way an unentitled suite does.
  bool swallowWrites = false;

  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    reads++;
    if (failReads) throw StateError('read refused');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWrites) throw StateError('write refused');
    if (swallowWrites) return;
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    removals++;
    data.remove(key);
  }
}
