import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';

Map<String, dynamic> _base(String type) => {
      'authorUid': 'alice',
      'author': {'username': 'alice', 'displayName': 'Alice'},
      'type': type,
      'createdAt': 1700000000000, // epoch millis — parsed without Firestore
      'caption': 'nice',
      'audience': ['alice', 'bob'],
    };

void main() {
  group('Post.fromMap', () {
    test('parses a milestone post', () {
      final post = Post.fromMap('p1', {
        ..._base('milestone'),
        'taskName': 'Spanish',
        'milestoneHours': 20,
        'totalHours': 21,
      });
      expect(post, isA<MilestonePost>());
      expect(post.type, PostType.milestone);
      final m = post as MilestonePost;
      expect(m.taskName, 'Spanish');
      expect(m.milestoneHours, 20);
      expect(m.totalHours, 21);
      expect(m.author.label, 'Alice');
      expect(m.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('parses a streak post', () {
      final post = Post.fromMap('p2', {
        ..._base('streak'),
        'streakDays': 12,
        'habits': ['Run', 'Cold shower'],
      });
      expect(post, isA<StreakPost>());
      final s = post as StreakPost;
      expect(s.streakDays, 12);
      expect(s.habits, ['Run', 'Cold shower']);
    });

    test('parses a session post', () {
      final post = Post.fromMap('p3', {
        ..._base('session'),
        'taskName': 'Piano',
        'sessionSeconds': 8100,
      });
      expect(post, isA<SessionPost>());
      final s = post as SessionPost;
      expect(s.taskName, 'Piano');
      expect(s.sessionSeconds, 8100);
    });

    test('author label falls back to handle without a display name', () {
      const author = PostAuthor(username: 'tom', displayName: '');
      expect(author.label, '@tom');
    });

    test('tolerates a null createdAt (server timestamp not yet landed)', () {
      final post = Post.fromMap('p4', {
        ..._base('session'),
        'createdAt': null,
        'taskName': 'Golf',
        'sessionSeconds': 600,
      });
      expect(post.createdAt, isNull);
    });

    test('reads like/comment counts, defaulting to 0 when absent', () {
      final withCounts = Post.fromMap('p5', {
        ..._base('milestone'),
        'taskName': 'Spanish',
        'milestoneHours': 20,
        'totalHours': 20,
        'likeCount': 3,
        'commentCount': 2,
      });
      expect(withCounts.likeCount, 3);
      expect(withCounts.commentCount, 2);

      // Older posts written before counters existed read as 0.
      final legacy = Post.fromMap('p6', {
        ..._base('streak'),
        'streakDays': 5,
        'habits': const ['Run'],
      });
      expect(legacy.likeCount, 0);
      expect(legacy.commentCount, 0);
    });
  });

  group('Comment.fromMap', () {
    test('parses author, text and timestamp', () {
      final c = Comment.fromMap('c1', {
        'authorUid': 'bob',
        'author': {'username': 'bob', 'displayName': 'Bob'},
        'text': 'Strong work',
        'createdAt': 1700000000000,
      });
      expect(c.authorUid, 'bob');
      expect(c.author.label, 'Bob');
      expect(c.text, 'Strong work');
      expect(c.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('falls back to handle and tolerates a missing timestamp', () {
      final c = Comment.fromMap('c2', {
        'authorUid': 'tom',
        'author': {'username': 'tom'},
        'text': 'nice',
      });
      expect(c.author.label, '@tom');
      expect(c.createdAt, isNull);
    });
  });
}
