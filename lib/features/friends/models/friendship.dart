/// A relationship between two users. One document per pair lives at
/// `friendships/{pairId}`, where the id is the two uids sorted and joined so it
/// is identical no matter who initiates. The pair's identities are denormalized
/// into the doc so listing friends needs no cross-user profile reads (which the
/// rules keep private): the requester writes their own on create, the recipient
/// writes theirs on accept.
enum FriendshipStatus { pending, accepted }

/// The denormalized public identity of one side of a friendship.
class FriendIdentity {
  const FriendIdentity({required this.username, required this.displayName});

  final String username;
  final String displayName;

  /// What to show in a list: the display name, falling back to the handle.
  String get label => displayName.isNotEmpty ? displayName : '@$username';

  factory FriendIdentity.fromMap(Map<String, dynamic> map) => FriendIdentity(
        username: (map['username'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
      );
}

class Friendship {
  const Friendship({
    required this.id,
    required this.users,
    required this.requestedBy,
    required this.status,
    required this.profiles,
  });

  /// The pair id (== [pairId]).
  final String id;

  /// Both uids, sorted — the array `array-contains` queries filter on.
  final List<String> users;

  /// Who sent the request (the other side is the recipient who accepts).
  final String requestedBy;

  final FriendshipStatus status;

  /// uid → that user's denormalized identity.
  final Map<String, FriendIdentity> profiles;

  bool get isAccepted => status == FriendshipStatus.accepted;

  /// A request this user sent and is awaiting acceptance on.
  bool isOutgoing(String myUid) =>
      status == FriendshipStatus.pending && requestedBy == myUid;

  /// A request awaiting *this* user's acceptance.
  bool isIncoming(String myUid) =>
      status == FriendshipStatus.pending && requestedBy != myUid;

  /// The other participant's uid relative to [myUid].
  String otherUid(String myUid) =>
      users.firstWhere((u) => u != myUid, orElse: () => myUid);

  /// The other participant's identity (may be null if not yet written).
  FriendIdentity? otherIdentity(String myUid) => profiles[otherUid(myUid)];

  /// Deterministic doc id for a pair, independent of initiation order.
  static String pairId(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join('__');
  }

  factory Friendship.fromMap(String id, Map<String, dynamic> map) {
    final rawProfiles = (map['profiles'] as Map?) ?? const {};
    final profiles = <String, FriendIdentity>{};
    rawProfiles.forEach((k, v) {
      if (v is Map) {
        profiles['$k'] = FriendIdentity.fromMap(Map<String, dynamic>.from(v));
      }
    });
    return Friendship(
      id: id,
      users: (map['users'] as List?)?.map((e) => '$e').toList() ?? const [],
      requestedBy: (map['requestedBy'] as String?) ?? '',
      status: map['status'] == 'accepted'
          ? FriendshipStatus.accepted
          : FriendshipStatus.pending,
      profiles: profiles,
    );
  }
}
