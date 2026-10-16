import 'dart:convert';

/// A session, as the wall clock sees it.
///
/// The timer used to be a counter that a one-second ticker incremented. A
/// ticker only fires while the app is awake, so locking the phone, taking a
/// call or switching apps stopped time: an hour of real work logged as the
/// minute before the screen went dark. And the count lived only in memory,
/// so iOS reclaiming the app mid-session lost the whole thing.
///
/// Kept as two timestamps and a total instead. Elapsed is derived, never
/// accumulated, so nothing has to be running for time to pass.
class SessionClock {
  const SessionClock({
    required this.startedAt,
    this.pausedTotal = Duration.zero,
    this.pausedAt,
    this.taskId,
  });

  /// When Start was first pressed.
  final DateTime startedAt;

  /// Everything spent paused before the current pause, if any.
  final Duration pausedTotal;

  /// When the current pause began; null while running.
  final DateTime? pausedAt;

  /// The task the session belongs to, so a restored session knows what it
  /// was for.
  final String? taskId;

  bool get isPaused => pausedAt != null;

  /// How long this session has run, at [now].
  ///
  /// While paused the answer stops moving: the clock is read at the moment
  /// of the pause, not now.
  Duration elapsedAt(DateTime now) {
    final end = pausedAt ?? now;
    final raw = end.difference(startedAt) - pausedTotal;
    // A clock moved backwards — a timezone change, an NTP correction —
    // must never produce a negative session.
    return raw.isNegative ? Duration.zero : raw;
  }

  SessionClock pause(DateTime now) =>
      isPaused ? this : _copy(pausedAt: now, clearPausedAt: false);

  SessionClock resume(DateTime now) {
    final since = pausedAt;
    if (since == null) return this;
    final waited = now.difference(since);
    return _copy(
      pausedTotal: pausedTotal + (waited.isNegative ? Duration.zero : waited),
      clearPausedAt: true,
    );
  }

  SessionClock _copy({
    Duration? pausedTotal,
    DateTime? pausedAt,
    required bool clearPausedAt,
  }) => SessionClock(
    startedAt: startedAt,
    pausedTotal: pausedTotal ?? this.pausedTotal,
    pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
    taskId: taskId,
  );

  Map<String, dynamic> toMap() => {
    'startedAt': startedAt.millisecondsSinceEpoch,
    'pausedMs': pausedTotal.inMilliseconds,
    if (pausedAt != null) 'pausedAt': pausedAt!.millisecondsSinceEpoch,
    if (taskId != null) 'taskId': taskId,
  };

  static SessionClock? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final started = map['startedAt'];
    if (started is! int) return null;
    final pausedAt = map['pausedAt'];
    return SessionClock(
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      pausedTotal: Duration(
        milliseconds: map['pausedMs'] is int ? map['pausedMs'] as int : 0,
      ),
      pausedAt: pausedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(pausedAt)
          : null,
      taskId: map['taskId'] is String ? map['taskId'] as String : null,
    );
  }

  String encode() => jsonEncode(toMap());

  /// Null for anything that is not a session this app wrote.
  static SessionClock? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? fromMap(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
