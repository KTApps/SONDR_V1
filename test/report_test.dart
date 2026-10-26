import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/reports/report.dart';
import 'package:sondr/features/reports/report_flow.dart';

import 'support/app_viewport.dart';

/// Reporting something, and what the reporter stops seeing.
///
/// Two separate things on purpose. The report is a write-only message to us
/// — the app can never read one back. Hiding is a document in the
/// reporter's own space, so it survives offline and so a report that fails
/// hides nothing. Everything below is one of those two halves.

/// A report we can inspect, for the sheet's tests.
class _RecordingReports implements Reports {
  _RecordingReports({this.sends = true});

  final bool sends;
  final List<String> sent = [];
  final List<String> hidden = [];

  @override
  Future<bool> send({
    required ReportTarget type,
    required String targetKey,
    required String targetOwnerUid,
    required ReportReason reason,
  }) async {
    if (!sends) return false;
    sent.add('${type.wire}|$targetKey|$targetOwnerUid|${reason.wire}');
    return true;
  }

  @override
  Future<void> hide(ReportTarget type, String targetKey) async {
    if (type == ReportTarget.user) return;
    hidden.add(hiddenKey(type, targetKey));
  }
}

Map<String, dynamic> _postDoc(String author, {String name = 'Golf'}) => {
  'type': 'session',
  'authorUid': author,
  'author': {'username': author},
  'audience': ['me', author],
  'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
  'taskName': name,
  'sessionSeconds': 600,
};

Map<String, dynamic> _commentDoc(String author, String text) => {
  'authorUid': author,
  'author': {'username': author},
  'audience': ['me', author],
  'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
  'text': text,
};

