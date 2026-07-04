import '../../../core/utils/date.dart';
import '../../tasks/models/task.dart';

/// A private photo captured at the end of a work session, tied to the task it
/// belongs to. Photos are private-first: they live under the owner's own space
/// (`users/{uid}/photos/{photoId}`, covered by the Firestore catch-all rule) and
/// the feed reads *from* this store rather than owning the image.
///
/// There is no persisted session in the app — time folds into
/// [Task.secondsByDay] aggregates — so [sessionSeconds] is snapshotted onto the
/// photo at capture time. [dayKey] is denormalised (matching [DayKey]) so the
/// calendar can query a day's photos with a single equality filter, and the
/// microsecond [timestamp] both orders same-day photos and forms the
/// deterministic document id, `{taskId}_{timestamp}`.
class Photo {
  const Photo({
    required this.taskId,
    required this.taskName,
    required this.dayKey,
    required this.timestamp,
    required this.sessionSeconds,
    required this.photoUrl,
    required this.storagePath,
    this.milestoneHours,
  });

  final String taskId;
  final String taskName;

  /// "yyyy-mm-dd" for the capture day — the same key [Task.secondsByDay] uses.
  final String dayKey;

  /// Microseconds since epoch at capture. Precise enough to disambiguate two
  /// photos on the same task, and it is the id's suffix.
  final int timestamp;

  /// The session's elapsed whole seconds at capture — snapshotted because the
  /// session itself is never persisted.
  final int sessionSeconds;

  final String photoUrl;

  /// The Storage object path (`users/{uid}/photos/{photoId}.jpg`), kept so the
  /// binary can be deleted alongside the doc.
  final String storagePath;

  /// The milestone hours crossed by the session this photo marks (20, 40, …), or
  /// null if the session crossed none. Snapshotted at capture; photos taken
  /// before this field existed read back as null.
  final int? milestoneHours;

  /// Deterministic, self-describing id: `{taskId}_{timestamp}`. Dedupe is
  /// trivial and identity is readable. Equals the Firestore document id by
  /// construction, so [Photo.fromMap] needs no separate id argument.
  String get id => docId(taskId, timestamp);

  static String docId(String taskId, int timestamp) => '${taskId}_$timestamp';

  /// The capture instant reconstructed from [timestamp].
  DateTime get capturedAt => DateTime.fromMicrosecondsSinceEpoch(timestamp);

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'taskName': taskName,
        'dayKey': dayKey,
        'timestamp': timestamp,
        'sessionSeconds': sessionSeconds,
        'photoUrl': photoUrl,
        'storagePath': storagePath,
        'milestoneHours': milestoneHours,
      };

  /// Rebuild from a stored document. Tolerates numbers coming back as `num`.
  /// The id is derived from the fields, so the doc key isn't needed here.
  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      taskId: (map['taskId'] as String?) ?? '',
      taskName: (map['taskName'] as String?) ?? '',
      dayKey: (map['dayKey'] as String?) ?? '',
      timestamp: _int(map['timestamp']),
      sessionSeconds: _int(map['sessionSeconds']),
      photoUrl: (map['photoUrl'] as String?) ?? '',
      storagePath: (map['storagePath'] as String?) ?? '',
      milestoneHours: (map['milestoneHours'] as num?)?.toInt(),
    );
  }
}

int _int(dynamic v) => v is num ? v.toInt() : 0;
