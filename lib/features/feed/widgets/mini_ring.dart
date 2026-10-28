import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../photos/collage_selection.dart' show kMilestoneBandSeconds;

/// The small ring at the right of a card's actions, on the words'
/// baseline: how far into its 20-hour band a task stood. The grey runs
/// clockwise from 12 to where the task stood BEFORE the session the card
/// is about; the session's own slice follows it in white. No text. The
/// same ring on a milestone's photo pages and on a session post.

/// Ø26, a 3 stroke; a soft drop shadow under it. Over a photo the ring
/// is white — the track at 30%, the band before the session at 60%, the
/// session itself solid — so the full circle always reads as a ring and
/// never as a part of one; on the surface it is grey.
const double kMiniRingSize = 26;
const double kMiniRingStroke = 3;
const Color kMiniRingTrack = Color(0xE63A3A3A); // #3A3A3A at 90%
const Color kMiniRingBefore = Color(0xFFADADAD);
const Color kMiniRingOwn = Color(0xFFFAFAFA);
const Color kMiniRingTrackOnPhoto = Color(0x4DFFFFFF); // white 30%
const Color kMiniRingBeforeOnPhoto = Color(0x99FFFFFF); // white 60%
const Color kMiniRingOwnOnPhoto = Color(0xFFFAFAFA);
const Color kMiniRingShadow = Color(0x80000000); // 50%
const double kMiniRingShadowBlur = 2;
const double kMiniRingShadowDy = 1;

/// What the ring shows: the band's seconds before the session, and the
/// session's own, over a band of [band] seconds.
@immutable
class MiniRingData {
  const MiniRingData({required this.before, required this.seconds, this.band = kMilestoneBandSeconds});

  final int before;
  final int seconds;
  final int band;

  /// The grey's end, 0..1.
  double get beforeFill => (before / band).clamp(0.0, 1.0);

  /// The white's end, 0..1: the grey's, then the session's own.
  double get ownFill => ((before + seconds) / band).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is MiniRingData && other.before == before && other.seconds == seconds && other.band == band;

  @override
  int get hashCode => Object.hash(before, seconds, band);
}

class MiniRing extends StatelessWidget {
  const MiniRing({super.key, required this.data, this.onPhoto = true});

  final MiniRingData data;

  /// Over a photo: the white palette. On the surface: the grey.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kMiniRingSize,
      height: kMiniRingSize,
      child: CustomPaint(painter: _MiniRingPainter(data, onPhoto)),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  const _MiniRingPainter(this.data, this.onPhoto);
  final MiniRingData data;
  final bool onPhoto;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(kMiniRingStroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kMiniRingStroke
      ..strokeCap = StrokeCap.butt;
    // The shadow, under everything.
    canvas.drawArc(
      rect.shift(const Offset(0, kMiniRingShadowDy)),
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kMiniRingStroke
        ..color = kMiniRingShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, kMiniRingShadowBlur),
    );
    // The track is the whole circle, always: the ring is never a part.
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = onPhoto ? kMiniRingTrackOnPhoto : kMiniRingTrack);
    const top = -math.pi / 2;
    final before = 2 * math.pi * data.beforeFill;
    if (before > 0) {
      canvas.drawArc(rect, top, before, false, paint..color = onPhoto ? kMiniRingBeforeOnPhoto : kMiniRingBefore);
    }
    final own = 2 * math.pi * (data.ownFill - data.beforeFill);
    if (own > 0) {
      canvas.drawArc(rect, top + before, own, false, paint..color = onPhoto ? kMiniRingOwnOnPhoto : kMiniRingOwn);
    }
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) => old.data != data || old.onPhoto != onPhoto;
}
