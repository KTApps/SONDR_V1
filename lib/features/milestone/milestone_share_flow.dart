import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../photos/models/photo.dart';
import '../shell/main_shell.dart';

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
/// -> caption; Not now -> home.
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

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MilestoneCaptionScreen(
          taskName: widget.taskName,
          milestoneHours: widget.milestoneHours,
          totalHours: widget.totalHours,
          capturedFile: _capturedSelected ? widget.capturedFile : null,
          bandPhotos: selectedBandInOrder(widget.pool, _selectedBand),
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

              Expanded(
                child: hasPool
                    ? _grid(tokens, theme)
                    : _emptyRing(tokens, theme),
              ),

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
              _PrimaryButton(label: 'Continue', onPressed: _continue),
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
  Widget _grid(GreyscaleTokens tokens, ThemeData theme) {
    final tiles = <Widget>[
      if (widget.capturedFile != null)
        _SelectableTile(
          file: widget.capturedFile,
          selected: _capturedSelected,
          onTap: _toggleCaptured,
        ),
      for (final p in widget.pool)
        _SelectableTile(
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
  Widget _emptyRing(GreyscaleTokens tokens, ThemeData theme) {
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

/// Step 5 — caption (optional) + a final preview, then Create. On Create each
/// selected photo is copied into the posts space and a MilestonePost is written;
/// the shell then lands on Feed. Back returns to the picker.
class MilestoneCaptionScreen extends ConsumerStatefulWidget {
  const MilestoneCaptionScreen({
    super.key,
    required this.taskName,
    required this.milestoneHours,
    required this.totalHours,
    required this.capturedFile,
    required this.bandPhotos,
  });

  final String taskName;
  final int milestoneHours;
  final int totalHours;

  /// The captured photo IF it was kept selected, else null.
  final File? capturedFile;

  /// The selected band photos, in order.
  final List<Photo> bandPhotos;

  @override
  ConsumerState<MilestoneCaptionScreen> createState() =>
      _MilestoneCaptionScreenState();
}

class _MilestoneCaptionScreenState
    extends ConsumerState<MilestoneCaptionScreen> {
  final _caption = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Copy each selected photo into the posts space (captured first, then band),
  /// then write the MilestonePost and land on Feed. Fallback: no photos -> a
  /// ring MilestonePost with photos: [].
  Future<void> _create() async {
    final repo = ref.read(postsRepositoryProvider);
    if (repo == null) {
      _toast('Sign in to share milestones.');
      return;
    }
    setState(() => _busy = true);
    try {
      final photos = <PostPhoto>[];
      final file = widget.capturedFile;
      if (file != null) {
        final up = await repo.uploadPostPhoto(file);
        photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
      }
      for (final p in widget.bandPhotos) {
        final up = await repo.copyToPostsSpace(p.storagePath);
        photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
      }
      final text = _caption.text.trim();
      await repo.createMilestonePost(
        taskName: widget.taskName,
        milestoneHours: widget.milestoneHours,
        totalHours: widget.totalHours,
        caption: text.isEmpty ? null : text,
        photos: photos,
      );
      if (!mounted) return;
      // Land on Feed so the fresh post is right there.
      ref.read(selectedTabProvider.notifier).set(1);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      debugPrint('SONDR milestone post error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _toast('Couldn’t create the post. Please try again.');
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
    final hasPhotos =
        widget.capturedFile != null || widget.bandPhotos.isNotEmpty;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasPhotos)
                        _previewGrid()
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: ProgressRing(
                              size: 180,
                              stroke: 180 * 0.09,
                              progress: 1.0,
                              center: Text(
                                '${widget.milestoneHours} hrs',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _caption,
                        maxLines: 3,
                        minLines: 1,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'Add a caption (optional)',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: tokens.textTertiary,
                          ),
                          filled: true,
                          fillColor: tokens.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _PrimaryButton(
                label: 'Create',
                busy: _busy,
                onPressed: _busy ? null : _create,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewGrid() {
    final tiles = <Widget>[
      if (widget.capturedFile != null)
        _SelectableTile(
          file: widget.capturedFile,
          selected: true,
          interactive: false,
        ),
      for (final p in widget.bandPhotos)
        _SelectableTile(url: p.photoUrl, selected: true, interactive: false),
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

/// One pool/preview tile: a File (the capture) or a cached network photo (a band
/// photo), square, with a selected check + a dim scrim when deselected. When
/// [interactive] is false it's a plain always-on preview tile (no scrim/badge).
class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
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

/// Filled greyscale primary button (matches the celebration / timer controls).
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.ringFillOuter,
          foregroundColor: tokens.background,
          disabledBackgroundColor: tokens.ringTrack,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

/// Pop the whole milestone flow back to the shell and land on Home (tab 0) —
/// the "Not now" / decline-to-post exit.
void goHome(WidgetRef ref, BuildContext context) {
  ref.read(selectedTabProvider.notifier).set(0);
  Navigator.of(context).popUntil((r) => r.isFirst);
}
