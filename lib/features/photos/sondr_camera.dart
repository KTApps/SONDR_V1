import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/ring/ring_metrics.dart';
import '../../shared/sondr_action.dart';
import 'capture_crop.dart';

/// Reference-point geometry. Device values are these × figmaScale, so on a
/// 13 Pro the viewfinder is 342 x 456 and the shutter is Ø71.3.
const double kCameraTaskTop = 12;
const double kCameraTaskToViewfinder = 16;
const double kCameraSideInset = 24;
const double kViewfinderRadius = 24;
const double kViewfinderToControls = 24;
const double kShutterSize = 72;
const double kCameraControlSize = 12;

/// The smallest a control may be and still be reliably hit.
const double kCameraTapTarget = 44;

/// What the flash is set to. The app's own, so the screen does not have to
/// speak the camera package's language — and `torch` is deliberately absent:
/// three states to cycle, not four.
enum CaptureFlash { off, on, auto }

extension on CaptureFlash {
  String get label => switch (this) {
    CaptureFlash.off => 'flash off',
    CaptureFlash.on => 'flash on',
    CaptureFlash.auto => 'flash auto',
  };

  CaptureFlash get next => switch (this) {
    CaptureFlash.off => CaptureFlash.on,
    CaptureFlash.on => CaptureFlash.auto,
    CaptureFlash.auto => CaptureFlash.off,
  };

  FlashMode get mode => switch (this) {
    CaptureFlash.off => FlashMode.off,
    CaptureFlash.on => FlashMode.always,
    CaptureFlash.auto => FlashMode.auto,
  };
}

/// Why there is no viewfinder.
enum CameraTrouble { denied, unavailable }

/// The camera, as the screen needs it.
///
/// An interface rather than a CameraController directly, because a controller
/// cannot exist in a widget test — it needs a platform behind it — and the
/// whole of this screen's layout is worth testing.
abstract class CameraSession {
  /// Opens the camera. Returns null on success, or why it could not.
  Future<CameraTrouble?> start({bool front = false});

  /// The live preview, cover-filling whatever box it is given.
  Widget preview(BuildContext context);

  /// JPEG bytes as the sensor produced them, before cropping.
  Future<Uint8List?> capture();

  Future<void> setFlash(CaptureFlash flash);

  /// False on a device (or a lens) with no flash — the control is hidden
  /// rather than shown doing nothing.
  bool get hasFlash;

  /// False when there is only one lens, which hides "flip".
  bool get canFlip;

  /// True while the front lens is live, so the capture can be un-mirrored.
  bool get isFront;

  Future<void> stop();
}

/// The real one.
class DeviceCameraSession implements CameraSession {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _front = false;

  @override
  bool get isFront => _front;

  @override
  bool get canFlip => _cameras.length > 1;

  @override
  bool get hasFlash => !_front && _cameras.isNotEmpty;

