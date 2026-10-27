import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../photos/models/photo.dart';
import '../timer/session_store.dart' show kSessionAppGroup;
import 'band_story.dart' show SegmentUnit;
import 'collage_layout.dart';
import 'cover_render.dart';
import 'jpeg_encoder.dart';
import 'models/post.dart';
import 'share_trace.dart';

/// Sharing, as a job that outlives the screen.
///
/// Share writes the post at once — the author alone in its audience, its
/// photos still files on the phone — and the feed shows it the same
/// moment. Everything slow runs behind it as a job: the new shot saved
/// privately, every photo uploaded, the cover and the thumbnail rendered
/// and uploaded, then ONE update of the post that gives it its final URLs
/// and its friends, then the notices, the collage and the tags.
///
/// Every step is idempotent, so a job may be run again from wherever it
/// stopped — after a crash, after the app was killed, after a lost
/// connection — and land exactly one post, one set of files, one notice
/// per friend: Storage paths are named by the post, the post is set by
/// its id, the notices by the post's id under each friend. The job is
/// kept on the device until it is done.

/// Where a job has got to. Each step is persisted once its writes are
/// confirmed; a rerun starts at the step after.
enum ShareStep { created, uploaded, updated, done }

/// What the UI needs to know about a job.
enum ShareJobStatus { running, waiting, failed }

/// How many times a job is tried before it asks for help, and how long
/// it waits between tries.
const int kShareAttempts = 3;
const List<Duration> kShareBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 8),
  Duration(seconds: 30),
];

/// How many uploads run at once.
const int kShareConcurrency = 4;

/// One photo of the job.
@immutable
class ShareJobPhoto {
  const ShareJobPhoto({
    required this.id,
    this.localPath,
    this.sourceStoragePath,
    this.sourceUrl,
    this.framing = PhotoFraming.none,
    this.sessionIndex,
    this.isNew = false,
    this.url,
    this.storagePath,
  });

  /// [Photo.id] — for the new shot, the id it will be saved under.
  final String id;

  /// The bytes on the phone: the new shot's file, or nothing.
  final String? localPath;

  /// A band photo's private original, to fetch when it is not cached.
  final String? sourceStoragePath;
  final String? sourceUrl;

  final PhotoFraming framing;
  final int? sessionIndex;

  /// The shot taken this time, which is also saved privately.
  final bool isNew;

  /// Where it went: the post-space URL and path, once uploaded.
  final String? url;
  final String? storagePath;

  ShareJobPhoto uploaded(String url, String storagePath) => ShareJobPhoto(
    id: id,
    localPath: localPath,
    sourceStoragePath: sourceStoragePath,
    sourceUrl: sourceUrl,
    framing: framing,
    sessionIndex: sessionIndex,
    isNew: isNew,
    url: url,
    storagePath: storagePath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'localPath': ?localPath,
    'sourceStoragePath': ?sourceStoragePath,
    'sourceUrl': ?sourceUrl,
    'framing': framing.toMap(),
    'sessionIndex': ?sessionIndex,
    'isNew': isNew,
    'url': ?url,
    'storagePath': ?storagePath,
  };

  factory ShareJobPhoto.fromJson(Map<String, dynamic> m) => ShareJobPhoto(
    id: m['id'] as String,
    localPath: m['localPath'] as String?,
    sourceStoragePath: m['sourceStoragePath'] as String?,
    sourceUrl: m['sourceUrl'] as String?,
    framing: PhotoFraming.fromMap(m['framing']),
    sessionIndex: (m['sessionIndex'] as num?)?.toInt(),
    isNew: m['isNew'] == true,
    url: m['url'] as String?,
    storagePath: m['storagePath'] as String?,
  );

  /// What the author's card shows before the upload: the file itself, or
  /// the private original, which the author can already read.
  String get previewUrl => localPath != null
      ? Uri.file(localPath!).toString()
      : (sourceUrl ?? '');
}

