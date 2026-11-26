import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend.dart';

/// "In a session", for friends to count.
///
/// `presence/{uid}` exists while its owner is in a session — running or
/// paused — and holds nothing but `updatedAt` (the server's clock) and
/// `expiresAt` (a day on, which Firestore's TTL deletes after). Who is in a
/// session is a number on Home and nothing more: no name, task or time ever
/// goes in the document, so none can come out of it.
///
/// Paused counts. Pause and Resume from the Lock Screen only reach the App
/// Group, so Firestore could not hear them until the app came back; counting
/// both means it never has to.

/// A record older than this is not counted: a phone that never came back to
/// clear it, an app deleted mid-session, a session forgotten for days.
const Duration kPresenceCutoff = Duration(hours: 12);

/// How long a record lives before the TTL may take it. The rules allow up
/// to two days, so a phone's clock running fast is not refused.
const Duration kPresenceLifetime = Duration(hours: 24);

/// A running record is written again when it is older than this and the app
/// comes back, so a real long session never falls past [kPresenceCutoff].
const Duration kPresenceRefreshAfter = Duration(hours: 1);

/// The most friends one phone listens to.
const int kPresenceListenCap = 100;

/// How long signing out waits for the delete to reach the server, so it goes
/// out as the account that wrote it.
const Duration kPresenceSignOutWait = Duration(seconds: 3);

/// The one place presence touches the backend.
abstract class PresenceBackend {
  /// Whose record [write] and [clear] act on.
  String get uid;

  /// Mine, written or refreshed.
  Future<void> write();

  /// Mine, gone. Deleting a record that is not there is not an error.
  Future<void> clear();

  /// A friend's: when it was last written, or null when there is none.
  /// Errors (an unfriend landing between) end the stream.
  Stream<DateTime?> watch(String friendUid);

  /// Whether I show as in a session. A missing setting is on.
  Stream<bool> watchShowInSession();

  Future<void> setShowInSession(bool on);
}

class FirestorePresenceBackend implements PresenceBackend {
  FirestorePresenceBackend({required this.db, required this.uid});

  final FirebaseFirestore db;

  @override
  final String uid;

  DocumentReference<Map<String, dynamic>> _record(String who) =>
      db.collection('presence').doc(who);

  DocumentReference<Map<String, dynamic>> get _settings =>
      db.collection('users').doc(uid).collection('meta').doc('settings');

  @override
  Future<void> write() => _record(uid).set({
    'updatedAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(DateTime.now().add(kPresenceLifetime)),
  });

  @override
  Future<void> clear() => _record(uid).delete();

  @override
  Stream<DateTime?> watch(String friendUid) =>
      _record(friendUid).snapshots().map((snap) {
        if (!snap.exists) return null;
        final at = snap.data()?['updatedAt'];
        // Only the writer ever sees its own pending server time, but a
        // record without one is fresh, not absent.
        return at is Timestamp ? at.toDate() : DateTime.now();
      });

  @override
  Stream<bool> watchShowInSession() => _settings.snapshots().map(
    (snap) => snap.data()?['showInSession'] != false,
  );

  @override
  Future<void> setShowInSession(bool on) =>
      _settings.set({'showInSession': on}, SetOptions(merge: true));
}

/// Null without Firestore or before a uid exists.
final presenceBackendProvider = Provider<PresenceBackend?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return FirestorePresenceBackend(db: FirebaseFirestore.instance, uid: uid);
});

/// Whether I show as in a session. On until said otherwise, and on with no
/// backend at all, where there is nothing to show anyway.
final showInSessionProvider = StreamProvider<bool>((ref) {
  final backend = ref.watch(presenceBackendProvider);
  if (backend == null) return Stream.value(true);
  return backend.watchShowInSession();
});

/// Whose record this phone last wrote and has not seen deleted.
///
/// A launch with no session deletes it, and only then: a delete on every
/// launch would be a paid write for nothing. Kept on the phone because it is
/// about this phone's writes.
abstract class PresenceFlag {
  Future<String?> read();
  Future<void> set(String? uid);
}

class PrefsPresenceFlag implements PresenceFlag {
  static const String key = 'sondr.presenceWrittenBy';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> set(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, uid);
    }
  }
}

final presenceFlagProvider = Provider<PresenceFlag>((ref) => PrefsPresenceFlag());

/// The timer asking for the record to be written again: on the way back
/// into the app (refreshed if an hour old) and on the "Still going?" answer
/// ([force]d). A signal rather than a call, because the writer watches the
/// timer and a provider cannot depend on what depends on it.
class PresenceTouch extends Notifier<({int count, bool force})> {
  @override
  ({int count, bool force}) build() => (count: 0, force: false);

  void touch({bool force = false}) =>
      state = (count: state.count + 1, force: force);
}

final presenceTouchProvider =
    NotifierProvider<PresenceTouch, ({int count, bool force})>(
      PresenceTouch.new,
    );
