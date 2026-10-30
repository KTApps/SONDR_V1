import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/figma_scale.dart';

/// Which edge a [SondrSwipeRow]'s tray is uncovered from.
///
/// [trailing] is the app's direction everywhere — swipe left, tray on the
/// right — and the default. [leading] is its mirror, swipe right, which
/// nothing uses today: one direction app-wide is the point, so reach for this
/// only where a row genuinely cannot open the other way.
enum SondrSwipeSide { trailing, leading }

/// A row whose actions are hidden until swiped sideways.
///
/// Reveal, never dismiss: swiping uncovers the actions and waits; nothing is
/// destroyed by the gesture itself. Swipe back, or tap the row, to close.
///
/// The row does not slide. The tray is uncovered into the trailing space so
/// the identity stays anchored — with placeholder photos all alike, the name
/// is the only thing telling you whose row you just opened.
///
/// Built by hand rather than with a slidable package — the behaviour is a
/// translate and a snap, which is not worth a dependency.
///
/// The actions stay WHITE at full emphasis. They are summoned by a deliberate
/// gesture rather than standing on the screen, so they never clutter, and a
/// tray of nothing but grey text would read as disabled (see DESIGN.md).
class SondrSwipeRow extends StatefulWidget {
  const SondrSwipeRow({
    super.key,
    required this.child,
    required this.actions,
    this.side = SondrSwipeSide.trailing,
    this.trayInset = defaultTrayInset,
    this.haptic = false,
  });

  /// Whether the swipe is felt as the tray is revealed: a light impact at
  /// the point where it opens. Comments only.
  final bool haptic;

  /// The tray's own outer inset, on the edge it is uncovered from.
  ///
  /// The default is what the friend and habit rows use. A row whose actions
  /// have to line up with a control elsewhere on the screen passes the
  /// inset of THAT control instead — the comments sheet passes its
  /// composer's, so the action a swipe reveals sits exactly under Post.
  static const double defaultTrayInset = 24;

  final Widget child;

  /// The edge the tray comes from, and so the direction of the swipe that
  /// opens it. Defaults to the app's established trailing/swipe-left.
  final SondrSwipeSide side;

  /// Most severe LAST, so the outermost action is the gravest one.
  final List<Widget> actions;

  /// Points on the reference canvas, scaled like everything else.
  final double trayInset;

  @override
  State<SondrSwipeRow> createState() => _SondrSwipeRowState();

  /// Close the tray of the row enclosing [context] — for an action to call
  /// once it has been tapped, so a row is never left standing open after the
  /// thing it offered has been done. No-op outside a row.
  static void close(BuildContext context) {
    context.findAncestorStateOfType<_SondrSwipeRowState>()?._open.reverse();
  }
}

class _SondrSwipeRowState extends State<SondrSwipeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  final GlobalKey _trayKey = GlobalKey();
  double _trayWidth = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTray());
  }

  @override
  void didUpdateWidget(covariant SondrSwipeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTray());
  }

  void _measureTray() {
    final box = _trayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    if (box.size.width != _trayWidth) {
      setState(() => _trayWidth = box.size.width);
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  /// +1 when opening means dragging RIGHT (a leading tray), -1 for the
  /// trailing default. Both the drag and the fling read from this, so the two
  /// can never disagree about which way is open.
  double get _sign => widget.side == SondrSwipeSide.leading ? 1 : -1;

  void _drag(DragUpdateDetails d) {
    if (_trayWidth <= 0) return;
    final delta = _sign * d.primaryDelta! / _trayWidth;
    _open.value = (_open.value + delta).clamp(0.0, 1.0);
  }

  /// How open the tray was when the swipe began: a swipe that reveals a
  /// tray already revealed is not felt again.
  double _openAtStart = 0;

  void _began(DragStartDetails _) => _openAtStart = _open.value;

  void _settle(DragEndDetails d) {
    final flung = _sign * d.velocity.pixelsPerSecond.dx;
    final opens = flung > 250 || (flung >= -250 && _open.value > 0.5);
    if (opens) {
      // The swipe has reached the point where the tray is revealed.
      if (widget.haptic && _openAtStart < 1) HapticFeedback.lightImpact();
      _open.forward().ignore();
    } else {
      _open.reverse().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    final leading = widget.side == SondrSwipeSide.leading;
    final edge = leading ? Alignment.centerLeft : Alignment.centerRight;

    // The whole thing rebuilds with the animation, not just the tray: the tap
    // handler has to read the LIVE open value. Built outside the listener it
    // captured the value at first build — always 0 — so a tap on an open row
    // did nothing and only a swipe back could close it.
    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final revealed = _open.value * _trayWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _began,
          onHorizontalDragUpdate: _drag,
          onHorizontalDragEnd: _settle,
          // A tap anywhere on an open row closes it, so the gesture is
          // reversible without having to find the exact swipe back.
          onTap: _open.value > 0 ? () => _open.reverse() : null,
          child: Stack(
            alignment: edge,
            children: [
              // The tray is uncovered from the right edge inwards. The row
              // itself never moves: with identical placeholder photos the
              // NAME is the only thing identifying who you are about to
              // remove, so it stays put and readable beside the actions.
              ClipRect(
                child: Align(
                  alignment: edge,
                  widthFactor: _open.value,
                  // The key is on the padding, not the row inside it, so the
                  // measured width includes the tray's own outer inset.
                  child: Padding(
                    key: _trayKey,
                    padding: leading
                        ? EdgeInsets.only(left: widget.trayInset * scale)
                        : EdgeInsets.only(right: widget.trayInset * scale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.actions,
                    ),
                  ),
                ),
              ),
              // The content's width shrinks by exactly what the tray takes, so
              // a long name ellipsises rather than sliding under the actions.
              Padding(
                padding: leading
                    ? EdgeInsets.only(left: revealed)
                    : EdgeInsets.only(right: revealed),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}
