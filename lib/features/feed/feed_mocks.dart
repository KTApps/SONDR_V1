import 'models/post.dart';

/// Off by default; run `flutter run --dart-define=MOCK_FEED=true` to preview the
/// feed cards on the simulator without needing real friends/posts. Real builds
/// use the live `feedProvider`.
const bool kMockFeed = bool.fromEnvironment('MOCK_FEED');

const _tom = PostAuthor(username: 'tom', displayName: 'Tom Hardy');
const _amara = PostAuthor(username: 'amara', displayName: 'Amara Okafor');
const _kenji = PostAuthor(username: 'kenji', displayName: '');

/// [n] mock photos alternating the two bundled samples (enough to exercise every
/// collage bucket; the images repeat — the layout is what's being previewed).
List<PostPhoto> _photos(int n) => [
  for (var i = 0; i < n; i++)
    PostPhoto(
      url: i.isEven ? 'assets/mock/sample1.jpg' : 'assets/mock/sample2.jpg',
      storagePath: '',
    ),
];

/// Sample posts covering every card variant, incl. the multi-photo collage
/// buckets (1 / 2 / 3 / 4 / 9+). A 1-photo and a 3-photo milestone sit adjacent
/// so the single-photo backdrop and the collage card read as one card family.
List<Post> mockPosts() {
  final now = DateTime.now();
  return [
    MilestonePost(
      id: 'mock-m1',
      authorUid: 'u-tom',
      author: _tom,
      createdAt: now.subtract(const Duration(hours: 2)),
      caption: 'Forty hours into Spanish — starting to dream in it.',
      photos: _photos(1),
      taskName: 'Spanish',
      milestoneHours: 40,
      totalHours: 41,
    ),
    MilestonePost(
      id: 'mock-m3',
      authorUid: 'u-amara',
      author: _amara,
      createdAt: now.subtract(const Duration(hours: 3)),
      caption: 'Sixty hours of pottery — a few from the wheel.',
      photos: _photos(3),
      taskName: 'Pottery',
      milestoneHours: 60,
      totalHours: 61,
    ),
    MilestonePost(
      id: 'mock-m2b',
      authorUid: 'u-tom',
      author: _tom,
      createdAt: now.subtract(const Duration(hours: 4)),
      caption: null,
      photos: _photos(2),
      taskName: 'Climbing',
      milestoneHours: 20,
      totalHours: 20,
    ),
    MilestonePost(
      id: 'mock-m4',
      authorUid: 'u-kenji',
      author: _kenji,
      createdAt: now.subtract(const Duration(hours: 5)),
      caption: 'A 2×2 of the build.',
      photos: _photos(4),
      taskName: 'Woodworking',
      milestoneHours: 40,
      totalHours: 42,
    ),
    MilestonePost(
      id: 'mock-m12',
      authorUid: 'u-amara',
      author: _amara,
      createdAt: now.subtract(const Duration(hours: 6)),
      caption: 'A hundred hours — the whole journey.',
      photos: _photos(12),
      taskName: 'Painting',
      milestoneHours: 100,
      totalHours: 101,
    ),
    StreakPost(
      id: 'mock-s1',
      authorUid: 'u-amara',
      author: _amara,
      createdAt: now.subtract(const Duration(hours: 9)),
      caption: 'Two weeks straight.',
      streakDays: 14,
      habits: ['6AM wake', 'Cold shower', 'Morning run', '50 press-ups'],
    ),
    MilestonePost(
      id: 'mock-m2',
      authorUid: 'u-kenji',
      author: _kenji,
      createdAt: now.subtract(const Duration(days: 1)),
      caption: 'First milestone on piano.',
      taskName: 'Piano',
      milestoneHours: 20,
      totalHours: 20,
    ),
    SessionPost(
      id: 'mock-l1',
      authorUid: 'u-tom',
      author: _tom,
      createdAt: now.subtract(const Duration(days: 2)),
      caption: null,
      taskName: 'Spanish',
      sessionSeconds: 8100, // 2h 15m
    ),
  ];
}
