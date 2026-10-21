import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../shared/ring/ring_metrics.dart';
import '../../../shared/sondr_swipe_row.dart';
import '../../tasks/models/task.dart';
import '../../tasks/tasks_providers.dart';
import '../timer_controller.dart';

/// Top-of-screen task switcher.
///
/// Tapping opens a minimal greyscale dropdown: a pinned "Select your task"
/// label, a list of slim full-width task pills, and a plain "Add Task" row at
/// the bottom. Each pill IS its own progress bar — a lighter-grey fill sweeps
/// left-to-right to show hours toward the first 20-hour milestone over a darker
/// remainder (the only place milestone progress is shown). The pill list is a
/// fixed area (~6 pills) that scrolls internally when there are more, so the
/// dropdown never grows unbounded.
///
/// All-tasks (collective) mode is reached by **double-tapping** the selector, so
/// it no longer needs a menu entry. The control is locked while a timer session
/// is active so logged time can't be misattributed by switching mid-session.
/// How long a row that has been acted on takes to collapse — the habits
/// list's 180ms ease-out, so the two lists move the same way.
const Duration _kLeaveDuration = Duration(milliseconds: 180);

class TaskDropdown extends ConsumerStatefulWidget {
  const TaskDropdown({super.key});

  @override
  ConsumerState<TaskDropdown> createState() => _TaskDropdownState();
}

class _TaskDropdownState extends ConsumerState<TaskDropdown> {
  final GlobalKey _selectorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final selected = ref.watch(selectedTaskProvider);
    final locked = ref.watch(timerControllerProvider).isActive;
    final isCollective = selected == null;

    final label = isCollective ? 'Task' : selected.name;

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : _openMenu,
        // Double-tap snaps back to the all-tasks overview; only meaningful when
        // a specific task is selected.
        onDoubleTap: (locked || isCollective) ? null : _snapToCollective,
        child: Container(
          key: _selectorKey,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // The phantom left box equals the chevron + gap, so the TEXT is what
          // optically centres on screen while the chevron hangs off its right.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down,
                  size: 22, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _snapToCollective() {
    ref.read(selectedTaskIdProvider.notifier).clear();
  }

  Future<void> _openMenu() async {
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      // Screen-global coordinates (no SafeArea) so the panel lands just beneath
      // the selector: 382x382 at X6. Top (146) sits just above the dial's top
      // (152) so the opaque panel fully covers the dial when open.
      useSafeArea: false,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: _panelTop * figmaScale(context),
              left: 6 * figmaScale(context),
              child: const _TaskMenuPanel(),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;
    // One kind of result now: a task id. A task created inside the sheet pops
    // its own id, so being added and being chosen are the same path.
    ref.read(selectedTaskIdProvider.notifier).select(result);
  }
}

/// Screen-global Y (reference space) the open panel is pinned at — just above
/// the dial's top (152) so the opaque panel covers it.
const double _panelTop = 146;

/// Panel metrics (Figma, 393-wide screen; container 382 wide at X6), with the
/// pills thickened from 20 to 28.
const double _panelWidth = 382;
const double _pillHeight = 28;
const int _maxVisiblePills = 6;

/// The one spacing unit: above the first pill, between pills, below the last
/// pill, and under the footer row. Even spacing throughout is what gives the
/// sheet its airy feel, so these are deliberately not tuned separately.
const double _panelSpacing = 21;

/// Height of the footer row — "Add Task" / "Archived", or "Back" (Inter 15).
const double _footerHeight = 18;

/// Height of the archived view's one-line empty state (13 regular).
const double _emptyLineHeight = 18;

/// Reference-space Y of Home's "Last 10 days" heading — the sheet must stay
/// above it so the heading and the day circles below it remain visible.
const double _lastTenDaysTop = 511;

/// Height of the pill list for [pills] visible pills.
double _listHeightFor(int pills) =>
    pills == 0 ? 0 : pills * _pillHeight + (pills - 1) * _panelSpacing;

/// Panel height around a pill list (or empty line) of [listHeight].
double _panelHeightFor(double listHeight) =>
    _panelSpacing + listHeight + _panelSpacing + _footerHeight + _panelSpacing;

/// The dropdown body: the task pills, then a footer row beneath them. One
/// spacing unit is used above the first pill, between the pills, below the
/// last one and under the footer, so the sheet reads as evenly spaced
/// throughout. It is only as tall as its contents — one task gives a compact
/// sheet — and grows per task up to [_maxVisiblePills], beyond which the pills
/// scroll. At its tallest it still stops above Home's "Last 10 days" heading
/// (asserted below). Pops the route with the chosen task id (or the add-task
/// sentinel).
///
/// Two lists, one sheet. The active list is the default: pills, "Add Task"
/// centred, and "Archive" hard right at the same weight and tone — two
/// actions of equal standing, told apart by position. "Archive" swaps the
/// SAME sheet over to the put-away tasks — same pills, same progress bars —
/// where the footer is a single grey "Back". The mode is local to the open
/// sheet, so closing the dropdown and reopening it always lands on the active
/// list.
class _TaskMenuPanel extends ConsumerStatefulWidget {
  const _TaskMenuPanel();

