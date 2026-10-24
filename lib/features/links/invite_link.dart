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

/// Where links come from, as a seam.
///
/// The two sources are not the same thing and must not be merged: one is
/// "the link this process was launched with", which iOS can hand over
/// again on a later launch, and the other is "a link that just arrived",
/// which is always somebody tapping something now.
abstract interface class IncomingLinks {
  /// The link that launched this process, if any.
  Future<Uri?> initial();

  /// Links arriving while the app runs.
  Stream<Uri> stream();
}

class PluginIncomingLinks implements IncomingLinks {
  final AppLinks _links = AppLinks();

  @override
  Future<Uri?> initial() => _links.getInitialLink();

  @override
  Stream<Uri> stream() => _links.uriLinkStream;
}

final incomingLinksSourceProvider = Provider<IncomingLinks>(
  (ref) => PluginIncomingLinks(),
);

/// The link this launch should act on, or null.
///
/// iOS keeps a scene session when an app is swiped away and can hand its
/// browsing activity back on the next launch, and the plugin cannot tell
/// that from a fresh tap — which is how a normal launch from the Home
/// Screen opened somebody's profile. So a launch link is acted on once,
/// ever: the value is remembered, and an identical one next time is
/// nothing.
///
/// Kept alive for the life of the app. A provider that can be disposed and
/// re-created would ask the plugin again mid-process and get the same link
/// a second time.
final launchLinkProvider = FutureProvider<Uri?>((ref) async {
  ref.keepAlive();
  final first = await ref.read(incomingLinksSourceProvider).initial();
  // Only ours is worth remembering. The Lock Screen card's own sondr://
  // links arrive here too, and must not spend the one slot.
  if (first == null || inviteHandleFrom(first) == null) return null;

  final store = ref.read(lastLaunchLinkProvider);
  if (await store.read() == first.toString()) return null;
  await store.write(first.toString());
  return first;
});

/// Links that arrive while the app is running.
///
/// Always acted on, including one identical to the last: tapping the same
/// invite twice is somebody asking twice.
final liveLinksProvider = StreamProvider<Uri>((ref) {
  ref.keepAlive();
  return ref.read(incomingLinksSourceProvider).stream();
});

/// The launch link already acted on, so it is not acted on again.
abstract interface class LastLaunchLink {
  Future<String?> read();
  Future<void> write(String link);
}

class PrefsLastLaunchLink implements LastLaunchLink {
  PrefsLastLaunchLink({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(
              suiteName: kSessionAppGroup,
            ),
          );

  static const String key = 'sondr.lastLaunchLink';

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read() async {
    try {
      return await _prefs.getString(key);
    } catch (e) {
      debugPrint('SONDR last launch link read error: ${e.runtimeType}');
      // Unreadable means unknown, and unknown must not replay a link: the
      // launch is treated as one that has already been acted on.
      return null;
    }
  }

  @override
  Future<void> write(String link) async {
    try {
      await _prefs.setString(key, link);
    } catch (e) {
      debugPrint('SONDR last launch link write error: ${e.runtimeType}');
    }
  }
}

final lastLaunchLinkProvider = Provider<LastLaunchLink>(
  (ref) => PrefsLastLaunchLink(),
);

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
