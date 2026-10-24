import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../tasks/tasks_providers.dart';
import '../timer/session_store.dart' show kSessionAppGroup;

/// A task the widget chose while the app was not running.
///
/// Tapping a name on the Home Screen selects that task for the widget AND
/// for Home — but the app may be days from its next launch, so the widget
/// leaves the id here and the app takes it when it next starts. Written
/// by `WidgetSelection.set` in ios/SondrWidgets/WidgetIntents.swift; the
/// key is the whole agreement.
abstract interface class WidgetSelectionInbox {
  /// The id left for us, if any, and clear it. Taken once: a selection
  /// read twice would override whatever the person did in between.
  Future<String?> take();
}

class PrefsWidgetSelectionInbox implements WidgetSelectionInbox {
  PrefsWidgetSelectionInbox({SharedPreferencesAsync? prefs}) : _given = prefs;

  static const String key = 'sondr.widgetSelection';

  final SharedPreferencesAsync? _given;

  /// Built on first use rather than in the constructor. Making it in the
  /// constructor throws where the platform is not registered, and this
  /// is read from the boot gate: a missing inbox must leave the launch
  /// alone, not fail it.
  late final SharedPreferencesAsync _prefs =
      _given ??
      SharedPreferencesAsync(
        options: SharedPreferencesAsyncFoundationOptions(
          suiteName: kSessionAppGroup,
        ),
      );

  @override
  Future<String?> take() async {
    try {
      final id = await _prefs.getString(key);
      if (id == null || id.isEmpty) return null;
      await _prefs.remove(key);
      return id;
    } catch (e) {
      debugPrint('SONDR widget selection read error: ${e.runtimeType}');
      return null;
    }
  }
}

final widgetSelectionInboxProvider = Provider<WidgetSelectionInbox>(
  (ref) => PrefsWidgetSelectionInbox(),
);

/// Apply whatever the widget chose, once, at launch.
///
/// A task deleted since is ignored rather than selected: the widget's
/// copy can be older than the app's.
final applyWidgetSelectionProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final id = await ref.read(widgetSelectionInboxProvider).take();
    if (id == null) return;
    final tasks = await ref.read(tasksProvider.future);
    if (!tasks.any((task) => task.id == id)) return;
    ref.read(selectedTaskIdProvider.notifier).select(id);
  },
);
