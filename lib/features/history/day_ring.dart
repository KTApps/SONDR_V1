import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/segmented_dial.dart';
import '../photos/models/photo.dart';

/// One day's ring, as the calendar draws it: that day's task split and
/// habits, the day's first photo inside it, the date's number on top, and a
/// dot when there is more than one photo.
///
/// The calendar's cell at 49, and the day sheet's header at 44, which also
/// lights one task's slice — [selectedTaskIndex], Home's treatment.
class CalendarDayRing extends StatelessWidget {
  const CalendarDayRing({
    super.key,
    required this.size,
    required this.day,
    required this.isToday,
    required this.segments,
    required this.habitStates,
    required this.photos,
    this.selectedTaskIndex,
  });

  /// The calendar's cell size, which the stroke and dot are drawn against.
  static const double calendarSize = 49;

  final double size;
  final int day;
  final bool isToday;
  final List<double> segments;
  final List<bool> habitStates;
  final List<Photo> photos;
  final int? selectedTaskIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final k = size / calendarSize;
    final hero = photos.isEmpty ? null : photos.first; // first capture
    final hasPhoto = hero != null;

    Widget dial = SegmentedDial(
      size: size,
      compact: true,
      stroke: 5 * k, // a touch thinner than the proportional ~6
      taskTodaySeconds: segments,
      selectedTaskIndex: selectedTaskIndex,
      habitStates: habitStates,
      fill: hasPhoto ? _PhotoFill(url: hero.photoUrl) : null,
      center: Text(
        '$day',
        style: theme.textTheme.labelMedium?.copyWith(
          // Matches Home's Last-10-days numbers: bold (w700), size 12.
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: hasPhoto
              ? Colors.white
              : (isToday ? tokens.textPrimary : tokens.textSecondary),
          // Kept legible over the tinted photo.
          shadows: hasPhoto
              ? const [Shadow(color: Color(0xCC000000), blurRadius: 3)]
              : null,
        ),
      ),
    );
    if (photos.length > 1) {
      dial = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          dial,
          Positioned(top: 5 * k, right: 8 * k, child: const _MultipleDot()),
        ],
      );
    }
    return dial;
  }
}

// ── Photo-in-ring tint — a FIXED, uniform treatment on every photo cell so the
// calendar reads consistently. Both values are tuned on screen; adjust here.
/// Photo colour saturation: 1 = full colour, 0 = full greyscale. Lower = more
/// muted toward the app's greyscale world.
const double _kPhotoSaturation = 0.32;

/// Dark scrim painted over the photo. Higher alpha = darker/more muted and a
/// stronger backing for the white day number. 0x9E ≈ 62% black.
const Color _kPhotoTint = Color(0x9E000000);

/// A day's hero photo inside the effort ring: the network image, desaturated
/// toward the app's greyscale, under the fixed dark tint that both mutes it and
/// backs the white day number. A broken or still-loading URL shows nothing —
/// the ring-only cell — so it never breaks the cell or flashes a
/// tinted-but-empty disc.
class _PhotoFill extends StatelessWidget {
  const _PhotoFill({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SondrPhoto(
      url: url,
      saturation: _kPhotoSaturation,
      tint: _kPhotoTint,
    );
  }
}

/// The quiet "more than one photo today" marker, top-right of the cell.
class _MultipleDot extends StatelessWidget {
  const _MultipleDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 2)],
      ),
    );
  }
}