@immutable
class ShareJob {
  const ShareJob({
    required this.postId,
    required this.type,
    required this.taskId,
    required this.taskName,
    required this.sessionSeconds,
    required this.cumulativeSeconds,
    required this.photos,
    required this.createdAtMs,
    this.milestoneHours,
    this.totalHours,
    this.caption,
    this.segments = const [],
    this.unit,
    this.shotTimestamp,
    this.step = ShareStep.created,
    this.attempts = 0,
    this.audience,
    this.coverUrl,
    this.coverStoragePath,
    this.thumbUrl,
    this.thumbStoragePath,
    this.bandSeconds,
  });

  final String postId;
  final PostType type;
  final String taskId;
  final String taskName;
  final int sessionSeconds;
  final int cumulativeSeconds;
  final List<ShareJobPhoto> photos;

  /// The client's clock when Share was tapped: the post's createdAt.
  final int createdAtMs;

  final int? milestoneHours;
  final int? totalHours;
  final String? caption;
  final List<PostSegment> segments;
  final SegmentUnit? unit;

  /// The new shot's capture instant, which names its private photo.
  final int? shotTimestamp;

  final ShareStep step;
  final int attempts;

  /// The friends the post will reach, decided once and kept, so a retry
  /// reaches the same people.
  final List<String>? audience;

  final String? coverUrl;
  final String? coverStoragePath;
  final String? thumbUrl;
  final String? thumbStoragePath;

  /// A session's seconds into its band, for its card's ring.
  final int? bandSeconds;

  bool get isMilestone => type == PostType.milestone;

  ShareJobPhoto? get newShot => photos.where((p) => p.isNew).firstOrNull;

  /// The private photo id the new shot is saved under.
  String? get shotPhotoId =>
      shotTimestamp == null ? null : Photo.docId(taskId, shotTimestamp!);

  /// The Storage paths this job writes, by name, so a retry overwrites and
  /// a cancel knows what to remove.
  static String photoPath(String uid, String postId, int n) =>
      'users/$uid/posts/$postId/$n.jpg';
  static String coverPath(String uid, String postId) => 'users/$uid/posts/$postId/cover.jpg';
  static String thumbPath(String uid, String postId) => 'users/$uid/posts/$postId/thumb.jpg';
  static String privatePhotoPath(String uid, String photoId) => 'users/$uid/photos/$photoId.jpg';

  List<String> storagePaths(String uid) => [
    for (var i = 0; i < photos.length; i++) photoPath(uid, postId, i),
    if (isMilestone) coverPath(uid, postId),
    if (isMilestone) thumbPath(uid, postId),
  ];

  ShareJob copyWith({
    List<ShareJobPhoto>? photos,
    ShareStep? step,
    int? attempts,
    List<String>? audience,
    String? coverUrl,
    String? coverStoragePath,
    String? thumbUrl,
    String? thumbStoragePath,
  }) => ShareJob(
    postId: postId,
    type: type,
    taskId: taskId,
    taskName: taskName,
    sessionSeconds: sessionSeconds,
    cumulativeSeconds: cumulativeSeconds,
    photos: photos ?? this.photos,
    createdAtMs: createdAtMs,
    milestoneHours: milestoneHours,
    totalHours: totalHours,
    caption: caption,
    segments: segments,
    unit: unit,
    shotTimestamp: shotTimestamp,
    step: step ?? this.step,
    attempts: attempts ?? this.attempts,
    audience: audience ?? this.audience,
    coverUrl: coverUrl ?? this.coverUrl,
    coverStoragePath: coverStoragePath ?? this.coverStoragePath,
    thumbUrl: thumbUrl ?? this.thumbUrl,
    thumbStoragePath: thumbStoragePath ?? this.thumbStoragePath,
    bandSeconds: bandSeconds,
  );

