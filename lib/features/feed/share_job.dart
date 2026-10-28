import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
/// Share PREPARES the post on the phone — every photo's bytes written to
/// the job's own folder, the cover and the thumbnail rendered beside them
/// — and only then lets the review go. Everything slow runs behind it as a
/// job: every file uploaded, four at a time, with the bytes counted as
/// they go; then ONE write of the post, complete — its final URLs, its
/// cover, its thumbnail, its friends — so nobody ever sees a post that is
/// not finished; then the notices, the collage and the tags.
///
/// Every step is idempotent, so a job may be run again from wherever it
/// stopped — after a crash, after the app was killed, after a lost
/// connection — and land exactly one post, one set of files, one notice
/// per friend: Storage paths are named by the post, the post is set by
/// its id, the notices by the post's id under each friend. The job is
/// kept on the device until it is done.

/// Where a job has got to. Each step is persisted once its writes are
/// confirmed; a rerun starts at the step after.
enum ShareStep { created, prepared, uploaded, posted, done }

/// What the UI needs to know about a job. [discarded]: the job could not
/// be finished and has been thrown away — said once, then dismissed.
enum ShareJobStatus { running, waiting, posted, failed, discarded }

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
    this.privateSaved = false,
  });

  /// [Photo.id] — for the new shot, the id it will be saved under.
  final String id;

  /// The bytes on the phone: the new shot's file, or — once the job is
  /// prepared — the copy in the job's folder.
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

  /// The new shot's private copy has landed, with its record.
  final bool privateSaved;

  ShareJobPhoto copyWith({
    String? localPath,
    String? url,
    String? storagePath,
    bool? privateSaved,
  }) => ShareJobPhoto(
    id: id,
    localPath: localPath ?? this.localPath,
    sourceStoragePath: sourceStoragePath,
    sourceUrl: sourceUrl,
    framing: framing,
    sessionIndex: sessionIndex,
    isNew: isNew,
    url: url ?? this.url,
    storagePath: storagePath ?? this.storagePath,
    privateSaved: privateSaved ?? this.privateSaved,
  );

  ShareJobPhoto uploaded(String url, String storagePath) =>
      copyWith(url: url, storagePath: storagePath);

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
    'privateSaved': privateSaved,
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
    privateSaved: m['privateSaved'] == true,
  );
}

@immutable
class ShareJob {
  const ShareJob({
    required this.postId,
    this.uid,
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
    this.coverLocalPath,
    this.thumbLocalPath,
    this.coverUrl,
    this.coverStoragePath,
    this.thumbUrl,
    this.thumbStoragePath,
    this.bandSeconds,
    this.lastError,
  });

  final String postId;

  /// Whose job it is. Null on a record from before jobs were kept per
  /// account, which cannot be finished: there is no knowing whose it was.
  final String? uid;

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

  /// The cover and the thumbnail, rendered on the phone before the review
  /// let go.
  final String? coverLocalPath;
  final String? thumbLocalPath;

  final String? coverUrl;
  final String? coverStoragePath;
  final String? thumbUrl;
  final String? thumbStoragePath;

  /// A session's seconds into its band, for its card's ring.
  final int? bandSeconds;

