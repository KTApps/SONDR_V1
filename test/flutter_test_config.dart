import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real typeface for every test in the suite.
///
/// Without this the tests render in Flutter's built-in test font, whose glyphs
/// are square: each character advances exactly `fontSize`, so every string
/// measures about twice its real width. Line HEIGHTS matched already — every
/// style in AppTypography sets `height` explicitly, which overrides the font's
/// own metrics — but the width did not, and the two stat labels wrapped to a
/// second line in tests that they never wrap on device. That pushed everything
/// below the stats row 17pt down the page, and the gap assertions were
/// re-baselined to the wrapped layout: a harness measuring a page no device
/// ever renders.
///
/// Inter is a bundled asset, not the iOS system font, so the file the app
/// ships is the file loaded here.
///
/// This runs ONCE per test file, around `main`, which is the only place the
/// read can happen: inside `testWidgets` the binding's fake async never
/// completes real file I/O and the test hangs until the 10-minute timeout.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
  await testMain();
}
