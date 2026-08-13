import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/post_collage.dart';
import 'package:sondr/features/feed/widgets/session_log_card.dart';
import 'package:sondr/features/feed/widgets/streak_card.dart';

List<PostPhoto> _mockPhotos(int n) => [
  for (var i = 0; i < n; i++)
    const PostPhoto(url: 'assets/mock/sample1.jpg', storagePath: ''),
];

MilestonePost _milestone(List<PostPhoto> photos) => MilestonePost(
  id: 'm',
  authorUid: 'u',
  author: _author,
  createdAt: DateTime(2026, 6, 1),
  caption: 'done',
  photos: photos,
  taskName: 'Spanish',
  milestoneHours: 40,
  totalHours: 41,
);

const _author = PostAuthor(username: 'tom', displayName: 'Tom Hardy');

// Cards now use the interactive PostInteractions (a ConsumerWidget), so a
// ProviderScope is required. With no Firebase the interaction providers resolve
// to empty/null and the affordances simply render inert.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    // Scrollable like the feed's ListView, so a tall multi-photo card doesn't
    // overflow the test viewport.
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('MilestoneCard (no photo) shows the hours figure and badge', (
    tester,
  ) async {
    await _pump(
      tester,
      MilestoneCard(
        post: MilestonePost(
          id: 'm',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'done',
          taskName: 'Spanish',
          milestoneHours: 20,
          totalHours: 21,
        ),
      ),
    );
    expect(find.text('20'), findsOneWidget); // ring centre figure
    expect(find.text('Milestone · 20h'), findsOneWidget);
    expect(find.text('Tom Hardy'), findsWidgets);
  });

  testWidgets('MilestoneCard (with photo) builds over a backdrop', (
    tester,
  ) async {
    await _pump(
      tester,
      MilestoneCard(
        post: MilestonePost(
          id: 'm',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'done',
          photos: const [
            PostPhoto(url: 'assets/mock/sample1.jpg', storagePath: ''),
          ],
          taskName: 'Spanish',
          milestoneHours: 40,
          totalHours: 41,
        ),
      ),
    );
    expect(find.byType(MilestoneCard), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('MilestoneCard (1 photo) uses the backdrop, not a collage', (
    tester,
  ) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(1))));
    expect(find.byType(PostCollage), findsNothing);
    expect(find.text('40'), findsOneWidget); // ring figure over the backdrop
  });

  testWidgets('MilestoneCard (3 photos) renders the collage, no ring', (
    tester,
  ) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(3))));
    expect(find.byType(PostCollage), findsOneWidget);
    expect(find.text('Milestone · 40h'), findsOneWidget); // badge carries it
    expect(find.text('40'), findsNothing); // ring figure gone
  });

  testWidgets('PostCollage caps at 9 tiles with a +N overflow', (tester) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(12))));
    expect(find.byType(PostCollage), findsOneWidget);
    expect(find.text('+3'), findsOneWidget); // 12 - 9
  });

  testWidgets('PostCollage at exactly 9 shows no overflow', (tester) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(9))));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('StreakCard makes the streak number the hero', (tester) async {
    await _pump(
      tester,
      StreakCard(
        post: StreakPost(
          id: 's',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: null,
          streakDays: 14,
          habits: const ['Run', 'Cold shower'],
        ),
      ),
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('day habit streak'), findsOneWidget);
    expect(find.textContaining('Run'), findsOneWidget);
  });

  testWidgets('SessionLogCard (no photo) renders the slim middot line', (
    tester,
  ) async {
    await _pump(
      tester,
      SessionLogCard(
        post: SessionPost(
          id: 'l',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: null,
          taskName: 'Spanish',
          sessionSeconds: 8100, // 2h 15m
        ),
      ),
    );
    expect(find.text('Tom Hardy · Spanish · 2h 15m'), findsOneWidget);
    expect(find.textContaining('logged'), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing); // no interactions
  });

  testWidgets('SessionLogCard (no photo) shows the caption as a second line', (
    tester,
  ) async {
    await _pump(
      tester,
      SessionLogCard(
        post: SessionPost(
          id: 'lc',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'grinding away',
          taskName: 'Spanish',
          sessionSeconds: 8100,
        ),
      ),
    );
    expect(find.text('Tom Hardy · Spanish · 2h 15m'), findsOneWidget);
    expect(find.text('grinding away'), findsOneWidget); // caption line
  });

  testWidgets('SessionLogCard (no photo) rounds :30 up in the slim line', (
    tester,
  ) async {
    await _pump(
      tester,
      SessionLogCard(
        post: SessionPost(
          id: 'l2',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: null,
          taskName: 'Spanish',
          sessionSeconds: 3629, // 1h 0m 29s -> "1h"
        ),
      ),
    );
    expect(find.text('Tom Hardy · Spanish · 1h'), findsOneWidget);
  });

  testWidgets('SessionLogCard (with photo) renders the photo + interactions', (
    tester,
  ) async {
    await _pump(
      tester,
      SessionLogCard(
        post: SessionPost(
          id: 'l3',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'nice',
          taskName: 'Spanish',
          sessionSeconds: 3600, // 1h
          photos: const [
            PostPhoto(url: 'assets/mock/sample1.jpg', storagePath: ''),
          ],
        ),
      ),
    );
    expect(find.byType(Image), findsWidgets); // the session photo renders
    expect(find.byIcon(Icons.favorite_border), findsOneWidget); // like/comment
    expect(find.text('Spanish · 1h'), findsOneWidget);
    expect(find.textContaining('logged'), findsNothing);
  });
}