  @override
  ConsumerState<_TaskMenuPanel> createState() => _TaskMenuPanelState();
}

class _TaskMenuPanelState extends ConsumerState<_TaskMenuPanel> {
  bool _archived = false;

  /// The unnamed pill at the top of the list, if one is open.
  bool _drafting = false;
  final TextEditingController _draft = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Open the draft pill. A second tap on "Add Task" is a no-op rather than a
  /// second pill — there is only ever one unnamed task.
  void _openDraft() {
    if (_drafting) return;
    setState(() {
      _draft.clear();
      _drafting = true;
    });
    // Past six tasks the list scrolls, and a draft inserted at the top of a
    // scrolled list is off-screen behind the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Enter on the draft. A name creates the task and pops its id, so the sheet
  /// closes and the new task is selected by the same path a tap takes.
  /// Nothing typed is a cancel, not an unnamed task — the same reading the
  /// habits screen takes.
  Future<void> _submitDraft(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) {
      setState(() => _drafting = false);
      return;
    }
    final task = await ref.read(tasksProvider.notifier).addTask(name);
    if (!mounted) return;
    Navigator.of(context).pop(task.id);
  }

  /// Put [task] away, or bring it back.
  ///
  /// Clearing the selection matters: leaving the dial pointing at a task you
  /// have just archived would keep its name and its timer controls on Home —
  /// the ghost. Dropping the selection lands back on the collective "Task"
  /// overview, which is view-only.
  ///
  /// There is no running timer to orphan here. The selector is locked while a
  /// session is active (see [_TaskDropdownState.build]), so this sheet cannot
  /// be opened mid-session and a task cannot be archived out from under a
  /// running clock.
  Future<void> _setArchived(Task task, bool archived) async {
    if (archived && ref.read(selectedTaskIdProvider) == task.id) {
      ref.read(selectedTaskIdProvider.notifier).clear();
    }
    await _leave(task);
    await ref.read(tasksProvider.notifier).setArchived(task.id, archived);
    _arrived(task);
  }

  /// Rows on their way out: collapsed over 180ms (the habits list's move)
  /// so the rows below visibly slide up, then removed by the refresh.
  ///
  /// Forgotten again once the refresh has landed — the same task is about
  /// to be drawn at full height on the OTHER list, and a row still marked
  /// as leaving would arrive there collapsed and invisible.
  final Set<String> _leaving = {};

  Future<void> _leave(Task task) async {
    if (!mounted) return;
    setState(() => _leaving.add(task.id));
    await Future<void>.delayed(_kLeaveDuration);
  }

  void _arrived(Task task) {
    if (!mounted) return;
    setState(() => _leaving.remove(task.id));
  }


  @override
  Widget build(BuildContext context) {
    // Guards the one hard constraint: even at its tallest the sheet may not
    // reach Home's "Last 10 days" heading.
    assert(
      _panelTop + _panelHeightFor(_listHeightFor(_maxVisiblePills)) <
          _lastTenDaysTop,
      'open task panel would cover the "Last 10 days" heading',
    );

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final tasks = _archived
        ? ref.watch(archivedTasksProvider)
        : ref.watch(activeTasksProvider);

    // Only the archived view says when it is empty. An empty ACTIVE list is a
    // first run, and "Add Task" directly beneath it is the whole answer.
    final showEmpty = _archived && tasks.isEmpty;
    final visiblePills = tasks.length.clamp(0, _maxVisiblePills);
    // The draft takes a pill's height, and a spacing unit too once there is
    // something below it to be separated from.
    final draftHeight = _drafting
        ? _pillHeight + (tasks.isEmpty ? 0 : _panelSpacing)
        : 0.0;
    final listHeight = showEmpty
        ? _emptyLineHeight
        : _listHeightFor(visiblePills) + draftHeight;
    final footerTop = _panelSpacing + listHeight + _panelSpacing;

    // "Add Task" is Inter Bold 15, white — the app's other headings. The
    // quiet ones take the supporting treatment, grey at regular weight.
    //
    // Built as bare Text rather than SondrAction deliberately: the footer's
    // height is a measured constant the panel's geometry depends on, and
    // SondrAction's 12 of vertical tap padding would make it 42 in an 18 row.
    final primaryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );
    final quietStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w400,
      color: tokens.textSecondary,
    );