  @override
  Future<CameraTrouble?> start({bool front = false}) async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) return CameraTrouble.unavailable;
      final wanted = _cameras.firstWhere(
        (c) =>
            c.lensDirection ==
            (front ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );
      _front = wanted.lensDirection == CameraLensDirection.front;
      await _controller?.dispose();
      final controller = CameraController(
        wanted,
        ResolutionPreset.high,
        // Stills only. Asking for audio asks for the microphone permission,
        // and the app has no use for one.
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      return null;
    } on CameraException catch (e) {
      debugPrint('SONDR camera error: ${e.code} :: ${e.description}');
      return e.code.toLowerCase().contains('permission')
          ? CameraTrouble.denied
          : CameraTrouble.unavailable;
    } catch (e) {
      debugPrint('SONDR camera error: ${e.runtimeType} :: $e');
      return CameraTrouble.unavailable;
    }
  }

  @override
  Widget preview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    // The sensor is not 3:4. Cover-fill the rectangle the viewfinder is, so
    // what is framed is what the crop keeps.
    final size = controller.value.previewSize;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size?.height ?? 3,
        height: size?.width ?? 4,
        child: CameraPreview(controller),
      ),
    );
  }

  @override
  Future<Uint8List?> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final shot = await controller.takePicture();
      return await shot.readAsBytes();
    } catch (e) {
      debugPrint('SONDR capture error: ${e.runtimeType} :: $e');
      return null;
    }
  }

  @override
  Future<void> setFlash(CaptureFlash flash) async {
    try {
      await _controller?.setFlashMode(flash.mode);
    } catch (e) {
      debugPrint('SONDR flash error: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _controller?.dispose();
    _controller = null;
  }
}

/// Finders for the test harness, which measures this screen's geometry.
const Key kViewfinderKey = Key('sondr-viewfinder');
const Key kShutterKey = Key('sondr-shutter');

/// The sondr camera: a 3:4 viewfinder and a shutter that doubles as the
/// task's progress ring.
///
/// Full screen and outside the shell, so there is no tab bar under it. Pops
/// the captured JPEG — already cropped to [kCaptureWidth] x [kCaptureHeight] —
/// or null if the session was skipped.
class SondrCameraScreen extends StatefulWidget {
  const SondrCameraScreen({
    super.key,
    required this.taskName,
    required this.sessionLabel,
    required this.ringProgress,
    this.session,
    this.onOpenSettings,
  });

  final String taskName;

  /// "1h 20m" — already formatted, so this screen owns no duration rules.
  final String sessionLabel;

  /// Progress toward the next milestone INCLUDING the session just finished,
  /// already passed through shownProgress by the caller.
  final double ringProgress;

  /// Injected by tests; a real device session otherwise.
  final CameraSession? session;

  /// Opening iOS Settings is the host app's job — see the note in
  /// [photo_capture_flow].
  final VoidCallback? onOpenSettings;

  @override
  State<SondrCameraScreen> createState() => _SondrCameraScreenState();
}

class _SondrCameraScreenState extends State<SondrCameraScreen>
    with WidgetsBindingObserver {
  late final CameraSession _session = widget.session ?? DeviceCameraSession();
  CameraTrouble? _trouble;
  CaptureFlash _flash = CaptureFlash.off;
  bool _front = false;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.stop();
    super.dispose();
  }

  /// Hold a camera only while the screen is in front of someone. iOS will
  /// take it away in the background anyway; releasing it deliberately means
  /// coming back to a live preview rather than a frozen one.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _session.stop();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed && !_ready) {
      _start();
    }
  }

  Future<void> _start() async {
    final trouble = await _session.start(front: _front);
    if (!mounted) return;
    setState(() {
      _trouble = trouble;
      _ready = trouble == null;
    });
    if (trouble == null && _session.hasFlash) await _session.setFlash(_flash);
  }

  Future<void> _flip() async {
    setState(() => _front = !_front);
    await _start();
  }

  Future<void> _cycleFlash() async {
    final next = _flash.next;
    setState(() => _flash = next);
    await _session.setFlash(next);
  }

  Future<void> _shoot() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final raw = await _session.capture();
    if (!mounted) return;
    if (raw == null) {
      setState(() => _busy = false);
      return;
    }
    // Crop before anyone sees it, so the review screen shows exactly the
    // file that will be stored.
    final shot = cropToCaptureShape(raw, mirror: _session.isFront);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(shot ?? raw);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final media = MediaQuery.of(context);
    final viewfinderWidth = media.size.width - 2 * kCameraSideInset * scale;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: kCameraTaskTop * scale),
          child: Column(
            children: [
              Text(
                '${widget.taskName} · ${widget.sessionLabel}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              SizedBox(height: kCameraTaskToViewfinder * scale),
              SizedBox(
                key: kViewfinderKey,
                width: viewfinderWidth,
                height: viewfinderWidth / kCaptureAspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kViewfinderRadius * scale),
                  child: _trouble == null
                      ? ColoredBox(
                          color: tokens.surface,
                          child: _ready
                              ? _session.preview(context)
                              : const SizedBox.expand(),
                        )
                      : _troubleBox(tokens, theme, scale),
                ),
              ),
              SizedBox(height: kViewfinderToControls * scale),
              if (_trouble == null) _controls(tokens, theme, scale),
              const Spacer(),
              SondrAction(
                label: 'skip',
                supporting: true,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// No viewfinder: say why, and offer the one thing that fixes it.
  Widget _troubleBox(GreyscaleTokens tokens, ThemeData theme, double scale) {
    return ColoredBox(
      color: tokens.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _trouble == CameraTrouble.denied
                  ? 'Camera access is off.'
                  : 'No camera on this device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            ),
            if (_trouble == CameraTrouble.denied &&
                widget.onOpenSettings != null)
              SondrAction(
                label: 'Open Settings',
                onPressed: widget.onOpenSettings,
              ),
          ],
        ),
      ),
    );
  }

  /// flash · shutter · flip, the two words vertically centred on the ring.
  Widget _controls(GreyscaleTokens tokens, ThemeData theme, double scale) {
    final wordStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: kCameraControlSize * scale,
      color: tokens.textSecondary,
    );

    Widget word(String label, VoidCallback? onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        // A word is not a tap target; this is.
        constraints: BoxConstraints(
          minWidth: kCameraTapTarget * scale,
          minHeight: kCameraTapTarget * scale,
        ),
        child: Center(child: Text(label, style: wordStyle)),
      ),
    );

    return SizedBox(
      height: kShutterSize * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: kShutterSize * scale,
            child: _session.hasFlash
                ? word(_flash.label, _busy ? null : _cycleFlash)
                : const SizedBox.shrink(),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : _shoot,
            child: ProgressRing(
              key: kShutterKey,
              size: kShutterSize * scale,
              stroke: ringStroke(scale),
              progress: widget.ringProgress,
            ),
          ),
          SizedBox(
            width: kShutterSize * scale,
            child: _session.canFlip
                ? word('flip', _busy ? null : _flip)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
