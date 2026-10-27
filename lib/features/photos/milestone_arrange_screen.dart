import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_prompt.dart';
import '../feed/collage_layout.dart';
import '../feed/widgets/milestone_card.dart' show kMilestoneCardRadius;
import '../feed/widgets/milestone_cover.dart';
import '../feed/widgets/milestone_frame.dart';
import '../feed/widgets/milestone_ring.dart';
import 'capture_crop.dart';
import 'milestone_arrangement.dart';

/// Arrange: the milestone's collage as the card will show it, and the
/// band's photos beneath to choose from. Tap a photo in the strip to put
/// it in or take it out; long-press a tile and drag it onto another to
/// swap them; tap a tile and pinch or drag to frame the photo inside it.
/// One screen, no scrolling. Next goes on to the final look; Keep saves
/// the shot privately and ends the journey; Retake reopens the camera.

/// What the person did here.
enum ArrangeOutcomeKind { retake, kept, next }

@immutable
class ArrangeOutcome {
  const ArrangeOutcome(this.kind, {this.arrangement});

  final ArrangeOutcomeKind kind;

  /// The arrangement as left, for Next and for Retake — a retake replaces
  /// the shot and keeps everything else.
  final Arrangement? arrangement;
}

/// The feed's gutter: the preview is the card at the card's width.
const double kArrangeGutter = 16;

/// The strip's tiles: 3:4 at 46 across, 8 radius, 6 apart.
const double kArrangeTileWidth = 46;
const double kArrangeTileHeight = 61;
const double kArrangeTileRadius = 8;
const double kArrangeTileGap = 6;

/// Air beneath the top row and between the blocks.
const double kArrangeTop = 12;
const double kArrangeGap = 12;
const double kArrangeHelpGap = 8;

const String kArrangeHelp = 'Tap to add · Drag to swap · Pinch to frame';
const String kArrangeFullHelp = 'Up to 9 photos';
const Duration kArrangeFullHelpFor = Duration(milliseconds: 1500);

/// How a chosen tile is drawn as the one being framed.
const double kArrangeOutline = 2;

/// The question Keep asks.
const String kKeepTitle = 'Keep it private?';
const String kKeepBody = 'It’s saved to your milestones. Only you will see it.';

const Key kArrangePreviewKey = Key('sondr-arrange-preview');
const Key kArrangeStripKey = Key('sondr-arrange-strip');
const Key kArrangeHelpKey = Key('sondr-arrange-help');

class MilestoneArrangeScreen extends ConsumerStatefulWidget {
  const MilestoneArrangeScreen({
    super.key,
    required this.entries,
    required this.milestoneHours,
    this.initial,
    this.onKeep,
  });

  /// Every photo of the band, oldest first, the new shot last.
  final List<ArrangeEntry> entries;

  final int milestoneHours;

  /// Where a previous visit left things — coming back from the final
  /// look, or back from a retake.
  final Arrangement? initial;

  /// Saves the shot privately. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  bool get hasShot => entries.any((e) => e.isNew);

  @override
  ConsumerState<MilestoneArrangeScreen> createState() => _MilestoneArrangeScreenState();
}

class _MilestoneArrangeScreenState extends ConsumerState<MilestoneArrangeScreen> {
  late Arrangement _arrangement =
      widget.initial ?? Arrangement.initial(widget.entries);

  /// The tile being framed, if one is.
  String? _selected;

  /// The tile picked up, and where its grab point is now, in the
  /// preview's coordinates.
  String? _dragging;
  Offset _dragAt = Offset.zero;
  Offset _grab = Offset.zero;

  /// The framing a pinch began from.
  PhotoFraming? _frameBase;
  Offset? _frameFocal;

