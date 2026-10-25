import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/models/post.dart';

void main() {
  // A Firestore-shaped milestone map carrying the given photos (photos are
  // stored as the list of PostPhoto maps, exactly as PostsRepository writes).
  Map<String, dynamic> milestoneMap(List<PostPhoto> photos) => {
    'type': 'milestone',
    'authorUid': 'u1',
    'author': {'username': 'tom', 'displayName': 'Tom'},
    'createdAt': DateTime(2026, 8, 12).millisecondsSinceEpoch,
    'caption': 'hello',
    'photos': [for (final p in photos) p.toMap()],
    'likeCount': 2,
    'commentCount': 1,
    'taskName': 'Spanish',
    'milestoneHours': 20,
    'totalHours': 21,
  };

  group('Post multi-photo schema round-trips (write -> read -> equal)', () {
    const one = [
      PostPhoto(url: 'u/a.jpg', storagePath: 'users/u1/posts/a.jpg'),
    ];
    const many = [
      PostPhoto(url: 'u/a.jpg', storagePath: 'users/u1/posts/a.jpg'),
      PostPhoto(url: 'u/b.jpg', storagePath: 'users/u1/posts/b.jpg'),
      PostPhoto(url: 'u/c.jpg', storagePath: 'users/u1/posts/c.jpg'),
    ];

    for (final entry in const <String, List<PostPhoto>>{
      '0 photos': [],
      '1 photo': one,
      'N photos': many,
    }.entries) {
      test(entry.key, () {
        final photos = entry.value;
        final post = Post.fromMap('p1', milestoneMap(photos));
        expect(post, isA<MilestonePost>());
        expect(post.photos, equals(photos)); // element-wise via PostPhoto ==
        expect(post.id, 'p1');
        expect(post.caption, 'hello');
      });
    }

    test('missing photos field is tolerated -> empty list', () {
      final map = milestoneMap(const [])..remove('photos');
      expect(Post.fromMap('p2', map).photos, isEmpty);
    });

    test('PostPhoto toMap/fromMap round-trips', () {
      const p = PostPhoto(url: 'x', storagePath: 'users/u/posts/x.jpg');
      expect(PostPhoto.fromMap(p.toMap()), p);
    });
  });

  group('the story fields', () {
    test('a milestone with sessions, unit and photo→session round-trips', () {
      final map = milestoneMap(const [
        PostPhoto(url: 'a', storagePath: 'p/a', sessionIndex: 0),
        PostPhoto(url: 'b', storagePath: 'p/b', sessionIndex: 2),
      ])
        ..['sessions'] = [
          {'at': 1000, 'seconds': 3600, 'photo': true},
          {'at': 2000, 'seconds': 1800, 'photo': false},
          {'at': 3000, 'seconds': 7200, 'photo': true},
        ]
        ..['unit'] = 'session';
      final post = Post.fromMap('p', map) as MilestonePost;
      expect(post.hasStory, isTrue);
      expect(post.unit, SegmentUnit.session);
      expect(post.segments, const [
        PostSegment(at: 1000, seconds: 3600, photo: true),
        PostSegment(at: 2000, seconds: 1800),
        PostSegment(at: 3000, seconds: 7200, photo: true),
      ]);
      expect(post.photos.map((p) => p.sessionIndex), [0, 2]);
    });

    test('a day-unit story reads as days', () {
      final map = milestoneMap(const [])
        ..['sessions'] = [
          {'at': 1000, 'seconds': 3600},
        ]
        ..['unit'] = 'day';
      final post = Post.fromMap('p', map) as MilestonePost;
      expect(post.unit, SegmentUnit.day);
      expect(post.segments.single.photo, isFalse);
    });

    test('an old milestone post has no story and still reads', () {
      final post = Post.fromMap('p', milestoneMap(const [])) as MilestonePost;
      expect(post.hasStory, isFalse);
      expect(post.segments, isEmpty);
      expect(post.unit, isNull);
    });

    test('a malformed segment is dropped, not thrown', () {
      final map = milestoneMap(const [])
        ..['sessions'] = [
          {'at': 'soon', 'seconds': 1},
          {'at': 1, 'seconds': 1},
        ]
        ..['unit'] = 'session';
      final post = Post.fromMap('p', map) as MilestonePost;
      expect(post.segments.length, 1);
    });

    test('a session post carries its seconds into the band', () {
      final map = milestoneMap(const [])
        ..['type'] = 'session'
        ..['sessionSeconds'] = 900
        ..['bandSeconds'] = 5400;
      final post = Post.fromMap('p', map) as SessionPost;
      expect(post.bandSeconds, 5400);
      final old = Post.fromMap('p', map..remove('bandSeconds')) as SessionPost;
      expect(old.bandSeconds, isNull);
    });

    test('PostSegment round-trips', () {
      const s = PostSegment(at: 5, seconds: 6, photo: true);
      expect(PostSegment.fromMap(s.toMap()), s);
    });
  });
}
