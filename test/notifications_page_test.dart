import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/friends/audience_widen.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/notifications/notifications_page.dart';
import 'package:sondr/features/notifications/notifications_repository.dart';
import 'package:sondr/features/profile/profile_action_bar.dart';

/// The word on the Feed, and the page it opens.
void main() {
  // Midday today, not the clock: at a few minutes past midnight a like
  // five minutes before now fell on yesterday, and the folding failed.
  final today = DateTime.now();
  final now = DateTime(today.year, today.month, today.day, 12);
  AppNotification n(String id, NotificationType type, {DateTime? at, String handle = 'cass', String? postId}) =>
      AppNotification(id: id, type: type, actorUid: 'u_$handle', actorHandle: handle, at: at ?? now, postId: postId);

  // The reference phone, so the type scale is the app's 0.9906.
  const w = 390.0, h = 844.0, scale = 0.9906137184115524;
  Future<void> pumpEntry(WidgetTester tester, {required bool unread}) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
    ProviderScope(
      overrides: [hasUnreadNotificationsProvider.overrideWithValue(unread)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Column(
            children: [NotificationsEntry(), Expanded(child: SizedBox(key: Key('feed')))],
          ),
        ),
      ),
    ),
  );
  }

  group('the word on the Feed', () {
    testWidgets('quiet with nothing new; white with a dot when there is', (tester) async {
      await pumpEntry(tester, unread: false);
      final quiet = tester.widget<Text>(find.text('Notifications'));
      expect(quiet.style?.color, const Color(0xFF6E6E6E));
      expect(quiet.style?.fontSize, closeTo(13 * scale, 0.05));
      expect(find.byType(Container), findsNothing);

      await pumpEntry(tester, unread: true);
      final loud = tester.widget<Text>(find.text('Notifications'));
      expect(loud.style?.color, const Color(0xFFFAFAFA));
      final dot = tester.widget<Container>(find.byType(Container));
      expect((dot.decoration as BoxDecoration).shape, BoxShape.circle);
      expect(tester.getSize(find.byType(Container)).width, closeTo(6 * scale, 0.05));
    });

    testWidgets('sits top right; the feed starts exactly below its row', (tester) async {
      await pumpEntry(tester, unread: false);
      final word = tester.getRect(find.text('Notifications'));
      final row = tester.getRect(find.byType(NotificationsEntry));
      final feed = tester.getRect(find.byKey(const Key('feed')));
      expect(word.right, closeTo(w - 16 * scale, 0.05), reason: 'inset 16 from the right');
      expect(feed.top, row.bottom, reason: 'the list moves down by the row alone');
      // ignore: avoid_print
      print('ENTRY row height=${row.height} word top=${word.top} right inset=${w - word.right}');
    });
  });

  group('the page', () {
    Future<void> pumpPage(WidgetTester tester, List<AppNotification> items, {FriendsRepository? friends}) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUidProvider.overrideWithValue('me'),
              myNotificationsProvider.overrideWith((ref) => Stream.value(items)),
              if (friends != null) friendsRepositoryProvider.overrideWithValue(friends),
            ],
            child: MaterialApp(theme: AppTheme.dark(), home: const NotificationsPage()),
          ),
        );

    testWidgets('"Nothing yet" when empty, Back in the centre slot', (tester) async {
      await pumpPage(tester, const []);
      await tester.pumpAndSettle();
      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.byType(ProfileActionBar), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('grouped by day, newest first, likes folded', (tester) async {
      await pumpPage(tester, [
        n('a', NotificationType.like, postId: 'p', handle: 'ann'),
        n('b', NotificationType.like, at: now.subtract(const Duration(minutes: 5)), postId: 'p', handle: 'bea'),
        n('c', NotificationType.comment, at: now.subtract(const Duration(days: 1)), postId: 'p'),
        n('d', NotificationType.invite, at: now.subtract(const Duration(days: 5)), handle: 'dee'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.textContaining('and 1 other liked your post'), findsOneWidget);
      expect(find.textContaining('commented on your post'), findsOneWidget);
      expect(find.textContaining('joined from your invite'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Today')).dy,
        lessThan(tester.getTopLeft(find.text('Yesterday')).dy),
      );
    });

    testWidgets('a request offers Accept, and the row says so after', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('me').collection('meta').doc('profile').set({'username': 'ada', 'displayName': 'Ada'});
      await db.collection('friendships').doc(Friendship.pairId('me', 'u_cass')).set({
        'users': ['me', 'u_cass']..sort(), 'requestedBy': 'u_cass', 'status': 'pending',
        'profiles': {'u_cass': {'username': 'cass', 'displayName': 'Cass'}},
      });
      final friends = FriendsRepository(
        db: db, uid: 'me', pruner: _NoPrune(),
        widener: AudienceWidener(uid: 'me', audiences: _NoAudiences(), blocked: () async => const {}),
        notifier: const NoNotificationsWriter(),
      );
      await pumpPage(tester, [n('r', NotificationType.request)], friends: friends);
      await tester.pumpAndSettle();
      expect(find.textContaining('wants to be friends'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.textContaining("You're now friends with cass"), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      final doc = await db.collection('friendships').doc(Friendship.pairId('me', 'u_cass')).get();
      expect(doc.data()?['status'], 'accepted');
    });
  });
}

class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

class _NoAudiences implements WidenableAudiences {
  @override
  dynamic noSuchMethod(Invocation invocation) async => const [];
}
