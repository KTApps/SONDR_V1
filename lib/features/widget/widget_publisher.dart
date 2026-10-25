import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../habits/habits_providers.dart';
import '../tasks/tasks_providers.dart';
import '../timer/session_store.dart';
import '../timer/timer_controller.dart';
import 'widget_bridge.dart';
import 'widget_snapshot.dart';

/// What the Home Screen widget should be showing, right now.
///
/// Derived rather than pushed, so there is no list of places that have to
/// remember to update it: anything that changes a task, the selection or
/// today's habits changes this, and the publisher below writes it.
final widgetSnapshotProvider = Provider<WidgetSnapshot>((ref) {
  // The session is watched but not carried: its own document in the App
  // Group is the truth, and the widget reads that. Watching it here is
  // what makes a start or a stop redraw the widget.
  ref.watch(timerControllerProvider);
  return WidgetSnapshot.of(
    tasks: ref.watch(tasksProvider).value ?? const [],
    habits: ref.watch(todayHabitsProvider),
    selectedTaskId: ref.watch(selectedTaskIdProvider),
    now: ref.watch(nowProvider)(),
  );
});

/// Keeps the widget's copy in step. Listened to once, at launch.
///
/// Fires immediately so a widget added while the app was closed has
/// something to draw the next time the app is opened, and on every change
/// after that — but only when the snapshot would actually look different,
/// because a timeline reload is not free.
final widgetPublisherProvider = Provider<void>((ref) {
  final bridge = ref.watch(widgetBridgeProvider);

  // Starting, pausing and stopping change the session, not the document
  // — the widget reads the session itself — so there is nothing to
  // publish and everything to redraw. Status, not elapsed: a tick is not
  // news, and the widget counts its own seconds.
  ref.listen<TimerStatus>(
    timerControllerProvider.select((timer) => timer.status),
    (_, _) => bridge.reload(),
  );

  WidgetSnapshot? last;
  ref.listen<WidgetSnapshot>(
    widgetSnapshotProvider,
    (_, next) {
      // A refetch empties the task list for an instant before it comes
      // back with the same tasks. Publishing that would blank the widget
      // and fill it again, on a screen nobody asked to flicker.
      final reloading = ref.read(tasksProvider).isLoading;
      if (reloading && next.tasks.isEmpty && last != null) return;
      if (next == last) return;
      last = next;
      bridge.publish(next);
    },
    fireImmediately: true,
  );
});
