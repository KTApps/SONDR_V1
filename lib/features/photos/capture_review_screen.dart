
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import 'capture_crop.dart';
import 'models/photo.dart';
import 'sondr_camera.dart';

/// The band photos chosen, in pool order (chronological).
///
/// Pure, and order-preserving: the post's photos read in the order they were
/// taken, not the order they were tapped. The captured photo is handled
/// separately — it always leads.
List<Photo> selectedBandInOrder(List<Photo> pool, Set<String> selectedIds) => [
  for (final p in pool)
    if (selectedIds.contains(p.id)) p,
];

/// The longest a caption may be.
///
/// Enforced by a formatter rather than by maxLength, which comes with a
/// counter this app did not draw.
const int kCaptionMaxLength = 200;

/// Whether this capture can be posted, and if not, why not.
///
/// A bool said only that Share was absent; the screen has to say what would
/// make it appear, and the two answers are different sentences.
enum ShareState {
  /// Signed in and past 20 hours on this task.
  allowed,

  /// A guest. An account is what is missing, not hours.
  guest,

  /// Signed in, but the task has not reached its first milestone.
  underTwentyHours;

  bool get canShare => this == ShareState.allowed;

  /// What the review screen says in place of Share.
  String get lockedCopy => switch (this) {
    ShareState.allowed => '',
    ShareState.guest => 'Create an account to share',
    ShareState.underTwentyHours => 'Sharing unlocks at 20h',
  };
}

/// What the person did with the capture.
enum ReviewOutcome {
  /// Back to the camera; the shot is discarded.
  retake,

  /// Saved to the private gallery and nothing more.
  kept,

  /// Saved and posted.
  shared,
}

const Key kReviewPhotoKey = Key('sondr-review-photo');
const Key kBandRowKey = Key('sondr-review-band');

/// The band thumbnails under the caption, on a milestone post.
const double kBandThumb = 56;
const double kBandThumbRadius = 10;
const double kBandGap = 8;

