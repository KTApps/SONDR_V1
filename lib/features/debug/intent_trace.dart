import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../timer/session_store.dart' show kSessionAppGroup;

/// What the Swift intents did with their clocks — DEBUG_TOOLS only.
///
/// Each of the card's Pause/Resume, the widget's Start and the widget's
/// Stop records when it performed, how old its process was, whether it
/// back-dated to the launch, and the instant it finally wrote. Swift
/// writes only while [enable] has left its flag; see `IntentTrace` in
/// ios/SondrWidgets/SessionMutation.swift.
class IntentTraceStore {
  static const String key = 'sondr.debug.intents';
  static const String enabledKey = 'sondr.debug.enabled';

  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync(
    options: SharedPreferencesAsyncFoundationOptions(
      suiteName: kSessionAppGroup,
    ),
  );

  static Future<void> enable() async {
    try {
      await _prefs.setBool(enabledKey, true);
    } catch (e) {
      debugPrint('SONDR intent trace: ${e.runtimeType}');
    }
  }

  /// The last three entries, newest last.
  static Future<List<Map<String, Object?>>> last() async {
    try {
      final raw = await _prefs.getString(key);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final e in list) if (e is Map) e.cast<String, Object?>()];
    } catch (e) {
      return const [];
    }
  }

  /// One line per entry, for a monospace readout.
  static String describe(Map<String, Object?> e) {
    final performed = DateTime.fromMillisecondsSinceEpoch(
      (e['performedAt'] as num?)?.toInt() ?? 0,
    );
    final stamp = DateTime.fromMillisecondsSinceEpoch(
      (e['finalStamp'] as num?)?.toInt() ?? 0,
    );
    final age = (e['launchAge'] as num?)?.toInt() ?? -1;
    final process = (e['process'] as String? ?? '?').split('.').last;
    String hms(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}.'
        '${(d.millisecond ~/ 100)}';
    return '${e['kind']} @${hms(performed)} '
        'age=${age < 0 ? '—' : '${age}ms'} '
        '${e['backDated'] == true ? 'backdated' : 'as-is'} '
        '→ ${hms(stamp)} [$process]';
  }
}
