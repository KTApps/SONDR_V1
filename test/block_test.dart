import 'package:flutter_test/flutter_test.dart';
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
    // Mirrors blockedEitherWay() in the rules and _blockedEitherWay() in the
    // repository: a pair is blocked if EITHER document exists.
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
