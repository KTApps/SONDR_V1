import '../friends/models/friendship.dart';

/// Where I stand with someone, as their profile shows it.
///
/// One rule, in one place: the profile's action, the friends list's label and
/// the search results all mean the same four words by the same four states.
enum FriendStatus {
  /// No friendship either way — the profile offers Add friend.
  none,

  /// I asked and they have not answered. Shown, not tappable: there is
  /// nothing to do but wait.
  requested,

  /// They asked me — the profile offers Accept.
  incoming,

  accepted,

  /// I blocked them. Nothing of theirs is shown and the only action is
  /// Unblock. Takes precedence over everything else: a block leaves the
  /// friendship deleted, so this is not a conflict in practice, but if a
  /// stale pair document ever survived one the block is what must win.
  blockedByMe,
}

/// Where I stand with [theirUid], from the friendships I can already see.
///
/// Costs no reads: [friendships] is the stream Profile and Friends are
/// already watching, and [blockedUids] the one the blocked list is.
///
/// Only MY blocks are consulted. Whether they have blocked ME is
/// deliberately unknowable here — the rules refuse the write and the wording
/// matches "no one found", which is the only answer that does not disclose
/// a block.
FriendStatus friendStatusOf({
  required String myUid,
  required String theirUid,
  required List<Friendship> friendships,
  required Set<String> blockedUids,
}) {
  if (blockedUids.contains(theirUid)) return FriendStatus.blockedByMe;
  for (final f in friendships) {
    if (!f.users.contains(theirUid) || !f.users.contains(myUid)) continue;
    if (f.isAccepted) return FriendStatus.accepted;
    return f.requestedBy == myUid ? FriendStatus.requested : FriendStatus.incoming;
  }
  return FriendStatus.none;
}

/// The friendship document between us, if there is one — what Accept and
/// Remove friend act on.
Friendship? friendshipWith({
  required String myUid,
  required String theirUid,
  required List<Friendship> friendships,
}) {
  for (final f in friendships) {
    if (f.users.contains(theirUid) && f.users.contains(myUid)) return f;
  }
  return null;
}

/// The label the status action carries.
String friendStatusLabel(FriendStatus status) => switch (status) {
  FriendStatus.none => 'Add friend',
  FriendStatus.requested => 'Requested',
  FriendStatus.incoming => 'Accept',
  FriendStatus.accepted => 'Friends',
  FriendStatus.blockedByMe => 'Unblock',
};

/// Whether the action does anything when tapped. "Requested" and "Friends"
/// are states, not offers.
bool friendStatusIsActionable(FriendStatus status) =>
    status == FriendStatus.none ||
    status == FriendStatus.incoming ||
    status == FriendStatus.blockedByMe;

/// Whether this profile shows what they have been doing. Only a friend sees
/// posts and milestones; everyone else sees the handle, the hours, and an
/// invitation to add each other.
bool friendStatusSeesContent(FriendStatus status) =>
    status == FriendStatus.accepted;
