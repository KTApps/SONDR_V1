import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/blur_sheet.dart';
import '../../shared/cached_photo.dart';
import '../auth/account_cascade.dart' show profilePhotoPathOf;
import '../auth/profile_repository.dart';
import '../photos/capture_crop.dart' show kCaptureQuality;
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../photos/sondr_camera.dart';
import 'public_profile.dart';

/// The chosen profile photo: a square copy of one of your own photos, at
/// `users/{uid}/profile/photo.jpg`, readable by anyone signed in.
///
/// The choice is recorded in your own profile and published with the rest
/// of `publicProfiles/{uid}`, so it reaches everyone who opens your page —
/// strangers included, which is the one thing the private original never
/// does. Deleting the original leaves the copy.

/// The copy's side, in pixels.
const int kProfilePhotoSize = 600;

/// How many of your photos the picker offers, newest first.
const int kProfilePhotoChoices = 60;

/// The sheet's words.
const String kProfilePhotoTitle = 'Profile photo';
const String kUseThisPhoto = 'Use this photo';
const String kTakeANewOne = 'Take a new one';
const String kUseMyNewestPhoto = 'Use my newest photo';
const String kProfilePhotoFailed = 'Couldn’t change your photo. Try again.';

/// What the camera says above the viewfinder when the shot is for the
/// profile — alone, since the shot belongs to no task.
const String kProfilePhotoCameraLabel = 'Profile photo';

/// [bytes] cut to the biggest centred square and scaled to
/// [kProfilePhotoSize], as a JPEG. Null when the bytes are not an image.
Uint8List? squareProfileJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final side = upright.width < upright.height ? upright.width : upright.height;
  final square = img.copyCrop(
    upright,
    x: ((upright.width - side) / 2).round(),
    y: ((upright.height - side) / 2).round(),
    width: side,
    height: side,
  );
  final sized = img.copyResize(
    square,
    width: kProfilePhotoSize,
    height: kProfilePhotoSize,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(sized, quality: kCaptureQuality);
}

/// Where the copy's bytes come from and go to. A seam: Storage has nothing
/// on the other end of it in a test.
abstract interface class ProfilePhotoFiles {
  /// The original's bytes, from its private path.
  Future<Uint8List?> bytesOf(Photo photo);

  /// Put the copy at [path]; returns its download URL.
  Future<String> put(String path, Uint8List jpeg);

  /// Take the copy down. Already gone is not a failure.
  Future<void> remove(String path);
}

