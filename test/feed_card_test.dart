import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/session_log_card.dart';
import 'package:sondr/features/feed/widgets/streak_card.dart';

const _author = PostAuthor(username: 'tom', displayName: 'Tom Hardy');

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('MilestoneCard (no photo) shows the hours figure and badge',
      (tester) async {
    await _pump(
      tester,
      MilestoneCard(
        post: MilestonePost(
          id: 'm',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'done',
          photoUrl: null,
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

  testWidgets('MilestoneCard (with photo) builds over a backdrop',
      (tester) async {
    await _pump(
      tester,
      MilestoneCard(
        post: MilestonePost(
          id: 'm',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: 'done',
          photoUrl: 'assets/mock/sample1.jpg',
          taskName: 'Spanish',
          milestoneHours: 40,
          totalHours: 41,
        ),
      ),
    );
    expect(find.byType(MilestoneCard), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
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
          photoUrl: null,
          streakDays: 14,
          habits: const ['Run', 'Cold shower'],
        ),
      ),
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('day habit streak'), findsOneWidget);
    expect(find.textContaining('Run'), findsOneWidget);
  });

  testWidgets('SessionLogCard renders the one-line summary', (tester) async {
    await _pump(
      tester,
      SessionLogCard(
        post: SessionPost(
          id: 'l',
          authorUid: 'u',
          author: _author,
          createdAt: DateTime(2026, 6, 1),
          caption: null,
          photoUrl: null,
          taskName: 'Spanish',
          sessionSeconds: 8100,
        ),
      ),
    );
    expect(find.textContaining('logged'), findsOneWidget);
    expect(find.textContaining('2h 15m'), findsOneWidget);
  });
}
