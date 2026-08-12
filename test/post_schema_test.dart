import 'package:flutter_test/flutter_test.dart';
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
}
