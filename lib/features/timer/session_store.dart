import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_clock.dart';

/// Where a running session is kept so it outlives the process.
///
/// An interface because the controller's whole job is arithmetic over a
/// clock and a store, and neither should need a device to be tested.
abstract class SessionStore {
  Future<SessionClock?> read();
  Future<void> write(SessionClock clock);
  Future<void> clear();
}

/// One key in SharedPreferences. A running session is device-local and
/// changes on every pause — writing it to Firestore would be a network
/// round trip for something only this phone can answer.
class PrefsSessionStore implements SessionStore {
  static const String key = 'sondr.session';

  @override
  Future<SessionClock?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SessionClock.decode(prefs.getString(key));
    } catch (e) {
      debugPrint('SONDR session read error: ${e.runtimeType} :: $e');
      return null;
    }
  }

  @override
  Future<void> write(SessionClock clock) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, clock.encode());
    } catch (e) {
      debugPrint('SONDR session write error: ${e.runtimeType} :: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (e) {
      debugPrint('SONDR session clear error: ${e.runtimeType} :: $e');
    }
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => PrefsSessionStore(),
);

/// Now, injectable so a test can move time without waiting for it.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