  Map<String, dynamic> toJson() => {
    'postId': postId,
    'type': type.name,
    'taskId': taskId,
    'taskName': taskName,
    'sessionSeconds': sessionSeconds,
    'cumulativeSeconds': cumulativeSeconds,
    'photos': [for (final p in photos) p.toJson()],
    'createdAtMs': createdAtMs,
    'milestoneHours': ?milestoneHours,
    'totalHours': ?totalHours,
    'caption': ?caption,
    'segments': [for (final s in segments) s.toMap()],
    'unit': ?unit?.name,
    'shotTimestamp': ?shotTimestamp,
    'step': step.name,
    'attempts': attempts,
    'audience': ?audience,
    'coverUrl': ?coverUrl,
    'coverStoragePath': ?coverStoragePath,
    'thumbUrl': ?thumbUrl,
    'thumbStoragePath': ?thumbStoragePath,
    'bandSeconds': ?bandSeconds,
  };

  factory ShareJob.fromJson(Map<String, dynamic> m) => ShareJob(
    postId: m['postId'] as String,
    type: m['type'] == 'session' ? PostType.session : PostType.milestone,
    taskId: m['taskId'] as String,
    taskName: (m['taskName'] as String?) ?? '',
    sessionSeconds: (m['sessionSeconds'] as num?)?.toInt() ?? 0,
    cumulativeSeconds: (m['cumulativeSeconds'] as num?)?.toInt() ?? 0,
    photos: [
      for (final p in (m['photos'] as List? ?? const []))
        ShareJobPhoto.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
    milestoneHours: (m['milestoneHours'] as num?)?.toInt(),
    totalHours: (m['totalHours'] as num?)?.toInt(),
    caption: m['caption'] as String?,
    segments: [
      for (final s in (m['segments'] as List? ?? const []))
        ?PostSegment.fromMap(Map<String, dynamic>.from(s as Map)),
    ],
    unit: m['unit'] == 'session' ? SegmentUnit.session : null,
    shotTimestamp: (m['shotTimestamp'] as num?)?.toInt(),
    step: ShareStep.values.firstWhere(
      (s) => s.name == m['step'],
      orElse: () => ShareStep.created,
    ),
    attempts: (m['attempts'] as num?)?.toInt() ?? 0,
    audience: (m['audience'] as List?)?.map((e) => '$e').toList(),
    coverUrl: m['coverUrl'] as String?,
    coverStoragePath: m['coverStoragePath'] as String?,
    thumbUrl: m['thumbUrl'] as String?,
    thumbStoragePath: m['thumbStoragePath'] as String?,
    bandSeconds: (m['bandSeconds'] as num?)?.toInt(),
  );

  /// The post as the author's feed shows it the moment Share is tapped:
  /// everything the final post will have, the photos as the files on the
  /// phone, the author alone in the audience, marked pending.
  Map<String, dynamic> pendingDocument(String uid, PostAuthor author) => {
    'authorUid': uid,
    'author': author.toMap(),
    'type': type.name,
    'createdAt': createdAtMs,
    'caption': caption,
    'photos': [
      for (final p in photos)
        PostPhoto(
          url: p.previewUrl,
          storagePath: '',
          sessionIndex: p.sessionIndex,
          framing: p.framing,
        ).toMap(),
    ],
    'audience': [uid],
    'pending': true,
    'likeCount': 0,
    'commentCount': 0,
    'taskName': taskName,
    if (isMilestone) ...{
      'milestoneHours': milestoneHours,
      'totalHours': totalHours ?? 0,
      if (segments.isNotEmpty && unit != null) ...{
        'sessions': [for (final s in segments) s.toMap()],
        'unit': unit!.name,
      },
    } else ...{
      'sessionSeconds': sessionSeconds,
      'bandSeconds': ?bandSeconds,
    },
  };

  /// The one update that finishes the post.
  Map<String, dynamic> finalUpdate(PostAuthor author, List<String> audience) => {
    'author': author.toMap(),
    'photos': [
      for (final p in photos)
        PostPhoto(
          url: p.url ?? p.previewUrl,
          storagePath: p.storagePath ?? '',
          sessionIndex: p.sessionIndex,
          framing: p.framing,
        ).toMap(),
    ],
    if (coverUrl != null) ...{'coverUrl': coverUrl, 'coverStoragePath': coverStoragePath},
    if (thumbUrl != null) ...{'thumbUrl': thumbUrl, 'thumbStoragePath': thumbStoragePath},
    'audience': audience,
    'pending': false,
  };
}

class _CancelledJob implements Exception {
  const _CancelledJob();
}

/// Where jobs are kept between launches.
abstract class ShareJobStore {
  Future<List<ShareJob>> load();
  Future<void> save(ShareJob job);
  Future<void> remove(String postId);
}

class MemoryShareJobStore implements ShareJobStore {
  final Map<String, ShareJob> jobs = {};

