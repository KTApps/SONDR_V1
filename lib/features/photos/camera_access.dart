import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timer/live_activity.dart';

/// Where this app stands with the camera, as iOS keeps it.
///
/// Read without asking: iOS answers the question "may this app use the
/// camera" without putting up its prompt, so the More sheet can say On or
/// Off — or that it has never been asked — without being the reason the
/// prompt appears.
enum CameraAccess {
  /// Never asked. The one state in which asking puts up the prompt.
  notDetermined,
  authorized,
  denied,

  /// Off by a rule the person cannot change here — Screen Time, a managed
  /// phone. Shown as Off; Settings is still the only place it can be seen.
  restricted;

  static CameraAccess? fromName(String? name) => switch (name) {
    'notDetermined' => CameraAccess.notDetermined,
    'authorized' => CameraAccess.authorized,
    'denied' => CameraAccess.denied,
    'restricted' => CameraAccess.restricted,
    _ => null,
  };
}

/// The words after "Camera access" in the More sheet.
String? cameraAccessDetail(CameraAccess? access) => switch (access) {
  CameraAccess.authorized => '· On',
  CameraAccess.denied || CameraAccess.restricted => '· Off',
  CameraAccess.notDetermined => '· Not set',
  null => null,
};

/// The two questions Swift answers, on the channel the Lock Screen card
/// already uses — one bridge, not two.
abstract interface class CameraAccessSource {
  /// The status, without prompting. Null where there is nothing to ask —
  /// a widget test, or a host with no bridge.
  Future<CameraAccess?> status();

  /// Put up iOS's camera prompt, and the status once it has been answered.
  /// Only ever prompts when the status is [CameraAccess.notDetermined]; at
  /// any other status iOS answers at once with what it already knows.
  Future<CameraAccess?> request();
}

class ChannelCameraAccessSource implements CameraAccessSource {
  ChannelCameraAccessSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(ChannelLiveActivity.channelName);

  final MethodChannel _channel;

  @override
  Future<CameraAccess?> status() => _ask('cameraStatus');

  @override
  Future<CameraAccess?> request() => _ask('requestCamera');

  Future<CameraAccess?> _ask(String method) async {
    try {
      return CameraAccess.fromName(await _channel.invokeMethod<String>(method));
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('SONDR camera access $method error: ${e.runtimeType} :: $e');
      return null;
    }
  }
}

final cameraAccessSourceProvider = Provider<CameraAccessSource>(
  (ref) => ChannelCameraAccessSource(),
);

/// The current status, read once and again every time the app comes back
/// to the front — which is how a change made in Settings arrives.
class CameraAccessController extends AsyncNotifier<CameraAccess?> {
  AppLifecycleListener? _lifecycle;

  @override
  Future<CameraAccess?> build() {
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() => _lifecycle?.dispose());
    return ref.read(cameraAccessSourceProvider).status();
  }

  /// Read it again.
  Future<void> refresh() async {
    final next = await ref.read(cameraAccessSourceProvider).status();
    state = AsyncData(next);
  }

  /// Ask, where asking means something, and keep what comes back.
  Future<void> request() async {
    final next = await ref.read(cameraAccessSourceProvider).request();
    state = AsyncData(next ?? await ref.read(cameraAccessSourceProvider).status());
  }
}

final cameraAccessProvider =
    AsyncNotifierProvider<CameraAccessController, CameraAccess?>(
      CameraAccessController.new,
    );
