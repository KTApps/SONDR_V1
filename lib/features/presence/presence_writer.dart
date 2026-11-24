import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../timer/session_store.dart';
import '../timer/timer_controller.dart';
import 'presence_repository.dart';

/// Keeps `presence/{uid}` in step with the session on this phone.
///
/// Separate from the timer, which knows nothing about it: this watches
/// whether a session is active — running or paused — and writes when one
/// begins and deletes when it ends. Every way out of a session reaches
/// `TimerController.discard()`, which makes the session inactive, so every
/// Stop deletes. Pause and Resume never write.
///
/// Shown only for a permanent account with the setting on. Turning the
/// setting off deletes at once; on, mid-session, writes at once.
class PresenceWriter {
  PresenceWriter(this._ref);

  final Ref _ref;

  /// The backend the current record was written through, or null when
  /// there is none — so a delete goes to the account that wrote it.
  PresenceBackend? _shownBy;
  DateTime? _lastWrite;
  Future<void>? _pending;

  DateTime _now() => _ref.read(nowProvider)();

  void start() {
    _ref.listen(
      timerControllerProvider.select((t) => t.isActive),
      (_, _) => evaluate(),
    );
    _ref.listen(showInSessionProvider, (_, _) => evaluate());
    _ref.listen(isGuestProvider, (_, _) => evaluate());
    _ref.listen(presenceBackendProvider, (_, _) => evaluate());
    _ref.listen(presenceTouchProvider, (_, next) => touch(force: next.force));
    evaluate();
    unawaited(_clearLeftover());
  }

  bool get _wanted =>
      _ref.read(presenceBackendProvider) != null &&
      !_ref.read(isGuestProvider) &&
      _ref.read(timerControllerProvider).isActive &&
      _ref.read(showInSessionProvider).value == true;

  /// Write or delete if what is wanted has changed. Idempotent.
  void evaluate() {
    final backend = _ref.read(presenceBackendProvider);
    final want = _wanted;
    final shown = _shownBy;
    if (shown != null && (!want || shown.uid != backend?.uid)) {
      _shownBy = null;
      _lastWrite = null;
      _pending = _clear(shown);
    }
    if (want && _shownBy == null) {
      _shownBy = backend;
      _pending = _write(backend!);
    }
  }

  /// Write again if the record is older than [kPresenceRefreshAfter], or
  /// at once when [force]d — the "Still going?" answer.
  void touch({bool force = false}) {
    final shown = _shownBy;
    final last = _lastWrite;
    if (shown == null) return;
    if (!force && last != null && _now().difference(last) < kPresenceRefreshAfter) {
      return;
    }
    _pending = _write(shown);
  }

  /// The last write or delete, for a caller that must see it out — signing
  /// out, before the account changes under it.
  Future<void> settle() {
    evaluate();
    return _pending ?? Future<void>.value();
  }

  Future<void> _write(PresenceBackend backend) async {
    _lastWrite = _now();
    try {
      // The flag first: a launch that finds it with no session deletes.
      await _ref.read(presenceFlagProvider).set(backend.uid);
      await backend.write();
    } catch (e) {
      debugPrint('SONDR presence write error: ${e.runtimeType}');
    }
  }

  Future<void> _clear(PresenceBackend backend) async {
    try {
      await backend.clear();
      final flag = _ref.read(presenceFlagProvider);
      if (await flag.read() == backend.uid) await flag.set(null);
    } catch (e) {
      debugPrint('SONDR presence clear error: ${e.runtimeType}');
    }
  }

  /// A record this phone wrote and never saw deleted, with no session to
  /// show for it: the app was killed before Stop's delete went out.
  Future<void> _clearLeftover() async {
    final backend = _ref.read(presenceBackendProvider);
    if (backend == null) return;
    try {
      await _ref.read(timerControllerProvider.notifier).restored;
      if (_shownBy != null) return;
      if (await _ref.read(presenceFlagProvider).read() != backend.uid) return;
      _pending = _clear(backend);
    } catch (e) {
      debugPrint('SONDR presence leftover error: ${e.runtimeType}');
    }
  }
}

/// Alive for the app's lifetime: `main()` listens to it on the container
/// itself, which no covering route can pause.
final presenceWriterProvider = Provider<PresenceWriter>((ref) {
  final writer = PresenceWriter(ref);
  writer.start();
  return writer;
});
