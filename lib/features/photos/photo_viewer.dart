import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/sondr_action.dart';
import 'delete_photo.dart';
import 'models/photo.dart';
import 'photo_viewer_text.dart';

/// Open the viewer on [photos], starting at [index]. A full-screen modal
/// route that fades in; the page beneath stays put behind the scrim.
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<Photo> photos,
  required int index,
}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: kPhotoViewerFade,
      reverseTransitionDuration: kPhotoViewerFade,
      pageBuilder: (_, _, _) => PhotoViewer(
        photos: photos,
        index: index.clamp(0, photos.length - 1),
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

const Duration kPhotoViewerFade = Duration(milliseconds: 180);

/// The photo, large, with what it is: the task and the session it came
/// from, when it was taken and where the task stood, and — for a crossing
/// photo — the milestone it marks. Swipe sideways through the set; tap,
/// swipe down, or Close to leave. Delete asks first, then takes the photo
/// out of everything it is in ([deletePhotoEverywhere]) and moves on to
/// the next one, or leaves when it was the last.
///
/// No AppBar, no Material buttons: a dark scrim, the photo at 3:4 inset 18
/// with an 18 radius, centred in the space above the text, and the app's
/// own actions beneath. Greyscale only (see DESIGN.md).
class PhotoViewer extends ConsumerStatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.index,
  });

  final List<Photo> photos;
  final int index;

  @override
  ConsumerState<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<PhotoViewer> {
  late final List<Photo> _photos = List.of(widget.photos);
  late int _index = widget.index;
  late final PageController _pages = PageController(initialPage: _index);
  bool _deleting = false;

  static const double _inset = 18;
  static const double _radius = 18;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmNeighbours());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The pages either side, decoded before they are swiped to.
  void _warmNeighbours() {
    if (!mounted) return;
    precachePhotos(context, [
      if (_index > 0) _photos[_index - 1].photoUrl,
      if (_index < _photos.length - 1) _photos[_index + 1].photoUrl,
    ]);
  }

  void _onPage(int i) {
    setState(() => _index = i);
    _warmNeighbours();
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _delete() async {
    if (_deleting) return;
    final photo = _photos[_index];
    // Busy only once the prompt has been answered: a photo being deleted,
    // not a question being asked.
    final gone = await confirmDeletePhoto(
      context,
      ref,
      photo,
      onDeleting: () => setState(() => _deleting = true),
    );
    if (!mounted) return;
    if (!gone) {
      if (_deleting) setState(() => _deleting = false);
      return;
    }
    if (_photos.length == 1) {
      // The last one: leave, still "Deleting…" through the fade. The set is
      // not emptied — there is no frame to build from nothing.
      _close();
      return;
    }
    _photos.removeAt(_index);
    // The next photo in the set, or the new last one.
    final next = _index.clamp(0, _photos.length - 1);
    setState(() {
      _index = next;
      _deleting = false;
    });
    _pages.jumpToPage(next);
    _warmNeighbours();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final photo = _photos[_index];
    String time(DateTime when) => MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(when));
    final line3 = viewerLine3(photo);
    final counter = viewerCounter(_index, _photos.length);

    TextStyle? style(double size, Color color, [FontWeight? weight]) =>
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: size * scale,
          fontWeight: weight,
          color: color,
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      // Swipe down to leave; a sideways swipe belongs to the pages.
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! > 300) _close();
      },
      child: ColoredBox(
        color: tokens.background.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _inset * scale),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_radius * scale),
                        child: PageView.builder(
                          controller: _pages,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: _onPage,
                          itemCount: _photos.length,
                          itemBuilder: (_, i) => SondrPhoto(
                            key: ValueKey(_photos[i].id),
                            url: _photos[i].photoUrl,
                            // Full colour: a close look, meant to be enjoyed.
                            saturation: null,
                            placeholder: (_) => ColoredBox(color: tokens.surface),
                            error: (_) => ColoredBox(color: tokens.ringTrack),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12 * scale),
              Text(
                viewerLine1(photo),
                textAlign: TextAlign.center,
                style: style(14, tokens.textPrimary, FontWeight.w700),
              ),
              SizedBox(height: 4 * scale),
              Text(
                viewerLine2(photo, time: time),
                textAlign: TextAlign.center,
                style: style(12, tokens.textSecondary),
              ),
              if (line3 != null) ...[
                SizedBox(height: 4 * scale),
                Text(
                  line3,
                  textAlign: TextAlign.center,
                  style: style(11, tokens.textTertiary),
                ),
              ],
              if (counter != null) ...[
                SizedBox(height: 4 * scale),
                Text(
                  counter,
                  textAlign: TextAlign.center,
                  style: style(11, tokens.textTertiary),
                ),
              ],
              SizedBox(height: 32 * scale),
              SondrAction(label: 'Close', supporting: true, onPressed: _close),
              SizedBox(height: 12 * scale),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _deleting ? null : _delete,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24 * scale,
                    vertical: 4 * scale,
                  ),
                  child: Text(
                    _deleting ? 'Deleting…' : 'Delete',
                    style: style(15, tokens.textTertiary),
                  ),
                ),
              ),
              SizedBox(height: 24 * scale),
            ],
          ),
        ),
      ),
    );
  }
}
