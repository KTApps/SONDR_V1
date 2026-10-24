import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The brand is lowercase: "sondr", everywhere a user can read it.
///
/// Four places say it and they are in four different languages — a plist key,
/// a MaterialApp title, a Flutter wordmark and two pieces of share copy — so
/// there is no single definition to point at and nothing stopping one of them
/// drifting back to a capital on its own.
void main() {
  test('the home-screen label is lowercase', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    expect(match, isNotNull, reason: 'CFBundleDisplayName is missing');
    expect(match!.group(1), 'sondr');
  });

  test('the splash wordmark is lowercase', () {
    // The splash widget is private to boot_gate, and making it public to read
    // one string would be a worse trade than reading the string.
    final src = File('lib/features/splash/boot_gate.dart').readAsStringSync();
    expect(src, contains("'sondr',"));
    expect(src.contains("'Sondr',"), isFalse);
  });

  test('the app title is lowercase', () {
    final src = File('lib/app.dart').readAsStringSync();
    expect(src, contains("title: 'sondr',"));
  });

  test('the share copy is lowercase', () {
    // The sentence moved out of the Friends screen when the invite started
    // carrying the sender's own link; the heading above the button did not.
    final link = File(
      'lib/features/links/invite_link.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/friends/friends_screen.dart',
    ).readAsStringSync();
    expect(link, contains("'Join me on sondr: "));
    expect(screen, contains("'Invite your friends to sondr'"));
    for (final src in [link, screen]) {
      expect(src.contains('on Sondr'), isFalse);
      expect(src.contains('to Sondr'), isFalse);
    }
  });
}
