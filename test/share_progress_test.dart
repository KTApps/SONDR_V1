import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/feed/feed_screen.dart';
import 'package:sondr/features/feed/firebase_share_backend.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/share_job.dart';
import 'package:sondr/features/feed/share_progress.dart';

import 'fake_share_backend.dart';
import 'tiny_png.dart';

/// The feed's one line for a share: the upload's progress, "Posted" for a
/// moment, or that it could not post and a word to try again — and the
/// line back after a relaunch, with the job.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('share_progress_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('what the line says', () {
    test('nothing, a share going up, posted, or failed — a failure first', () {
      expect(shareLineOf(const {}), isNull);
      expect(
        shareLineOf(const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 42, totalBytes: 100)}),
        const ShareLine(ShareLineKind.uploading, percent: 42),
      );
      expect(
        shareLineOf(const {'p': ShareJobState(ShareJobStatus.waiting, uploadedBytes: 1, totalBytes: 3)}),
        const ShareLine(ShareLineKind.uploading, percent: 33),
      );
      expect(
        shareLineOf(const {'p': ShareJobState(ShareJobStatus.running)}),
        const ShareLine(ShareLineKind.uploading, percent: 0),
      );
      expect(shareLineOf(const {'p': ShareJobState(ShareJobStatus.posted)}), const ShareLine(ShareLineKind.posted));
      expect(
        shareLineOf(const {
          'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 50, totalBytes: 100),
          'q': ShareJobState(ShareJobStatus.failed),
        }),
        const ShareLine(ShareLineKind.failed),
      );
      // Two going up are one figure.
      expect(
        shareLineOf(const {
          'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 100, totalBytes: 100),
          'q': ShareJobState(ShareJobStatus.running, uploadedBytes: 0, totalBytes: 100),
        }),
        const ShareLine(ShareLineKind.uploading, percent: 50),
      );
    });
  });

  _SpyRunner runner(FakeShareBackend backend, {MemoryShareJobStore? store}) => _SpyRunner(
    store: store ?? MemoryShareJobStore(),
    backend: backend,
    dirFor: (id) async => Directory('${dir.path}/$id')..createSync(recursive: true),
  );

  /// The job's real work — files, the fake's turns — runs outside the
  /// test's fake clock.
  Future<void> untilDone(WidgetTester tester, ShareJobRunner r, String id, {ShareJobStatus? or}) =>
      tester.runAsync(() async {
        for (var i = 0; i < 300 && r.stateOf(id) != null && r.stateOf(id)?.status != or; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

  /// A change of state reaches the widget on the next turn — after the
  /// job's own zone has had its say.
  Future<void> turn(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(Duration.zero);
    await tester.pump();
  }

  Future<void> pumpLine(WidgetTester tester, ShareJobRunner r, {Widget? home}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          shareJobRunnerProvider.overrideWithValue(r),
          feedProvider.overrideWithValue(const AsyncValue.data(<Post>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: home ?? const Scaffold(body: ShareProgressLine()),
        ),
      ),
    );
    await tester.pump();
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  group('the line', () {
    testWidgets('while the upload runs: "Uploading your post 42%", quiet, 13 and semibold', (tester) async {
      final r = runner(FakeShareBackend());
      r.states.value = const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 42, totalBytes: 100)};
      await pumpLine(tester, r);
      expect(find.text('Uploading your post 42%'), findsOneWidget);
      final style = tester.widget<Text>(find.text('Uploading your post 42%')).style!;
      expect(style.fontSize, 13 * figmaScale(tester.element(find.text('Uploading your post 42%'))));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, GreyscaleTokens.dark.textSecondary);
      // It moves.
      r.states.value = const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 90, totalBytes: 100)};
      await turn(tester);
      expect(find.text('Uploading your post 90%'), findsOneWidget);
    });

    testWidgets('when the post lands: "Posted", bright, for two seconds, then it fades', (tester) async {
      final r = runner(FakeShareBackend());
      r.states.value = const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 1, totalBytes: 2)};
      await pumpLine(tester, r);
      r.states.value = const {'p': ShareJobState(ShareJobStatus.posted)};
      await turn(tester);
      expect(find.text(kPostedText), findsOneWidget);
      expect(colorOf(tester, kPostedText), GreyscaleTokens.dark.textPrimary);
      // The job finishes and its state goes; the word stays its two seconds.
      r.states.value = const {};
      await turn(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(kPostedText), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
      await tester.pump(kPostedFade);
      await tester.pump();
      expect(find.text(kPostedText), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a post that lands and is done between two frames still gets its "Posted"', (tester) async {
      final r = runner(FakeShareBackend());
      r.states.value = const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 1, totalBytes: 2)};
      await pumpLine(tester, r);
      r.states.value = const {};
      await turn(tester);
      expect(find.text(kPostedText), findsOneWidget);
      await tester.pump(kPostedHold + kPostedFade + const Duration(milliseconds: 50));
    });

    testWidgets('when it gives up: "Couldn’t post · Try again", and the word tries the jobs again', (tester) async {
      final backend = FakeShareBackend()..failAt = 'createPost'..failTimes = 99;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      final shot = File('${dir.path}/shot.jpg')..writeAsBytesSync(tinyPng);
      await tester.runAsync(() => r.begin(ShareJob(
        postId: 'p', type: PostType.session, taskId: 't', taskName: 'Spanish',
        sessionSeconds: 60, cumulativeSeconds: 60, createdAtMs: 1,
        photos: [ShareJobPhoto(id: 't_1', localPath: shot.path, isNew: true)],
      )));
      await untilDone(tester, r, 'p', or: ShareJobStatus.failed);
      expect(r.stateOf('p')?.status, ShareJobStatus.failed);
      expect(backend.posts, isEmpty);
      await pumpLine(tester, r);
      final rich = find.byWidgetPredicate(
        (w) => w is Text && w.textSpan != null && w.textSpan!.toPlainText() == kCouldNotPostText + kTryAgainText,
      );
      expect(rich, findsOneWidget);
      final span = tester.widget<Text>(rich).textSpan as TextSpan;
      expect(span.style?.color, GreyscaleTokens.dark.textSecondary);
      final tryAgain = span.children!.single as TextSpan;
      expect(tryAgain.text, kTryAgainText);
      expect(tryAgain.style?.color, GreyscaleTokens.dark.textPrimary);
      expect(tryAgain.style?.fontWeight, FontWeight.w700);
      // The last word is the tap: at the right end of the line. It asks
      // the runner for every failed job again — what that does is the
      // runner's own test.
      final rect = tester.getRect(rich);
      await tester.tapAt(Offset(rect.right - 8, rect.center.dy));
      await tester.pump();
      expect(r.retriedFailed, 1);
      // And nowhere else on the line is.
      await tester.tapAt(Offset(rect.left + 8, rect.center.dy));
      await tester.pump();
      expect(r.retriedFailed, 1);
    });

    testWidgets('after a relaunch with a job unfinished, the line is back and the job runs on', (tester) async {
      final backend = FakeShareBackend()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      final shot = File('${dir.path}/shot.jpg')..writeAsBytesSync(tinyPng);
      final job = ShareJob(
        postId: 'p', type: PostType.session, taskId: 't', taskName: 'Spanish',
        sessionSeconds: 60, cumulativeSeconds: 60, createdAtMs: 1,
        photos: [ShareJobPhoto(id: 't_1', localPath: shot.path, isNew: true)],
      );
      await tester.runAsync(() async => store.save(await runner(backend).prepare(job)));
      // The next launch: a fresh runner over the same record.
      final r = runner(backend, store: store);
      await pumpLine(tester, r);
      expect(find.byType(Text), findsNothing);
      await tester.runAsync(() => r.resume());
      await turn(tester);
      expect(find.text('Uploading your post 0%'), findsOneWidget);
      await tester.runAsync(() async => backend.holdUploads!.complete());
      await untilDone(tester, r, 'p');
      await turn(tester);
      expect(backend.posts.keys, ['p']);
      expect(find.text(kPostedText), findsOneWidget);
      await tester.pump(kPostedHold + kPostedFade + const Duration(milliseconds: 50));
    });

    testWidgets('nothing to say: nothing drawn', (tester) async {
      await pumpLine(tester, runner(FakeShareBackend()));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('in the feed', () {
    testWidgets('at the left of the row "Notifications" ends, on the same line', (tester) async {
      final r = runner(FakeShareBackend());
      r.states.value = const {'p': ShareJobState(ShareJobStatus.running, uploadedBytes: 42, totalBytes: 100)};
      await pumpLine(tester, r, home: const FeedScreen());
      await tester.pump();
      final line = tester.getRect(find.text('Uploading your post 42%'));
      final word = tester.getRect(find.text('Notifications'));
      final scale = figmaScale(tester.element(find.text('Notifications')));
      expect(line.left, closeTo(16 * scale, 0.01));
      expect(word.right, closeTo(390 - 16 * scale, 0.01));
      expect(line.bottom, closeTo(word.bottom, 0.5));
      final a = tester.widget<Text>(find.text('Uploading your post 42%')).style!;
      final b = tester.widget<Text>(find.text('Notifications')).style!;
      expect(a.fontSize, b.fontSize);
      expect(a.fontWeight, b.fontWeight);
    });
  });
}

/// A runner that counts how often the line asks for the failed jobs again.
class _SpyRunner extends ShareJobRunner {
  _SpyRunner({required super.store, required super.backend, required super.dirFor})
    : super(
        encoder: NoEncode(),
        cached: (_) async => null,
        backoff: const [Duration.zero, Duration.zero, Duration.zero],
      );

  int retriedFailed = 0;

  @override
  Future<void> retryFailed() async {
    retriedFailed++;
  }
}
