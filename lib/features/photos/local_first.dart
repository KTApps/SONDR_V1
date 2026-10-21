import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Answer from the local cache first, then check the server behind the
/// answer and re-answer only if it differs.
///
/// Firestore's persistence is on (the default on iOS), so a read from
/// [Source.cache] returns at once with whatever the last launch saw — which
/// is what a cold start should paint. A default `get()` waits for the server
/// whenever the network is up, and that wait is what put the photos a moment
/// behind the rest of Profile. When the cache has nothing (a first launch,
/// a fresh account) the server is asked outright, so nothing is ever shown
/// as empty that the server could have filled.
///
/// The server is still consulted, unawaited, after every cached answer. If
/// it disagrees — by [same] — the provider is invalidated and re-runs: the
/// cache now holds what the server said, so the re-run answers from it and
/// its own background check finds nothing to change.
Future<T> localFirst<T>(
  Ref ref, {
  required Future<T> Function(Source source) read,
  required bool Function(T) isEmpty,
  required bool Function(T a, T b) same,
}) async {
  T cached;
  try {
    cached = await read(Source.cache);
  } catch (_) {
    return read(Source.serverAndCache);
  }
  if (isEmpty(cached)) return read(Source.serverAndCache);
  unawaited(
    read(Source.server).then((fresh) {
      if (!same(fresh, cached)) ref.invalidateSelf();
    }).catchError((Object e) {
      debugPrint('SONDR local-first refresh error: $e');
    }),
  );
  return cached;
}

/// Equal as lists of ids, in order.
bool sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
