import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../timer/live_activity.dart' show ChannelLiveActivity;
import '../timer/session_store.dart' show kSessionAppGroup;
import 'widget_snapshot.dart';

/// Putting the snapshot where the widget can read it, and telling
/// WidgetKit to draw again.
///
/// A seam: both halves are platform, and what is worth testing is that
/// the app publishes at the right moments and that what it publishes is
/// the right shape.
abstract interface class WidgetBridge {
  Future<void> publish(WidgetSnapshot snapshot);
}

class PlatformWidgetBridge implements WidgetBridge {
  PlatformWidgetBridge({SharedPreferencesAsync? prefs, MethodChannel? channel})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(
              suiteName: kSessionAppGroup,
            ),
          ),
      _channel =
          channel ?? const MethodChannel(ChannelLiveActivity.channelName);

  final SharedPreferencesAsync _prefs;
  final MethodChannel _channel;

  /// The App Group first, then the reload: a widget asked to redraw
  /// before the document is there would draw the old one and be told
  /// nothing more.
  @override
  Future<void> publish(WidgetSnapshot snapshot) async {
    try {
      await _prefs.setString(WidgetSnapshot.key, snapshot.toJson());
      await _channel.invokeMethod<void>('reloadWidgets');
    } catch (e) {
      // A widget that misses one redraw shows the last thing it had,
      // which is never worse than the screen it is on top of.
      debugPrint('SONDR widget publish error: ${e.runtimeType}');
    }
  }
}

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => PlatformWidgetBridge(),
);
