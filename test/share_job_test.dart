import 'dart:async';
import 'dart:convert';
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

  ShareJob milestone({bool withShot = true, int bandPhotos = 2, String? uid = 'me'}) => ShareJob(
    postId: 'post-1',
    uid: uid,
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

      // The order: every upload before the post; the notices land with it.
      expect(backend.calls.lastIndexOf('upload'), lessThan(backend.calls.indexOf('createPost')));
      expect(backend.calls, isNot(contains('notify')));
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
      expect(backend.posts['post-1']!['authorUid'], 'me');
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
    for (final step in ['upload', 'createPost', 'markShared', 'savePhoto']) {
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

    test('a crash after the post is written: the post is complete, so at launch the record is cleared without a word', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      // As persisted the moment the write was confirmed — and the post as
      // the server has it.
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
      backend.posts['post-1'] = {'audience': ['me', 'a', 'b'], 'photos': []};
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.uploads, isEmpty);
      expect(backend.calls, ['checkPost'], reason: 'nothing is run: the post is there and finished');
      expect(store.jobs, isEmpty);
      expect(r.states.value, isEmpty, reason: 'and nothing is said');
    });

    test('a write that landed and is run again — the rules refusing its notices — is taken as done', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      // As persisted the moment before the write was confirmed: the
      // write landed, the record did not say so.
      final prepared = await runner(backend).prepare(milestone());
      final uploaded = prepared.copyWith(
        step: ShareStep.uploaded,
        audience: ['me', 'a', 'b'],
        photos: [for (var i = 0; i < 3; i++) prepared.photos[i].uploaded('u$i', 'p$i').copyWith(privateSaved: true)],
        coverUrl: 'c', coverStoragePath: 'cp', thumbUrl: 't', thumbStoragePath: 'tp',
      );
      await store.save(uploaded);
      final first = runner(backend, store: store);
      await first.begin(uploaded.copyWith(step: ShareStep.prepared));
      await settle(first, 'post-1');
      expect(backend.notices, [['a', 'b']]);
      // The rerun's write is refused as a whole, the post being there.
      await store.save(uploaded);
      backend.checks['post-1'] = PostCheck.pending; // not triaged away: let it run
      final again = runner(backend, store: store);
      await again.resume();
      await settle(again, 'post-1');
      expect(backend.notices, [['a', 'b']], reason: 'told once');
      expect(again.stateOf('post-1'), isNull, reason: 'done, not failed');
    });

    test('a session post tells nobody', () async {
      final backend = withOriginals();
      final r = runner(backend);
      await r.begin(ShareJob(
        postId: 'post-1', uid: 'me', type: PostType.session, taskId: 't', taskName: 'Spanish',
        sessionSeconds: 60, cumulativeSeconds: 60, createdAtMs: 1, shotTimestamp: 999,
        photos: [ShareJobPhoto(id: 't_999', localPath: shot.path, isNew: true)],
      ));
      await settle(r, 'post-1');
      expect(backend.notices, isEmpty);
      expect(backend.posts.keys, ['post-1']);
    });

    test('the audience is decided once: a rerun after the write reaches the same friends', () async {
      final backend = withOriginals()..failAt = 'markShared';
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

  group('what a launch finds on record', () {
    test('a post already complete with a record left behind: the record and the files go, nothing is said, nothing is run', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      await store.save(prepared.copyWith(step: ShareStep.uploaded));
      backend.posts['post-1'] = {'audience': ['me'], 'photos': [{'url': 'https://x/0.jpg'}]};
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(store.jobs, isEmpty);
      expect(jobDir('post-1').existsSync(), isFalse);
      expect(backend.calls.where((c) => c == 'createPost'), isEmpty);
      expect(backend.uploads, isEmpty);
      expect(r.states.value, isEmpty);
    });

    test('falsified: a post that is there but pending is not complete — the job runs and finishes it', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(await runner(backend).prepare(milestone()));
      backend.posts['post-1'] = {'pending': true, 'audience': ['me']};
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.calls.where((c) => c == 'createPost').length, 1);
      expect(backend.posts['post-1']!.containsKey('pending'), isFalse);
      expect(store.jobs, isEmpty);
    });

    test('falsified: the check decides, not the step — a record at "posted" whose post is pending runs on', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      await store.save(prepared.copyWith(
        step: ShareStep.uploaded,
        photos: [for (var i = 0; i < 3; i++) prepared.photos[i].uploaded('u$i', 'p$i').copyWith(privateSaved: true)],
        coverUrl: 'c', coverStoragePath: 'cp', thumbUrl: 't', thumbStoragePath: 'tp',
      ));
      backend.checks['post-1'] = PostCheck.pending;
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.calls, contains('createPost'));
      expect(store.jobs, isEmpty);
    });

    test('its files gone: discarded with its partial uploads, said once, and never again', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      await store.save(prepared);
      File(prepared.photos[0].localPath!).deleteSync();
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(store.jobs, isEmpty);
      expect(backend.deleted.single, prepared.storagePaths('me'));
      expect(backend.posts, isEmpty);
      expect(r.stateOf('post-1')?.status, ShareJobStatus.discarded);
      expect(r.stateOf('post-1')?.lastError, 'files missing');
      expect(jobDir('post-1').existsSync(), isFalse);
      r.dismiss('post-1');
      expect(r.states.value, isEmpty);
      // The next launch finds nothing.
      final again = runner(backend, store: store);
      await again.resume();
      expect(again.states.value, isEmpty);
    });

    test('the shot gone before the job was prepared: discarded too; a band photo gone is fetched, not missed', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(milestone());
      shot.deleteSync();
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.discarded);
      expect(store.jobs, isEmpty);
    });

    test('an obsolete record — from before jobs were kept per account — is discarded, and its pending post taken down', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      store.legacy.add(milestone(uid: null));
      backend.posts['post-1'] = {'pending': true, 'audience': ['me']};
      final r = runner(backend, store: store);
      await r.resume();
      expect(store.legacy, isEmpty);
      expect(store.jobs, isEmpty);
      expect(backend.deleted.single, milestone().storagePaths('me'));
      expect(r.stateOf('post-1')?.status, ShareJobStatus.discarded);
      expect(r.stateOf('post-1')?.lastError, 'obsolete record');
      expect(backend.calls, isNot(contains('createPost')));
    });

    test('a record without an account in the account\'s own store is discarded as well', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(milestone(uid: null));
      final r = runner(backend, store: store);
      await r.resume();
      expect(store.jobs, isEmpty);
      expect(r.stateOf('post-1')?.status, ShareJobStatus.discarded);
    });

    test('its post deleted after it was written: discarded, nothing re-posted', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      await store.save(prepared.copyWith(step: ShareStep.posted, audience: ['me', 'a']));
      final r = runner(backend, store: store);
      await r.resume();
      expect(store.jobs, isEmpty);
      expect(backend.posts, isEmpty);
      expect(backend.notices, isEmpty);
      expect(r.stateOf('post-1')?.status, ShareJobStatus.discarded);
      expect(r.stateOf('post-1')?.lastError, 'post deleted');
    });

    test('a job that failed for a passing reason is run again, not discarded', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final prepared = await runner(backend).prepare(milestone());
      await store.save(prepared.copyWith(attempts: 3, lastError: 'firebase_storage/retry-limit-exceeded'));
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.posts.keys, ['post-1']);
      expect(store.jobs, isEmpty);
    });

    test('the record carries its last error', () async {
      final backend = withOriginals()..failAt = 'createPost'..failTimes = 99;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(store.jobs['post-1']?.lastError, 'StateError: createPost failed on purpose');
      expect(r.stateOf('post-1')?.lastError, 'StateError: createPost failed on purpose');
      expect(describeShareError(Exception('[firebase_storage/unauthorized] User does not have permission')),
          'firebase_storage/unauthorized');
    });

    test('a finished job never leaves a record: it is gone before done is reported', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      final gone = <bool>[];
      r.states.addListener(() {
        if (r.states.value['post-1'] == null) gone.add(!store.jobs.containsKey('post-1'));
      });
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(gone, [true], reason: 'the record was already removed when the state went');
    });

    test('Discard throws a failed job away: the record, the files, what went up', () async {
      final backend = withOriginals()..failAt = 'createPost'..failTimes = 99;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone());
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
      await r.discardFailed();
      expect(store.jobs, isEmpty);
      expect(backend.deleted.single, milestone().storagePaths('me'));
      expect(jobDir('post-1').existsSync(), isFalse);
      expect(r.states.value, isEmpty);
      expect(backend.posts, isEmpty);
    });
  });

  group('one store per account', () {
    test('an account sees its own jobs and nobody else\'s; signing out leaves them', () async {
      final lists = MemoryStringLists();
      final mine = PrefsShareJobStore(uid: 'me', lists: lists);
      final theirs = PrefsShareJobStore(uid: 'them', lists: lists);
      await mine.save(milestone());
      expect((await theirs.load()), isEmpty);
      expect((await mine.load()).single.postId, 'post-1');
      // Somebody else signs in and shares: nothing of mine moves.
      await theirs.save(milestone().copyWith(uid: 'them'));
      expect((await mine.load()).single.uid, 'me');
      expect((await theirs.load()).single.uid, 'them');
      await theirs.remove('post-1');
      expect((await mine.load()), hasLength(1));
      expect(lists.data.keys.toSet(), {PrefsShareJobStore.keyFor('me'), PrefsShareJobStore.keyFor('them')});
    });

    test('the one key every account once shared is read as legacy, and cleared', () async {
      final lists = MemoryStringLists();
      await lists.write(PrefsShareJobStore.legacyKey, [jsonEncode(milestone(uid: null).toJson())]);
      final store = PrefsShareJobStore(uid: 'me', lists: lists);
      expect(await store.load(), isEmpty);
      expect((await store.loadLegacy()).single.uid, isNull);
      await store.clearLegacy();
      expect(await store.loadLegacy(), isEmpty);
      expect(lists.data.containsKey(PrefsShareJobStore.legacyKey), isFalse);
    });

    test('a job begun is stamped with the account', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone(uid: null));
      expect(store.jobs['post-1']?.uid, 'me');
      await settle(r, 'post-1');
    });

    test('a job of another account found in the store is discarded, not run as mine', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(milestone(uid: 'them'));
      final r = runner(backend, store: store);
      await r.resume();
      expect(store.jobs, isEmpty);
      expect(backend.posts, isEmpty);
      expect(r.stateOf('post-1')?.lastError, 'another account');
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