class FirebaseProfilePhotoFiles implements ProfilePhotoFiles {
  FirebaseProfilePhotoFiles({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<Uint8List?> bytesOf(Photo photo) =>
      _storage.ref(photo.storagePath).getData(10 * 1024 * 1024);

  @override
  Future<String> put(String path, Uint8List jpeg) async {
    final ref = _storage.ref(path);
    await ref.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  @override
  Future<void> remove(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

final profilePhotoFilesProvider = Provider<ProfilePhotoFiles>(
  (ref) => FirebaseProfilePhotoFiles(),
);

/// Choosing and clearing, in one place, behind a seam so the sheet's tests
/// need neither Storage nor Firestore.
abstract interface class ProfilePhotoChooser {
  /// Make [photo] the profile photo, read from the original. Returns
  /// whether it is done.
  Future<bool> choose(Photo photo);

  /// Make a shot just taken the profile photo. It goes nowhere else: no
  /// task, no photo of yours, only the profile copy.
  Future<bool> useShot(Uint8List shot);

  /// No chosen photo: the newest stands in the ring again.
  Future<bool> clear();
}

class FirebaseProfilePhotoChooser implements ProfilePhotoChooser {
  FirebaseProfilePhotoChooser({
    required this.uid,
    required this.profiles,
    required this.files,
    required this.publish,
    required this.changed,
    this.square = squareProfileJpegAsync,
  });

  final String uid;
  final ProfileRepository profiles;
  final ProfilePhotoFiles files;

  /// Publishes the public profile, which carries the photo to everyone.
  final Future<void> Function() publish;

  /// Called once the choice is recorded, before publishing, so the profile
  /// the publish reads is the new one.
  final void Function() changed;

  final Future<Uint8List?> Function(Uint8List bytes) square;

  @override
  Future<bool> choose(Photo photo) async {
    try {
      final source = await files.bytesOf(photo);
      if (source == null) return false;
      return await _use(source, sourceId: photo.id);
    } catch (e) {
      debugPrint('SONDR profile photo error: ${e.runtimeType} :: $e');
      return false;
    }
  }

  @override
  Future<bool> useShot(Uint8List shot) async {
    try {
      return await _use(shot);
    } catch (e) {
      debugPrint('SONDR profile photo error: ${e.runtimeType} :: $e');
      return false;
    }
  }

  /// Square [source], store it, record it, publish it.
  Future<bool> _use(Uint8List source, {String? sourceId}) async {
    final jpeg = await square(source);
    if (jpeg == null) return false;
    final path = profilePhotoPathOf(uid);
    final url = await files.put(path, jpeg);
    await profiles.setPhoto(uid, url: url, path: path, sourceId: sourceId);
    changed();
    await publish();
    return true;
  }

  @override
  Future<bool> clear() async {
    try {
      await profiles.clearPhoto(uid);
      changed();
      await publish();
      // The file last: a failure to remove it leaves a copy nobody points
      // at, not a profile pointing at nothing.
      await files.remove(profilePhotoPathOf(uid));
      return true;
    } catch (e) {
      debugPrint('SONDR profile photo clear error: ${e.runtimeType} :: $e');
      return false;
    }
  }
}

/// [squareProfileJpeg] off the UI thread.
Future<Uint8List?> squareProfileJpegAsync(Uint8List bytes) =>
    compute(squareProfileJpeg, bytes);

/// Null where there is no account to choose for.
final profilePhotoChooserProvider = Provider<ProfilePhotoChooser?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final profiles = ref.watch(profileRepositoryProvider);
  if (uid == null || profiles == null) return null;
  return FirebaseProfilePhotoChooser(
    uid: uid,
    profiles: profiles,
    files: ref.watch(profilePhotoFilesProvider),
    publish: () => ref.read(publishPublicProfileProvider)(),
    changed: () => ref.invalidate(currentProfileProvider),
  );
});

/// Your photos for the picker, newest first.
final profilePhotoChoicesProvider = FutureProvider.autoDispose<List<Photo>>((ref) async {
  final repo = ref.watch(photosRepositoryProvider);
  if (repo == null) return const <Photo>[];
  return repo.photosRecent(kProfilePhotoChoices);
});

/// The sheet behind a tap on your own Profile's photo.
///
/// Your photos as circles, three across, the chosen one ringed; tap one to
/// pick it. "Use this photo" once the pick differs from what is chosen,
/// "Take a new one" for the camera, "Use my newest photo" to go back to no
/// choice, and Back.
Future<void> showProfilePhotoSheet(BuildContext context, WidgetRef ref) async {
  final chooser = ref.read(profilePhotoChooserProvider);
  if (chooser == null) return;
  final profile = ref.read(currentProfileProvider).value;
  final chosen = profile?.photoSourceId;
  final hasChoice = profile?.photoUrl != null;
  final photos = await ref.read(profilePhotoChoicesProvider.future);
  if (!context.mounted) return;

  String? picked = chosen;
  String? error;
  var busy = false;
  late BlurView Function(BlurSheetHandle handle) view;

  /// [op] answers true when done, false when it failed, and null when
  /// nothing happened (the camera was skipped) — which says nothing.
  Future<void> run(BlurSheetHandle handle, Future<bool?> Function() op) async {
    if (busy) return;
    busy = true;
    final ok = await op();
    busy = false;
    if (ok == null) return;
    if (ok) {
      handle.close();
    } else {
      error = kProfilePhotoFailed;
      handle.update(view(handle));
    }
  }

  view = (handle) {
    final pick = photos.where((p) => p.id == picked).firstOrNull;
    final canUse = pick != null && picked != chosen;
    return BlurView(
      title: kProfilePhotoTitle,
      explanation: error,
      body: photos.isEmpty
          ? null
          : ProfilePhotoGrid(
              photos: photos,
              picked: picked,
              onPick: (id) {
                picked = id;
                handle.update(view(handle));
              },
            ),
      items: [
        if (photos.isNotEmpty)
          BlurItem(
            label: kUseThisPhoto,
            // Grey and inert until there is something new to use.
            quiet: !canUse,
            onTap: () {
              if (!canUse) return;
              run(handle, () => chooser.choose(pick));
            },
          ),
        BlurItem(
          label: kTakeANewOne,
          onTap: () => run(handle, () async {
            final shot = await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const SondrCameraScreen(
                  taskName: null,
                  sessionLabel: kProfilePhotoCameraLabel,
                  ringProgress: 0,
                ),
              ),
            );
            // Skipped: nothing changes, and the sheet stays.
            if (shot == null) return null;
            return chooser.useShot(shot);
          }),
        ),
        if (hasChoice)
          BlurItem(
            label: kUseMyNewestPhoto,
            secondary: true,
            onTap: () => run(handle, chooser.clear),
          ),
      ],
    );
  };

  await showBlurSheet(context, view);
}

/// The picker's photos: circles, three across, newest first, the picked one
/// ringed 2pt in the text tone. Scrolls within itself past three rows, so
/// the answers under it never move.
class ProfilePhotoGrid extends StatelessWidget {
  const ProfilePhotoGrid({
    super.key,
    required this.photos,
    required this.picked,
    required this.onPick,
  });

  final List<Photo> photos;
  final String? picked;
  final ValueChanged<String> onPick;

  static const int columns = 3;
  static const int visibleRows = 3;
  static const double gap = 12;
  static const double ring = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return LayoutBuilder(
      builder: (context, box) {
        final spacing = gap * scale;
        final side = (box.maxWidth - spacing * (columns - 1)) / columns;
        final rows = (photos.length / columns).ceil();
        final shown = rows < visibleRows ? rows : visibleRows;
        return Padding(
          padding: EdgeInsets.only(bottom: kBlurItemPad * scale),
          child: SizedBox(
            height: shown * side + (shown - 1) * spacing,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              itemCount: photos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
              ),
              itemBuilder: (context, i) {
                final p = photos[i];
                final on = p.id == picked;
                return GestureDetector(
                  key: ValueKey('profile-photo-${p.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(p.id),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: on
                          ? Border.all(color: tokens.textPrimary, width: ring)
                          : null,
                    ),
                    child: ClipOval(
                      child: SondrPhoto(
                        url: p.photoUrl,
                        placeholder: (_) => ColoredBox(color: tokens.surface),
                        error: (_) => ColoredBox(color: tokens.surface),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
