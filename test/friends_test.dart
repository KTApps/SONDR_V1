import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/models/friendship.dart';

void main() {
  group('Friendship', () {
    test('pairId is identical regardless of argument order', () {
      expect(Friendship.pairId('alice', 'bob'),
          Friendship.pairId('bob', 'alice'));
    });

    test('classifies incoming / outgoing / accepted relative to a user', () {
      final pending = Friendship.fromMap('alice__bob', {
        'users': ['alice', 'bob'],
        'requestedBy': 'alice',
        'status': 'pending',
        'profiles': {
          'alice': {'username': 'alice', 'displayName': 'Alice'},
          'bob': {'username': 'bob'},
        },
      });

      // Alice sent it → outgoing for her, incoming for Bob.
      expect(pending.isOutgoing('alice'), isTrue);
      expect(pending.isIncoming('alice'), isFalse);
      expect(pending.isIncoming('bob'), isTrue);
      expect(pending.isOutgoing('bob'), isFalse);
      expect(pending.isAccepted, isFalse);

      final accepted = Friendship.fromMap('alice__bob', {
        'users': ['alice', 'bob'],
        'requestedBy': 'alice',
        'status': 'accepted',
        'profiles': {
          'alice': {'username': 'alice', 'displayName': 'Alice'},
          'bob': {'username': 'bob', 'displayName': 'Bob'},
        },
      });
      expect(accepted.isAccepted, isTrue);
      expect(accepted.isIncoming('bob'), isFalse);
    });

    test('resolves the other participant and their identity', () {
      final f = Friendship.fromMap('alice__bob', {
        'users': ['alice', 'bob'],
        'requestedBy': 'alice',
        'status': 'accepted',
        'profiles': {
          'alice': {'username': 'alice', 'displayName': 'Alice'},
          'bob': {'username': 'bob', 'displayName': 'Bob'},
        },
      });
      expect(f.otherUid('alice'), 'bob');
      expect(f.otherIdentity('alice')?.label, 'Bob');
    });

    test('identity label falls back to the handle without a display name', () {
      const id = FriendIdentity(username: 'tom', displayName: '');
      expect(id.label, '@tom');
    });
  });
}
