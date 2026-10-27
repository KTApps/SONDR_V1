import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/cover_render.dart';
import 'package:sondr/features/feed/jpeg_encoder.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/share_job.dart';
import 'package:sondr/features/feed/share_trace.dart';
import 'package:sondr/features/photos/models/photo.dart';

import 'tiny_png.dart';

/// The share job: the post at once, the rest behind it, and every step
/// safe to run again. The backend here records and can be told to fail,
/// so the rules are falsified rather than hoped for.
class _Fake implements ShareBackend {
  @override
  String get uid => 'me';

  /// Which call throws, and how many times, before working.
  String? failAt;
  int failTimes = 1;
  bool noticesDenied = false;

  int ids = 0;
  final List<String> calls = [];
  final Map<String, int> uploads = {};
  final Map<String, Map<String, dynamic>> pending = {};
  final Map<String, Map<String, dynamic>> finished = {};
  final List<Photo> savedPhotos = [];
  final List<(String, int, String)> crossings = [];
  final List<List<String>> notices = [];
  final List<String> covers = [];
  final List<List<String>> tagged = [];
  final List<List<String>> deleted = [];
  final Map<String, Uint8List> originals = {};
  int downloads = 0;

  /// Lets a test hold an upload open.
  Completer<void>? holdUploads;

  void _maybeFail(String step) {
    calls.add(step);
    if (failAt == step && failTimes > 0) {
      failTimes--;
      throw StateError('$step failed on purpose');
    }
  }

  @override
  String newPostId() => 'post-${++ids}';

  @override
  Future<void> setPendingPost(String postId, Map<String, dynamic> doc) async {
    _maybeFail('setPendingPost');
    pending[postId] = doc;
  }

  @override
  Future<String> upload(String path, Uint8List bytes) async {
    if (holdUploads != null) await holdUploads!.future;
    _maybeFail('upload');
    uploads[path] = (uploads[path] ?? 0) + 1;
    return 'https://x/$path';
  }

  @override
  Future<Uint8List> download(String storagePath) async {
    _maybeFail('download');
    downloads++;
    return originals[storagePath] ?? (throw StateError('no original at $storagePath'));
  }

  @override
  Future<void> savePhoto(Photo photo) async {
    _maybeFail('savePhoto');
    savedPhotos.add(photo);
  }

  @override
  Future<void> attachCrossing(String taskId, int milestoneHours, String photoId) async {
    _maybeFail('attachCrossing');
    crossings.add((taskId, milestoneHours, photoId));
  }

  @override
  Future<PostAuthor> author() async {
    _maybeFail('author');
    return const PostAuthor(username: 'cass', displayName: 'Cass');
  }

  @override
  Future<List<String>> audience() async {
    _maybeFail('audience');
    return ['me', 'a', 'b'];
  }

  @override
  Future<void> finishPost(String postId, Map<String, dynamic> update) async {
    _maybeFail('finishPost');
    finished[postId] = update;
  }

  final Set<String> _noticed = {};

  /// As the rules make it: a notice is created under the post's id and
  /// can never be updated, so a second landing is refused — and taken as
  /// already sent.
  @override
  Future<void> notify(ShareJob job, List<String> friends, PostAuthor author) async {
    _maybeFail('notify');
    if (noticesDenied || !_noticed.add(job.postId)) return;
    notices.add(friends);
  }

  @override
  Future<void> setCover(String taskId, int milestoneHours, {String? coverUrl, String? thumbUrl}) async {
    _maybeFail('setCover');
    covers.add('$coverUrl|$thumbUrl');
  }

  @override
  Future<void> markShared(List<String> photoIds) async {
    _maybeFail('markShared');
    tagged.add(photoIds);
  }

  @override
  Future<void> deleteFiles(List<String> paths) async {
    deleted.add(paths);
  }
}

