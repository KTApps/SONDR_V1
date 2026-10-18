import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import 'session_clock.dart';

/// The container the app shares with its own extensions.
///
/// A Live Activity runs in a separate process and cannot see the app's own
/// UserDefaults. An App Group is the only place both can read.
const String kSessionAppGroup = 'group.com.tanakabere.sondr';

/// Where a running session is kept so it outlives the process.
///
/// An interface because the controller's whole job is arithmetic over a
/// clock and a store, and neither should need a device to be tested.
abstract class SessionStore {
  Future<SessionClock?> read();
  Future<void> write(SessionClock clock);
  Future<void> clear();
}

/// A store of strings that outlives the process.
///
/// Two of them stand behind a session — the App Group container and the
/// standard defaults the app wrote to before the group existed — and a test
/// has to be able to make either one fail.
abstract class SessionPrefs {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// The App Group container.
///
/// Reached through the async API because it is the only one of the two
/// shared_preferences APIs that takes a suite name. It also writes the key
/// verbatim, with none of the legacy API's `flutter.` prefix — which is why
/// the Swift side can look for exactly [PrefsSessionStore.key].
class GroupPrefs implements SessionPrefs {
  GroupPrefs({this.suiteName = kSessionAppGroup});

  final String suiteName;

  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync(
    options: SharedPreferencesAsyncFoundationOptions(suiteName: suiteName),
  );

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// The standard defaults, where sessions lived before the App Group.
///
/// Kept only so a session written by an older build can be moved. The
/// legacy API prefixes everything it stores, so the real key on the device
/// is `flutter.sondr.session`.
class LegacyPrefs implements SessionPrefs {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> remove(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// One key in the App Group container. A running session is device-local
/// and changes on every pause — writing it to Firestore would be a network
/// round trip for something only this phone can answer.
class PrefsSessionStore implements SessionStore {
  PrefsSessionStore({SessionPrefs? group, SessionPrefs? legacy})
    : _groupOverride = group,
      _legacyOverride = legacy;

  /// The one key, and the shape of what is under it.
  ///
  /// This JSON is the contract the Live Activity's Swift will mirror, so it
  /// is spelled out here rather than left to be read off
  /// `SessionClock.toMap()`:
  ///
  /// ```json
  /// {
  ///   "startedAt":   1760000000000,  // ms since epoch, when Start was pressed
  ///   "pausedMs":    0,              // ms spent paused before the current pause
  ///   "pausedAt":    1760000600000,  // ms since epoch; present only while paused
  ///   "taskId":      "abc123",       // absent when the session has no task
  ///   "confirmedMs": 10800000        // elapsed reading last confirmed by
  ///                                  // "Still going?"; absent until confirmed once
  /// }
  /// ```
  ///
  /// Only `startedAt` and `pausedMs` are always present. Elapsed is derived,
  /// never stored — `(pausedAt ?? now) - startedAt - pausedMs`, floored at
  /// zero — so both sides compute the same answer and neither can drift.
  static const String key = 'sondr.session';

  final SessionPrefs? _groupOverride;
  final SessionPrefs? _legacyOverride;

  // Lazy: a test injects both, and constructing the real ones reaches for
  // plugins that are not registered under `flutter test`.
  late final SessionPrefs _group = _groupOverride ?? GroupPrefs();
  late final SessionPrefs _legacy = _legacyOverride ?? LegacyPrefs();

  /// Whether the old key has been dealt with — moved, or found empty. Once
  /// it has, nothing can write there again, so it is never read again.
  bool _settled = false;

  @override
  Future<SessionClock?> read() async {
    final group = await _get(_group, 'group');
    if (group != null) {
      _settled = true;
      return SessionClock.decode(group);
    }
    if (_settled) return null;
    return SessionClock.decode(await _migrate());
  }

  @override
  Future<void> write(SessionClock clock) async {
    // The group is the single source of truth. A write that fails there is
    // not mirrored to the old key: that would leave two sessions of
    // different ages with no way to tell which is current.
    await _put(_group, clock.encode());
  }

  @override
  Future<void> clear() async {
    await _remove(_group, 'group');
    // The old key may still be there if the migration has not run this
    // launch. Stopping a session has to stop it in both places, or the next
    // launch would migrate the stopped one back into the group.
    if (!_settled) await _remove(_legacy, 'legacy');
  }

  /// Move a session written before the App Group existed.
  ///
  /// Copy, read back, then delete: the session is never removed from the
  /// only place it exists until it is provably in the other one. If the
  /// group will not take it — an entitlement that has not arrived yet, a
  /// container the device will not open — the old key is left exactly as it
  /// was and the move is retried on the next read.
  ///
  /// Returns whatever the old key held, moved or not. A session the group
  /// would not accept is still a session, and this launch still has to
  /// restore it.
  Future<String?> _migrate() async {
    final legacy = await _get(_legacy, 'legacy');
    if (legacy == null) {
      _settled = true;
      return null;
    }
    if (!await _put(_group, legacy)) return legacy;
    if (await _get(_group, 'group') != legacy) {
      debugPrint('SONDR session migration unverified; old key kept');
      return legacy;
    }
    await _remove(_legacy, 'legacy');
    _settled = true;
    return legacy;
  }

  Future<String?> _get(SessionPrefs prefs, String where) async {
    try {
      return await prefs.read(key);
    } catch (e) {
      debugPrint('SONDR session $where read error: ${e.runtimeType} :: $e');
      return null;
    }
  }

  Future<bool> _put(SessionPrefs prefs, String value) async {
    try {
      await prefs.write(key, value);
      return true;
    } catch (e) {
      debugPrint('SONDR session write error: ${e.runtimeType} :: $e');
      return false;
    }
  }

  Future<void> _remove(SessionPrefs prefs, String where) async {
    try {
      await prefs.remove(key);
    } catch (e) {
      debugPrint('SONDR session $where clear error: ${e.runtimeType} :: $e');
    }
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => PrefsSessionStore(),
);

/// Now, injectable so a test can move time without waiting for it.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
