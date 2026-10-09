import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/utils/figma_scale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../core/utils/date.dart';
import '../../shared/ring/progress_ring.dart';
import 'models/photo.dart';
import 'photo_picker.dart';
import 'photos_repository.dart';

/// A kept capture: the local [file] the share flows preview and upload, and the
/// [photoId] of the gallery document it was just saved as.
///
/// The id travels with the file because a share needs to tag its SOURCE photo,
/// and the only place that id exists is the moment of the save — it is derived
/// from the capture's own microsecond, so nothing downstream could recompute
/// it.
typedef KeptCapture = ({File file, String photoId});

/// Show the optional end-of-session photo capture as a full-screen moment, over
/// the home dial. Resolves to the [KeptCapture] (or null if the user
/// skipped/dismissed) — an ordinary stop ignores it and lands back on home,
/// while the share flows carry the kept file forward to pre-select it.
///
/// Capture is camera-only everywhere (see [captureFromCamera]).
///
/// Only call this when a task was actually credited ([taskId] non-null upstream)
/// and the session logged time — a photo must never exist without a task.
Future<KeptCapture?> showPhotoCapture(
  BuildContext context, {
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  int? milestoneHours,
  int? cumulativeSeconds,
}) {
  return Navigator.of(context).push<KeptCapture>(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => PhotoCaptureScreen(
        taskId: taskId,
        taskName: taskName,
        sessionSeconds: sessionSeconds,
        milestoneHours: milestoneHours,
        cumulativeSeconds: cumulativeSeconds,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The capture surface. Two states on one screen:
///  - **lens**: the just-earned ring holds a camera lens; tap to pick, or "skip".
///  - **preview**: the chosen photo as a rounded rectangle, "retake · keep", and
///    an × to dismiss. "keep" uploads + writes the private photo doc.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({
    super.key,
    required this.taskId,
    required this.taskName,
    required this.sessionSeconds,
    this.milestoneHours,
    this.cumulativeSeconds,
  });

  final String taskId;
  final String taskName;
  final int sessionSeconds;
  final int? milestoneHours;
  final int? cumulativeSeconds;

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  File? _photo;
  bool _busy = false;
  String? _error;

  /// Lens tap / retake: capture (and downscale) a photo into the preview state.
  /// Camera-only everywhere.
  Future<void> _pick() async {
    final file = await captureFromCamera(context, onError: _say);
    if (file != null && mounted) setState(() => _photo = file);
  }

  /// Leave with no photo — skip on the lens, or × on the preview.
  void _dismiss() => Navigator.of(context).pop();

  /// Commit: upload the binary, then write the private photo doc with the full
  /// session snapshot, then land back on home.
  Future<void> _keep() async {
    final repo = ref.read(photosRepositoryProvider);
    if (repo == null) {
      _say('Sign in to save photos.');
      return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch;
    final photoId = Photo.docId(widget.taskId, timestamp);
    try {
      final up = await repo.uploadPhoto(_photo!, photoId: photoId);
      await repo.savePhoto(
        Photo(
          taskId: widget.taskId,
          taskName: widget.taskName,
          dayKey: DayKey.of(now),
          timestamp: timestamp,
          sessionSeconds: widget.sessionSeconds,
          photoUrl: up.url,
          storagePath: up.storagePath,
          milestoneHours: widget.milestoneHours,
          cumulativeSeconds: widget.cumulativeSeconds,
        ),
      );
      if (!mounted) return;
      // Return the kept file AND the id it was saved under, so the milestone
      // flow can carry it forward (pre-selected in the share picker) and tag
      // the gallery original if it gets posted. Ordinary stops ignore both.
      Navigator.of(context).pop((file: _photo!, photoId: photoId));
    } catch (e) {
      debugPrint('SONDR photo save error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _say('Couldn’t save the photo. Please try again.');
      }
    }
  }

  void _say(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: _photo == null ? _lens(tokens, theme) : _preview(tokens, theme),
      ),
    );
  }

  /// Camera inside the ring + a text-only "skip", under a quiet "CAPTURE" label
  /// (a sibling of Focus Mode's "FOCUS").
  Widget _lens(GreyscaleTokens tokens, ThemeData theme) {
    // Full width so the column centres horizontally; on its own it shrinks to
    // the ring's width and sits at the left edge.
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'CAPTURE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: tokens.textTertiary,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _pick,
            child: ProgressRing(
              size: 260,
              stroke: 260 * 0.09,
              progress: 1.0,
              center: Icon(
                Icons.camera_alt_outlined,
                size: 44,
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 44),
          TextButton(
            onPressed: _dismiss,
            style: TextButton.styleFrom(
              // Deliberately recessed — passing on a photo should feel
              // low-pressure, quietly there rather than competing for attention.
              foregroundColor: tokens.textTertiary,
              textStyle: theme.textTheme.labelLarge,
            ),
            child: const Text('skip'),
          ),
        ],
      ),
    );
  }

  /// The picked photo, "retake · keep", and an × to dismiss.
  Widget _preview(GreyscaleTokens tokens, ThemeData theme) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.file(_photo!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 32),
              if (_error != null) ...[
                SondrError(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              _keepRetake(),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            onPressed: _busy ? null : _dismiss,
            icon: Icon(Icons.close, color: tokens.textSecondary),
          ),
        ),
      ],
    );
  }

  /// keep | retake — side by side at the pair's own spacing, but NOT equals:
  /// keep is the forward action and stays white, retake is the go-back and
  /// takes the supporting tone, mirroring Delete/Close and the guest
  /// landing. SondrActionPair would render both at full emphasis, so the row
  /// is built by hand and borrows only its gap.
  Widget _keepRetake() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SondrAction(
          label: _busy ? 'saving…' : 'keep',
          onPressed: _busy ? null : _keep,
        ),
        SizedBox(width: SondrActionPair.gap * figmaScale(context)),
        SondrAction(
          label: 'retake',
          supporting: true,
          onPressed: _busy ? null : _pick,
        ),
      ],
    );
  }
}
