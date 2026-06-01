import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'ring_painter.dart';

/// The signature component of Sondr: the dual-ring effort dial.
///
/// This is built once and reused everywhere — home screen, feed cards, and
/// profiles — so it must stay self-contained and presentational. It takes two
/// progress values and renders them against the greyscale ladder:
///
///  * **Outer ring** = time logged toward the current task's milestone today
///    (the brightest fill).
///  * **Inner ring** = daily habits completed today, completed ÷ total (one
///    step dimmer).
///  * **Centre** = the task's time figure (e.g. "13 hrs" over "today").
///
/// Set [onPhoto] when the dial sits over a photo backdrop: fills switch to
/// near-white regardless of theme and the painter adds contrast halos, so the
/// ring stays legible over any image.
class RingDial extends StatelessWidget {
  const RingDial({
    super.key,
    required this.taskProgress,
    required this.habitProgress,
    this.size = 280,
    this.onPhoto = false,
    this.centerValue,
    this.centerLabel,
    this.center,
    this.animate = true,
  });

  /// 0..1 — time on the current task today toward its active milestone.
  final double taskProgress;

  /// 0..1 — habits checked off today ÷ today's total habits.
  final double habitProgress;

  /// Overall diameter in logical pixels.
  final double size;

  /// Render the photo-backdrop variant (light fills + contrast halos).
  final bool onPhoto;

  /// Big centre figure, e.g. "13 hrs". Ignored if [center] is supplied.
  final String? centerValue;

  /// Small label under the figure, e.g. "today". Ignored if [center] is set.
  final String? centerLabel;

  /// Replaces the default centre content entirely.
  final Widget? center;

  /// Animate progress changes (disable for static feed/profile dials).
  final bool animate;

  // Stroke widths scale with the dial so the component looks right at any size.
  double get _outerThickness => size * 0.090;
  double get _innerThickness => size * 0.074;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);

    // On a photo the fills go near-white (with halos) regardless of app theme;
    // on a solid surface they follow the ladder (outer brightest, inner dimmer).
    final outerFill = onPhoto ? const Color(0xFFFFFFFF) : tokens.ringFillOuter;
    final innerFill = onPhoto ? const Color(0xFFE6E6E6) : tokens.ringFillInner;
    final track =
        onPhoto ? Colors.white.withValues(alpha: 0.30) : tokens.ringTrack;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AnimatedRings(
            taskProgress: taskProgress.clamp(0.0, 1.0),
            habitProgress: habitProgress.clamp(0.0, 1.0),
            size: size,
            onPhoto: onPhoto,
            outerThickness: _outerThickness,
            innerThickness: _innerThickness,
            outerTrack: track,
            innerTrack: track,
            outerFill: outerFill,
            innerFill: innerFill,
            animate: animate,
          ),
          _buildCenter(context, tokens),
        ],
      ),
    );
  }

  Widget _buildCenter(BuildContext context, GreyscaleTokens tokens) {
    if (center != null) return center!;
    if (centerValue == null && centerLabel == null) {
      return const SizedBox.shrink();
    }

    final textColor = onPhoto ? const Color(0xFFFFFFFF) : tokens.textPrimary;
    final labelColor =
        onPhoto ? Colors.white.withValues(alpha: 0.85) : tokens.textSecondary;
    final shadows = onPhoto
        ? const [Shadow(color: Colors.black54, blurRadius: 8)]
        : const <Shadow>[];

    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (centerValue != null)
          Text(
            centerValue!,
            style: theme.textTheme.displayMedium?.copyWith(
              color: textColor,
              shadows: shadows,
            ),
          ),
        if (centerLabel != null)
          Padding(
            padding: EdgeInsets.only(top: size * 0.012),
            child: Text(
              centerLabel!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: labelColor,
                shadows: shadows,
              ),
            ),
          ),
      ],
    );
  }
}

/// Drives the implicit progress animation and hands flat values to the painter.
class _AnimatedRings extends StatelessWidget {
  const _AnimatedRings({
    required this.taskProgress,
    required this.habitProgress,
    required this.size,
    required this.onPhoto,
    required this.outerThickness,
    required this.innerThickness,
    required this.outerTrack,
    required this.innerTrack,
    required this.outerFill,
    required this.innerFill,
    required this.animate,
  });

  final double taskProgress;
  final double habitProgress;
  final double size;
  final bool onPhoto;
  final double outerThickness;
  final double innerThickness;
  final Color outerTrack;
  final Color innerTrack;
  final Color outerFill;
  final Color innerFill;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final duration =
        animate ? const Duration(milliseconds: 650) : Duration.zero;
    // Animate both progress values together off a single 0..1 driver.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return CustomPaint(
          size: Size.square(size),
          painter: RingPainter(
            onPhoto: onPhoto,
            layers: [
              RingLayer(
                progress: taskProgress * t,
                thickness: outerThickness,
                track: outerTrack,
                fill: outerFill,
              ),
              RingLayer(
                progress: habitProgress * t,
                thickness: innerThickness,
                track: innerTrack,
                fill: innerFill,
              ),
            ],
          ),
        );
      },
    );
  }
}
