import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/cover_render.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/share_job.dart';
import 'package:sondr/features/feed/share_trace.dart';
import 'package:sondr/features/photos/models/photo.dart';

import 'fake_share_backend.dart';
import 'tiny_png.dart';

/// The share job: prepared on the phone before the review lets go, every
/// file up behind the feed, and the post written ONCE, complete, at the
/// end — and every step safe to run again.
void main() {
  late Directory dir;
  late File shot;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('share_job_test');
    shot = File('${dir.path}/shot.jpg')..writeAsBytesSync(tinyPng);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Directory jobDir(String postId) => Directory('${dir.path}/jobs/$postId');

  Photo band(int ts) => Photo(
    taskId: 't', taskName: 'Spanish', dayKey: '2026-10-01', timestamp: ts,
    sessionSeconds: 60, photoUrl: 'https://x/private/$ts.jpg', storagePath: 'users/me/photos/t_$ts.jpg',
  );

  ShareJob milestone({bool withShot = true, int bandPhotos = 2}) => ShareJob(
    postId: 'post-1',
    type: PostType.milestone,
    taskId: 't',
    taskName: 'Spanish',
    sessionSeconds: 3600,
    cumulativeSeconds: 72000,
    createdAtMs: 1000,
    milestoneHours: 20,
    totalHours: 20,
    caption: 'Twenty.',
    segments: [const PostSegment(at: 1, seconds: 3600)],
    unit: SegmentUnit.session,
    shotTimestamp: withShot ? 999 : null,
    photos: [
      for (var i = 0; i < bandPhotos; i++)
        ShareJobPhoto(
          id: band(i).id,
          sourceStoragePath: band(i).storagePath,
          sourceUrl: band(i).photoUrl,
          sessionIndex: 0,
          framing: const PhotoFraming(scale: 1.2),
        ),
      if (withShot)
        ShareJobPhoto(id: Photo.docId('t', 999), localPath: shot.path, isNew: true, sessionIndex: 0),
    ],
  );

  ShareJobRunner runner(FakeShareBackend backend, {MemoryShareJobStore? store, List<Duration>? backoff}) =>
      ShareJobRunner(
        store: store ?? MemoryShareJobStore(),
        backend: backend,
        dirFor: (id) async => jobDir(id)..createSync(recursive: true),
        encoder: NoEncode(),
        cached: (_) async => null,
        coverStyles: const CoverTextStyles(figure: null, unit: null),
        backoff: backoff ?? const [Duration.zero, Duration.zero, Duration.zero],
      );

  FakeShareBackend withOriginals() {
    final f = FakeShareBackend();
    for (var i = 0; i < 3; i++) {
      f.originals[band(i).storagePath] = tinyPng;
    }
    return f;
  }

  Future<void> settle(ShareJobRunner r, String postId) async {
    for (var i = 0; i < 200 && r.stateOf(postId) != null && r.stateOf(postId)!.status != ShareJobStatus.failed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  const allPaths = {
    'users/me/posts/post-1/0.jpg',
    'users/me/posts/post-1/1.jpg',
    'users/me/posts/post-1/2.jpg',
    'users/me/photos/t_999.jpg',
    'users/me/posts/post-1/cover.jpg',
    'users/me/posts/post-1/thumb.jpg',
  };

  group('prepared before the review lets go', () {
    test('Share returns once the bytes are on the phone and the cover is drawn: no upload, no post yet', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await Future<void>.delayed(Duration.zero);
      // The job is kept, prepared: every photo a file of its own, the
      // cover and the thumbnail beside them.
      final job = store.jobs['post-1']!;
      expect(job.step, ShareStep.prepared);
      expect(File('${jobDir('post-1').path}/0.jpg').existsSync(), isTrue);
      expect(File('${jobDir('post-1').path}/1.jpg').existsSync(), isTrue);
      expect(job.photos[2].localPath, shot.path, reason: 'the shot stays where it was written');
      expect(File(job.coverLocalPath!).existsSync(), isTrue);
      expect(File(job.thumbLocalPath!).existsSync(), isTrue);
      expect(backend.downloads, 2, reason: 'the band photos, fetched once');
      // Nothing has gone up and nothing has been posted.
      expect(backend.uploads, isEmpty);
      expect(backend.posts, isEmpty);
      expect(r.stateOf('post-1')?.status, ShareJobStatus.running);
      backend.holdUploads!.complete();
      await settle(r, 'post-1');
      expect(backend.posts.keys, ['post-1']);
      expect(r.stateOf('post-1'), isNull);
    });

    test('what cannot be prepared fails the share on the screen, and leaves no job', () async {
      final backend = withOriginals()..failAt = 'download'..failTimes = 99;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await expectLater(r.begin(milestone()), throwsStateError);
      expect(store.jobs, isEmpty);
      expect(r.stateOf('post-1'), isNull);
      expect(backend.posts, isEmpty);
    });
  });

  group('the job', () {
    test('uploads by named path, saves the shot privately, writes the post once — complete — then tells the friends', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');

      expect(backend.uploads.keys.toSet(), allPaths);
      expect(backend.uploads.values.every((n) => n == 1), isTrue);
      expect(backend.savedPhotos.single.id, 't_999');
      expect(backend.crossings, [('t', 20, 't_999')]);

      // The post, once, with everything in it.
      expect(backend.calls.where((c) => c == 'createPost').length, 1);
      final doc = backend.posts['post-1']!;
      expect(doc.containsKey('pending'), isFalse);
      expect(doc['audience'], ['me', 'a', 'b']);
      expect(doc['authorUid'], 'me');
      expect(doc['createdAt'], 1000);
      expect(doc['caption'], 'Twenty.');
      expect(doc['milestoneHours'], 20);
      expect(doc['likeCount'], 0);
      expect(doc['coverUrl'], 'https://x/users/me/posts/post-1/cover.jpg');
      expect(doc['thumbUrl'], 'https://x/users/me/posts/post-1/thumb.jpg');
      final photos = doc['photos'] as List;
      expect(photos, hasLength(3));
      expect((photos[2] as Map)['url'], 'https://x/users/me/posts/post-1/2.jpg');
      expect((photos[2] as Map)['storagePath'], 'users/me/posts/post-1/2.jpg');
      expect((photos[0] as Map)['framing'], {'scale': 1.2, 'dx': 0.0, 'dy': 0.0});
      expect(photos.every((p) => (p as Map)['url'].toString().startsWith('https://')), isTrue);

      // The order: every upload before the post, the post before the notices.
      expect(backend.calls.lastIndexOf('upload'), lessThan(backend.calls.indexOf('createPost')));
      expect(backend.calls.indexOf('createPost'), lessThan(backend.calls.indexOf('notify')));
      expect(backend.notices, [['a', 'b']]);
      expect(backend.covers, hasLength(1));
      expect(backend.tagged.single, ['t_0', 't_1', 't_999']);
      expect(store.jobs, isEmpty);
      expect(shot.existsSync(), isFalse, reason: 'the local copy goes when the job is done');
      expect(jobDir('post-1').existsSync(), isFalse, reason: 'and so does the folder');
    });

    test('a session post: its photo, no cover, no notices', () async {
      final backend = withOriginals();
      final r = runner(backend);
      final job = ShareJob(
        postId: 'post-1',
        type: PostType.session,
        taskId: 't',
        taskName: 'Spanish',
        sessionSeconds: 3600,
        cumulativeSeconds: 7200,
        createdAtMs: 1,
        shotTimestamp: 999,
        bandSeconds: 7200,
        photos: [ShareJobPhoto(id: 't_999', localPath: shot.path, isNew: true)],
      );
      await r.begin(job);
      await settle(r, 'post-1');
      expect(backend.uploads.keys.toSet(), {'users/me/posts/post-1/0.jpg', 'users/me/photos/t_999.jpg'});
      expect(backend.notices, isEmpty);
      expect(backend.covers, isEmpty);
      final doc = backend.posts['post-1']!;
      expect(doc['type'], 'session');
      expect(doc['bandSeconds'], 7200);
      expect(doc['sessionSeconds'], 3600);
      expect(doc.containsKey('coverUrl'), isFalse);
    });

    test('the bytes are counted as they go, over the whole of them', () async {
      final backend = withOriginals();
      final r = runner(backend);
      final seen = <ShareJobState>[];
      r.states.addListener(() {
        final s = r.states.value['post-1'];
        if (s != null) seen.add(s);
      });
      await r.begin(milestone());
      await settle(r, 'post-1');
      // Three photos, the shot's private copy, the cover and the thumbnail.
      final total = tinyPng.length * 4 + 3 + 3;
      final running = seen.where((s) => s.status == ShareJobStatus.running && s.totalBytes > 0).toList();
      expect(running, isNotEmpty);
      expect(running.every((s) => s.totalBytes == total), isTrue);
      expect(running.last.uploadedBytes, total);
      for (var i = 1; i < running.length; i++) {
        expect(running[i].uploadedBytes, greaterThanOrEqualTo(running[i - 1].uploadedBytes));
      }
      expect(seen.any((s) => s.status == ShareJobStatus.posted), isTrue);
    });
  });

  group('falsifying "the post only at the end"', () {
    for (final step in ['upload', 'savePhoto']) {
      test('a job that gives up at $step has written no post; a retry writes it once', () async {
        // Every call fails until told otherwise: the uploads run four
        // abreast, so a count of three would be spent in one attempt.
        final backend = withOriginals()..failAt = step..failTimes = 99;
        final store = MemoryShareJobStore();
        final r = runner(backend, store: store);
        await r.begin(milestone());
        await settle(r, 'post-1');
        expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
        expect(backend.posts, isEmpty, reason: 'nothing is posted until everything is up');
        backend.failTimes = 0;
        await r.retry('post-1');
        expect(backend.posts.keys, ['post-1']);
        expect(backend.calls.where((c) => c == 'createPost').length, 1);
      });
    }

    test('an upload that never finishes: no post, however long', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final r = runner(backend);
      await r.begin(milestone());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.posts, isEmpty);
      expect(backend.calls, isNot(contains('createPost')));
      backend.holdUploads!.complete();
      await settle(r, 'post-1');
    });

    test('a post is never written with a photo not uploaded', () {
      const author = PostAuthor(username: 'cass', displayName: '');
      expect(() => milestone().document('me', author, ['me']), throwsStateError);
    });
  });

  group('falsifying the idempotency', () {
    for (final step in ['upload', 'createPost', 'notify', 'markShared', 'savePhoto']) {
      test('a failure at $step, then a retry: one post, one file per path, one notice per friend', () async {
        final backend = withOriginals()..failAt = step;
        final store = MemoryShareJobStore();
        final r = runner(backend, store: store);
        await r.begin(milestone());
        await settle(r, 'post-1');
        expect(store.jobs, isEmpty, reason: 'retried and done');
        expect(backend.posts.length, 1);
        expect(backend.notices, [['a', 'b']]);
        expect(backend.uploads.keys, hasLength(6), reason: 'no extra paths, whatever was rerun');
        expect(backend.savedPhotos.map((p) => p.id).toSet(), {'t_999'});
      });
    }

    test('what landed before a crash is not sent again', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      // As persisted the moment the first photo's upload was confirmed.
      await store.save(prepared.copyWith(
        photos: [
          prepared.photos[0].uploaded('u0', 'users/me/posts/post-1/0.jpg'),
          prepared.photos[1],
          prepared.photos[2],
        ],
      ));
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.uploads.keys.toSet(), allPaths.difference({'users/me/posts/post-1/0.jpg'}));
      expect(((backend.posts['post-1']!['photos'] as List)[0] as Map)['url'], 'u0');
    });

    test('a crash after the post is written but before the notices: the rerun only notifies', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      // As persisted the moment the write was confirmed.
      final after = milestone().copyWith(
        step: ShareStep.posted,
        audience: ['me', 'a', 'b'],
        photos: [for (var i = 0; i < 3; i++) milestone().photos[i].uploaded('u$i', 'p$i')],
        coverUrl: 'c',
        coverStoragePath: 'cp',
        thumbUrl: 't',
        thumbStoragePath: 'tp',
      );
      await store.save(after);
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.uploads, isEmpty);
      expect(backend.posts, isEmpty);
      expect(backend.notices, [['a', 'b']]);
      expect(backend.covers, ['c|t']);
      expect(store.jobs, isEmpty);
    });

    test('notices the rules refuse as already there are taken as sent', () async {
      final backend = withOriginals()..noticesDenied = true;
      final r = runner(backend);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(backend.notices, isEmpty);
      expect(r.stateOf('post-1'), isNull, reason: 'done, not failed');
    });

    test('the audience is decided once: a rerun after the write reaches the same friends', () async {
      final backend = withOriginals()..failAt = 'notify';
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(backend.calls.where((c) => c == 'audience').length, 1);
    });
  });

  group('resume, failure, retry, cancel', () {
    test('a job left from before is picked up at its step after a relaunch, and the line is back', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      await store.save(await runner(backend).prepare(milestone()));
      final r = runner(backend, store: store);
      await r.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(r.stateOf('post-1')?.status, ShareJobStatus.running, reason: 'the feed can say so');
      expect(r.stateOf('post-1')?.totalBytes, greaterThan(0));
      backend.holdUploads!.complete();
      await settle(r, 'post-1');
      expect(backend.posts, hasLength(1));
      expect(store.jobs, isEmpty);
    });

    test('a job from the build before, never prepared, is prepared on resume and finished', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(milestone());
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.posts, hasLength(1));
      expect(store.jobs, isEmpty);
    });

    test('three failures and the job asks for help; a retry from the line finishes it, with one post', () async {
      final backend = withOriginals()..failAt = 'createPost'..failTimes = 3;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
      expect(r.stateOf('post-1')?.attempts, 3);
      expect(store.jobs['post-1']?.step, ShareStep.uploaded, reason: 'the uploads were kept');
      expect(backend.posts, isEmpty);
      await r.retry('post-1');
      expect(backend.posts, hasLength(1));
      expect(backend.uploads.values.every((n) => n == 1), isTrue, reason: 'nothing uploaded twice');
      expect(r.stateOf('post-1'), isNull);
    });

    test('a retry that stumbles once is tried again, not given up at once', () async {
      // The record said three attempts; a retry that did not put it back
      // to nought gave up on its first stumble, which looked like nothing
      // happening at all.
      final backend = withOriginals()..failAt = 'createPost'..failTimes = 3;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
      backend.failTimes = 1;
      await r.retry('post-1');
      expect(backend.posts, hasLength(1), reason: 'the second attempt of the retry got through');
      expect(r.stateOf('post-1'), isNull);
    });

    test('retryFailed tries every job that gave up', () async {
      final backend = withOriginals()..failAt = 'createPost'..failTimes = 3;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
      await r.retryFailed();
      expect(backend.posts, hasLength(1));
      expect(r.states.value, isEmpty);
    });

    test('cancel forgets the job and takes its files down, on the phone too', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await r.cancel('post-1');
      backend.holdUploads!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.jobs, isEmpty);
      expect(r.stateOf('post-1'), isNull);
      expect(backend.deleted.single, [
        'users/me/posts/post-1/0.jpg',
        'users/me/posts/post-1/1.jpg',
        'users/me/posts/post-1/2.jpg',
        'users/me/posts/post-1/cover.jpg',
        'users/me/posts/post-1/thumb.jpg',
      ]);
      expect(backend.posts, isEmpty, reason: 'a cancelled job never writes the post');
      expect(jobDir('post-1').existsSync(), isFalse);
    });
  });

  group('the job survives a round trip', () {
    test('to JSON and back', () {
      final job = milestone().copyWith(
        step: ShareStep.uploaded,
        attempts: 2,
        audience: ['me', 'a'],
        coverLocalPath: '/c.jpg',
        thumbLocalPath: '/t.jpg',
        photos: [milestone().photos[0].copyWith(privateSaved: true), milestone().photos[1], milestone().photos[2]],
      );
      final back = ShareJob.fromJson(job.toJson());
      expect(back.postId, job.postId);
      expect(back.step, ShareStep.uploaded);
      expect(back.attempts, 2);
      expect(back.audience, ['me', 'a']);
      expect(back.coverLocalPath, '/c.jpg');
      expect(back.thumbLocalPath, '/t.jpg');
      expect(back.photos.length, 3);
      expect(back.photos[0].privateSaved, isTrue);
      expect(back.photos[0].framing, const PhotoFraming(scale: 1.2));
      expect(back.photos[2].isNew, isTrue);
      expect(back.segments.single.seconds, 3600);
      expect(back.unit, SegmentUnit.session);
      expect(back.shotPhotoId, 't_999');
    });

    test('a record from the build before reads: its "updated" is "posted" now', () {
      final back = ShareJob.fromJson({...milestone().toJson(), 'step': 'updated'});
      expect(back.step, ShareStep.posted);
    });

    test('the trace reports each step', () {
      final t = ShareTrace('p')..mark('a', bytes: 2048)..mark('b');
      t.feedShown();
      expect(t.report(), contains('a'));
      expect(t.report(), contains('2 KB'));
      expect(t.report(), contains('time to feed'));
    });
  });
}
