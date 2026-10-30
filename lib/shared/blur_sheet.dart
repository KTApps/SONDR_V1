import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend.dart';
import '../core/theme/greyscale_tokens.dart';
import '../core/theme/spacing.dart';
import '../core/utils/figma_scale.dart';
import 'sondr_action.dart';

/// The Habits page's numbers, which this is modelled on.
///
/// Measured off it on a 13 Pro rather than reinvented: a question put to
/// the person over a blurred app should be the same object as the habits
/// over a blurred app, or the app has two ideas of what a lifted surface
/// is. Every one of these is asserted against the Habits screen in
/// test/blur_sheet_test.dart, so a change there fails here.
const double kBlurSigma = 18;
const double kBlurScrimAlpha = 0.55;

/// Home's title line, where the weekday sits. Screen-global, like Home.
const double kBlurTitleTop = 106;

/// Unscaled by the canvas, because Home's title is.
const double kBlurTitleSize = 20;

/// The list's box: from under the title to one base above the exit.
const double kBlurListTop = kBlurTitleTop + 40;
const double kBlurListBottom = kBlurExitTop;

/// Home's "View your progress" line, less the tap padding the action
/// carries above its own text.
const double kBlurExitTop = 732 - kSpacingBase;

/// The footer's air above the bottom inset.
const double kBlurFooterBottom = 12;

/// An item: the habit name's size and weight, with the habit row's
/// padding either side of it.
const double kBlurItemSize = 27;
const double kBlurItemPad = kSpacingBase;

/// The tap padding either side of a label, and the least a target is tall.
const double kBlurTapSide = 24;
const double kBlurTapMinHeight = 44;
const double kBlurSideInset = 32;

/// The line under a title, for a question that needs one.
const double kBlurExplanationSize = 13;
const double kBlurExplanationGap = kSpacingBase;

/// One answer in a blur view.
class BlurItem {
  const BlurItem({
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The not-done grey. For an answer that acts on the account rather than
  /// moving around it — Sign out, Delete account — so the list's ordinary
  /// white stays the colour of an ordinary choice.
  final bool quiet;
}

/// What one frosted view shows.
class BlurView {
  const BlurView({
    this.title,
    this.explanation,
    this.items = const [],
    this.body,
    this.cancelLabel = 'Back',
    this.footer,
  });

  /// On Home's title line, in Home's title type.
  final String? title;

  /// A line under the title, quiet and centred, for a question whose
  /// consequence has to be spelled out.
  final String? explanation;

  /// The answers, where the habits are.
  final List<BlurItem> items;

  /// Something other than a list in that same space — the password field
  /// is the only one.
  final Widget? body;

  final String cancelLabel;

  /// A line at the very bottom of the view, under the exit, for nothing
  /// more than a word about the build. Not a tap target.
  final Widget? footer;
}

/// The sheet, from inside: how a view moves to the next one, and how it
/// ends.
abstract interface class BlurSheetHandle {
  /// Cross-fade to [next] IN PLACE. The blur does not move and a second
  /// one is never stacked over the first.
  void show(BlurView next);

  /// Close the whole thing.
  void close();

  /// Completes when the sheet has gone, however it went — an answer, the
  /// exit, a tap on the blur, a swipe. A flow waiting on an answer uses
  /// it to hear a no that was never spoken.
  Future<void> get closed;
}

/// Put a question over the app, frosted, in the Habits page's own clothes.
///
/// A route rather than a dialog, and the same one Habits uses: not opaque,
/// no barrier colour of its own (the blur IS the barrier), a 200ms fade in
/// and a 160ms fade out. Dismissed by a tap anywhere the content is not,
/// or by a downward swipe — the gestures the overlay already taught.
Future<void> showBlurSheet(
  BuildContext context,
  BlurView Function(BlurSheetHandle handle) first,
) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => BlurSheet(first: first),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

@visibleForTesting
class BlurSheet extends ConsumerStatefulWidget {
  const BlurSheet({super.key, required this.first});

  final BlurView Function(BlurSheetHandle handle) first;

  @override
  ConsumerState<BlurSheet> createState() => _BlurSheetState();
}

class _BlurSheetState extends ConsumerState<BlurSheet> implements BlurSheetHandle {
  late BlurView _view = widget.first(this);

  final Completer<void> _closed = Completer<void>();

  @override
  Future<void> get closed => _closed.future;

  @override
  void dispose() {
    if (!_closed.isCompleted) _closed.complete();
    super.dispose();
  }

  /// Which view is showing, so the cross-fade has something to key on.
  int _step = 0;

  double _pull = 0;

  @override
  void show(BlurView next) {
    if (!mounted) return;
    setState(() {
      _view = next;
      _step++;
    });
  }

  @override
  void close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  /// The account has changed hands under the sheet — a sign-out, a
  /// deletion, a sign-in — so whatever it was asking is over: it goes,
  /// wherever it is in the stack, and the guest state is what is left.
  void _accountChanged() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).maybePop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _pullUpdate(DragUpdateDetails d) => _pull += d.primaryDelta ?? 0;

  void _pullEnd(DragEndDetails d) {
    final flung = d.velocity.pixelsPerSecond.dy;
    if (_pull > 60 || flung > 500) close();
    _pull = 0;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(currentUidProvider, (previous, next) {
      if (previous != next) _accountChanged();
    });
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final screen = MediaQuery.sizeOf(context).height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    // With a keyboard up, the whole view lifts by exactly what the keyboard
    // covers of the exit — and by nothing at all when there is no keyboard,
    // which is what keeps every position identical to the Habits page's.
    final exitBottom = (kBlurExitTop + kBlurItemPad) * scale +
        _lineHeight(context, theme, 15 * scale) +
        kBlurItemPad * scale;
    final lift = inset == 0
        ? 0.0
        : math.max(0.0, exitBottom - (screen - inset));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: close,
      onVerticalDragUpdate: _pullUpdate,
      onVerticalDragEnd: _pullEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: kBlurSigma, sigmaY: kBlurSigma),
              child: ColoredBox(
                color: tokens.background.withValues(alpha: kBlurScrimAlpha),
              ),
            ),
          ),
          // Transparent Material, not a Scaffold: a field needs a Material
          // ancestor for its cursor, and a Scaffold would paint over the
          // blur.
          Material(
            type: MaterialType.transparency,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              offset: Offset(0, -lift / screen),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _ViewBody(view: _view),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _lineHeight(BuildContext context, ThemeData theme, double size) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'Hg',
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: size),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.height;
}

