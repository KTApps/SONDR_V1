/// One person blocking another.
///
/// Directional, unlike a friendship: `a__b` means a blocked b, and says
/// nothing about whether b blocked a. The two are separate documents, so
/// unblocking one direction cannot lift the other.
///
/// The doc id is derived, not random, so the security rules can `exists()` a
/// block without being able to read it — which is what lets the record stay
/// readable by the blocker alone while still being enforced for everyone.
/// [id] must stay byte-identical to the expression in firestore.rules.
class Block {
  const Block({
    required this.blocker,
    required this.blocked,
    required this.username,
    required this.displayName,
  });

  /// Who did the blocking.
  final String blocker;

  /// Who was blocked.
  final String blocked;

  /// The blocked person's handle and name, denormalised the way friendships
  /// denormalise `profiles`: `users/{uid}/**` is owner-only, so the Blocked
  /// list could not render their name from a cross-read.
  final String username;
  final String displayName;

  /// What to show in a list.
  String get label => displayName.isNotEmpty ? displayName : username;

  /// The document id for [blocker] blocking [blocked].
  ///
  /// Mirrored in firestore.rules as `blocker + '__' + blocked`. Changing the
  /// separator here without changing it there silently disables enforcement.
  static String idFor(String blocker, String blocked) => '${blocker}__$blocked';

  factory Block.fromMap(Map<String, dynamic> map) => Block(
    blocker: (map['blocker'] as String?) ?? '',
    blocked: (map['blocked'] as String?) ?? '',
    username: (map['username'] as String?) ?? '',
    displayName: (map['displayName'] as String?) ?? '',
  );
}