  @override
  Future<List<ShareJob>> load() async => jobs.values.toList();

  @override
  Future<void> save(ShareJob job) async => jobs[job.postId] = job;

  @override
  Future<void> remove(String postId) async => jobs.remove(postId);
}

/// The jobs in the App Group container, beside the running session.
class PrefsShareJobStore implements ShareJobStore {
  PrefsShareJobStore({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(suiteName: kSessionAppGroup),
          );

  static const String key = 'sondr.shareJobs';
  final SharedPreferencesAsync _prefs;

  @override
  Future<List<ShareJob>> load() async {
    try {
      final raw = await _prefs.getStringList(key) ?? const [];
      return [
        for (final s in raw)
          ShareJob.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)),
      ];
    } catch (e) {
      debugPrint('SONDR share jobs read error: ${e.runtimeType}');
      return const [];
    }
  }

  Future<void> _write(List<ShareJob> jobs) async {
    try {
      await _prefs.setStringList(key, [for (final j in jobs) jsonEncode(j.toJson())]);
    } catch (e) {
      debugPrint('SONDR share jobs write error: ${e.runtimeType}');
    }
  }

  @override
  Future<void> save(ShareJob job) async {
    final jobs = await load();
    final i = jobs.indexWhere((j) => j.postId == job.postId);
    if (i < 0) {
      jobs.add(job);
    } else {
      jobs[i] = job;
    }
    await _write(jobs);
  }

  @override
  Future<void> remove(String postId) async {
    final jobs = await load();
    await _write([for (final j in jobs) if (j.postId != postId) j]);
  }
}

/// What the job talks to. A seam, so the runner's rules — the order, the
/// retries, the idempotency — are tested against a backend that records
/// and can be told to fail.
abstract class ShareBackend {
  String get uid;

  /// A fresh post id, made on the client.
  String newPostId();

  /// The post as the author sees it at once. Set by id.
  Future<void> setPendingPost(String postId, Map<String, dynamic> doc);

  /// Bytes to [path], returning the download URL. By path: a rerun overwrites.
  Future<String> upload(String path, Uint8List bytes);

  /// A band photo's private original.
  Future<Uint8List> download(String storagePath);

  /// The new shot's private record. Set by id.
  Future<void> savePhoto(Photo photo);
  Future<void> attachCrossing(String taskId, int milestoneHours, String photoId);

  Future<PostAuthor> author();
  Future<List<String>> audience();

  /// The one update that lets friends see the post.
  Future<void> finishPost(String postId, Map<String, dynamic> update);

  /// A milestone notice to each friend, under the post's id. Returns
  /// normally when the notices turn out to be there already.
  Future<void> notify(ShareJob job, List<String> friends, PostAuthor author);

  Future<void> setCover(String taskId, int milestoneHours, {String? coverUrl, String? thumbUrl});
  Future<void> markShared(List<String> photoIds);

  /// The job's files, when the post is deleted before it finished.
  Future<void> deleteFiles(List<String> paths);
}

/// Bytes a photo's URL already has on the phone — the image cache.
typedef CachedBytes = Future<Uint8List?> Function(String url);

@immutable
class ShareJobState {
  const ShareJobState(this.status, {this.attempts = 0});
  final ShareJobStatus status;
  final int attempts;
}

class ShareJobRunner {
  ShareJobRunner({
    required this.store,
    required this.backend,
    this.encoder = const PlatformJpegEncoder(),
    this.cached,
    this.coverStyles,
    this.backoff = kShareBackoff,
    this.onTrace,
    this.onPrivateSaved,
  });

