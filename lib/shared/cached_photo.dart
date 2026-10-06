import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'photo_tint.dart';

/// A cached [ImageProvider] for a Firebase Storage URL. Backed by
/// `cached_network_image`'s disk+memory cache, so an image isn't re-fetched on
/// every rebuild or surface re-entry — the root of the intermittent blank-tile
/// bug, where a flaky connection or an expired Storage token turned a re-render
/// into a failed request. Drop-in for `NetworkImage`.
ImageProvider cachedPhotoProvider(String url) =>
    CachedNetworkImageProvider(url);

/// The one cached-image widget behind the app's Storage photos (calendar,
/// day-detail thumbnails, collages, profile gallery). It's a plain [Image] fed
/// by [cachedPhotoProvider] — deliberately, so its layout, sizing and fit behave
/// exactly like the raw `Image.network` widgets it replaced (a `CachedNetworkImage`
/// widget lays out differently and wouldn't paint in the calendar's clipped-oval
/// fill slot). Caching comes from the provider, not the widget.
///
/// Centralising the fetch must not flatten the per-surface look, so each call
/// site keeps its own treatment, reapplied here in the frame builder just as the
/// old inline widgets did: an optional [saturation] + [tint] pair, plus its own
/// [placeholder] (shown until the first frame) and [error] fallbacks. Pass
/// `saturation: null` for a raw, untinted image.
///
/// Sizing/fit come from the surrounding slot — callers already wrap this in a
/// fixed box, grid cell or clipped disc — so [fit] fills those constraints. The
/// feed milestone card and the day-detail full-photo overlay compose their own
/// [Image] and use [cachedPhotoProvider] directly.
class SondrPhoto extends StatelessWidget {
  const SondrPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.saturation,
    this.tint,
    this.placeholder,
    this.error,
  });

  final String url;
  final BoxFit fit;

  /// Colour treatment reapplied on the decoded image. Null → rendered raw.
  final double? saturation;

  /// Flat colour painted over the image via `foregroundDecoration`, exactly as
  /// the old inline treatments did. Null → no tint.
  final Color? tint;

  /// Shown until the first frame decodes, and on a load failure. Each defaults
  /// to an empty box, so a site that wants "nothing" (ring/cell only) gets it.
  final WidgetBuilder? placeholder;
  final WidgetBuilder? error;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: cachedPhotoProvider(url),
      fit: fit,
      // Hold the last frame across rebuilds instead of flashing the placeholder.
      gaplessPlayback: true,
      errorBuilder: (ctx, _, _) => error?.call(ctx) ?? const SizedBox.shrink(),
      frameBuilder: (ctx, child, frame, _) {
        if (frame == null) {
          return placeholder?.call(ctx) ?? const SizedBox.shrink();
        }
        Widget img = child;
        if (saturation != null) {
          img = ColorFiltered(
            colorFilter: ColorFilter.matrix(saturationMatrix(saturation!)),
            child: img,
          );
        }
        if (tint != null) {
          img = Container(
            foregroundDecoration: BoxDecoration(color: tint),
            child: img,
          );
        }
        return img;
      },
    );
  }
}
