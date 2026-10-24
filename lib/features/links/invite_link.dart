import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../timer/session_store.dart' show kSessionAppGroup;

/// The one host the app answers for. `www` redirects to it and cannot
/// serve the association file, so only the root is claimed — see
/// site/.well-known/apple-app-site-association and the Associated Domains
/// entitlement, which must agree with both.
const String kSondrHost = 's-ndr.com';

/// The same rule the handle screen enforces and the usernames index is
/// keyed by. A link is not a reason to relax it.
final RegExp kHandleFormat = RegExp(r'^[a-z0-9_]{3,20}$');

/// The handle an invite link names, or null if the link is not one.
///
/// Pure, because this is the part that has to be right about every URL the
/// OS might hand over — including the ones meant for somebody else.
String? inviteHandleFrom(Uri uri) {
  if (uri.scheme != 'https') return null;
  if (uri.host != kSondrHost && uri.host != 'www.$kSondrHost') return null;
  final parts = uri.pathSegments;
  if (parts.length != 2 || parts.first != 'u') return null;
  final handle = parts[1].toLowerCase();
  return kHandleFormat.hasMatch(handle) ? handle : null;
}

/// Where an invitation points. Without a handle there is nobody to credit,
/// so it points at the site itself.
String inviteUrlFor(String handle) =>
    handle.isEmpty ? 'https://$kSondrHost' : 'https://$kSondrHost/u/$handle';

/// What the share sheet sends.
String inviteText(String handle) => 'Join me on sondr: ${inviteUrlFor(handle)}';

/// Links arriving from outside the app, cold and warm.
///
/// `getInitialLink` is the one that launched the app and `uriLinkStream` is
/// everything after it, so the two together are every link there is. A
/// provider so a test can push URIs without a platform channel.
final incomingLinksProvider = StreamProvider<Uri>((ref) async* {
  final links = AppLinks();
  final first = await links.getInitialLink();
  if (first != null) yield first;
  yield* links.uriLinkStream;
});

/// The handle of whoever invited this device, kept until the account that
/// arrives is asked about it.
///
/// Local and small, beside the session and the pending prunes: a link can
/// land on a phone with no account at all, and the question it answers is
/// asked minutes later, after a sign-up.
abstract interface class PendingInviter {
  Future<String?> read();
  Future<void> remember(String handle);
  Future<void> clear();
}

class PrefsPendingInviter implements PendingInviter {
  PrefsPendingInviter({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(
              suiteName: kSessionAppGroup,
            ),
          );

  static const String key = 'sondr.pendingInviter';

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read() async {
    try {
      final held = await _prefs.getString(key);
      return (held != null && kHandleFormat.hasMatch(held)) ? held : null;
    } catch (e) {
      debugPrint('SONDR pending inviter read error: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> remember(String handle) async {
    if (!kHandleFormat.hasMatch(handle)) return;
    try {
      await _prefs.setString(key, handle);
    } catch (e) {
      debugPrint('SONDR pending inviter write error: ${e.runtimeType}');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _prefs.remove(key);
    } catch (e) {
      debugPrint('SONDR pending inviter clear error: ${e.runtimeType}');
    }
  }
}

final pendingInviterProvider = Provider<PendingInviter>(
  (ref) => PrefsPendingInviter(),
);
