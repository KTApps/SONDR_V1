import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../friends/friends_repository.dart';

/// What another person's profile can do about the person it is about.
///
/// A seam, so the screen and its tests never reach Firestore — the same
/// shape as TaskPurge and PhotoDeleter. Everything here is addressed by
/// **uid**: a profile is opened by uid, and the published document that
/// would name its owner may not exist.
abstract interface class ProfileActions {
  /// [handle] is carried for the wording and for the pending row to print.
  /// It is never what the request is addressed to.
  Future<void> addFriend(String uid, {String handle});

  Future<void> acceptRequest(String pairId);

  Future<void> removeFriend(String pairId);

  Future<void> block({
    required String uid,
    required String handle,
    required String displayName,
  });

  Future<void> unblock(String uid);
}

class _RepoProfileActions implements ProfileActions {
  _RepoProfileActions(this.repo);

  final FriendsRepository repo;

  @override
  Future<void> addFriend(String uid, {String handle = ''}) =>
      repo.sendRequestTo(uid, handle: handle);
  @override
  Future<void> acceptRequest(String pairId) => repo.accept(pairId);
  @override
  Future<void> removeFriend(String pairId) => repo.remove(pairId);
  @override
  Future<void> block({
    required String uid,
    required String handle,
    required String displayName,
  }) => repo.blockUser(
    targetUid: uid,
    username: handle,
    displayName: displayName,
  );
  @override
  Future<void> unblock(String uid) => repo.unblockUser(uid);
}

/// Null on the local/offline backend or before a uid exists.
final profileActionsProvider = Provider<ProfileActions?>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  return repo == null ? null : _RepoProfileActions(repo);
});
