import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../photos/models/photo.dart';
import 'share_caption_screen.dart';

/// The band photos selected for the post, in pool order (chronological). Pure —
/// the captured photo is handled separately (it always leads), so this is just
/// the band pool filtered to the selection, order preserved. Unit-tested.
List<Photo> selectedBandInOrder(List<Photo> pool, Set<String> selectedIds) => [
  for (final p in pool)
    if (selectedIds.contains(p.id)) p,
];

/// Step 4 — "Share milestone post". The captured photo (if any) is pre-selected;
/// the band pool ([pool] = the celebration's <=9 collageSelection) starts
/// deselected and is *added* by tapping. Tapping toggles; the grid is the live
/// preview of what's in the post (deselect everything -> a ring post). Continue
/// -> the shared caption screen; Not now -> home.
class ShareMilestoneScreen extends ConsumerStatefulWidget {
  const ShareMilestoneScreen({
    super.key,
    required this.taskId,
    required this.taskName,
    required this.milestoneHours,
    required this.totalHours,
    required this.capturedFile,
    required this.pool,
  });

  final String taskId;
  final String taskName;
  final int milestoneHours;
  final int totalHours;

  /// The just-captured photo, or null if the user skipped capture.
  final File? capturedFile;

  /// This band's prior in-app captures (<=9), the pool that can be added.
  final List<Photo> pool;

  @override
  ConsumerState<ShareMilestoneScreen> createState() =>
      _ShareMilestoneScreenState();
}

class _ShareMilestoneScreenState extends ConsumerState<ShareMilestoneScreen> {
  /// Captured photo pre-selected (deselectable); band photos added by tapping.
  late bool _capturedSelected = widget.capturedFile != null;
  final Set<String> _selectedBand = {};

  int get _count => (_capturedSelected ? 1 : 0) + _selectedBand.length;

  void _toggleCaptured() =>
      setState(() => _capturedSelected = !_capturedSelected);

  void _toggleBand(Photo p) => setState(() {
    if (!_selectedBand.remove(p.id)) _selectedBand.add(p.id);
  });

  /// Continue to the shared caption screen with the current selection: the
  /// captured photo (if kept) leads, then the selected band photos in order.
  void _continue() {
    final captured = _capturedSelected ? widget.capturedFile : null;
    final band = selectedBandInOrder(widget.pool, _selectedBand);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharePostCaptionScreen(
          submitLabel: 'Create',
          preview: _MilestonePreview(
            milestoneHours: widget.milestoneHours,
            capturedFile: captured,
            bandPhotos: band,
          ),
          onSubmit: (ref, caption) async {
            final repo = ref.read(postsRepositoryProvider);
            if (repo == null) throw StateError('not signed in');
            // Copy each selected photo into the posts space: captured first
            // (direct upload), then band photos (copy from the gallery original).
            final photos = <PostPhoto>[];
            if (captured != null) {
              final up = await repo.uploadPostPhoto(captured);
              photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
            }
            for (final p in band) {
              final up = await repo.copyToPostsSpace(p.storagePath);
              photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
            }
            await repo.createMilestonePost(
              taskName: widget.taskName,
              milestoneHours: widget.milestoneHours,
              totalHours: widget.totalHours,
              caption: caption,
              photos: photos,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final hasPool = widget.capturedFile != null || widget.pool.isNotEmpty;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share your milestone',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.milestoneHours} hours · ${widget.taskName}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              Expanded(child: hasPool ? _grid() : _emptyRing(theme)),

              const SizedBox(height: 12),
              Text(
                _count == 0
                    ? 'No photos — you’ll post the milestone ring.'
                    : '$_count photo${_count == 1 ? '' : 's'} selected',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textTertiary,
                ),
              ),
              const SizedBox(height: 10),
              SharePrimaryButton(label: 'Continue', onPressed: _continue),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => goHome(ref, context),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The selectable pool: the captured photo first (if any), then band photos.
  Widget _grid() {
    final tiles = <Widget>[
      if (widget.capturedFile != null)
        SelectablePhotoTile(
          file: widget.capturedFile,
          selected: _capturedSelected,
          onTap: _toggleCaptured,
        ),
      for (final p in widget.pool)
        SelectablePhotoTile(
          url: p.photoUrl,
          selected: _selectedBand.contains(p.id),
          onTap: () => _toggleBand(p),
        ),
    ];
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: tiles,
    );
  }

  /// No photos to pick — show the milestone ring (what a photoless post is).
  Widget _emptyRing(ThemeData theme) {
    return Center(
      child: ProgressRing(
        size: 200,
        stroke: 200 * 0.09,
        progress: 1.0,
        center: Text(
          '${widget.milestoneHours} hrs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The caption-screen preview for a milestone post: the selected photos as a
/// grid, or the milestone ring when none were selected.
class _MilestonePreview extends StatelessWidget {
  const _MilestonePreview({
    required this.milestoneHours,
    required this.capturedFile,
    required this.bandPhotos,
  });

  final int milestoneHours;
  final File? capturedFile;
  final List<Photo> bandPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhotos = capturedFile != null || bandPhotos.isNotEmpty;
    if (!hasPhotos) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: ProgressRing(
            size: 180,
            stroke: 180 * 0.09,
            progress: 1.0,
            center: Text(
              '$milestoneHours hrs',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    final tiles = <Widget>[
      if (capturedFile != null)
        SelectablePhotoTile(
          file: capturedFile,
          selected: true,
          interactive: false,
        ),
      for (final p in bandPhotos)
        SelectablePhotoTile(
          url: p.photoUrl,
          selected: true,
          interactive: false,
        ),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: tiles,
    );
  }
}

/// One pool/preview tile: a File (a capture) or a cached network photo (a band
/// photo), square, with a selected check + a dim scrim when deselected. When
/// [interactive] is false it's a plain always-on preview tile (no scrim/badge).
class SelectablePhotoTile extends StatelessWidget {
  const SelectablePhotoTile({
    super.key,
    this.file,
    this.url,
    required this.selected,
    this.onTap,
    this.interactive = true,
  });

  final File? file;
  final String? url;
  final bool selected;
  final VoidCallback? onTap;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final image = file != null
        ? Image.file(file!, fit: BoxFit.cover)
        : SondrPhoto(
            url: url!,
            placeholder: (_) => ColoredBox(color: tokens.surface),
            error: (_) => ColoredBox(color: tokens.ringTrack),
          );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (interactive && !selected)
              ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            if (interactive)
              Positioned(
                top: 6,
                right: 6,
                child: _CheckBadge(selected: selected, tokens: tokens),
              ),
          ],
        ),
      ),
    );
  }
}

/// The per-tile selected marker: a filled check when in, a hollow ring when out.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.selected, required this.tokens});

  final bool selected;
  final GreyscaleTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? tokens.textPrimary
            : Colors.black.withValues(alpha: 0.35),
        border: selected ? null : Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? Icon(Icons.check, size: 14, color: tokens.background)
          : null,
    );
  }
}