  final ShareJobStore store;
  final ShareBackend backend;
  final JpegEncoder encoder;
  final CachedBytes? cached;

  /// The ring's text styles for the cover, taken from a context by the
  /// screen that starts the share.
  CoverTextStyles? coverStyles;

  final List<Duration> backoff;

  /// Where a finished trace goes (debug tools).
  final void Function(ShareTrace trace)? onTrace;

  /// The new shot has landed in the private gallery: the surfaces that
  /// show it can be told.
  final VoidCallback? onPrivateSaved;

  /// What each job is doing, for the cards.
  final ValueNotifier<Map<String, ShareJobState>> states = ValueNotifier(const {});

  final Set<String> _running = {};
  final Set<String> _cancelled = {};
  final Map<String, ShareTrace> _traces = {};

  ShareJobState? stateOf(String postId) => states.value[postId];

  void _setState(String postId, ShareJobState? s) {
    final next = Map<String, ShareJobState>.from(states.value);
    if (s == null) {
      next.remove(postId);
    } else {
      next[postId] = s;
    }
    states.value = next;
  }

  /// Share: the pending post goes out now and the job starts; the caller
  /// does not wait for either.
  Future<void> begin(ShareJob job, PostAuthor author, {ShareTrace? trace}) async {
    if (trace != null) _traces[job.postId] = trace;
    await store.save(job);
    _setState(job.postId, const ShareJobState(ShareJobStatus.running));
    unawaited(
      backend
          .setPendingPost(job.postId, job.pendingDocument(backend.uid, author))
          .then((_) => trace?.mark('pending post written'))
          .catchError((Object e) {
        debugPrint('SONDR pending post write error: ${e.runtimeType} :: $e');
      }),
    );
    unawaited(_run(job));
  }

  /// Every job left from before, run again from where it stopped.
  Future<void> resume() async {
    for (final job in await store.load()) {
      if (_running.contains(job.postId)) continue;
      _setState(job.postId, ShareJobState(ShareJobStatus.running, attempts: job.attempts));
      unawaited(_run(job.copyWith(attempts: 0)));
    }
  }

  /// Try a failed job again from where it stopped.
  Future<void> retry(String postId) async {
    final job = (await store.load()).where((j) => j.postId == postId).firstOrNull;
    if (job == null || _running.contains(postId)) return;
    await _run(job.copyWith(attempts: 0));
  }

  /// The post was deleted: stop the job, forget it, and take down what it
  /// uploaded.
  Future<void> cancel(String postId) async {
    _cancelled.add(postId);
    final job = (await store.load()).where((j) => j.postId == postId).firstOrNull;
    await store.remove(postId);
    _setState(postId, null);
    if (job != null) {
      try {
        await backend.deleteFiles(job.storagePaths(backend.uid));
      } catch (e) {
        debugPrint('SONDR share cancel cleanup error: ${e.runtimeType}');
      }
      _deleteLocalFiles(job);
    }
  }

  Future<void> _run(ShareJob start) async {
    final id = start.postId;
    if (_running.contains(id)) return;
    _running.add(id);
    var job = start;
    try {
      while (true) {
        if (_cancelled.contains(id)) return;
        try {
          job = await _steps(job);
          await store.remove(id);
          _setState(id, null);
          _deleteLocalFiles(job);
          final trace = _traces.remove(id);
          if (trace != null) {
            trace.mark('done');
            onTrace?.call(trace);
          }
          return;
        } catch (e, st) {
          if (e is _CancelledJob || _cancelled.contains(id)) return;
          debugPrint('SONDR share job error: ${e.runtimeType} :: $e\n$st');
          // Carry on from what the steps had already persisted — the
          // uploads that landed stay landed — not from where this attempt
          // began.
          final latest = (await store.load()).where((j) => j.postId == id).firstOrNull ?? job;
          job = latest.copyWith(attempts: latest.attempts + 1);
          await store.save(job);
          if (job.attempts >= kShareAttempts) {
            _setState(id, ShareJobState(ShareJobStatus.failed, attempts: job.attempts));
            return;
          }
          _setState(id, ShareJobState(ShareJobStatus.waiting, attempts: job.attempts));
          await Future<void>.delayed(backoff[(job.attempts - 1).clamp(0, backoff.length - 1)]);
          _setState(id, ShareJobState(ShareJobStatus.running, attempts: job.attempts));
        }
      }
    } finally {
      _running.remove(id);
      _cancelled.remove(id);
    }
  }

