import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';

Friendship _pair(String a, String b, {bool accepted = false}) =>
    Friendship(
      id: Friendship.pairId(a, b),
      users: [a, b]..sort(),
      requestedBy: a,
      status: accepted ? FriendshipStatus.accepted : FriendshipStatus.pending,
      profiles: const {},
    );

void main() {
  group('adding by uid', () {
    FriendException? refusal({
      String targetUid = 'them',
      String myHandle = 'ada',
      String handle = '',
      Set<String> blocked = const {},
      Friendship? existing,
    }) => addFriendRefusal(
      myUid: 'me',
      targetUid: targetUid,
      myHandle: myHandle,
      handle: handle,
      blockedByMe: blocked,
      existing: existing,
    );

    test('a uid with NO handle is allowed — a profile is not a search box', () {
      // The bug: a profile whose owner has published nothing has no handle
      // to offer, and the add was refused for want of one.
      expect(refusal(), isNull);
      expect(refusal(handle: 'cass'), isNull);
    });

    test('my own profile, and an empty uid, are refused', () {
      expect(refusal(targetUid: 'me')?.message, 'That is your own profile.');
      expect(refusal(targetUid: '')?.message, 'That is your own profile.');
    });

    test('I need a handle of my own before I can add anyone', () {
      expect(
        refusal(myHandle: '')?.message,
        'Set a handle before adding friends.',
      );
    });

    test('someone I blocked is refused in the words of someone who is not there', () {
      // Identical to the handle-not-found wording, and to what the rules
      // produce when THEY blocked me: a block must not be detectable.
      expect(
        refusal(blocked: const {'them'}, handle: 'cass')?.message,
        'No one found with the handle @cass.',
      );
      expect(addFriendUnavailable('cass'), 'No one found with the handle @cass.');
      expect(addFriendUnavailable(''), 'That person is no longer available.');
      expect(
        refusal(blocked: const {'them'})?.message,
        'That person is no longer available.',
      );
    });

    test('a friendship that already exists says which kind, named if it can', () {
      expect(
        refusal(existing: _pair('me', 'them', accepted: true), handle: 'cass')
            ?.message,
        "You're already friends with @cass.",
      );
      expect(
        refusal(existing: _pair('me', 'them'))?.message,
        'There’s already a pending request.',
      );
    });
  });

  test('normalizeHandle trims, lowercases, and drops a leading @', () {
    expect(normalizeHandle('  @TanaKa '), 'tanaka');
    expect(normalizeHandle('kelly@test'), 'kelly@test');
    expect(normalizeHandle('   '), '');
  });

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