  /// Why the last attempt failed, as a short code, for the debug panel.
  final String? lastError;

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
    String? uid,
    List<ShareJobPhoto>? photos,
    ShareStep? step,
    int? attempts,
    List<String>? audience,
    String? coverLocalPath,
    String? thumbLocalPath,
    String? coverUrl,
    String? coverStoragePath,
    String? thumbUrl,
    String? thumbStoragePath,
    String? lastError,
  }) => ShareJob(
    postId: postId,
    uid: uid ?? this.uid,
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
    coverLocalPath: coverLocalPath ?? this.coverLocalPath,
    thumbLocalPath: thumbLocalPath ?? this.thumbLocalPath,
    coverUrl: coverUrl ?? this.coverUrl,
    coverStoragePath: coverStoragePath ?? this.coverStoragePath,
    thumbUrl: thumbUrl ?? this.thumbUrl,
    thumbStoragePath: thumbStoragePath ?? this.thumbStoragePath,
    bandSeconds: bandSeconds,
    lastError: lastError ?? this.lastError,
  );

  Map<String, dynamic> toJson() => {
    'postId': postId,
    'uid': ?uid,
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
    'coverLocalPath': ?coverLocalPath,
    'thumbLocalPath': ?thumbLocalPath,
    'coverUrl': ?coverUrl,
    'coverStoragePath': ?coverStoragePath,
    'thumbUrl': ?thumbUrl,
    'thumbStoragePath': ?thumbStoragePath,
    'bandSeconds': ?bandSeconds,
    'lastError': ?lastError,
  };

  factory ShareJob.fromJson(Map<String, dynamic> m) => ShareJob(
    postId: m['postId'] as String,
    uid: m['uid'] as String?,
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
    step: _stepFrom(m['step']),
    attempts: (m['attempts'] as num?)?.toInt() ?? 0,
    audience: (m['audience'] as List?)?.map((e) => '$e').toList(),
    coverLocalPath: m['coverLocalPath'] as String?,
    thumbLocalPath: m['thumbLocalPath'] as String?,
    coverUrl: m['coverUrl'] as String?,
    coverStoragePath: m['coverStoragePath'] as String?,
    thumbUrl: m['thumbUrl'] as String?,
    thumbStoragePath: m['thumbStoragePath'] as String?,
    bandSeconds: (m['bandSeconds'] as num?)?.toInt(),
    lastError: m['lastError'] as String?,
  );

  /// Whether the job still needs a file on the phone that is not there.
  /// Before it is prepared only the new shot has to be present — the
  /// band photos have their originals to fetch; prepared, every photo
  /// not yet uploaded, and the cover and the thumbnail not yet uploaded,
  /// must be; uploaded, nothing on the phone is needed any more.
  bool get filesMissing {
    bool gone(String? path) => path == null || !File(path).existsSync();
    if (step.index >= ShareStep.uploaded.index) return false;
    for (final p in photos) {
      final needed = step.index < ShareStep.prepared.index
          ? p.isNew
          : p.url == null || (p.isNew && !p.privateSaved);
      if (needed && gone(p.localPath)) return true;
    }
    if (isMilestone && step.index >= ShareStep.prepared.index) {
      if (coverUrl == null && gone(coverLocalPath)) return true;
      if (thumbUrl == null && gone(thumbLocalPath)) return true;
    }
    return false;
  }

  /// A job from before the post was written last: its "updated" was the
  /// post's final write, which is "posted" now.
  static ShareStep _stepFrom(Object? name) {
    if (name == 'updated') return ShareStep.posted;
    return ShareStep.values.firstWhere((s) => s.name == name, orElse: () => ShareStep.created);
  }

  /// The post, complete: written once, when every file is up. Throws when
  /// a photo has not been uploaded — the post is never written short.
  Map<String, dynamic> document(String uid, PostAuthor author, List<String> audience) => {
    'authorUid': uid,
    'author': author.toMap(),
    'type': type.name,
    'createdAt': createdAtMs,
    'caption': caption,
    'photos': [
      for (final p in photos)
        PostPhoto(
          url: p.url ?? (throw StateError('photo ${p.id} is not uploaded')),
          storagePath: p.storagePath ?? '',
          sessionIndex: p.sessionIndex,
          framing: p.framing,
        ).toMap(),
    ],
    'audience': audience,
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
      if (coverUrl != null) ...{'coverUrl': coverUrl, 'coverStoragePath': coverStoragePath},
      if (thumbUrl != null) ...{'thumbUrl': thumbUrl, 'thumbStoragePath': thumbStoragePath},
    } else ...{
      'sessionSeconds': sessionSeconds,
      'bandSeconds': ?bandSeconds,
    },
  };
}

class _CancelledJob implements Exception {
  const _CancelledJob();
}

