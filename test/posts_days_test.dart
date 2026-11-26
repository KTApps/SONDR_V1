import 'package:flutter/material.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/feed/feed_days.dart';
import 'package:sondr/features/feed/milestone_hints.dart';
import 'package:sondr/features/feed/milestone_pages.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/share_job.dart';
import 'package:sondr/features/feed/widgets/day_card.dart';
import 'package:sondr/features/feed/widgets/deletable_post_card.dart';
import 'package:sondr/features/feed/widgets/feed_view.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/post_card_chrome.dart';
import 'package:sondr/features/feed/widgets/post_chrome.dart' show kTextShadows;
import 'package:sondr/features/feed/widgets/session_card.dart';
import 'package:sondr/shared/blur_sheet.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// The Posts tab as days: a friend's last 24 hours on one card, every
/// milestone on its own, the line above each, and the two ways a long-press
/// takes something down.
void main() {
  final now = DateTime(2026, 11, 26, 12);
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  const tom = PostAuthor(username: 'tom', displayName: 'Tom');

  SessionPost shot(
    String id, {
    String author = 'cass-uid',
    PostAuthor who = cass,
    Duration ago = const Duration(hours: 1),
    int seconds = 1800,
    bool first = false,
    bool unstamped = false,
  }) => SessionPost(
    id: id,
    authorUid: author,
    author: who,
    createdAt: unstamped ? null : now.subtract(ago),
    caption: null,
    photos: [PostPhoto(url: 'https://x/$id.jpg', storagePath: id)],
    taskName: 'Golf',
    sessionSeconds: seconds,
    bandSeconds: seconds,
    firstSession: first,
  );

  MilestonePost milestone(
    String id, {
    Duration ago = const Duration(days: 28),
    List<PostPhoto>? photos,
    String author = 'cass-uid',
  }) => MilestonePost(
    id: id,
    authorUid: author,
    author: cass,
    createdAt: now.subtract(ago),
    caption: null,
    photos: photos ?? const [],
    taskName: 'Guitar',
    milestoneHours: 20,
    totalHours: 20,
  );

  late ImageProvider Function(String) factoryBefore;
  setUp(() {
    factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
  });
  tearDown(() => photoImageProviderFactory = factoryBefore);

  group('days', () {
    test('one card per person, their photos newest first; cards by each newest photo', () {
      final items = feedItems([
        shot('c1', ago: const Duration(hours: 3)),
        shot('t1', author: 'tom-uid', who: tom, ago: const Duration(hours: 2)),
        shot('c2', ago: const Duration(minutes: 20)),
        shot('c3', ago: const Duration(hours: 5)),
      ], now: now);
      expect(items.length, 2);
      final first = items[0] as DayItem;
      expect(first.authorUid, 'cass-uid');
      expect([for (final p in first.posts) p.id], ['c2', 'c1', 'c3']);
      expect((items[1] as DayItem).authorUid, 'tom-uid');
    });

    test('a new photo brings that person\'s card to the top', () {
      final before = [
        shot('c1', ago: const Duration(hours: 1)),
        shot('t1', author: 'tom-uid', who: tom, ago: const Duration(hours: 2)),
      ];
      expect((feedItems(before, now: now).first as DayItem).authorUid, 'cass-uid');
      final after = [
        ...before,
        shot('t2', author: 'tom-uid', who: tom, ago: const Duration(minutes: 1)),
      ];
      final top = feedItems(after, now: now).first as DayItem;
      expect(top.authorUid, 'tom-uid');
      expect([for (final p in top.posts) p.id], ['t2', 't1']);
    });

    test('each photo goes 24 hours after it was posted; a day with none left is gone', () {
      final items = feedItems([
        shot('c1', ago: const Duration(hours: 23, minutes: 59)),
        shot('c2', ago: const Duration(hours: 24, minutes: 1)),
        shot('t1', author: 'tom-uid', who: tom, ago: const Duration(hours: 30)),
      ], now: now);
      expect(items.length, 1);
      expect([for (final p in (items.single as DayItem).posts) p.id], ['c1']);
    });

    test('a photo whose server time has not come back is now: first in its day, its day first', () {
      final items = feedItems([
        shot('t1', author: 'tom-uid', who: tom, ago: const Duration(minutes: 5)),
        shot('c1', ago: const Duration(hours: 2)),
        shot('c0', unstamped: true),
      ], now: now);
      final top = items.first as DayItem;
      expect(top.authorUid, 'cass-uid');
      expect(top.posts.first.id, 'c0');
    });

    test('milestones stand alone, kept for good, in time order with the days', () {
      final items = feedItems([
        shot('c1', ago: const Duration(hours: 2)),
        milestone('m-new', ago: const Duration(hours: 1)),
        milestone('m-old', ago: const Duration(days: 300)),
      ], now: now);
      expect([for (final i in items) i.key], ['milestone-m-new', 'day-cass-uid', 'milestone-m-old']);
    });
  });

  group('the two queries, as one list', () {
    test('merged newest first, a milestone in both shown once', () {
      final m = milestone('m1', ago: const Duration(hours: 3));
      final merged = mergeFeedPosts(
        [shot('c1', ago: const Duration(hours: 1)), m],
        [m, milestone('m0', ago: const Duration(days: 9))],
        now: now,
      );
      expect([for (final p in merged) p.id], ['c1', 'm1', 'm0']);
    });

    test('a page more of milestones each time', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(milestoneLimitProvider), kMilestonePageSize);
      c.read(milestoneLimitProvider.notifier).more();
      expect(c.read(milestoneLimitProvider), 2 * kMilestonePageSize);
      expect(kMilestonePageSize, 20);
    });

    test('the last day starts 24 hours ago, and is asked again', () {
      var clock = now;
      final c = ProviderContainer(overrides: [feedNowProvider.overrideWithValue(() => clock)]);
      addTearDown(c.dispose);
      expect(c.read(feedCutoffProvider), now.subtract(const Duration(hours: 24)));
      clock = now.add(const Duration(minutes: 5));
      c.read(feedCutoffProvider.notifier).refresh();
      expect(c.read(feedCutoffProvider), clock.subtract(const Duration(hours: 24)));
      expect(kFeedRefresh, const Duration(minutes: 5));
    });

    testWidgets('scrolling to the end reads the next page of milestones, when there may be one', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late ProviderContainer c;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          feedNowProvider.overrideWithValue(() => now),
          moreMilestonesProvider.overrideWithValue(true),
          milestoneHintsProvider.overrideWithValue(MemoryMilestoneHints(const MilestoneHintState(tapped: true))),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(builder: (context, ref, _) {
            c = ProviderScope.containerOf(context);
            return Scaffold(
              body: FeedView(posts: [
                for (var i = 0; i < 4; i++) milestone('m$i', ago: Duration(days: i + 1)),
              ]),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(c.read(milestoneLimitProvider), 20);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(c.read(milestoneLimitProvider), greaterThan(20));
    });
  });

  group('the line above a card', () {
    test('a day: photos, the time of those posts, how long since the newest', () {
      final day = feedItems([
        shot('c1', ago: const Duration(minutes: 20), seconds: 3600),
        shot('c2', ago: const Duration(hours: 2), seconds: 5400),
      ], now: now).single as DayItem;
      expect(dayLine(day, now: now), '2 photos · 2h 30m · 20m ago');
      final one = feedItems([shot('c1', ago: const Duration(hours: 3), seconds: 600)], now: now).single as DayItem;
      expect(dayLine(one, now: now), '1 photo · 10m · 3h ago');
      final fresh = feedItems([shot('c1', ago: const Duration(seconds: 5))], now: now).single as DayItem;
      expect(dayLine(fresh, now: now), '1 photo · 30m · now');
    });

    test('a milestone: the task and how long since — the ring says the hours', () {
      expect(milestoneLine(milestone('m1'), now: now), 'Guitar · 4w ago');
    });

    test('the name without "@"', () {
      expect(feedName(cass), 'cass');
      expect(feedName(const PostAuthor(username: '@cass', displayName: 'Cass')), 'cass');
      expect(feedName(const PostAuthor(username: '', displayName: 'Cass')), 'Cass');
    });
  });

  group('first time', () {
    ShareJob job({required int seconds, required int total, PostType type = PostType.session}) => ShareJob(
      postId: 'p',
      type: type,
      taskId: 't',
      taskName: 'Golf',
      sessionSeconds: seconds,
      cumulativeSeconds: total,
      createdAtMs: 1,
      photos: const [],
      milestoneHours: type == PostType.milestone ? 20 : null,
    );

    test('stored only when the task had nothing before this session', () {
      expect(job(seconds: 600, total: 600).document('me', cass, ['me'])['firstSession'], isTrue);
      expect(job(seconds: 600, total: 601).document('me', cass, ['me']).containsKey('firstSession'), isFalse);
      // A credit that did not come back reads 0: not a first time.
      expect(job(seconds: 600, total: 0).document('me', cass, ['me']).containsKey('firstSession'), isFalse);
      expect(job(seconds: 72000, total: 72000, type: PostType.milestone).document('me', cass, ['me']).containsKey('firstSession'), isFalse);
    });

    test('read back as stored, never worked out again', () {
      SessionPost read(Map<String, dynamic> m) => Post.fromMap('p', {'type': 'session', ...m}) as SessionPost;
      expect(read({'firstSession': true, 'sessionSeconds': 600}).firstSession, isTrue);
      expect(read({'sessionSeconds': 600}).firstSession, isFalse);
    });
  });

  Future<ProviderContainer> pumpFeed(
    WidgetTester tester,
    Widget child, {
    String uid = 'me',
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late ProviderContainer c;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        feedNowProvider.overrideWithValue(() => now),
        milestoneHintsProvider.overrideWithValue(MemoryMilestoneHints(const MilestoneHintState(tapped: true))),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: Consumer(builder: (context, ref, _) {
          c = ProviderScope.containerOf(context);
          return Scaffold(body: child);
        }),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return c;
  }

  group('a day card', () {
    testWidgets('one photo: the session card at the feed\'s full width, no name on it', (tester) async {
      await pumpFeed(tester, FeedView(posts: [shot('c1')]));
      final r = tester.getRect(find.byType(SessionCard));
      expect(r.left, 16);
      expect(r.width, 390 - 32);
      expect(r.height, closeTo((390 - 32) * 4 / 3, 0.01));
      expect(find.byKey(kDayPagerKey), findsNothing);
      expect(find.descendant(of: find.byType(SessionCard), matching: find.text('cass')), findsNothing);
    });

    testWidgets('several: pages 340 wide, 8 apart, the first on the margin, the next peeking', (tester) async {
      await pumpFeed(tester, FeedView(posts: [shot('c1'), shot('c2', ago: const Duration(hours: 2))]));
      final pages = find.byType(SessionCard);
      expect(pages, findsNWidgets(2));
      final a = tester.getRect(pages.at(0));
      final b = tester.getRect(pages.at(1));
      expect(a.left, 16);
      expect(a.width, 340);
      expect(b.left - a.right, 8);
      expect(b.left, lessThan(390), reason: 'the next page peeks in');
      // Each page keeps the bottom: task line, Like, Comments.
      expect(find.text('Golf · 30m'), findsNWidgets(2));
      expect(find.text('Like'), findsNWidgets(2));
    });

    testWidgets('a swipe snaps one page on, and never two', (tester) async {
      await pumpFeed(tester, FeedView(posts: [
        shot('c1'),
        shot('c2', ago: const Duration(hours: 2)),
        shot('c3', ago: const Duration(hours: 3)),
      ]));
      final row = find.byKey(kDayPagerKey);
      await tester.fling(row, const Offset(-600, 0), 3000);
      await tester.pumpAndSettle();
      final pages = find.byType(SessionCard);
      expect(tester.getRect(pages.at(1)).left, closeTo(16, 0.5));
      // A slow, short drag settles back on the page it began from.
      await tester.timedDrag(row, const Offset(-60, 0), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.getRect(pages.at(1)).left, closeTo(16, 0.5), reason: 'a short drag settles back');
      // The last page settles at the row's end, on the right margin.
      await tester.fling(row, const Offset(-600, 0), 3000);
      await tester.pumpAndSettle();
      expect(tester.getRect(pages.at(2)).right, closeTo(390 - 16, 0.5));
    });

    testWidgets('a new photo arriving keeps the page being looked at', (tester) async {
      final posts = [shot('c1'), shot('c2', ago: const Duration(hours: 2))];
      final day = ValueNotifier<List<Post>>(posts);
      await pumpFeed(tester, ValueListenableBuilder<List<Post>>(
        valueListenable: day,
        builder: (_, p, _) => FeedView(posts: p),
      ));
      await tester.fling(find.byKey(kDayPagerKey), const Offset(-600, 0), 3000);
      await tester.pumpAndSettle();
      Finder page(String id) => find.byKey(ValueKey('page-$id'));
      // The last page, at the row's end.
      expect(tester.getRect(page('c2')).right, closeTo(390 - 16, 0.5));

      day.value = [shot('c0', ago: const Duration(minutes: 1)), ...posts];
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(page('c2')).right, closeTo(390 - 16, 0.5), reason: 'still on c2');
      expect(tester.getRect(page('c0')).right, lessThan(0), reason: 'the new one waits to the left');
    });

    test('the anchoring, pure', () {
      expect(anchoredPage(['a', 'b'], 1, ['n', 'a', 'b']), 2);
      expect(anchoredPage(['a', 'b'], 1, ['a']), 0, reason: 'the page went: the nearest');
      expect(anchoredPage(['a'], 0, const []), 0);
    });

    testWidgets('a long-press on a page is about that post alone', (tester) async {
      await pumpFeed(tester, FeedView(posts: [
        shot('c1', author: 'me'),
        shot('c2', author: 'me', ago: const Duration(hours: 2)),
      ]));
      final second = find.byKey(const ValueKey('page-c2'));
      expect(tester.widget<DeletablePostCard>(second).post.id, 'c2');
      await tester.longPress(find.descendant(of: find.byType(SessionCard).at(0), matching: find.text('Golf · 30m')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this post?'), findsOneWidget);
    });
  });

  group('"First time"', () {
    testWidgets('at the photo\'s top right, 11 semibold, on the task\'s first ever only', (tester) async {
      await pumpFeed(tester, FeedView(posts: [shot('c1', first: true)]));
      final label = find.byKey(kFirstTimeKey);
      expect(tester.widget<Text>(label).data, 'First time');
      final style = tester.widget<Text>(label).style!;
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.shadows, kTextShadows);
      expect(style.color, GreyscaleTokens.of(tester.element(label)).textPrimary);
      final card = tester.getRect(find.byType(SessionCard));
      final at = tester.getRect(label);
      expect(card.right - at.right, closeTo(18, 0.5));
      expect(at.top - card.top, closeTo(16, 0.5));

      await pumpFeed(tester, FeedView(posts: [shot('c1')]));
      expect(find.byKey(kFirstTimeKey), findsNothing);
    });
  });

  group('the header', () {
    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts: name over the card\'s inset, 24 from the card above, nothing overflows', (tester) async {
        await pumpFeed(
          tester,
          FeedView(posts: [
            shot('c1', ago: const Duration(minutes: 20)),
            milestone('m1', ago: const Duration(days: 2)),
          ]),
          textScale: ts,
        );
        final names = find.text('cass');
        expect(names, findsNWidgets(2));
        final firstCard = tester.getRect(find.byType(SessionCard));
        expect(tester.getRect(names.at(0)).left, 16 + 18);
        expect(find.text('1 photo · 30m · 20m ago'), findsOneWidget);
        expect(find.text('Guitar · 2d ago'), findsOneWidget);
        expect(find.textContaining('@'), findsNothing);
        expect(find.textContaining('session'), findsNothing);
        expect(tester.getRect(names.at(1)).top - firstCard.bottom, closeTo(24, 0.5));
        // The tap target is at least 44 tall.
        expect(tester.getSize(find.byKey(kPostHeaderKey).first).height, greaterThanOrEqualTo(44));
        final line = tester.widget<Text>(find.text('Guitar · 2d ago')).style!;
        expect(line.fontSize, 12);
        expect(line.fontWeight, FontWeight.w700);
        expect(line.color, GreyscaleTokens.of(tester.element(names.first)).textSecondary);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a milestone\'s photo pages', () {
    PostPhoto p(String id, {bool page = true}) => PostPhoto(url: 'https://x/$id.jpg', storagePath: id, page: page);

    test('a deleted page is skipped; the photo stays', () {
      final m = milestone('m', photos: [p('a'), p('b', page: false), p('c')]);
      expect(milestonePages(m), const [
        MilestonePage(MilestonePageKind.cover),
        MilestonePage(MilestonePageKind.photo, photoIndex: 0),
        MilestonePage(MilestonePageKind.photo, photoIndex: 2),
      ]);
      expect(m.photos.length, 3, reason: 'still in the collage');
    });

    test('one page left: the cover and that page; none left: the cover alone', () {
      expect(milestonePages(milestone('m', photos: [p('a', page: false), p('b')])), const [
        MilestonePage(MilestonePageKind.cover),
        MilestonePage(MilestonePageKind.photo, photoIndex: 1),
      ]);
      expect(milestonePages(milestone('m', photos: [p('a', page: false), p('b', page: false)])),
          const [MilestonePage(MilestonePageKind.cover)]);
    });

    test('page false round-trips, and is written only when false', () {
      expect(p('a').toMap().containsKey('page'), isFalse);
      expect(p('a', page: false).toMap()['page'], isFalse);
      expect(PostPhoto.fromMap(p('a', page: false).toMap()), p('a', page: false));
      expect(PostPhoto.fromMap(p('a').toMap()).page, isTrue);
      expect(p('a').withoutPage(), p('a', page: false));
    });

    Future<List<int>> holdPage(WidgetTester tester, {required String uid, bool onCover = false}) async {
      final hidden = <int>[];
      final m = milestone('m', author: 'cass-uid', ago: const Duration(hours: 1), photos: [p('a'), p('b'), p('c')]);
      await pumpFeed(
        tester,
        ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            DeletablePostCard(
              post: m,
              onDelete: (_) async {},
              child: MilestoneCard(post: m, onHidePage: (_, i) async => hidden.add(i)),
            ),
          ],
        ),
        uid: uid,
      );
      final r = tester.getRect(find.byType(MilestoneCard));
      if (!onCover) {
        await tester.tapAt(Offset(r.left + r.width * 0.9, r.center.dy));
        await tester.pumpAndSettle();
        await tester.tapAt(Offset(r.left + r.width * 0.9, r.center.dy));
        await tester.pumpAndSettle();
      }
      await tester.longPressAt(r.center);
      await tester.pumpAndSettle();
      return hidden;
    }

    testWidgets('my photo page, held: "Delete this photo?" — the page goes, the photo stays', (tester) async {
      final hidden = await holdPage(tester, uid: 'cass-uid');
      expect(find.text('Delete this photo?'), findsOneWidget);
      expect(find.text("It stays in the milestone's collage."), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Delete this post?'), findsNothing);
      await tester.tap(find.descendant(of: find.byType(BlurSheet), matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(hidden, [1], reason: 'the second photo — the page that was showing');
    });

    testWidgets('the cover, held, is still the whole post', (tester) async {
      await holdPage(tester, uid: 'cass-uid', onCover: true);
      expect(find.text('Delete this post?'), findsOneWidget);
      expect(find.text('Delete this photo?'), findsNothing);
    });

    testWidgets("someone else's photo page, held, is a report, not a delete", (tester) async {
      await holdPage(tester, uid: 'me');
      expect(find.text('Delete this photo?'), findsNothing);
      expect(find.text('Delete this post?'), findsNothing);
    });

    test('the hint says photo, not session', () {
      expect(kMilestoneHintText, 'Tap the right side to see each photo');
    });
  });

  test('the repository writes page false on that one photo only', () async {
    final db = FakeFirebaseFirestore();
    final m = milestone('m', author: 'me', photos: [
      const PostPhoto(url: 'a', storagePath: 'a', sessionIndex: 0),
      const PostPhoto(url: 'b', storagePath: 'b', sessionIndex: 1),
    ]);
    await db.collection('posts').doc('m').set({'photos': [for (final p in m.photos) p.toMap()]});
    await PostsRepository(db: db, uid: 'me').hidePhotoPage(m, 1);
    final stored = (await db.collection('posts').doc('m').get()).data()!['photos'];
    expect(stored, [
      {'url': 'a', 'storagePath': 'a', 'sessionIndex': 0},
      {'url': 'b', 'storagePath': 'b', 'sessionIndex': 1, 'page': false},
    ]);
    expect(() => PostsRepository(db: db, uid: 'someone').hidePhotoPage(m, 0), throwsStateError);
  });
}
