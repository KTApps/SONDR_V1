import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/duration_format.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';

/// What the person chose.
enum StillGoing {
  /// It is real; carry on.
  keepGoing,

  /// Stop it now, exactly as the Stop button would.
  stopNow,
}

/// What the sheet returns: a choice, or a corrected end time.
class StillGoingAnswer {
  const StillGoingAnswer.keepGoing()
    : choice = StillGoing.keepGoing,
      endedAt = null;
  const StillGoingAnswer.stopNow()
    : choice = StillGoing.stopNow,
      endedAt = null;
  const StillGoingAnswer.endedAt(DateTime this.endedAt)
    : choice = StillGoing.stopNow;

  final StillGoing choice;

  /// Set only when the session should be logged as having ended earlier.
  final DateTime? endedAt;
}

/// How the sheet says when a session began.
///
/// Today is just the time. Yesterday says so, because "9:14 pm" on its own
/// reads as this evening when it is in fact last night — which is exactly
/// the mistake this whole prompt exists to catch. Older says the weekday.
String startedAtSentence(
  BuildContext context,
  DateTime startedAt,
  DateTime now,
) {
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(startedAt));
  final startDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final daysAgo = today.difference(startDay).inDays;
  if (daysAgo <= 0) return time;
  if (daysAgo == 1) return 'yesterday, $time';
  return '${_weekday(startedAt.weekday)}, $time';
}

String _weekday(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

/// "Still going?" — the guard on a session nobody stopped.
///
/// Not dismissible: a forgotten timer is still running behind the sheet, so
/// tapping the scrim to make the question go away would leave the thing it
/// is asking about exactly as it was.
Future<StillGoingAnswer?> showStillGoingSheet(
  BuildContext context, {
  required String taskName,
  required Duration elapsed,
  required DateTime startedAt,
  required DateTime now,
}) {
  return showModalBottomSheet<StillGoingAnswer>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: GreyscaleTokens.of(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24 * figmaScale(context)),
      ),
    ),
    builder: (_) => _StillGoingBody(
      taskName: taskName,
      elapsed: elapsed,
      startedAt: startedAt,
      now: now,
    ),
  );
}

class _StillGoingBody extends StatefulWidget {
  const _StillGoingBody({
    required this.taskName,
    required this.elapsed,
    required this.startedAt,
    required this.now,
  });

  final String taskName;
  final Duration elapsed;
  final DateTime startedAt;
  final DateTime now;

  @override
  State<_StillGoingBody> createState() => _StillGoingBodyState();
}

class _StillGoingBodyState extends State<_StillGoingBody> {
  /// The wheel replaces the actions in place rather than pushing a screen:
  /// the question and the answer belong to one surface.
  bool _picking = false;
  late DateTime _end = widget.now;

  /// A session cannot have ended before it began. One minute, so the wheel
  /// has somewhere to go.
  DateTime get _earliest => widget.startedAt.add(const Duration(minutes: 1));

  /// The wheel shows a date as well as a time when the session has crossed
  /// midnight — a bare time would be ambiguous about which day it means.
  bool get _spansMidnight =>
      DateTime(widget.startedAt.year, widget.startedAt.month,
          widget.startedAt.day) !=
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(kSpacingSection * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Still going?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            Text(
              '${widget.taskName} has been running for '
              '${DurationFormat.hm(widget.elapsed)}, since '
              '${startedAtSentence(context, widget.startedAt, widget.now)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            if (_picking) ..._wheel(tokens, scale) else ..._choices(scale),
          ],
        ),
      ),
    );
  }

  List<Widget> _choices(double scale) => [
    Center(
      child: SondrAction(
        label: 'Keep going',
        onPressed: () =>
            Navigator.of(context).pop(const StillGoingAnswer.keepGoing()),
      ),
    ),
    Center(
      child: SondrAction(
        label: 'Stop now',
        supporting: true,
        onPressed: () =>
            Navigator.of(context).pop(const StillGoingAnswer.stopNow()),
      ),
    ),
    Center(
      child: SondrAction(
        label: 'Set end time',
        supporting: true,
        onPressed: () => setState(() => _picking = true),
      ),
    ),
  ];

  List<Widget> _wheel(GreyscaleTokens tokens, double scale) => [
    SizedBox(
      height: 180 * scale,
      child: CupertinoTheme(
        // Cupertino's own text theme is light; the wheel has to be read on
        // the app's surface.
        data: CupertinoThemeData(
          brightness: Brightness.dark,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 20 * scale,
              color: tokens.textPrimary,
            ),
          ),
        ),
        child: CupertinoDatePicker(
          key: const Key('still-going-wheel'),
          mode: _spansMidnight
              ? CupertinoDatePickerMode.dateAndTime
              : CupertinoDatePickerMode.time,
          initialDateTime: widget.now,
          minimumDate: _earliest,
          maximumDate: widget.now,
          // setState, because the confirm label names the time it will
          // log — a label that did not follow the wheel would be a lie
          // about what the button does.
          onDateTimeChanged: (value) => setState(() => _end = value),
        ),
      ),
    ),
    SizedBox(height: kSpacingBase * scale),
    Center(
      child: SondrAction(
        label: 'Log until '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_end))}',
        onPressed: () => Navigator.of(
          context,
        ).pop(StillGoingAnswer.endedAt(_clamped(_end))),
      ),
    ),
    Center(
      child: SondrAction(
        label: 'Back',
        supporting: true,
        onPressed: () => setState(() => _picking = false),
      ),
    ),
  ];

  /// The wheel is bounded, but a bound is not a guarantee — clamp anyway,
  /// because this number becomes logged time.
  DateTime _clamped(DateTime value) {
    if (value.isBefore(_earliest)) return _earliest;
    if (value.isAfter(widget.now)) return widget.now;
    return value;
  }
}