/// Where one account's jobs are kept between launches. Each account has
/// its own: signing out leaves them where they are, and signing in as
/// somebody else never sees them.
abstract class ShareJobStore {
  Future<List<ShareJob>> load();
  Future<void> save(ShareJob job);
  Future<void> remove(String postId);

  /// Records from before jobs were kept per account — one list for the
  /// phone, whoever was signed in. Nobody's now: they are thrown away at
  /// the next launch, once.
  Future<List<ShareJob>> loadLegacy();
  Future<void> clearLegacy();
}

class MemoryShareJobStore implements ShareJobStore {
  final Map<String, ShareJob> jobs = {};
  final List<ShareJob> legacy = [];

  @override
  Future<List<ShareJob>> load() async => jobs.values.toList();

  @override
  Future<void> save(ShareJob job) async => jobs[job.postId] = job;

  @override
  Future<void> remove(String postId) async => jobs.remove(postId);

  @override
  Future<List<ShareJob>> loadLegacy() async => List.of(legacy);

  @override
  Future<void> clearLegacy() async => legacy.clear();
}

/// Lists of strings by key: the preferences, or a map in a test.
abstract class StringLists {
  Future<List<String>?> read(String key);
  Future<void> write(String key, List<String> value);
  Future<void> delete(String key);
}

