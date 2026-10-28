import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:sondr/features/feed/jpeg_encoder.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/share_job.dart';
import 'package:sondr/features/photos/models/photo.dart';

/// A share backend that records and can be told to fail, so the runner's
/// rules — the order, the retries, the idempotency, the post only at the
/// end — are falsified rather than hoped for.
class FakeShareBackend implements ShareBackend {
  @override
  String get uid => 'me';

  /// Which call throws, and how many times, before working.
  String? failAt;
  int failTimes = 1;
  bool noticesDenied = false;

  int ids = 0;
  final List<String> calls = [];
  final Map<String, int> uploads = {};
  final Map<String, Map<String, dynamic>> posts = {};
  final List<Photo> savedPhotos = [];
  final List<(String, int, String)> crossings = [];
  final List<List<String>> notices = [];
  final List<String> covers = [];
  final List<List<String>> tagged = [];
  final List<List<String>> deleted = [];
  final Map<String, Uint8List> originals = {};
  int downloads = 0;

  /// Lets a test hold every upload open.
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
  Future<String> upload(String path, Uint8List bytes, {UploadProgress? onProgress}) async {
    if (holdUploads != null) await holdUploads!.future;
    _maybeFail('upload');
    // Half way, then the whole, as Storage reports.
    onProgress?.call(bytes.length ~/ 2);
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(bytes.length);
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
  Future<void> createPost(String postId, Map<String, dynamic> doc) async {
    _maybeFail('createPost');
    posts[postId] = doc;
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

/// An encoder that encodes nothing: three bytes stand for the JPEG.
class NoEncode implements JpegEncoder {
  @override
  Future<Uint8List> encode(ui.Image image, {required int quality}) async =>
      Uint8List.fromList([0xFF, 0xD8, quality]);
}
