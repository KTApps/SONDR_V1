import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/audience_widen.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';

/// Accepting a request lets the new friend into what I posted before.
void main() {
  test('accept widens my content to the person accepted', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('me').collection('meta').doc('profile')
        .set({'username': 'ada', 'displayName': 'Ada'});
    await db.collection('friendships').doc(Friendship.pairId('me', 'them')).set({
      'users': ['me', 'them'],
      'requestedBy': 'them',
      'status': 'pending',
      'profiles': {
        'them': {'username': 'cass', 'displayName': 'Cass'},
      },
    });
    final audiences = _Recording();
    final repo = FriendsRepository(
      db: db,
      uid: 'me',
      pruner: _NoPrune(),
      widener: AudienceWidener(
        uid: 'me',
        audiences: audiences,
        blocked: () async => const {},
      ),
    );

    await repo.accept(Friendship.pairId('me', 'them'));
    // The widening is not awaited by accept; let it run.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(audiences.asked, isTrue, reason: 'accept never reached the widener');
    expect(audiences.added, ['them']);
  });
}

/// One post of mine that lacks the new friend; records what it is asked.
class _Recording implements WidenableAudiences {
  bool asked = false;
  List<String> added = const [];

  @override
  Future<List<OwnPost>> myPosts() async {
    asked = true;
    return const [OwnPost(path: 'posts/p1', audience: ['me'])];
  }

  @override
  Future<List<OwnComment>> myComments() async => const [];

  @override
  Future<List<String>> audienceOf(String postPath) async => const ['me'];

  @override
  Future<void> addToPosts(List<(String, List<String>)> updates) async {
    added = [for (final (_, add) in updates) ...add];
  }

  @override
  Future<void> setComments(List<(String, List<String>)> updates) async {}
}

class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}