/// The App Group's preferences, beside the running session.
class PrefsStringLists implements StringLists {
  PrefsStringLists({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(suiteName: kSessionAppGroup),
          );

  final SharedPreferencesAsync _prefs;

  @override
  Future<List<String>?> read(String key) => _prefs.getStringList(key);

  @override
  Future<void> write(String key, List<String> value) => _prefs.setStringList(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

class MemoryStringLists implements StringLists {
  final Map<String, List<String>> data = {};

  @override
  Future<List<String>?> read(String key) async => data[key];

  @override
  Future<void> write(String key, List<String> value) async => data[key] = List.of(value);

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// One account's jobs, under a key of its own.
class PrefsShareJobStore implements ShareJobStore {
  PrefsShareJobStore({required this.uid, StringLists? lists}) : _lists = lists ?? PrefsStringLists();

  /// The one key every account once shared.
  static const String legacyKey = 'sondr.shareJobs';
  static String keyFor(String uid) => 'sondr.shareJobs.$uid';

  final String uid;
  final StringLists _lists;

  String get _key => keyFor(uid);

  Future<List<ShareJob>> _read(String key) async {
    try {
      final raw = await _lists.read(key) ?? const [];
      return [
        for (final s in raw)
          ShareJob.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)),
      ];
    } catch (e) {
      debugPrint('SONDR share jobs read error: ${e.runtimeType}');
      return const [];
    }
  }

  @override
  Future<List<ShareJob>> load() => _read(_key);

  Future<void> _write(List<ShareJob> jobs) async {
    try {
      await _lists.write(_key, [for (final j in jobs) jsonEncode(j.toJson())]);
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

  @override
  Future<List<ShareJob>> loadLegacy() => _read(legacyKey);

  @override
  Future<void> clearLegacy() async {
    try {
      await _lists.delete(legacyKey);
    } catch (e) {
      debugPrint('SONDR share jobs legacy clear error: ${e.runtimeType}');
    }
  }
}

/// What a job's post looks like on the server, for the launch triage.
enum PostCheck { missing, pending, complete }

/// Bytes sent so far on one upload.
typedef UploadProgress = void Function(int sent);

/// What the job talks to. A seam, so the runner's rules — the order, the
/// retries, the idempotency — are tested against a backend that records
/// and can be told to fail.
abstract class ShareBackend {
  String get uid;

  /// A fresh post id, made on the client.
  String newPostId();

  /// Bytes to [path], returning the download URL, saying how far it has
  /// got as it goes. By path: a rerun overwrites.
  Future<String> upload(String path, Uint8List bytes, {UploadProgress? onProgress});

  /// A band photo's private original.
  Future<Uint8List> download(String storagePath);

  /// The new shot's private record. Set by id.
  Future<void> savePhoto(Photo photo);
  Future<void> attachCrossing(String taskId, int milestoneHours, String photoId);

  Future<PostAuthor> author();
  Future<List<String>> audience();

  /// The post, complete. Set by id: a rerun writes the same post again.
  Future<void> createPost(String postId, Map<String, dynamic> doc);

  /// Whether the post is there, and finished.
  Future<PostCheck> checkPost(String postId);

  /// A post written at the moment of Share by a build before, never
  /// finished: taken down with the job that was to finish it.
  Future<void> deletePendingPost(String postId);

  /// A milestone notice to each friend, under the post's id. Returns
  /// normally when the notices turn out to be there already.
  Future<void> notify(ShareJob job, List<String> friends, PostAuthor author);

  Future<void> setCover(String taskId, int milestoneHours, {String? coverUrl, String? thumbUrl});
  Future<void> markShared(List<String> photoIds);

  /// The job's files, when it is cancelled before it finished.
  Future<void> deleteFiles(List<String> paths);
}

/// Bytes a photo's URL already has on the phone — the image cache.
typedef CachedBytes = Future<Uint8List?> Function(String url);

/// A job's own folder on the phone, where its bytes wait for the upload.
/// Somewhere that survives a relaunch: the temp directory can be emptied
/// while the app is not running.
typedef ShareJobDir = Future<Directory> Function(String postId);

@immutable
class ShareJobState {
  const ShareJobState(
    this.status, {
    this.attempts = 0,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
    this.lastError,
  });

  final ShareJobStatus status;
  final int attempts;

  /// Why the last attempt failed, or why the job was discarded.
  final String? lastError;

  /// How much of the job's bytes have gone up, over how many there are.
  final int uploadedBytes;
  final int totalBytes;

  ShareJobState copyWith({ShareJobStatus? status, int? attempts, int? uploadedBytes, int? totalBytes}) =>
      ShareJobState(
        status ?? this.status,
        attempts: attempts ?? this.attempts,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        lastError: lastError,
      );
}

class ShareJobRunner {
  ShareJobRunner({
    required this.store,
    required this.backend,
    required this.dirFor,
    this.encoder = const PlatformJpegEncoder(),
    this.cached,
    this.coverStyles,
    this.backoff = kShareBackoff,
    this.onTrace,
    this.onPrivateSaved,
  });

  final ShareJobStore store;
  final ShareBackend backend;
  final ShareJobDir dirFor;
  final JpegEncoder encoder;
  final CachedBytes? cached;

  /// The ring's text styles for the cover, taken from a context by the
  /// screen that starts the share.
  CoverTextStyles? coverStyles;

  final List<Duration> backoff;

  /// Where a finished — or a failed — trace goes (debug tools).
  final void Function(ShareTrace trace)? onTrace;

  /// The new shot has landed in the private gallery: the surfaces that
  /// show it can be told.
  final VoidCallback? onPrivateSaved;

  /// What each job is doing, for the feed's line.
  final ValueNotifier<Map<String, ShareJobState>> states = ValueNotifier(const {});

  final Set<String> _running = {};
  final Set<String> _cancelled = {};
  final Map<String, ShareTrace> _traces = {};
  bool _resuming = false;

  /// The save in progress, if any. Made as it is needed, never in the
  /// constructor: a future belongs to the zone it was made in, and a
  /// runner is made on the screen but runs its job elsewhere.
  Future<void>? _persisting;

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

  void _progress(String postId, int uploaded, int total) {
    final s = states.value[postId];
    if (s == null || s.status != ShareJobStatus.running) return;
    _setState(postId, s.copyWith(uploadedBytes: uploaded, totalBytes: total));
  }

  /// Saves, one after another, so two uploads finishing together cannot
  /// write over each other's record. A cancelled job is not written back
  /// by an upload that was already in the air.
  Future<void> _persist(ShareJob job) {
    final done = (_persisting ?? Future<void>.value()).then((_) {
      if (_cancelled.contains(job.postId)) return Future<void>.value();
      return store.save(job);
    });
    _persisting = done.catchError((_) {});
    return done;
  }

  /// Share: the post is prepared on the phone — bytes, cover, thumbnail —
  /// and the job starts; returns once the preparation is done, which is
  /// what the review waits for. Throws when it cannot be prepared.
  Future<void> begin(ShareJob job, {ShareTrace? trace}) async {
    job = job.copyWith(uid: backend.uid);
    if (trace != null) _traces[job.postId] = trace;
    _setState(job.postId, const ShareJobState(ShareJobStatus.running));
    try {
      job = await prepare(job, trace);
    } catch (e) {
      _setState(job.postId, null);
      _traces.remove(job.postId);
      rethrow;
    }
    await store.save(job);
    unawaited(_run(job));
  }

  /// Every job left from before, looked at before it is run: one whose
  /// post is there and finished is done, and is cleared without a word;
  /// one that cannot be finished — nobody's, its files gone, its post
  /// deleted — is thrown away with its partial uploads, and said once;
  /// the rest run again from where they stopped.
  Future<void> resume() async {
    if (_resuming) return;
    _resuming = true;
    try {
      // Records from before jobs were kept per account are nobody's.
      final legacy = await store.loadLegacy();
      for (final job in legacy) {
        await _discard(job, 'obsolete record', check: null);
      }
      if (legacy.isNotEmpty) await store.clearLegacy();

      for (final job in await store.load()) {
        if (_running.contains(job.postId)) continue;
        final verdict = await triage(job);
        switch (verdict.kind) {
          case TriageKind.done:
            await store.remove(job.postId);
            await _deleteLocal(job);
            _setState(job.postId, null);
            debugPrint('SONDR share job ${job.postId}: post already complete, record cleared');
          case TriageKind.discard:
            await _discard(job, verdict.reason!, check: verdict.check);
          case TriageKind.run:
            final fresh = job.copyWith(attempts: 0);
            await store.save(fresh);
            _setState(job.postId, const ShareJobState(ShareJobStatus.running));
            unawaited(_run(fresh));
        }
      }
    } finally {
      _resuming = false;
    }
  }

  /// What to do with a job found at launch.
  Future<Triage> triage(ShareJob job) async {
    if (job.uid == null) return const Triage(TriageKind.discard, reason: 'obsolete record');
    if (job.uid != backend.uid) return const Triage(TriageKind.discard, reason: 'another account');
    PostCheck? check;
    try {
      check = await backend.checkPost(job.postId);
    } catch (e) {
      debugPrint('SONDR share job ${job.postId}: post check failed, ${e.runtimeType}');
    }
    if (check == PostCheck.complete) return const Triage(TriageKind.done);
    if (check == PostCheck.missing && job.step.index >= ShareStep.posted.index) {
      return Triage(TriageKind.discard, reason: 'post deleted', check: check);
    }
    if (job.filesMissing) return Triage(TriageKind.discard, reason: 'files missing', check: check);
    return Triage(TriageKind.run, check: check);
  }

  /// Thrown away: the record, the files on the phone, what went up, and
  /// a post a build before wrote at the moment of Share. Said once.
  Future<void> _discard(ShareJob job, String reason, {required PostCheck? check}) async {
    debugPrint('SONDR share job ${job.postId} discarded: $reason');
    await store.remove(job.postId);
    try {
      await backend.deleteFiles(job.storagePaths(backend.uid));
    } catch (e) {
      debugPrint('SONDR share discard cleanup error: ${e.runtimeType}');
    }
    if (check == PostCheck.pending) {
      try {
        await backend.deletePendingPost(job.postId);
      } catch (e) {
        debugPrint('SONDR share discard pending post error: ${e.runtimeType}');
      }
    }
    await _deleteLocal(job);
    _setState(job.postId, ShareJobState(ShareJobStatus.discarded, lastError: reason));
  }

  /// The feed has said that a job was discarded: nothing more to show.
  void dismiss(String postId) {
    if (states.value[postId]?.status == ShareJobStatus.discarded) _setState(postId, null);
  }

  /// Every job that gave up, thrown away by its owner: the record, the
  /// files, what went up.
  Future<void> discardFailed() async {
    final failed = [
      for (final e in states.value.entries)
        if (e.value.status == ShareJobStatus.failed) e.key,
    ];
    for (final id in failed) {
      await cancel(id);
    }
  }

  /// Try a failed job again from where it stopped — with its attempts
  /// back at nought, in the record as well as in hand, or the first
  /// stumble would end it.
  Future<void> retry(String postId) async {
    final job = (await store.load()).where((j) => j.postId == postId).firstOrNull;
    if (job == null || _running.contains(postId)) return;
    final fresh = job.copyWith(attempts: 0);
    await store.save(fresh);
    await _run(fresh);
  }

  /// Every job that gave up, tried again.
  Future<void> retryFailed() async {
    final failed = [
      for (final e in states.value.entries)
        if (e.value.status == ShareJobStatus.failed) e.key,
    ];
    await Future.wait([for (final id in failed) retry(id)]);
  }

  /// The share is abandoned: stop the job, forget it, and take down what
  /// it uploaded.
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
      await _deleteLocal(job);
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
          _setState(id, null);
          await _deleteLocal(job);
          final trace = _traces.remove(id);
          if (trace != null) {
            trace.mark('done');
            onTrace?.call(trace);
          }
          return;
        } catch (e, st) {
          if (e is _CancelledJob || _cancelled.contains(id)) return;
          debugPrint('SONDR share job error: ${e.runtimeType} :: $e\n$st');
          _traces[id]?.mark('failed: ${e.runtimeType}');
          // Carry on from what the steps had already persisted — the
          // uploads that landed stay landed — not from where this attempt
          // began.
          await _persisting;
          final latest = (await store.load()).where((j) => j.postId == id).firstOrNull ?? job;
          final code = describeShareError(e);
          job = latest.copyWith(attempts: latest.attempts + 1, lastError: code);
          await store.save(job);
          if (job.attempts >= kShareAttempts) {
            _setState(id, ShareJobState(ShareJobStatus.failed, attempts: job.attempts, lastError: code));
            final trace = _traces[id];
            if (trace != null) {
              trace.mark('gave up: $e');
              onTrace?.call(trace);
            }
            return;
          }
          _setState(id, ShareJobState(ShareJobStatus.waiting, attempts: job.attempts, lastError: code));
          await Future<void>.delayed(backoff[(job.attempts - 1).clamp(0, backoff.length - 1)]);
          _setState(id, ShareJobState(ShareJobStatus.running, attempts: job.attempts, lastError: code));
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

    // A job from before the phone kept its bytes: prepared now.
    if (job.step.index < ShareStep.prepared.index) {
      job = await prepare(job, trace);
      await _persist(job);
    }

    // The reads, alongside the uploads: who I am, and who my friends are.
    final authorFuture = backend.author();
    final audienceFuture = job.audience != null
        ? Future.value(job.audience!)
        : backend.audience();

    if (job.step.index < ShareStep.uploaded.index) {
      job = await _upload(job, trace);
      _checkCancelled(job.postId);
      await _persist(job);
    }

    if (job.step.index < ShareStep.posted.index) {
      _checkCancelled(job.postId);
      final author = await authorFuture;
      // The friends are decided and kept BEFORE the write, so a rerun
      // after a crash between the two reaches the same people.
      final audience = await audienceFuture;
      job = job.copyWith(audience: audience);
      await _persist(job);
      await backend.createPost(job.postId, job.document(uid, author, audience));
      trace?.mark('post written');
      trace?.friendsCanSee();
      job = job.copyWith(step: ShareStep.posted);
      await _persist(job);
      _setState(job.postId, ShareJobState(ShareJobStatus.posted, attempts: job.attempts));
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
    // Done IS the record gone: nothing is marked done and left behind.
    await _persisting;
    await store.remove(job.postId);
    return job;
  }

  /// Everything the upload needs, on the phone: each photo's bytes in the
  /// job's folder — the file on the phone, the image cache, or the
  /// original, fetched — and, for a milestone, the cover and the
  /// thumbnail rendered from the same bytes.
  Future<ShareJob> prepare(ShareJob job, [ShareTrace? trace]) async {
    final dir = await dirFor(job.postId);
    final photos = [...job.photos];
    final bytes = List<Uint8List?>.filled(photos.length, null);

    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
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
      final path = photos[i].sourceStoragePath;
      if (path == null) throw StateError('photo ${photos[i].id} has no bytes and no source');
      bytes[i] = await backend.download(path);
    });
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      if (p.localPath != null && File(p.localPath!).existsSync()) continue;
      final file = File('${dir.path}/$i.jpg');
      await file.writeAsBytes(bytes[i]!, flush: true);
      photos[i] = p.copyWith(localPath: file.path);
    }
    trace?.mark('bytes gathered', bytes: bytes.fold<int>(0, (s, b) => s + (b?.length ?? 0)));

    String? coverLocal = job.coverLocalPath;
    String? thumbLocal = job.thumbLocalPath;
    if (job.isMilestone &&
        (coverLocal == null || !File(coverLocal).existsSync() ||
            thumbLocal == null || !File(thumbLocal).existsSync())) {
      final images = <ui.Image>[];
      for (final b in bytes.take(kCollageMax)) {
        images.add(await decodeForCover(b!));
      }
      try {
        final framings = [for (final p in photos) p.framing];
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
        final coverFile = File('${dir.path}/cover.jpg');
        final thumbFile = File('${dir.path}/thumb.jpg');
        await coverFile.writeAsBytes(cover, flush: true);
        await thumbFile.writeAsBytes(thumb, flush: true);
        coverLocal = coverFile.path;
        thumbLocal = thumbFile.path;
      } finally {
        for (final i in images) {
          i.dispose();
        }
      }
    }
    trace?.mark('prepared');
    return job.copyWith(
      photos: photos,
      step: ShareStep.prepared,
      coverLocalPath: coverLocal,
      thumbLocalPath: thumbLocal,
    );
  }

  /// One thing to send: its bytes, and what to do with them.
  ({int size, Future<void> Function(UploadProgress onProgress) send}) _unit(
    int size,
    Future<void> Function(UploadProgress onProgress) send,
  ) => (size: size, send: send);

  /// Every file up, four at a time, the bytes counted as they go: each
  /// photo to its post path — the new shot to its private path as well,
  /// from the same bytes — and, for a milestone, the cover and the
  /// thumbnail. What has already landed is counted and not sent again;
  /// each landing is recorded as it happens.
  Future<ShareJob> _upload(ShareJob job, ShareTrace? trace) async {
    final uid = backend.uid;
    final photos = [...job.photos];
    String? coverUrl = job.coverUrl, coverPath = job.coverStoragePath;
    String? thumbUrl = job.thumbUrl, thumbPath = job.thumbStoragePath;

    Future<Uint8List> read(String? path, String what) async {
      if (path == null || !File(path).existsSync()) {
        throw StateError('$what is not on the phone (${path ?? 'no path'})');
      }
      return File(path).readAsBytes();
    }

    int sizeOf(String? path) => path == null || !File(path).existsSync() ? 0 : File(path).lengthSync();

    final units = <({int size, Future<void> Function(UploadProgress) send})>[];
    var already = 0;
    Future<void> record() => _persist(
      job.copyWith(
        photos: photos,
        coverUrl: coverUrl,
        coverStoragePath: coverPath,
        thumbUrl: thumbUrl,
        thumbStoragePath: thumbPath,
      ),
    );

    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      final size = sizeOf(p.localPath);
      if (p.url == null) {
        units.add(_unit(size, (onProgress) async {
          final data = await read(p.localPath, 'photo ${p.id}');
          final path = ShareJob.photoPath(uid, job.postId, i);
          final url = await backend.upload(path, data, onProgress: onProgress);
          photos[i] = photos[i].uploaded(url, path);
          await record();
        }));
      } else {
        already += size;
      }
      if (p.isNew && job.shotPhotoId != null) {
        if (p.privateSaved) {
          already += size;
        } else {
          units.add(_unit(size, (onProgress) async {
            final data = await read(p.localPath, 'photo ${p.id}');
            await _savePrivately(job, data, onProgress);
            photos[i] = photos[i].copyWith(privateSaved: true);
            await record();
          }));
        }
      }
    }
    if (job.isMilestone) {
      final coverSize = sizeOf(job.coverLocalPath);
      final thumbSize = sizeOf(job.thumbLocalPath);
      if (coverUrl == null) {
        units.add(_unit(coverSize, (onProgress) async {
          final data = await read(job.coverLocalPath, 'the cover');
          coverPath = ShareJob.coverPath(uid, job.postId);
          coverUrl = await backend.upload(coverPath!, data, onProgress: onProgress);
          await record();
        }));
      } else {
        already += coverSize;
      }
      if (thumbUrl == null) {
        units.add(_unit(thumbSize, (onProgress) async {
          final data = await read(job.thumbLocalPath, 'the thumbnail');
          thumbPath = ShareJob.thumbPath(uid, job.postId);
          thumbUrl = await backend.upload(thumbPath!, data, onProgress: onProgress);
          await record();
        }));
      } else {
        already += thumbSize;
      }
    }

    final total = already + units.fold<int>(0, (s, u) => s + u.size);
    final sent = List<int>.filled(units.length, 0);
    void report() => _progress(job.postId, already + sent.fold<int>(0, (s, b) => s + b), total);
    report();
    await _inParallel(List.generate(units.length, (i) => i), (i) async {
      await units[i].send((n) {
        sent[i] = n.clamp(0, units[i].size);
        report();
      });
      sent[i] = units[i].size;
      report();
    });
    trace?.mark('uploads done', bytes: total);
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
  Future<void> _savePrivately(ShareJob job, Uint8List data, UploadProgress onProgress) async {
    final uid = backend.uid;
    final photoId = job.shotPhotoId!;
    final path = ShareJob.privatePhotoPath(uid, photoId);
    final url = await backend.upload(path, data, onProgress: onProgress);
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

  /// The job's folder, and any file of its that lies elsewhere, gone.
  Future<void> _deleteLocal(ShareJob job) async {
    for (final path in [
      for (final p in job.photos) ?p.localPath,
      ?job.coverLocalPath,
      ?job.thumbLocalPath,
    ]) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    try {
      final dir = await dirFor(job.postId);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// What the launch triage decided.
enum TriageKind { done, discard, run }

@immutable
class Triage {
  const Triage(this.kind, {this.reason, this.check});
  final TriageKind kind;
  final String? reason;
  final PostCheck? check;
}

/// A failure as a short code: the plugin's own where there is one.
String describeShareError(Object e) {
  final s = e.toString();
  final m = RegExp(r'\[([a-z_]+/[a-z\-]+)\]').firstMatch(s);
  if (m != null) return m.group(1)!;
  final text = s.replaceFirst(RegExp(r'^(Bad state|Exception|Error): '), '');
  return '${e.runtimeType}: ${text.length > 80 ? '${text.substring(0, 80)}…' : text}';
}

/// One account's store on the device, or memory where there are no
/// preferences.
ShareJobStore shareJobStoreFor(String uid) {
  try {
    return PrefsShareJobStore(uid: uid);
  } catch (e) {
    debugPrint('SONDR share job store unavailable: ${e.runtimeType}');
    return MemoryShareJobStore();
  }
}
