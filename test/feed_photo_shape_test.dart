import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/session_card.dart';

/// The feed shows a photo at the shape it was framed and stored at.
///
/// The cards used to pin a height — 300 on one, 460 on the other — which
/// cropped a 3:4 capture a third time, to two ratios nothing else in the app
/// uses.
void main() {
    Future<Rect> pumpCard(WidgetTester tester, Widget card) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: SingleChildScrollView(child: card)),
          ),
        ),
      );
      await tester.pump();
      return tester.getRect(find.byType(AspectRatio).first);
    }

    final photo = const PostPhoto(
      url: 'https://example.test/a.jpg',
      storagePath: 'p/a',
    );

    testWidgets('a session card', (tester) async {
      final rect = await pumpCard(
        tester,
        SessionCard(
          post: SessionPost(
            id: 'p1',
            authorUid: 'u',
            author: const PostAuthor(username: 'tanaka', displayName: 'T'),
            createdAt: DateTime(2026, 10, 14),
            caption: null,
            taskName: 'Spanish',
            sessionSeconds: 3600,
            photos: [photo],
          ),
        ),
      );
      expect(rect.width / rect.height, closeTo(3 / 4, 0.01));
    });

    testWidgets('a milestone card', (tester) async {
      final rect = await pumpCard(
        tester,
        MilestoneCard(
          post: MilestonePost(
            id: 'p2',
            authorUid: 'u',
            author: const PostAuthor(username: 'tanaka', displayName: 'T'),
            createdAt: DateTime(2026, 10, 14),
            caption: null,
            taskName: 'Spanish',
            milestoneHours: 20,
            totalHours: 20,
            photos: [photo],
          ),
        ),
      );
      expect(rect.width / rect.height, closeTo(3 / 4, 0.01));
    });
}