class _NoEncode implements JpegEncoder {
  @override
  Future<Uint8List> encode(ui.Image image, {required int quality}) async =>
      Uint8List.fromList([0xFF, 0xD8, quality]);
}

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

  ShareJobRunner runner(_Fake backend, {MemoryShareJobStore? store, List<Duration>? backoff}) =>
      ShareJobRunner(
        store: store ?? MemoryShareJobStore(),
        backend: backend,
        encoder: _NoEncode(),
        cached: (_) async => null,
        coverStyles: const CoverTextStyles(figure: null, unit: null),
        backoff: backoff ?? const [Duration.zero, Duration.zero, Duration.zero],
      );

  _Fake withOriginals() {
    final f = _Fake();
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

  group('the post at once', () {
    test('Share returns before any upload, with the pending post written for the author alone', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      final job = milestone();
      final sw = Stopwatch()..start();
      await r.begin(job, const PostAuthor(username: 'cass', displayName: ''));
      await Future<void>.delayed(Duration.zero);
      expect(sw.elapsedMilliseconds, lessThan(500));
      // The job is kept, the post is pending, and nothing has gone up.
      expect(store.jobs.keys, ['post-1']);
      final doc = backend.pending['post-1']!;
      expect(doc['pending'], isTrue);
      expect(doc['audience'], ['me']);
      expect(doc['caption'], 'Twenty.');
      expect(doc['milestoneHours'], 20);
      final photos = doc['photos'] as List;
      expect(photos, hasLength(3));
      expect((photos[2] as Map)['url'], startsWith('file://'));
      expect((photos[0] as Map)['url'], 'https://x/private/0.jpg');
      expect((photos[0] as Map)['framing'], {'scale': 1.2, 'dx': 0.0, 'dy': 0.0});
      expect(backend.uploads, isEmpty);
      expect(r.stateOf('post-1')?.status, ShareJobStatus.running);
      backend.holdUploads!.complete();
      await settle(r, 'post-1');
      expect(r.stateOf('post-1'), isNull);
    });
  });

  group('the job', () {
    test('uploads by named path, saves the shot privately, finishes the post once, then tells the friends', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
      await settle(r, 'post-1');

      expect(backend.uploads.keys.toSet(), {
        'users/me/posts/post-1/0.jpg',
        'users/me/posts/post-1/1.jpg',
        'users/me/posts/post-1/2.jpg',
        'users/me/photos/t_999.jpg',
        'users/me/posts/post-1/cover.jpg',
        'users/me/posts/post-1/thumb.jpg',
      });
      expect(backend.uploads.values.every((n) => n == 1), isTrue);
      expect(backend.downloads, 2, reason: 'the two band photos, once each; the shot from its file');
      expect(backend.savedPhotos.single.id, 't_999');
      expect(backend.crossings, [('t', 20, 't_999')]);

      final update = backend.finished['post-1']!;
      expect(update['pending'], isFalse);
      expect(update['audience'], ['me', 'a', 'b']);
      expect(update['coverUrl'], 'https://x/users/me/posts/post-1/cover.jpg');
      expect(update['thumbUrl'], 'https://x/users/me/posts/post-1/thumb.jpg');
      final photos = update['photos'] as List;
      expect((photos[2] as Map)['url'], 'https://x/users/me/posts/post-1/2.jpg');
      expect((photos[2] as Map)['storagePath'], 'users/me/posts/post-1/2.jpg');
      expect((photos[0] as Map)['framing'], {'scale': 1.2, 'dx': 0.0, 'dy': 0.0});

      expect(backend.notices, [['a', 'b']]);
      expect(backend.covers, hasLength(1));
      expect(backend.tagged.single, ['t_0', 't_1', 't_999']);
      expect(store.jobs, isEmpty);
      expect(shot.existsSync(), isFalse, reason: 'the local copy goes when the job is done');
      // The order: the update before the notices.
      expect(backend.calls.indexOf('finishPost'), lessThan(backend.calls.indexOf('notify')));
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
      await r.begin(job, const PostAuthor(username: 'cass', displayName: ''));
      await settle(r, 'post-1');
      expect(backend.pending['post-1']!['bandSeconds'], 7200);
      expect(backend.uploads.keys.toSet(), {'users/me/posts/post-1/0.jpg', 'users/me/photos/t_999.jpg'});
      expect(backend.notices, isEmpty);
      expect(backend.covers, isEmpty);
      expect(backend.finished['post-1']!['pending'], isFalse);
    });
  });

  group('falsifying the idempotency', () {
    for (final step in ['upload', 'finishPost', 'notify', 'markShared', 'savePhoto']) {
      test('a failure at $step, then a retry: one post, one file per path, one notice per friend', () async {
        final backend = withOriginals()..failAt = step;
        final store = MemoryShareJobStore();
        final r = runner(backend, store: store);
        await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
        await settle(r, 'post-1');
        expect(store.jobs, isEmpty, reason: 'retried and done');
        expect(backend.finished.length, 1);
        expect(backend.notices, [['a', 'b']]);
        expect(backend.uploads.keys, hasLength(6), reason: 'no extra paths, whatever was rerun');
        expect(backend.savedPhotos.map((p) => p.id).toSet(), {'t_999'});
      });
    }

    test('a crash after the post is finished but before the notices: the rerun only notifies', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      // As persisted the moment the update was confirmed.
      final after = milestone().copyWith(
        step: ShareStep.updated,
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
      expect(backend.finished, isEmpty);
      expect(backend.notices, [['a', 'b']]);
      expect(backend.covers, ['c|t']);
      expect(store.jobs, isEmpty);
    });

    test('notices the rules refuse as already there are taken as sent', () async {
      final backend = withOriginals()..noticesDenied = true;
      final r = runner(backend);
      await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
      await settle(r, 'post-1');
      expect(backend.notices, isEmpty);
      expect(r.stateOf('post-1'), isNull, reason: 'done, not failed');
    });

    test('the audience is decided once: a rerun after the update reaches the same friends', () async {
      final backend = withOriginals()..failAt = 'notify';
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
      await settle(r, 'post-1');
      expect(backend.calls.where((c) => c == 'audience').length, 1);
    });
  });

  group('resume, failure, retry, cancel', () {
    test('a job left from before is picked up at its step after a relaunch', () async {
      final backend = withOriginals();
      final store = MemoryShareJobStore();
      await store.save(milestone());
      final r = runner(backend, store: store);
      await r.resume();
      await settle(r, 'post-1');
      expect(backend.finished, hasLength(1));
      expect(store.jobs, isEmpty);
    });

    test('three failures and the job asks for help; a retry from the card finishes it', () async {
      final backend = withOriginals()..failAt = 'finishPost'..failTimes = 3;
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
      await settle(r, 'post-1');
      expect(r.stateOf('post-1')?.status, ShareJobStatus.failed);
      expect(r.stateOf('post-1')?.attempts, 3);
      expect(store.jobs['post-1']?.step, ShareStep.uploaded, reason: 'the uploads were kept');
      expect(backend.finished, isEmpty);
      await r.retry('post-1');
      expect(backend.finished, hasLength(1));
      expect(backend.uploads.values.every((n) => n == 1), isTrue, reason: 'nothing uploaded twice');
      expect(r.stateOf('post-1'), isNull);
    });

    test('cancel forgets the job and takes its files down', () async {
      final backend = withOriginals()..holdUploads = Completer<void>();
      final store = MemoryShareJobStore();
      final r = runner(backend, store: store);
      await r.begin(milestone(), const PostAuthor(username: 'cass', displayName: ''));
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
      expect(backend.finished, isEmpty, reason: 'a cancelled job never finishes the post');
    });
  });

  group('the job survives a round trip', () {
    test('to JSON and back', () {
      final job = milestone().copyWith(step: ShareStep.uploaded, attempts: 2, audience: ['me', 'a']);
      final back = ShareJob.fromJson(job.toJson());
      expect(back.postId, job.postId);
      expect(back.step, ShareStep.uploaded);
      expect(back.attempts, 2);
      expect(back.audience, ['me', 'a']);
      expect(back.photos.length, 3);
      expect(back.photos[0].framing, const PhotoFraming(scale: 1.2));
      expect(back.photos[2].isNew, isTrue);
      expect(back.segments.single.seconds, 3600);
      expect(back.unit, SegmentUnit.session);
      expect(back.shotPhotoId, 't_999');
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
