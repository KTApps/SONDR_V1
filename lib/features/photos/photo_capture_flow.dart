import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../shared/ring/progress_ring.dart';
import 'models/photo.dart';
import 'photo_picker.dart';
import 'photos_repository.dart';

/// Show the optional end-of-session photo capture as a full-screen moment, over
/// the home dial. Resolves when the user keeps a photo, skips, or dismisses —
/// the caller just awaits and lands back on home either way.
///
/// Only call this when a task was actually credited ([taskId] non-null upstream)
/// and the session logged time — a photo must never exist without a task.
Future<void> showPhotoCapture(
  BuildContext context, {
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  int? milestoneHours,
  int? cumulativeSeconds,
}) {
  return Navigator.of(context).push(
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

  /// Lens tap / retake: pick (and downscale) a photo into the preview state.
  Future<void> _pick() async {
    final file = await pickAndDownscale(context);
    if (file != null && mounted) setState(() => _photo = file);
  }

  /// Leave with no photo — skip on the lens, or × on the preview.
  void _dismiss() => Navigator.of(context).pop();

  /// Commit: upload the binary, then write the private photo doc with the full
  /// session snapshot, then land back on home.
  Future<void> _keep() async {
    final repo = ref.read(photosRepositoryProvider);
    if (repo == null) {
      _toast('Sign in to save photos.');
      return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch;
    final photoId = Photo.docId(widget.taskId, timestamp);
    try {
      final up = await repo.uploadPhoto(_photo!, photoId: photoId);
      await repo.savePhoto(Photo(
        taskId: widget.taskId,
        taskName: widget.taskName,
        dayKey: DayKey.of(now),
        timestamp: timestamp,
        sessionSeconds: widget.sessionSeconds,
        photoUrl: up.url,
        storagePath: up.storagePath,
        milestoneHours: widget.milestoneHours,
        cumulativeSeconds: widget.cumulativeSeconds,
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('SONDR photo save error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _toast('Couldn’t save the photo. Please try again.');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    return Column(
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
            center: Icon(Icons.camera_alt_outlined,
                size: 44, color: tokens.textPrimary),
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
              if (_busy)
                SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tokens.textPrimary),
                )
              else
                _keepRetake(tokens, theme),
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

  Widget _keepRetake(GreyscaleTokens tokens, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "keep" is the primary commit — the filled white pill, matching Focus
        // Mode's "Stop" button (same shape, fill, and label style).
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _keep,
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.ringFillOuter,
              foregroundColor: tokens.background,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle: theme.textTheme.labelLarge,
            ),
            child: const Text('keep'),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _pick,
          style: TextButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            textStyle: theme.textTheme.labelLarge,
          ),
          child: const Text('retake'),
        ),
      ],
    );
  }
}
