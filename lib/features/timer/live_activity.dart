import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_clock.dart';

/// The Lock Screen card, as the app can affect it.
///
/// Never load-bearing. Every method here may quietly do nothing — an iPhone
/// below iOS 17, Live Activities switched off in Settings, a simulator with
/// no Dynamic Island — and the timer is exactly as correct either way. The
/// card is a window onto the session, not where the session lives.
abstract class LiveActivity {
  /// Put [clock] on the Lock Screen, starting a card if there is not one.
  Future<void> show(SessionClock clock);

  /// Take the card away now.
  Future<void> clear();

  /// Taps on the card, as bare actions: `stop`, `pause`, `resume`, `home`.
  Stream<String> get links;

  /// Something outside the app changed the stored session.
  ///
  /// The card's Pause and Resume are intents, and so is the widget's
  /// Start: they write the App Group in another process (or in this one,
  /// without Dart), and nothing comes down the channel for them. Swift
  /// posts a Darwin notification after every such write and this is it,
  /// arriving here. It carries nothing — the answer is always to re-read
  /// the session.
  Stream<void> get sessionChanges;

  /// Say the app is ready to act on a tap.
  ///
  /// A card tapped while the app was not running has to wait: stopping a
  /// session the app has not read yet would stop nothing. Anything tapped
  /// before this is held and delivered the moment it is called.
  Future<void> ready();
}

/// The real one, over a method channel to [SessionActivityChannel] in Swift.
class ChannelLiveActivity implements LiveActivity {
  ChannelLiveActivity({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'sondr/live_activity';

  final MethodChannel _channel;
  final StreamController<String> _taps = StreamController<String>.broadcast();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Future<bool>? _asked;

  @override
  Stream<String> get links => _taps.stream;

  @override
  Stream<void> get sessionChanges => _changes.stream;

  /// Whether this phone can show a card at all.
  ///
  /// Asked once per launch. Switching Live Activities off in Settings while
  /// the app is running would leave this stale, which costs nothing: the
  /// Swift side checks again before it requests anything, so a stale yes
  /// means a call that does nothing rather than a card that should not
  /// exist.
  Future<bool> get _supported =>
      _asked ??= _invoke<bool>('supported').then((yes) => yes ?? false);

  @override
  Future<void> show(SessionClock clock) async {
    if (!await _supported) return;
    // The stored session, field for field — the same contract the extension
    // reads out of the App Group, so there is only ever one shape.
    await _invoke<void>('show', clock.toMap());
  }

  @override
  Future<void> clear() async {
    if (!await _supported) return;
    await _invoke<void>('clear');
  }

  @override
  Future<void> ready() async {
    if (!await _supported) return;
    await _invoke<void>('ready');
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'sessionChanged') {
      _changes.add(null);
      return;
    }
    if (call.method != 'link') return;
    final action = call.arguments;
    if (action is String && action.isNotEmpty) _taps.add(action);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // A host with no bridge at all: a widget test, or Android.
      return null;
    } catch (e) {
      debugPrint('SONDR live activity $method error: ${e.runtimeType} :: $e');
      return null;
    }
  }

  void dispose() => _taps.close();
}

final liveActivityProvider = Provider<LiveActivity>((ref) {
  final activity = ChannelLiveActivity();
  ref.onDispose(activity.dispose);
  return activity;
});

/// What a tap on the card asks for.
enum CardTap { pause, resume, stop, home }

/// Turns a tap on the card into something the app does.
///
/// Apart from the screen that owns the stop flow, so the order can be tested
/// without a Lock Screen. The order is the point: a card tapped while the app
/// was not running launches it, and the tap beats the launch. Acting on
/// "stop" before the stored session has been read would stop nothing and log
/// nothing, and the time would be gone.
class CardTapRouter {
  CardTapRouter({
    required this.restored,
    required this.alive,
    required this.onHome,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  /// Completes when the app knows what session, if any, is running.
  final Future<void> restored;

  /// Whether there is still anything to act on — the screen can go away
  /// while the restore is in flight.
  final bool Function() alive;

  /// Every tap lands on Home first: these are all the timer's own actions,
  /// and finishing a session on the Feed tab would be a strange place to be
  /// left.
  final void Function() onHome;

  final void Function() onPause;
  final void Function() onResume;
  final Future<void> Function() onStop;

  static CardTap? parse(String action) => switch (action) {
    'pause' => CardTap.pause,
    'resume' => CardTap.resume,
    'stop' => CardTap.stop,
    'home' => CardTap.home,
    // A card left over from a build that spoke a word this one does not.
    _ => null,
  };

  Future<void> handle(String action) async {
    final tap = parse(action);
    if (tap == null) return;
    await restored;
    if (!alive()) return;
    onHome();
    switch (tap) {
      case CardTap.pause:
        onPause();
      case CardTap.resume:
        onResume();
      case CardTap.stop:
        await onStop();
      case CardTap.home:
        break;
    }
  }
}
