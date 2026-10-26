import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/date.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_swipe_row.dart';
import 'habits_providers.dart';
import 'models/daily_habits.dart';

/// Reference size of a habit name. Large and plain: the names ARE the screen,
/// so nothing else on it needs to be big.
const double _kNameSize = 27;

/// Home's own vertical lines, measured off it and copied here.
///
/// Home carries these as inline literals by design, so this is a deliberate
/// copy rather than a shared constant — the two are checked against each other
/// in a test instead (see test/habits_page_test.dart), which catches a drift
/// without tying the two screens' layout together.
///
/// [_kWeekdayTop] is where Home's task selector puts its TEXT (its Positioned
/// is at 102 and the selector adds 4 of its own padding); [_kAddTextTop] is
/// where "View your progress" puts its own. Both are screen-global, so this
/// overlay positions globally too — no SafeArea in the way.
const double _kWeekdayTop = 106;
const double _kWeekdaySize = 20;
const double _kAddTextTop = 732;

/// The floor of the list: clear of the add action by one base tier.
const double _kListBottom = _kAddTextTop - kSpacingBase;

/// Shows today's habits as a frosted overlay over whatever is behind it.
///
/// An overlay rather than a page: the habits are a glance at today, and the
/// screen you came from staying visible through the blur is what makes this
/// read as something lifted over the app rather than somewhere you navigated
/// to. There is no Back — it is pulled down by the handle at its top.
Future<void> showHabitsScreen(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => const HabitsScreen(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Today's habits, plain: the weekday, the names, and "add habit".
///
/// Only today — there is no day browsing here. A name carries its own state
/// (white when done, grey when not), tapping it toggles, and swiping it
/// uncovers "remove". Nothing else is drawn: no checkbox, no ring, no rule.
class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  final _name = TextEditingController();

  /// Whether the in-place field is open at the top of the list.
  bool _adding = false;

  /// Distance pulled down on the handle so far. Accumulated rather than read
  /// per-event, so a slow deliberate drag dismisses as readily as a flick.
  double _pull = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _openAdd() => setState(() {
    _name.clear();
    _adding = true;
  });

  void _closeAdd() {
    if (!mounted) return;
    setState(() {
      _adding = false;
      _name.clear();
    });
  }

  /// Enter on the field. A name adds a habit; nothing typed is a cancel, not
  /// an empty habit.
  Future<void> _submit(String raw) async {
    final name = raw.trim();
    _closeAdd();
    if (name.isEmpty) return;
    await ref.read(habitsProvider.notifier).addHabit(name);
  }

  void _pullUpdate(DragUpdateDetails d) => _pull += d.primaryDelta ?? 0;

  void _pullEnd(DragEndDetails d) {
    final flung = d.velocity.pixelsPerSecond.dy;
    if (_pull > 60 || flung > 500) Navigator.of(context).maybePop();
    _pull = 0;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final screen = MediaQuery.sizeOf(context).height;
    final ticks = ref.watch(todayHabitsProvider)?.ticks ?? const <HabitTick>[];
    final now = DateTime.now();

    // Two ways out, and no handle: a handle promises a sheet that can be
    // dragged, and this is not one. A tap on the blurred backdrop closes it —
    // the gesture the overlay has always taught — and so does a downward
    // swipe anywhere the list is not already claiming the drag. The names and
    // "add habit" are deeper, so their taps still win.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      onVerticalDragUpdate: _pullUpdate,
      onVerticalDragEnd: _pullEnd,
      child: Stack(
        children: [
          // Frosted backdrop — blurs whatever is behind.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: tokens.background.withValues(alpha: 0.55),
              ),
            ),
          ),
          // Transparent Material, not a Scaffold: the field needs a Material
          // ancestor to draw its cursor and selection into, and a Scaffold
          // would paint its own background over the blur.
          Material(
            type: MaterialType.transparency,
            // Screen-global, like Home — a y here is a y there.
            child: Stack(
              children: [
                // The day, on Home's title line and at its size. The date is a
                // number this screen has no use for, and a "Habits" label over
                // a page of habits is a word it already says.
                Positioned(
                  top: _kWeekdayTop * scale,
                  left: 0,
                  right: 0,
                  child: Text(
                    DayKey.weekday(now.weekday),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      // Unscaled, because Home's title is.
                      fontSize: _kWeekdaySize,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                // The names, centred in what is left between the day and the
                // add action.
                Positioned(
                  top: (_kWeekdayTop + 40) * scale,
                  bottom: (screen - _kListBottom * scale).clamp(0, screen),
                  left: 32 * scale,
                  right: 32 * scale,
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The field opens where the first habit was, and its
                          // growing height is what slides the list down — no
                          // reflow jump.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: _adding
                                // In a habit's row exactly: the same style
                                // (so the line box and the cursor are the
                                // habit text's height) and the same 12
                                // above and below, so the cursor and the
                                // first habit sit like two habits.
                                ? Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: kSpacingBase * scale,
                                    ),
                                    child: SondrField(
                                      controller: _name,
                                      filled: false,
                                      centered: true,
                                      autofocus: true,
                                      fontSize: _kNameSize,
                                      style: habitNameStyle(context),
                                      textInputAction: TextInputAction.done,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      onSubmitted: _submit,
                                    ),
                                  )
                                : const SizedBox(height: 0),
                          ),
                          for (final tick in ticks)
                            SondrSwipeRow(
                              key: ValueKey(tick.habitId),
                              // Reveal, never dismiss: the swipe uncovers the
                              // word and waits for a tap.
                              actions: [
                                SondrAction(
                                  label: 'Remove',
                                  fontSize: kRowActionSize,
                                  onPressed: () => ref
                                      .read(habitsProvider.notifier)
                                      .removeHabit(tick.habitId),
                                ),
                              ],
                              child: _HabitName(tick: tick),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // On Home's "View your progress" line. The BOX goes a tier
                // higher than the line because SondrAction's own 12 of tap
                // padding sits above its text.
                Positioned(
                  top: (_kAddTextTop - kSpacingBase) * scale,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SondrAction(
                      label: 'Add habit',
                      onPressed: _openAdd,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One habit name, carrying its own state.
///
/// White when it is done, grey when it is not — no checkbox, no circle and no
/// strike-through, because a struck-out name reads as cancelled rather than as
/// finished. Tapping toggles it, which writes today's record and nothing else:
/// past days are frozen.
///
/// The streak follows the name on the SAME line and the same baseline, at half
/// its size and the faint tone, so it reads as a number attached to the habit
/// rather than as a second column. Nothing is shown below one: a habit with no
/// run behind it yet has nothing to say, and a bare 0 beside a name reads as a
/// score.
/// A habit name's type: the one style the row and the add field share, so
/// the field's line box is a habit's line box.
TextStyle? habitNameStyle(BuildContext context, {bool done = true}) {
  final tokens = GreyscaleTokens.of(context);
  return Theme.of(context).textTheme.displayMedium?.copyWith(
    fontSize: _kNameSize * figmaScale(context),
    fontWeight: FontWeight.w600,
    color: done ? tokens.textPrimary : tokens.textTertiary,
  );
}

class _HabitName extends ConsumerWidget {
  const _HabitName({required this.tick});

  final HabitTick tick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final streak = ref.watch(habitStreakForProvider(tick.habitId));

    final name = habitNameStyle(context, done: tick.done);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(habitsProvider.notifier).toggle(tick.habitId),
      // Full width on purpose. SondrSwipeRow's Stack aligns its content to
      // the trailing edge (that is how the tray is uncovered), so a
      // shrink-wrapped name lands hard right and textAlign has nothing to
      // centre inside. Filling the row puts the name back in the middle,
      // where the add-field's cursor already is.
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: kSpacingBase * scale),
          child: Text.rich(
            TextSpan(
              children: [
                // As typed. Nothing here lowercases a name the user chose.
                TextSpan(text: tick.name, style: name),
                if (streak > 0)
                  TextSpan(
                    text: ' $streak',
                    style: name?.copyWith(
                      fontSize: _kNameSize * scale * 0.5,
                      color: tokens.textTertiary,
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
