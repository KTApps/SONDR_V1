import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';
import 'package:sondr/features/feed/widgets/session_log_card.dart';

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

// Cards use the interactive PostInteractions (a ConsumerWidget), so a
// ProviderScope is required. With no Firebase the interaction providers resolve
// to empty/null and the affordances simply render inert.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    // Scrollable like the feed's ListView.
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('MilestoneCard (no photo) shows the hours in the ring, the handle and the task', (
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
    expect(find.text('hours'), findsOneWidget);
    expect(find.text('tom'), findsOneWidget); // the handle, not the display name
    expect(find.text('Spanish'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(MilestoneRing), findsOneWidget);
  });

  testWidgets('MilestoneCard (with photo) builds over the photo', (
    tester,
  ) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(1))));
    expect(find.byType(MilestoneCard), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('MilestoneCard (3 photos, no sessions) is one frame: the collage, the ring', (
    tester,
  ) async {
    await _pump(tester, MilestoneCard(post: _milestone(_mockPhotos(3))));
    expect(find.byType(PageView), findsNothing); // no swiping: a tap steps
    expect(find.text('40'), findsOneWidget); // the ring stays, solid
    expect(find.textContaining('Milestone ·'), findsNothing); // no badge any more
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
    expect(find.textContaining('Logged'), findsNothing);
    expect(find.text('Like'), findsNothing); // no interactions
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
    expect(find.text('Like'), findsOneWidget); // like/comment are text now
    expect(find.text('Spanish · 1h'), findsOneWidget);
    expect(find.textContaining('Logged'), findsNothing);
  });
}