  String? _help;
  Timer? _helpTimer;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _helpTimer?.cancel();
    super.dispose();
  }

  ArrangeEntry _entry(String id) => widget.entries.firstWhere((e) => e.id == id);

  void _toggle(String id) {
    final next = _arrangement.toggled(id);
    if (next == null) {
      _helpTimer?.cancel();
      setState(() => _help = kArrangeFullHelp);
      _helpTimer = Timer(kArrangeFullHelpFor, () {
        if (mounted) setState(() => _help = null);
      });
      return;
    }
    setState(() {
      _arrangement = next;
      if (!next.contains(id)) _selected = null;
    });
  }

  Future<void> _keep() async {
    if (_busy) return;
    final yes = await showSondrConfirm(
      context,
      title: kKeepTitle,
      body: kKeepBody,
      confirmLabel: 'Keep',
    );
    if (!yes || !mounted) return;
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
    Navigator.of(context).pop(const ArrangeOutcome(ArrangeOutcomeKind.kept));
  }

  void _retake() => Navigator.of(context).pop(
    ArrangeOutcome(ArrangeOutcomeKind.retake, arrangement: _arrangement),
  );

  void _next() => Navigator.of(context).pop(
    ArrangeOutcome(ArrangeOutcomeKind.next, arrangement: _arrangement),
  );

  // --- the tiles' gestures -------------------------------------------------

  void _select(String id) => setState(() => _selected = id);

  void _deselect() {
    if (_selected != null) setState(() => _selected = null);
  }

  void _pickUp(String id, Rect tile, Offset local) {
    HapticFeedback.lightImpact();
    setState(() {
      _dragging = id;
      _grab = local;
      _dragAt = tile.topLeft + local;
    });
  }

  void _drag(Rect tile, Offset offsetFromOrigin) {
    setState(() => _dragAt = tile.topLeft + _grab + offsetFromOrigin);
  }

  void _drop(List<Rect> tiles) {
    final from = _arrangement.order.indexOf(_dragging ?? '');
    final to = tiles.indexWhere((r) => r.contains(_dragAt));
    setState(() {
      if (from >= 0 && to >= 0) _arrangement = _arrangement.swapped(from, to);
      _dragging = null;
    });
  }

  void _frameStart(String id, Offset focal) {
    _frameBase = _arrangement.framingOf(id);
    _frameFocal = focal;
  }

  void _frameUpdate(String id, Size tile, double scale, Offset focal) {
    final base = _frameBase;
    final start = _frameFocal;
    if (base == null || start == null) return;
    final delta = focal - start;
    setState(() {
      _arrangement = _arrangement.framed(
        id,
        PhotoFraming(
          scale: base.scale * scale,
          dx: base.dx + delta.dx / tile.width,
          dy: base.dy + delta.dy / tile.height,
        ),
      );
    });
  }

  // --- the screen ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final width = MediaQuery.sizeOf(context).width - 2 * kArrangeGutter;
    final frame = Size(width, width / kCaptureAspect);

    return Scaffold(
      backgroundColor: tokens.background,
      body: GestureDetector(
        // A tap anywhere that is not a tile lets the framed tile go.
        behavior: HitTestBehavior.translucent,
        onTap: _deselect,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kArrangeTop * scale),
              Row(
                children: [
                  SondrAction(
                    label: 'Keep',
                    supporting: true,
                    fontSize: 14,
                    onPressed: _busy ? null : _keep,
                  ),
                  const Spacer(),
                  if (widget.hasShot)
                    SondrAction(
                      label: 'Retake',
                      supporting: true,
                      fontSize: 14,
                      onPressed: _busy ? null : _retake,
                    ),
                ],
              ),
              Center(
                child: ClipRRect(
                  key: kArrangePreviewKey,
                  borderRadius: BorderRadius.circular(kMilestoneCardRadius),
                  child: SizedBox.fromSize(size: frame, child: _preview(frame)),
                ),
              ),
              SizedBox(height: kArrangeGap * scale),
              _strip(scale),
              SizedBox(height: kArrangeHelpGap * scale),
              Text(
                _help ?? kArrangeHelp,
                key: kArrangeHelpKey,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  color: tokens.textTertiary,
                ),
              ),
              const Spacer(),
              if (_error != null) ...[
                SondrError(_error!, textAlign: TextAlign.center),
                SizedBox(height: 6 * scale),
              ],
              Center(
                child: SondrAction(label: 'Next', onPressed: _busy ? null : _next),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The card's cover, live: the collage at the card's size under the
  /// scrim and the ring, the tiles answering to the hand. Nothing in the
  /// collage is drawn by the cover's own FittedBox here — the preview is
  /// at the card's width already, so the tiles are placed by the layout
  /// at this very size.
  Widget _preview(Size frame) {
    final tokens = GreyscaleTokens.of(context);
    final order = _arrangement.order;
    if (order.isEmpty) {
      return MilestoneNoPhotoFrame(milestoneHours: widget.milestoneHours);
    }
    final tiles = collageTiles(frame, order.length);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: tokens.surface),
        for (var i = 0; i < order.length; i++)
          AnimatedPositioned(
            key: ValueKey('slot-${order[i]}'),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: tiles[i].left,
            top: tiles[i].top,
            width: tiles[i].width,
            height: tiles[i].height,
            child: _tile(order[i], tiles[i], tiles),
          ),
        // The scrim and the ring, as the card draws them; neither takes a
        // touch.
        const IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(gradient: kMilestoneScrim)),
        ),
        Positioned(
          top: milestoneRingTop(frame.height),
          left: (frame.width - kMilestoneRingSize) / 2,
          child: IgnorePointer(
            child: MilestoneRing(
              onPhoto: true,
              center: MilestoneRingCentre(
                figure: '${widget.milestoneHours}',
                unit: 'hours',
                onPhoto: true,
              ),
            ),
          ),
        ),
        if (_dragging != null)
          Positioned(
            left: _dragAt.dx - _grab.dx,
            top: _dragAt.dy - _grab.dy,
            width: tiles[order.indexOf(_dragging!)].width,
            height: tiles[order.indexOf(_dragging!)].height,
            child: IgnorePointer(
              child: Transform.scale(
                scale: 1.04,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: FramedPhoto(
                    image: _entry(_dragging!).image,
                    size: tiles[order.indexOf(_dragging!)].size,
                    framing: _arrangement.framingOf(_dragging!),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(String id, Rect rect, List<Rect> tiles) {
    final selected = _selected == id;
    final lifted = _dragging == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(id),
      onLongPressStart: (d) => _pickUp(id, rect, d.localPosition),
      onLongPressMoveUpdate: (d) => _drag(rect, d.offsetFromOrigin),
      onLongPressEnd: (_) => _drop(tiles),
      onLongPressCancel: () => setState(() => _dragging = null),
      // Pinch and drag frame the photo — only once the tile is the one
      // being framed, so a stray finger never moves an unchosen photo.
      onScaleStart: selected ? (d) => _frameStart(id, d.localFocalPoint) : null,
      onScaleUpdate: selected
          ? (d) => _frameUpdate(id, rect.size, d.scale, d.localFocalPoint)
          : null,
      child: Opacity(
        opacity: lifted ? 0.3 : 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FramedPhoto(
              image: _entry(id).image,
              size: rect.size,
              framing: _arrangement.framingOf(id),
            ),
            if (selected)
              IgnorePointer(
                child: DecoratedBox(
                  key: const Key('sondr-arrange-outline'),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFAFAFA), width: kArrangeOutline),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Every photo of the band, oldest first, the new one last; the chosen
  /// ones at full with their collage position, the rest at 30%.
  Widget _strip(double scale) {
    return SizedBox(
      key: kArrangeStripKey,
      height: kArrangeTileHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kArrangeGutter),
        children: [
          for (var i = 0; i < widget.entries.length; i++) ...[
            if (i > 0) const SizedBox(width: kArrangeTileGap),
            _stripTile(widget.entries[i]),
          ],
        ],
      ),
    );
  }

  Widget _stripTile(ArrangeEntry entry) {
    final position = _arrangement.positionOf(entry.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(entry.id),
      child: Opacity(
        opacity: position == null ? 0.3 : 1,
        child: SizedBox(
          width: kArrangeTileWidth,
          height: kArrangeTileHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kArrangeTileRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: entry.image, fit: BoxFit.cover),
                if (position != null)
                  Positioned(
                    right: 4,
                    bottom: 3,
                    child: Text(
                      '$position',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFAFAFA),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
