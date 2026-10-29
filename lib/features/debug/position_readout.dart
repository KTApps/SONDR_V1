import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_tools.dart';

/// Whether the position readout is drawn. QA-only and OFF by default; toggled
/// from the debug panel, and meaningless unless the build carries
/// `--dart-define=DEBUG_TOOLS=true`.
class PositionReadoutToggle extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final positionReadoutProvider =
    NotifierProvider<PositionReadoutToggle, bool>(PositionReadoutToggle.new);

/// What to measure: the first element [index] for which [probe] is true.
class ReadoutTarget {
  const ReadoutTarget(this.label, this.probe, {this.index = 0});

  final String label;
  final bool Function(Element element) probe;

  /// Which match to take when several elements answer the probe — the third
  /// hairline, the second ring, and so on.
  final int index;
}

/// Matches a paragraph by its RENDERED text, so a `Text.rich` subtitle built
/// from spans is as findable as a plain one.
bool Function(Element) probeText(String contains) => (element) {
      final ro = element.renderObject;
      if (ro is! RenderParagraph) return false;
      return ro.text.toPlainText().contains(contains);
    };

/// Matches by widget type NAME rather than by type, so this file needs no
/// import of — and no dependency on — the screens it measures.
bool Function(Element) probeType(String name) =>
    (element) => element.widget.runtimeType.toString() == name;

/// The 1pt rules between sections.
bool Function(Element) probeHairline() => (element) {
      final w = element.widget;
      return w is SizedBox && w.height == 1;
    };

/// Draws the on-screen y of a list of targets, in points, as `top/centre/bottom`.
///
/// Measured from the live render tree after the frame is laid out, so these are
/// the real numbers the device produced — the point of the thing is to settle
/// disagreements between a widget-test harness and a screenshot.
///
/// **Zero layout effect when off**: build returns [child] itself, not a
/// wrapper around it. And `kDebugTools` is a const false in any normal build,
/// so everything below the guard is dead code and tree-shakes away.
class PositionReadout extends ConsumerStatefulWidget {
  const PositionReadout({
    super.key,
    required this.title,
    required this.targets,
    required this.child,
  });

  /// Which screen this is, so a screenshot of the overlay identifies itself.
  final String title;

  /// Built only when the readout is on — an off readout allocates nothing.
  final List<ReadoutTarget> Function() targets;

  final Widget child;

  @override
  ConsumerState<PositionReadout> createState() => _PositionReadoutState();
}

class _PositionReadoutState extends ConsumerState<PositionReadout> {
  final GlobalKey _subtree = GlobalKey();
  List<String> _lines = const [];

  void _measure() {
    final element = _subtree.currentContext as Element?;
    if (element == null) return;

    final found = <Element>[];
    void walk(Element e) {
      found.add(e);
      e.visitChildren(walk);
    }

    walk(element);

    final lines = <String>[];
    for (final target in widget.targets()) {
      var seen = -1;
      String? line;
      for (final e in found) {
        if (!target.probe(e)) continue;
        seen++;
        if (seen != target.index) continue;
        final ro = e.renderObject;
        if (ro is! RenderBox || !ro.hasSize) break;
        final top = ro.localToGlobal(Offset.zero).dy;
        final h = ro.size.height;
        line = '${target.label}  ${top.toStringAsFixed(1)}'
            ' / ${(top + h / 2).toStringAsFixed(1)}'
            ' / ${(top + h).toStringAsFixed(1)}';
        break;
      }
      lines.add(line ?? '${target.label}  —');
    }
    if (mounted && !listEquals(lines, _lines)) {
      setState(() => _lines = lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The guard is first and the return is the child itself: nothing is
    // wrapped, nothing is allocated, nothing can move.
    if (!ref.watch(debugToolsProvider)) return widget.child;
    if (!ref.watch(positionReadoutProvider)) return widget.child;

    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    return Stack(
      children: [
        KeyedSubtree(key: _subtree, child: widget.child),
        // Never intercepts a tap, and never participates in the page's
        // layout — the page is measured underneath it.
        Positioned(
          top: 0,
          left: 0,
          child: IgnorePointer(
            child: Container(
              color: const Color(0xCC000000),
              padding: const EdgeInsets.fromLTRB(4, 2, 5, 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.title}  top/centre/bottom',
                    style: const TextStyle(
                      fontSize: 7,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFAFAFA),
                    ),
                  ),
                  for (final line in _lines)
                    Text(
                      line,
                      style: const TextStyle(
                        fontSize: 7,
                        height: 1.5,
                        color: Color(0xFFB0B0B0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
