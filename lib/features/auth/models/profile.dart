/// A user's public-facing identity: their unique handle and display name.
/// Stored at `users/{uid}/meta/profile`; the handle is also reserved in the
/// top-level `usernames/{handle}` index for uniqueness and friend lookup.
class Profile {
  const Profile({
    required this.uid,
    required this.username,
    required this.displayName,
  });

  final String uid;
  final String username;
  final String displayName;

  factory Profile.fromMap(String uid, Map<String, dynamic> map) => Profile(
        uid: uid,
        username: (map['username'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
      );
}
