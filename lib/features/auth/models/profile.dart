/// A user's public-facing identity: their unique handle and display name.
/// Stored at `users/{uid}/meta/profile`; the handle is also reserved in the
/// top-level `usernames/{handle}` index for uniqueness and friend lookup.
class Profile {
  const Profile({
    required this.uid,
    required this.username,
    required this.displayName,
    this.photoUrl,
    this.photoPath,
    this.photoSourceId,
  });

  final String uid;
  final String username;
  final String displayName;

  /// The photo chosen for the profile: the square copy's download URL and
  /// Storage path (`users/{uid}/profile/photo.jpg`). Null when none has
  /// been chosen, and the newest photo stands in the ring instead.
  final String? photoUrl;
  final String? photoPath;

  /// Which private photo the copy was made from, so the picker can say
  /// which one is chosen. The copy stands on its own: deleting the
  /// original leaves it.
  final String? photoSourceId;

  factory Profile.fromMap(String uid, Map<String, dynamic> map) => Profile(
        uid: uid,
        username: (map['username'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
        photoUrl: _nonEmpty(map['photoUrl']),
        photoPath: _nonEmpty(map['photoPath']),
        photoSourceId: _nonEmpty(map['photoSourceId']),
      );

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
}