  /// A cancelled job stops at the next step boundary.
  void _checkCancelled(String id) {
    if (_cancelled.contains(id)) throw const _CancelledJob();
  }

  /// The steps from [job.step] on. Each persists the job once its writes
  /// are confirmed, and returns the job to carry on from.
  Future<ShareJob> _steps(ShareJob job) async {
    final trace = _traces[job.postId];
    final uid = backend.uid;
    _checkCancelled(job.postId);

    // The reads, alongside the uploads: who I am, and who my friends are.
    final authorFuture = backend.author();
    final audienceFuture = job.audience != null
        ? Future.value(job.audience!)
        : backend.audience();

    if (job.step.index < ShareStep.uploaded.index) {
      job = await _upload(job, trace);
      _checkCancelled(job.postId);
      await store.save(job);
    }

    if (job.step.index < ShareStep.updated.index) {
      _checkCancelled(job.postId);
      final author = await authorFuture;
      // The friends are decided and kept BEFORE the update, so a rerun
      // after a crash between the two reaches the same people.
      final audience = await audienceFuture;
      job = job.copyWith(audience: audience);
      await store.save(job);
      await backend.finishPost(job.postId, job.finalUpdate(author, audience));
      trace?.mark('post updated');
      trace?.friendsCanSee();
      job = job.copyWith(step: ShareStep.updated);
      await store.save(job);
    }

    if (job.step.index < ShareStep.done.index) {
      _checkCancelled(job.postId);
      final author = await authorFuture;
      final friends = [for (final u in job.audience ?? const <String>[]) if (u != uid) u];
      await Future.wait([
        if (job.isMilestone && friends.isNotEmpty) backend.notify(job, friends, author),
        if (job.isMilestone && (job.coverUrl != null || job.thumbUrl != null))
          backend.setCover(
            job.taskId,
            job.milestoneHours!,
            coverUrl: job.coverUrl,
            thumbUrl: job.thumbUrl,
          ),
        backend.markShared([for (final p in job.photos) p.id]),
      ]);
      trace?.mark('notices, collage, tags');
      job = job.copyWith(step: ShareStep.done);
    }
    return job;
  }

