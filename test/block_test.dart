import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';

void main() {
  group('Block id derivation', () {
    // These ids are duplicated in firestore.rules as `blocker + '__' + blocked`.
    // If this test is changed, the rule must change with it or enforcement
    // silently stops matching.
    test('is blocker then blocked, joined with __', () {
      expect(Block.idFor('alice', 'bob'), 'alice__bob');
    });

    test('is DIRECTIONAL — the two directions are different documents', () {
      expect(Block.idFor('alice', 'bob'), isNot(Block.idFor('bob', 'alice')));
    });

    test('does not collide with the friendship pair id', () {
      // A friendship sorts its uids; a block does not. For a sorted pair the
      // strings coincide, which is why blocks live in their own collection.
      expect(Friendship.pairId('alice', 'bob'), 'alice__bob');
      expect(Block.idFor('bob', 'alice'), 'bob__alice');
      expect(Friendship.pairId('bob', 'alice'), 'alice__bob');
    });
  });

  group('both-direction check', () {
    // Mirrors blockedEitherWay() in firestore.rules: a pair is blocked if
    // EITHER document exists. The CLIENT deliberately no longer asks this —
    // it can only see its own blocks — so this pins the rules' behaviour.
    bool blockedEitherWay(Set<String> existing, String a, String b) =>
        existing.contains(Block.idFor(a, b)) ||
        existing.contains(Block.idFor(b, a));

    test('no blocks: the pair is clear', () {
      expect(blockedEitherWay({}, 'alice', 'bob'), isFalse);
    });

    test('blocker side blocks the pair', () {
      expect(
        blockedEitherWay({'alice__bob'}, 'alice', 'bob'),
        isTrue,
      );
    });

    test('blocked side ALSO blocks the pair, whichever way round it is asked', () {
      // The person who was blocked must not be able to re-request.
      expect(blockedEitherWay({'alice__bob'}, 'bob', 'alice'), isTrue);
    });

    test('an unrelated block leaves the pair clear', () {
      expect(blockedEitherWay({'alice__carol'}, 'alice', 'bob'), isFalse);
    });
  });

  group('handlesNotBlocked', () {
    // The search filter. It runs against the uids streamed from
    // watchBlocked(), never a per-candidate get(): a get() of a block doc
    // that does not exist is denied, not empty, which broke search entirely.
    const candidates = [
      MapEntry('alice', 'uid-a'),
      MapEntry('bob', 'uid-b'),
      MapEntry('carol', 'uid-c'),
    ];

    test('drops the blocked person and keeps the rest, in order', () {
      expect(handlesNotBlocked(candidates, {'uid-b'}), ['alice', 'carol']);
    });

    test('no blocks: everyone is findable', () {
      expect(handlesNotBlocked(candidates, {}), ['alice', 'bob', 'carol']);
    });

    test('FAILS OPEN — an empty set filters nothing, never everything', () {
      // A denied or offline blocks read degrades to this. Search must still
      // work: the rules are the real boundary, this is only UX.
      expect(handlesNotBlocked(candidates, const {}), hasLength(3));
    });

    test('only THIS user\'s blocks apply — a stranger\'s uid is irrelevant', () {
      expect(handlesNotBlocked(candidates, {'uid-z'}), hasLength(3));
    });

    test('a usernames entry with no owner uid is dropped', () {
      expect(
        handlesNotBlocked(const [MapEntry('ghost', null)], {}),
        isEmpty,
      );
    });

    test('blocking everyone returns nothing', () {
      expect(
        handlesNotBlocked(candidates, {'uid-a', 'uid-b', 'uid-c'}),
        isEmpty,
      );
    });
  });

  group('withoutBlockedAuthors', () {
    // Hides content from people YOU blocked. The reciprocal case — someone
    // who blocked you — cannot be filtered client-side at all: their block
    // document is not yours to read.
    const items = [
      MapEntry('p1', 'uid-a'),
      MapEntry('p2', 'uid-b'),
      MapEntry('p3', 'uid-a'),
    ];
    String author(MapEntry<String, String> e) => e.value;

    test('drops every item by a blocked author, keeps the rest in order', () {
      expect(
        withoutBlockedAuthors(items, {'uid-a'}, author).map((e) => e.key),
        ['p2'],
      );
    });

    test('FAILS OPEN — an empty set returns everything, never nothing', () {
      // The set is empty while the blocks stream loads and whenever it
      // errors. A broken block read must not blank the feed.
      expect(withoutBlockedAuthors(items, const {}, author), hasLength(3));
    });

    test('a stranger\'s uid filters nothing', () {
      expect(withoutBlockedAuthors(items, {'uid-z'}, author), hasLength(3));
    });

    test('your own content is never filtered', () {
      // Your uid cannot be in your own blocked set — the rules refuse a
      // self-block and blockUser is never called with your own uid.
      const mine = [MapEntry('mine', 'me')];
      expect(withoutBlockedAuthors(mine, {'uid-a'}, author), hasLength(1));
    });

    test('blocking every author returns nothing', () {
      expect(
        withoutBlockedAuthors(items, {'uid-a', 'uid-b'}, author),
        isEmpty,
      );
    });
  });

  group('Block.fromMap', () {
    test('reads the denormalised identity and falls back to the handle', () {
      final named = Block.fromMap({
        'blocker': 'a',
        'blocked': 'b',
        'username': 'bob',
        'displayName': 'Bob Smith',
      });
      expect(named.label, 'Bob Smith');

      final handleOnly = Block.fromMap({
        'blocker': 'a',
        'blocked': 'b',
        'username': 'bob',
      });
      expect(handleOnly.label, 'bob');
      expect(handleOnly.displayName, '');
    });
  });
}
