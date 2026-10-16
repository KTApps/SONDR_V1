import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/ring/ring_metrics.dart';
import '../../shared/sondr_action.dart';
import 'capture_crop.dart';
import 'open_app_settings.dart';

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

/// Between the shutter's edge and the nearest edge of a control's word.
///
/// Measured from the SHUTTER, not from the screen. Anchored to the screen
/// the two words sat 105 from the ring and a thumb had to leave the control
/// it was using to reach the next one; they belong to the shutter, so they
/// are placed against it.
const double kCameraControlGap = 32;

/// What the flash is set to. The app's own, so the screen does not have to
/// speak the camera package's language — and `torch` is deliberately absent:
/// three states to cycle, not four.
enum CaptureFlash { off, on, auto }

extension on CaptureFlash {
  String get label => switch (this) {
    CaptureFlash.off => 'Flash off',
    CaptureFlash.on => 'Flash on',
    CaptureFlash.auto => 'Flash auto',
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
        // 1920x1080 on iOS, which is the one preset that lands exactly on
        // what is stored: a portrait frame is 1080 wide, and the 3:4 crop of
        // it is 1080x1440 with nothing resampled. `high` would be 1280x720
        // and upscale; `max` would decode a 12-megapixel frame to throw most
        // of it away, on the one screen where someone is waiting.
        ResolutionPreset.veryHigh,
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

  /// Injected by tests; [openAppSettings] otherwise.
  final Future<void> Function()? onOpenSettings;

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
    // Off the UI thread: this screen is showing a live preview and must not
    // stutter while the photo it just took is being cropped.
    final shot = await cropToCaptureShapeAsync(raw, mirror: _session.isFront);
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
                label: 'Skip',
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
            if (_trouble == CameraTrouble.denied)
              SondrAction(
                label: 'Open Settings',
                onPressed: () =>
                    (widget.onOpenSettings ?? openAppSettings)(),
              ),
          ],
        ),
      ),
    );
  }

  /// flash · shutter · flip, the two words anchored to the ring.
  ///
  /// Two equal Expanded slots either side of the shutter, so the ring is
  /// dead centre however wide the words get — "flash auto" is half again as
  /// wide as "flash on", and a centred Row of three real widths would have
  /// shunted the shutter sideways every time the flash was cycled.
  ///
  /// Not a Stack with the words hung outside it: that renders them and then
  /// refuses to hit-test them, because a Stack does not pass a pointer to a
  /// child beyond its own bounds.
  Widget _controls(GreyscaleTokens tokens, ThemeData theme, double scale) {
    final shutter = kShutterSize * scale;
    final gap = kCameraControlGap * scale;
    final wordStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: kCameraControlSize * scale,
      color: tokens.textSecondary,
    );

    /// The word, in a tap target that grows AWAY from the shutter: the edge
    /// facing the ring is the word's own, so the gap is measured to the text
    /// and the 44 is found outward, where there is nothing to crowd.
    Widget word(String label, Alignment edge, VoidCallback? onTap) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: kCameraTapTarget * scale,
              minHeight: kCameraTapTarget * scale,
            ),
            child: Align(alignment: edge, child: Text(label, style: wordStyle)),
          ),
        );

    /// One side of the ring: the word pinned against the gap, the rest of
    /// the slot empty.
    Widget side(Alignment edge, EdgeInsets inset, Widget? child) => Expanded(
      child: child == null
          ? const SizedBox.shrink()
          : Align(
              alignment: edge,
              child: Padding(padding: inset, child: child),
            ),
    );

    return SizedBox(
      height: shutter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          side(
            Alignment.centerRight,
            EdgeInsets.only(right: gap),
            _session.hasFlash
                ? word(
                    _flash.label,
                    Alignment.centerRight,
                    _busy ? null : _cycleFlash,
                  )
                : null,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : _shoot,
            child: ProgressRing(
              key: kShutterKey,
              size: shutter,
              stroke: ringStroke(scale),
              progress: widget.ringProgress,
            ),
          ),
          side(
            Alignment.centerLeft,
            EdgeInsets.only(left: gap),
            _session.canFlip
                ? word('Flip', Alignment.centerLeft, _busy ? null : _flip)
                : null,
          ),
        ],
      ),
    );
  }
}
