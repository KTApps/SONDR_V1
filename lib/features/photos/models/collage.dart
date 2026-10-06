/// A milestone collage: an ordered set of photo references for one task's 20h
/// milestone. Cheap — it stores photo *ids* (not binaries); display composes
/// live from the referenced photos.
///
/// Auto-composed and saved at the milestone moment ([edited] == false). Once the
/// user curates it (tapping photos in/out) it becomes [edited] == true, which
/// protects it from being overwritten by a later auto-compose.
class Collage {
  const Collage({
    required this.taskId,
    required this.milestoneHours,
    required this.photoIds,
    required this.edited,
    this.createdAt,
  });

  final String taskId;

  /// The milestone this collage belongs to (20, 40, …).
  final int milestoneHours;

  /// Ordered photo ids (`{taskId}_{timestamp}`) from [collageSelection].
  final List<String> photoIds;

  /// True once the user has edited the selection — guards against auto-compose
  /// clobbering a curated collage.
  final bool edited;

  /// Server timestamp of first composition. Null only briefly before it lands.
  final DateTime? createdAt;

  /// Deterministic id — one collage per task+milestone.
  String get id => docId(taskId, milestoneHours);

  static String docId(String taskId, int milestoneHours) =>
      '${taskId}_$milestoneHours';

  factory Collage.fromMap(Map<String, dynamic> map) => Collage(
        taskId: (map['taskId'] as String?) ?? '',
        milestoneHours: (map['milestoneHours'] as num?)?.toInt() ?? 0,
        photoIds: [
          for (final e in (map['photoIds'] as List?) ?? const []) '$e',
        ],
        edited: (map['edited'] as bool?) ?? false,
        createdAt: _parseTime(map['createdAt']),
      );
}

/// Tolerates a Firestore `Timestamp` (duck-typed via `toDate()`), epoch millis,
/// or a `DateTime` — mirrors the feed post parser, keeping the model
/// Firestore-agnostic and testable.
DateTime? _parseTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}