void main() {
  group('what a report is filed as', () {
    test('a post is its id; a comment is its post and itself', () {
      expect(
        reportTargetKey(type: ReportTarget.post, id: 'p1'),
        'p1',
      );
      expect(
        reportTargetKey(type: ReportTarget.comment, id: 'c1', postId: 'p1'),
        'p1/c1',
      );
      expect(reportTargetKey(type: ReportTarget.user, id: 'them'), 'them');
    });

    test('the id is the reporter, the type and the key — slashes swapped', () {
      expect(
        reportId(reporterUid: 'me', type: ReportTarget.post, targetKey: 'p1'),
        'me__post__p1',
      );
      // A document id cannot hold a slash, so the comment's key loses it
      // HERE and keeps it in the field a moderator reads.
      expect(
        reportId(
          reporterUid: 'me',
          type: ReportTarget.comment,
          targetKey: 'p1/c1',
        ),
        'me__comment__p1_c1',
      );
      expect(
        reportId(reporterUid: 'me', type: ReportTarget.user, targetKey: 'them'),
        'me__user__them',
      );
    });

    test('a hidden thing is filed by type and key, no reporter', () {
      expect(hiddenKey(ReportTarget.post, 'p1'), 'post__p1');
      expect(hiddenKey(ReportTarget.comment, 'p1/c1'), 'comment__p1_c1');
    });

    test('a refused write means we already have it, nothing else does', () {
      expect(
        reportAlreadyHeld(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
        isTrue,
      );
      expect(
        reportAlreadyHeld(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
    });
  });

  group('the write itself', () {
    late FakeFirebaseFirestore db;
    late FirestoreReports reports;

    setUp(() {
      db = FakeFirebaseFirestore();
      reports = FirestoreReports(db: db, uid: 'me');
    });

    test('a reported post: the id, and the six fields', () async {
      expect(
        await reports.send(
          type: ReportTarget.post,
          targetKey: 'p1',
          targetOwnerUid: 'them',
          reason: ReportReason.spam,
        ),
        isTrue,
      );

      final snap = await db.collection('reports').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.single.id, 'me__post__p1');
      final data = snap.docs.single.data();
      expect(data.keys.toSet(), {
        'reporterUid',
        'targetType',
        'targetKey',
        'targetOwnerUid',
        'reason',
        'createdAt',
      });
      expect(data['reporterUid'], 'me');
      expect(data['targetType'], 'post');
      expect(data['targetKey'], 'p1');
      expect(data['targetOwnerUid'], 'them');
      expect(data['reason'], 'spam');
      expect(data['createdAt'], isNotNull);
    });

    test('a reported comment keeps the readable key in the field', () async {
      await reports.send(
        type: ReportTarget.comment,
        targetKey: 'p1/c1',
        targetOwnerUid: 'them',
        reason: ReportReason.hate,
      );
      final doc = await db.collection('reports').doc('me__comment__p1_c1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['targetKey'], 'p1/c1');
      expect(doc.data()!['targetType'], 'comment');
    });

    test('telling us twice is still a success, and still one report', () async {
      for (var i = 0; i < 2; i++) {
        expect(
          await reports.send(
            type: ReportTarget.post,
            targetKey: 'p1',
            targetOwnerUid: 'them',
            reason: ReportReason.spam,
          ),
          isTrue,
          reason: 'report $i',
        );
      }
      expect((await db.collection('reports').get()).docs.length, 1);
    });

    test('hiding is the reporter\'s own document', () async {
      await reports.hide(ReportTarget.post, 'p1');
      await reports.hide(ReportTarget.comment, 'p1/c1');
      final hidden = await db
          .collection('users')
          .doc('me')
          .collection('hidden')
          .get();
      expect(
        {for (final d in hidden.docs) d.id},
        {'post__p1', 'comment__p1_c1'},
      );
    });

    test('reporting a PERSON hides nothing — blocking does that', () async {
      await reports.send(
        type: ReportTarget.user,
        targetKey: 'them',
        targetOwnerUid: 'them',
        reason: ReportReason.other,
      );
      await reports.hide(ReportTarget.user, 'them');
      expect((await db.collection('reports').get()).docs.length, 1);
      final hidden = await db
          .collection('users')
          .doc('me')
          .collection('hidden')
          .get();
      expect(hidden.docs, isEmpty);
    });
  });

  group('the reason sheet', () {
    late _RecordingReports reports;
    late ReportOutcome? outcome;

    Future<void> pumpSheet(
      WidgetTester tester, {
      ReportTarget type = ReportTarget.post,
      String targetKey = 'p1',
      bool sends = true,
    }) async {
      useReferenceViewport(tester);
      reports = _RecordingReports(sends: sends);
      outcome = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [reportsProvider.overrideWithValue(reports)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      outcome = await reportThing(
                        context,
                        ref,
                        type: type,
                        targetKey: targetKey,
                        targetOwnerUid: 'them',
                        title: reportTitle(type, handle: '@them'),
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks why, with five answers and a way out', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Report post'), findsOneWidget);
      expect(find.text('Why are you reporting this?'), findsOneWidget);
      for (final r in ReportReason.values) {
        expect(find.text(r.label), findsOneWidget, reason: r.wire);
      }
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('a reason sends the report and hides the post', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Nudity or sexual content'));
      await tester.pumpAndSettle();

      expect(reports.sent, ['post|p1|them|sexual']);
      expect(reports.hidden, ['post__p1']);
      expect(outcome, ReportOutcome.sent);
    });

    testWidgets('a reported comment names its post and itself', (tester) async {
      await pumpSheet(
        tester,
        type: ReportTarget.comment,
        targetKey: 'p1/c1',
      );
      expect(find.text('Report comment'), findsOneWidget);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(reports.sent, ['comment|p1/c1|them|spam']);
      expect(reports.hidden, ['comment__p1_c1']);
    });

    testWidgets('a reported person is named, and nothing is hidden', (
      tester,
    ) async {
      await pumpSheet(tester, type: ReportTarget.user, targetKey: 'them');
      expect(find.text('Report @them'), findsOneWidget);
      await tester.tap(find.text('Violence'));
      await tester.pumpAndSettle();
      expect(reports.sent, ['user|them|them|violence']);
      expect(reports.hidden, isEmpty);
      expect(outcome, ReportOutcome.sent);
    });

    testWidgets('Cancel writes nothing and hides nothing', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(reports.sent, isEmpty);
      expect(reports.hidden, isEmpty);
      expect(outcome, ReportOutcome.cancelled);
    });

    testWidgets('a report that fails hides nothing', (tester) async {
      await pumpSheet(tester, sends: false);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(reports.hidden, isEmpty, reason: 'it hid a post it never sent');
      expect(outcome, ReportOutcome.failed);
    });

    testWidgets('no backend at all is a failure, not a silent hide', (
      tester,
    ) async {
      useReferenceViewport(tester);
      ReportOutcome? result;
      await tester.pumpWidget(
        ProviderScope(
          // reportsProvider is null on the local backend and before a uid
          // exists. Nothing is written, and nothing is hidden.
          overrides: [reportsProvider.overrideWithValue(null)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async => result = await reportThing(
                      context,
                      ref,
                      type: ReportTarget.post,
                      targetKey: 'p1',
                      targetOwnerUid: 'them',
                      title: 'Report post',
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(result, ReportOutcome.failed);
    });

    testWidgets('the thanks and the failure say the same thing everywhere', (
      tester,
    ) async {
      expect(kReportThanks, "Thanks. We'll review this within 24 hours.");
      expect(kReportFailed, "Couldn't send that report. Please try again.");
    });
  });

  group('a hidden thing leaves every surface it was on', () {
    late FakeFirebaseFirestore db;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('posts').doc('p1').set(_postDoc('them'));
      await db.collection('posts').doc('p2').set(_postDoc('them', name: 'Run'));
      await db
          .collection('posts')
          .doc('p1')
          .collection('comments')
          .doc('c1')
          .set(_commentDoc('them', 'first'));
      await db
          .collection('posts')
          .doc('p1')
          .collection('comments')
          .doc('c2')
          .set(_commentDoc('them', 'second'));
    });

    ProviderContainer containerWith(Set<String> hidden) {
      final c = ProviderContainer(
        overrides: [
          postsRepositoryProvider.overrideWithValue(
            PostsRepository(db: db, uid: 'me'),
          ),
          hiddenThingsProvider.overrideWith((ref) => Stream.value(hidden)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// A provider nobody listens to is paused, so every read below holds a
    /// subscription first.
    /// `p` is dynamic because Riverpod 3 does not export a name for "a
    /// provider you can listen to", and the three surfaces are three
    /// different provider types.
    Future<List<T>> settle<T>(ProviderContainer c, dynamic p) async {
      c.listen<AsyncValue<List<T>>>(p, (_, _) {});
      for (var i = 0; i < 20; i++) {
        final value = c.read<AsyncValue<List<T>>>(p);
        if (value.hasValue && !value.isLoading) return value.requireValue;
        await Future<void>.delayed(Duration.zero);
      }
      return c.read<AsyncValue<List<T>>>(p).requireValue;
    }

    test('nothing hidden: both posts, both comments', () async {
      final c = containerWith(const {});
      expect(
        [for (final p in await settle<Post>(c, feedProvider)) p.id],
        ['p1', 'p2'],
      );
      expect(
        [for (final x in await settle<Comment>(c, postCommentsProvider('p1'))) x.id],
        ['c1', 'c2'],
      );
      expect(
        [for (final p in await settle<Post>(c, profilePostsProvider('them'))) p.id],
        ['p1', 'p2'],
      );
    });

    test('a reported post is gone from the feed', () async {
      final c = containerWith({'post__p1'});
      expect(
        [for (final p in await settle<Post>(c, feedProvider)) p.id],
        ['p2'],
      );
    });

    test("a reported post is gone from its author's Posts", () async {
      final c = containerWith({'post__p1'});
      expect(
        [for (final p in await settle<Post>(c, profilePostsProvider('them'))) p.id],
        ['p2'],
      );
    });

    test('a reported comment is gone from the thread', () async {
      final c = containerWith({'comment__p1_c1'});
      expect(
        [for (final x in await settle<Comment>(c, postCommentsProvider('p1'))) x.id],
        ['c2'],
      );
    });

    test('a reported PERSON hides nothing of theirs', () async {
      final c = containerWith({'user__them'});
      expect(
        [for (final p in await settle<Post>(c, feedProvider)) p.id],
        ['p1', 'p2'],
      );
      expect(
        [for (final p in await settle<Post>(c, profilePostsProvider('them'))) p.id],
        ['p1', 'p2'],
      );
    });

    test('a hidden list that cannot be read shows everything', () async {
      final c = ProviderContainer(
        overrides: [
          postsRepositoryProvider.overrideWithValue(
            PostsRepository(db: db, uid: 'me'),
          ),
          hiddenThingsProvider.overrideWith(
            (ref) => Stream<Set<String>>.error(Exception('denied')),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(
        [for (final p in await settle<Post>(c, feedProvider)) p.id],
        ['p1', 'p2'],
        reason: 'it must fail OPEN — a blank feed is far worse',
      );
    });

    test('the filter itself keeps order and drops only matches', () {
      final kept = withoutHidden(
        ['a', 'b', 'c'],
        {'post__b'},
        (s) => hiddenKey(ReportTarget.post, s),
      );
      expect(kept, ['a', 'c']);
      expect(withoutHidden(['a'], const {}, (s) => s), ['a']);
    });
  });
}
