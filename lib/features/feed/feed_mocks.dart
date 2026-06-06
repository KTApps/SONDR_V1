import 'models/post.dart';

/// Off by default; run `flutter run --dart-define=MOCK_FEED=true` to preview the
/// feed cards on the simulator without needing real friends/posts. Real builds
/// use the live `feedProvider`.
const bool kMockFeed = bool.fromEnvironment('MOCK_FEED');

const _tom = PostAuthor(username: 'tom', displayName: 'Tom Hardy');
const _amara = PostAuthor(username: 'amara', displayName: 'Amara Okafor');
const _kenji = PostAuthor(username: 'kenji', displayName: '');

/// Sample posts covering every card variant: milestone with photo, streak,
/// milestone without photo, and a tiny session log.
List<Post> mockPosts() {
  final now = DateTime.now();
  return [
    MilestonePost(
      id: 'mock-m1',
      authorUid: 'u-tom',
      author: _tom,
      createdAt: now.subtract(const Duration(hours: 2)),
      caption: 'Forty hours into Spanish — starting to dream in it.',
      photoUrl: 'assets/mock/sample1.jpg',
      taskName: 'Spanish',
      milestoneHours: 40,
      totalHours: 41,
    ),
    StreakPost(
      id: 'mock-s1',
      authorUid: 'u-amara',
      author: _amara,
      createdAt: now.subtract(const Duration(hours: 9)),
      caption: 'Two weeks straight.',
      photoUrl: null,
      streakDays: 14,
      habits: ['6AM wake', 'Cold shower', 'Morning run', '50 press-ups'],
    ),
    MilestonePost(
      id: 'mock-m2',
      authorUid: 'u-kenji',
      author: _kenji,
      createdAt: now.subtract(const Duration(days: 1)),
      caption: 'First milestone on piano.',
      photoUrl: null,
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
      photoUrl: null,
      taskName: 'Spanish',
      sessionSeconds: 8100, // 2h 15m
    ),
  ];
}