    // Horizontal padding only — it widens the tap target without changing the
    // row's height, which the panel is measured on.
    Widget footerAction(String label, TextStyle? style, VoidCallback onTap) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * scale),
            child: Text(label, style: style),
          ),
        );

    return SizedBox(
      width: _panelWidth * scale,
      height: _panelHeightFor(listHeight) * scale,
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20 * scale),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Pills: 365 wide, centred (8.5 inset), one spacing unit down from
            // the top edge so the first pill is not flush against it.
            Positioned(
              left: 8.5 * scale,
              top: _panelSpacing * scale,
              width: 365 * scale,
              height: listHeight * scale,
              child: showEmpty
                  ? Center(
                      child: Text(
                        'No archived tasks.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13 * scale,
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The draft opens where the first pill was, and its
                        // growing height is what slides the list down — the
                        // same move "add habit" makes, for the same reason:
                        // no reflow jump.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _drafting
                              ? SizedBox(
                                  height: draftHeight * scale,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: _DraftPill(
                                      scale: scale,
                                      controller: _draft,
                                      onSubmitted: _submitDraft,
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 0, width: double.infinity),
                        ),
                        Expanded(
                          child: ListView.separated(
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: _panelSpacing * scale),
                      itemBuilder: (context, i) {
                        final task = tasks[i];
                        // The app's one swipe: left to reveal, tray on the
                        // right, exactly as Friends and the comments sheet do
                        // it. Reveal, never dismiss — the gesture uncovers the
                        // word and waits for a tap, and a tap anywhere on the
                        // open row closes it again.
                        //
                        // Keyed by the TASK, not the slot: swipe state belongs
                        // to a row, and when a row leaves, the one that moves
                        // up into its slot must arrive closed. Keyed by index
                        // it arrived already open — and looked untouched.
                        return AnimatedSize(
                          key: ValueKey(task.id),
                          duration: _kLeaveDuration,
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _leaving.contains(task.id)
                              ? const SizedBox(height: 0, width: double.infinity)
                              : SondrSwipeRow(
                          actions: [
                            _PillTrayAction(
                              label: _archived ? 'Unarchive' : 'Archive',
                              onTap: () => _setArchived(task, !_archived),
                            ),
                          ],
                          child: _TaskPill(
                            scale: scale,
                            label: task.name,
                            progress: task.milestoneProgress,
                            // An archived pill is a record, not a choice —
                            // tapping it must not put you back on it. Bring it
                            // back with Unarchive first.
                            onTap: _archived
                                ? null
                                : () => Navigator.of(context).pop(task.id),
                          ),
                        ),
                        );
                      },
                          ),
                        ),
                      ],
                    ),
            ),
            // The footer row, one spacing unit below the last pill and the
            // same again above the panel's bottom edge.
            Positioned(
              left: 0,
              right: 0,
              top: footerTop * scale,
              child: _archived
                  // "Back" already reverses the "Archived" that got here, so
                  // this view carries no second toggle.
                  ? Center(
                      child: footerAction(
                        'Back',
                        quietStyle,
                        () => setState(() => _archived = false),
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        footerAction('Add task', primaryStyle, _openDraft),
                        // Same row, same baseline, hard right — and the
                        // SUPPORTING tone, the one "Back" takes in the view
                        // this opens. Adding a task is what the sheet is for;
                        // putting one away is the side door, and two actions
                        // at the same weight made the reader pick between
                        // them. Position tells them apart, tone says which
                        // one the sheet is about.
                        Positioned(
                          right: 2 * scale,
                          child: footerAction(
                            'Archive',
                            quietStyle,
                            () => setState(() => _archived = true),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A swipe-tray action sized for a 28-tall pill.
///
/// [SondrAction] cannot go in here: its 12 of vertical tap padding makes it
/// around 40 tall, and a 28 pill row has no room for that — it would break the
/// panel's measured height. So the label is built at the PILL's own type
/// (12/bold/textPrimary) with horizontal padding for the tap target.
///
/// White at full emphasis, like every other tray action: it was summoned by a
/// deliberate gesture rather than standing on the screen, so it costs nothing
/// in clutter and has nothing to be de-emphasised against (DESIGN.md).
class _PillTrayAction extends StatelessWidget {
  const _PillTrayAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The tray closes the moment its word is tapped: the row is never
      // left standing open after the thing it offered has been done.
      onTap: () {
        SondrSwipeRow.close(context);
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A 28-tall task pill (fully rounded) that doubles as its own progress bar: a
/// lighter-grey fill sweeps from the left over a darker remainder, in proportion
/// to [progress] (0..1) through the current 20-hour block — the same measure
/// the profile rings use, so a filled bar means the same thing everywhere.
/// Empty = all dark; it resets on each milestone and climbs again toward the
/// next. The fill is drawn through [shownProgress], the same clamp the rings
/// use, so any time at all shows a nub and a nearly-finished band keeps a
/// visible gap — a bar that filled to the end would claim a milestone the
/// task has not reached. The filled left end is rounded by the pill; the
/// filled/unfilled boundary is a clean vertical edge. Name centred, Inter bold
/// 12, white. Pure greyscale — fill and remainder are a brightness step apart.
/// A task being named: a pill with nothing in it yet.
///
/// The same capsule as [_TaskPill] at its empty state — track tone, zero
/// progress — with the field drawn straight onto it.
///
/// The field is built here rather than taken from SondrField, because this
/// one is not a form field: it is a LABEL being typed. It has to land on the
/// same line box the name will occupy a moment later, which means the pill's
/// own style, a forced strut so the line cannot be taller than the label's,
/// and a caret the height of that line rather than the field's own idea of
/// one. SondrField's column also expands to whatever height it is given and
/// puts its row at the top, which is what left the cursor against the pill's
/// top edge — 6.5 above where the name would sit.
///
/// Cursor tone and width are SondrField's, so the caret is the app's caret.
class _DraftPill extends StatelessWidget {
  const _DraftPill({
    required this.scale,
    required this.controller,
    required this.onSubmitted,
  });

  final double scale;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final height = _TaskPill.height * scale;
    // Byte for byte the style a named pill uses.
    final labelStyle = _TaskPill.labelStyleOf(context);
    // The line the label occupies: 1.4 of its size, forced, so the typed name
    // and the written one share a box and a baseline.
    final lineHeight = labelStyle.fontSize! * (labelStyle.height ?? 1);

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: _TaskPill.trackColour(tokens),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 1,
                style: labelStyle,
                strutStyle: StrutStyle.fromTextStyle(
                  labelStyle,
                  forceStrutHeight: true,
                ),
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: onSubmitted,
                cursorColor: tokens.textPrimary,
                cursorWidth: 1.5 * scale,
                // The label's line, not the field's default — a caret taller
                // than the text it is typing reads as a different component.
                cursorHeight: lineHeight,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({
    required this.scale,
    required this.label,
    required this.progress,
    required this.onTap,
  });

  /// Shared with [_DraftPill], so an empty pill and a named one cannot drift.
  static const double height = _height;
  static const double labelSize = 12;

  /// The name's style, so a pill being typed and a pill already named are
  /// the same text in the same place.
  static TextStyle labelStyleOf(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: labelSize * figmaScale(context),
        fontWeight: FontWeight.w700,
        color: GreyscaleTokens.of(context).textPrimary,
      );

  /// The capsule's own tone, with no progress drawn over it.
  static Color trackColour(GreyscaleTokens tokens) =>
      Color.lerp(tokens.surface, tokens.ringTrack, 0.5)!;

  static const double _height = 28;

  /// Figma-reference scale, so pills grow with the panel around them.
  final double scale;

  final String label;
  final double progress;

  /// Null on an archived row — a record, not a choice.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final height = _height * scale;
    final shown = shownProgress(progress);
    final remainder = trackColour(tokens);
    final fill = Color.lerp(tokens.ringTrack, tokens.ringFillInner, 0.35)!;
    final nameStyle = labelStyleOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: remainder),
              if (shown > 0)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth * shown;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: ColoredBox(color: fill),
                      ),
                    );
                  },
                ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: nameStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