  /// Every photo up, the new shot saved privately as well, and — for a
  /// milestone — the cover and the thumbnail rendered from the same bytes
  /// and uploaded, four at a time.
  Future<ShareJob> _upload(ShareJob job, ShareTrace? trace) async {
    final uid = backend.uid;
    final bytes = List<Uint8List?>.filled(job.photos.length, null);

    // The bytes: the file on the phone, the image cache, or the original.
    for (var i = 0; i < job.photos.length; i++) {
      final p = job.photos[i];
      if (p.localPath != null && File(p.localPath!).existsSync()) {
        bytes[i] = await File(p.localPath!).readAsBytes();
        continue;
      }
      if (p.sourceUrl != null && cached != null) {
        bytes[i] = await cached!(p.sourceUrl!);
      }
    }
    final missing = [for (var i = 0; i < bytes.length; i++) if (bytes[i] == null) i];
    await _inParallel(missing, (i) async {
      final path = job.photos[i].sourceStoragePath;
      if (path == null) throw StateError('photo ${job.photos[i].id} has no bytes and no source');
      bytes[i] = await backend.download(path);
    });
    trace?.mark('bytes gathered', bytes: bytes.fold<int>(0, (s, b) => s + (b?.length ?? 0)));

    final uploads = <Future<void>>[];
    final photos = [...job.photos];
    // The photos, four at a time; the new shot goes to its private path
    // too, from the same bytes.
    uploads.add(_inParallel(List.generate(photos.length, (i) => i), (i) async {
      final p = photos[i];
      final data = bytes[i]!;
      final path = ShareJob.photoPath(uid, job.postId, i);
      final futures = <Future<void>>[
        backend.upload(path, data).then((url) {
          photos[i] = p.uploaded(url, path);
        }),
      ];
      if (p.isNew && job.shotPhotoId != null) {
        futures.add(_savePrivately(job, data));
      }
      await Future.wait(futures);
    }));

    String? coverUrl, coverPath, thumbUrl, thumbPath;
    if (job.isMilestone) {
      uploads.add(() async {
        final images = <ui.Image>[];
        for (final b in bytes.take(kCollageMax)) {
          images.add(await decodeForCover(b!));
        }
        try {
          final framings = [for (final p in job.photos) p.framing];
          final cover = await renderMilestoneCover(
            photos: images,
            milestoneHours: job.milestoneHours!,
            styles: coverStyles ?? const CoverTextStyles(figure: null, unit: null),
            framings: framings,
            encoder: encoder,
          );
          trace?.mark('cover rendered', bytes: cover.length);
          final thumb = await renderMilestoneThumb(
            photos: images,
            framings: framings,
            encoder: encoder,
          );
          trace?.mark('thumb rendered', bytes: thumb.length);
          coverPath = ShareJob.coverPath(uid, job.postId);
          thumbPath = ShareJob.thumbPath(uid, job.postId);
          await Future.wait([
            backend.upload(coverPath!, cover).then((u) => coverUrl = u),
            backend.upload(thumbPath!, thumb).then((u) => thumbUrl = u),
          ]);
        } finally {
          for (final i in images) {
            i.dispose();
          }
        }
      }());
    }
    await Future.wait(uploads);
    trace?.mark('uploads done', bytes: bytes.fold<int>(0, (s, b) => s + (b?.length ?? 0)));
    return job.copyWith(
      photos: photos,
      step: ShareStep.uploaded,
      coverUrl: coverUrl,
      coverStoragePath: coverPath,
      thumbUrl: thumbUrl,
      thumbStoragePath: thumbPath,
    );
  }

  /// The new shot in the private gallery: its binary at its own path, its
  /// record set by id, and — at a crossing — into the milestone's collage.
  Future<void> _savePrivately(ShareJob job, Uint8List data) async {
    final uid = backend.uid;
    final photoId = job.shotPhotoId!;
    final path = ShareJob.privatePhotoPath(uid, photoId);
    final url = await backend.upload(path, data);
    final when = DateTime.fromMicrosecondsSinceEpoch(job.shotTimestamp!);
    await backend.savePhoto(
      Photo(
        taskId: job.taskId,
        taskName: job.taskName,
        dayKey: _dayKey(when),
        timestamp: job.shotTimestamp!,
        sessionSeconds: job.sessionSeconds,
        photoUrl: url,
        storagePath: path,
        milestoneHours: job.milestoneHours,
        cumulativeSeconds: job.cumulativeSeconds,
      ),
    );
    if (job.milestoneHours != null) {
      await backend.attachCrossing(job.taskId, job.milestoneHours!, photoId);
    }
    onPrivateSaved?.call();
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _inParallel(List<int> indices, Future<void> Function(int) work) async {
    final queue = [...indices];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final i = queue.removeAt(0);
        await work(i);
      }
    }
    await Future.wait([for (var k = 0; k < kShareConcurrency; k++) worker()]);
  }

  void _deleteLocalFiles(ShareJob job) {
    for (final p in job.photos) {
      final path = p.localPath;
      if (path == null) continue;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// The store on the device, or memory where there are no preferences.
final shareJobStoreProvider = Provider<ShareJobStore>((_) {
  try {
    return PrefsShareJobStore();
  } catch (e) {
    debugPrint('SONDR share job store unavailable: ${e.runtimeType}');
    return MemoryShareJobStore();
  }
});