/// Review: the shot at the size it was framed at, and what to do with it.
///
/// One screen for every path. It replaces both the old capture preview and
/// the separate caption screen, which between them asked the same question
/// twice and put the photo at two different sizes while doing it.
///
/// Sharing needs a photo and 20 hours on the task. Under either, the screen
/// is just "keep it" — and says why, rather than hiding the possibility.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  const CaptureReviewScreen({
    super.key,
    required this.shot,
    required this.taskName,
    required this.sessionLabel,
    required this.share,
    this.bandPhotos = const [],
    this.onKeep,
    this.onShare,
  });

  /// The cropped JPEG, exactly as it will be stored.
  final Uint8List shot;

  final String taskName;
  final String sessionLabel;

  /// Whether Share is offered, and what to say when it is not.
  final ShareState share;

  /// This milestone band's earlier captures, offered alongside the new one.
  /// Empty on an ordinary session.
  final List<Photo> bandPhotos;

  /// Saves privately. Returns false to keep the screen up on failure.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  /// Saves, then posts with [caption] and the chosen band photos.
  final Future<bool> Function(
    WidgetRef ref,
    String? caption,
    List<Photo> alsoPost,
  )?
  onShare;

  @override
  ConsumerState<CaptureReviewScreen> createState() =>
      _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  final TextEditingController _caption = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _captionFocus = FocusNode();
  final Set<String> _chosen = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Typing a caption must not put the field behind the keyboard.
    _captionFocus.addListener(() {
      if (!_captionFocus.hasFocus || !_scroll.hasClients) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    });
  }

  @override
  void dispose() {
    _caption.dispose();
    _scroll.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  Future<void> _keep() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onKeep?.call(ref) ?? true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Couldn’t save the photo. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(ReviewOutcome.kept);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final text = _caption.text.trim();
    final also = selectedBandInOrder(widget.bandPhotos, _chosen);
    final ok =
        await widget.onShare?.call(ref, text.isEmpty ? null : text, also) ??
        true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Couldn’t create the post. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(ReviewOutcome.shared);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final photoWidth =
        MediaQuery.sizeOf(context).width - 2 * kCameraSideInset * scale;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: kCameraTaskTop * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // retake sits where the task line is on the camera, hard right
              // — the one thing on this screen that goes backwards.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: kSpacingPair * scale),
                  child: SondrAction(
                    label: 'Retake',
                    supporting: true,
                    onPressed: _busy
                        ? null
                        : () =>
                              Navigator.of(context).pop(ReviewOutcome.retake),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          key: kReviewPhotoKey,
                          width: photoWidth,
                          height: photoWidth / kCaptureAspect,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              kViewfinderRadius * scale,
                            ),
                            child: Image.memory(
                              widget.shot,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  ColoredBox(color: tokens.surface),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: kCameraTaskToViewfinder * scale),
                      Text(
                        '${widget.taskName} · ${widget.sessionLabel}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                      if (!widget.share.canShare) ...[
                        SizedBox(height: kSpacingPair * scale),
                        Text(
                          widget.share.lockedCopy,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12 * scale,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ],
                      if (widget.share.canShare) ...[
                        // The band comes BEFORE the caption: what is going
                        // in the post is decided first, and the caption is
                        // written about it. Behind the field it also sat
                        // under the keyboard the moment you started typing.
                        if (widget.bandPhotos.isNotEmpty) ...[
                          SizedBox(height: kSpacingBase * scale),
                          _bandRow(tokens, scale),
                        ],
                        SizedBox(height: kSpacingBase * scale),
                        _captionField(tokens, theme, scale),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                SondrError(_error!, textAlign: TextAlign.center),
                SizedBox(height: kSpacingPair * scale),
              ],
              // Share ABOVE Keep: the primary leads, as it does in every
              // other pair in the app. The order was the other way round
              // for one round on the argument that the quiet way out should
              // come first; on the device it just read as the odd one out.
              if (widget.share.canShare)
                Center(
                  child: SondrAction(
                    label: _busy ? 'Sharing…' : 'Share',
                    onPressed: _busy ? null : _share,
                  ),
                ),
              Center(
                child: SondrAction(
                  label: _busy && !widget.share.canShare ? 'Saving…' : 'Keep',
                  supporting: widget.share.canShare,
                  onPressed: _busy ? null : _keep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _captionField(GreyscaleTokens tokens, ThemeData theme, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kCameraSideInset * scale),
      child: TextField(
        controller: _caption,
        focusNode: _captionFocus,
        maxLines: 3,
        minLines: 1,
        // Enforced, but not announced. maxLength draws Material's own
        // "0/200" beneath the field — unstyled by this app, and reserving
        // its line whether or not anyone is typing. A formatter stops the
        // 201st character and truncates a longer paste just the same, and
        // says nothing while the field is empty.
        inputFormatters: [LengthLimitingTextInputFormatter(kCaptionMaxLength)],
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Add a caption (optional)',
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            color: tokens.textTertiary,
          ),
          filled: true,
          fillColor: tokens.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16 * scale),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// This band's earlier captures. The new one leads and is already in; the
  /// rest are dimmed until chosen, so the row reads as "and these too?".
  Widget _bandRow(GreyscaleTokens tokens, double scale) {
    final size = kBandThumb * scale;
    return SizedBox(
      key: kBandRowKey,
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: kCameraSideInset * scale),
        children: [
          _thumb(child: Image.memory(widget.shot, fit: BoxFit.cover),
              selected: true, onTap: null, scale: scale, tokens: tokens),
          for (final photo in widget.bandPhotos) ...[
            SizedBox(width: kBandGap * scale),
            _thumb(
              child: SondrPhoto(
                url: photo.photoUrl,
                placeholder: (_) => ColoredBox(color: tokens.surface),
                error: (_) => ColoredBox(color: tokens.surface),
              ),
              selected: _chosen.contains(photo.id),
              onTap: () => setState(() {
                if (!_chosen.remove(photo.id)) _chosen.add(photo.id);
              }),
              scale: scale,
              tokens: tokens,
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumb({
    required Widget child,
    required bool selected,
    required VoidCallback? onTap,
    required double scale,
    required GreyscaleTokens tokens,
  }) {
    final size = kBandThumb * scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: selected ? 1 : 0.35,
        child: SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kBandThumbRadius * scale),
            child: child,
          ),
        ),
      ),
    );
  }
}