class _ViewBody extends StatelessWidget {
  const _ViewBody({required this.view});

  final BlurView view;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final screen = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        if (view.footer != null)
          Positioned(
            bottom: bottomInset + kBlurFooterBottom * scale,
            left: 0,
            right: 0,
            child: Center(child: IgnorePointer(child: view.footer)),
          ),
        if (view.title != null)
          Positioned(
            top: kBlurTitleTop * scale,
            left: kBlurSideInset * scale,
            right: kBlurSideInset * scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  view.title!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    // Unscaled by the canvas, as Home's title is.
                    fontSize: kBlurTitleSize,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                if (view.explanation != null) ...[
                  SizedBox(height: kBlurExplanationGap * scale),
                  Text(
                    view.explanation!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: kBlurExplanationSize * scale,
                      color: tokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        // The answers, centred in what is left between the title and the
        // exit — exactly as the habit names are.
        Positioned(
          top: kBlurListTop * scale,
          bottom: (screen - kBlurListBottom * scale).clamp(0, screen),
          left: kBlurSideInset * scale,
          right: kBlurSideInset * scale,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (view.body != null) view.body!,
                  for (final item in view.items)
                    _Answer(item: item, scale: scale),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: kBlurExitTop * scale,
          left: 0,
          right: 0,
          child: Center(
            child: Builder(
              builder: (context) => SondrAction(
                label: view.cancelLabel,
                onPressed: () =>
                    Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One answer, in the habit name's clothes.
class _Answer extends StatelessWidget {
  const _Answer({required this.item, required this.scale});

  final BlurItem item;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    // The LABEL is the target: its own bounds plus a tier of tap padding
    // (12 above and below, 24 either side), never less than 44 tall. The
    // rest of the row absorbs a tap and does nothing — it is not the blur,
    // which still dismisses, and it is not the word, which acts.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: item.onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: kBlurTapMinHeight * scale),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: kBlurItemPad * scale,
                  horizontal: kBlurTapSide * scale,
                ),
                child: Center(
                  // As wide as the word, as tall as the box: a Center
                  // without this fills the row, and the whole row would be
                  // the target again.
                  widthFactor: 1,
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: kBlurItemSize * scale,
                      fontWeight: FontWeight.w600,
                      color: item.quiet ? tokens.textTertiary : tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
