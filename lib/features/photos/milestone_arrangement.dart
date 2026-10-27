import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../feed/collage_layout.dart';
import 'models/photo.dart';

/// What a person arranges before a milestone is shared: which of the
/// band's photos go in, in what order, and how each is framed in its
/// tile. Pure, so the rules — the default, the nine, the swap, the
/// framing's range — are tested without a screen.

/// One photo on offer: the new shot, or one of the band's earlier ones.
@immutable
class ArrangeEntry {
  const ArrangeEntry({
    required this.id,
    required this.image,
    this.photo,
    this.shot,
  });

  /// The photo's id — [Photo.id], or [newShotId] for the one just taken.
  final String id;

  /// How it is drawn.
  final ImageProvider image;

  /// The band photo, or null for the new shot.
  final Photo? photo;

  /// The new shot's bytes, or null for a band photo.
  final Uint8List? shot;

  bool get isNew => photo == null;

  /// The id the new shot goes by until it is saved.
  static const String newShotId = 'new-shot';
}

/// The arrangement: the chosen photos in collage order, and each one's
/// framing. Immutable; every change is a new arrangement.
@immutable
class Arrangement {
  const Arrangement({this.order = const [], this.framings = const {}});

  /// Today's review default: the new photo, and nothing else — the band's
  /// earlier photos wait to be chosen. With no new photo, nothing: the
  /// no-photo milestone until something is tapped in.
  factory Arrangement.initial(List<ArrangeEntry> entries) => Arrangement(
    order: [for (final e in entries) if (e.isNew) e.id],
  );

  /// Ids in collage order — the order on screen, the order in the post.
  final List<String> order;

  /// Framing by id, for the photos whose framing has been set.
  final Map<String, PhotoFraming> framings;

  bool contains(String id) => order.contains(id);

  /// 1-based collage position of [id], or null when it is not chosen.
  int? positionOf(String id) {
    final i = order.indexOf(id);
    return i < 0 ? null : i + 1;
  }

  PhotoFraming framingOf(String id) => framings[id] ?? PhotoFraming.none;

  bool get isFull => order.length >= kCollageMax;

  /// [id] chosen or unchosen. A tenth is refused: null says so, and the
  /// screen says "Up to 9 photos".
  Arrangement? toggled(String id) {
    if (contains(id)) {
      return Arrangement(
        order: [for (final o in order) if (o != id) o],
        framings: {...framings}..remove(id),
      );
    }
    if (isFull) return null;
    return Arrangement(order: [...order, id], framings: framings);
  }

  /// The photos at collage positions [a] and [b] exchanged.
  Arrangement swapped(int a, int b) {
    if (a == b || a < 0 || b < 0 || a >= order.length || b >= order.length) {
      return this;
    }
    final next = [...order];
    next[a] = order[b];
    next[b] = order[a];
    return Arrangement(order: next, framings: framings);
  }

  /// [id] framed as [framing], kept to the range.
  Arrangement framed(String id, PhotoFraming framing) => Arrangement(
    order: order,
    framings: {...framings, id: framing.clamped()},
  );

  /// The chosen entries in collage order, with their framings alongside.
  List<ArrangeEntry> chosen(List<ArrangeEntry> entries) => [
    for (final id in order) entries.firstWhere((e) => e.id == id),
  ];

  List<PhotoFraming> framingsInOrder() => [for (final id in order) framingOf(id)];

  @override
  bool operator ==(Object other) =>
      other is Arrangement &&
      listEquals(other.order, order) &&
      mapEquals(other.framings, framings);

  @override
  int get hashCode => Object.hash(Object.hashAll(order), Object.hashAll(framings.entries));
}
