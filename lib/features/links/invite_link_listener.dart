import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../auth/profile_repository.dart';
import '../profile/other_profile_screen.dart';
import '../shell/main_shell.dart';
import '../timer/home_notice.dart';
import 'invite_link.dart';

/// What the app says when a link names a handle nobody holds.
const String kHandleNotFound = "Couldn't find that account.";

/// Turning an invite link into a handle's uid.
///
/// A seam, because the lookup is one Firestore read and the routing around
/// it is the part worth testing.
abstract interface class HandleLookup {
  /// The uid behind [handle], or null when nobody holds it.
  Future<String?> uidFor(String handle);
}

class FirestoreHandleLookup implements HandleLookup {
  FirestoreHandleLookup(this.db);

  final FirebaseFirestore db;

  @override
  Future<String?> uidFor(String handle) async {
    final doc = await db.collection('usernames').doc(handle).get();
    return doc.data()?['uid'] as String?;
  }
}

final handleLookupProvider = Provider<HandleLookup?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return FirestoreHandleLookup(FirebaseFirestore.instance);
});

/// Where an invite link goes, once the app is on its feet.
///
/// Wraps the shell rather than living in it, so it exists only after the
/// splash has lifted: a link that arrives on a cold start has a navigator
/// to push onto by the time this is listening.
///
/// Three endings, and the first of them is the common one:
///
/// * **Somebody else's handle** — their profile, the ordinary one, with
///   every rule that already applies to it. A guest sees what a stranger
///   sees: the handle, the hours, and the line saying to add each other.
/// * **Your own handle** — the Profile tab. Pushing your own profile as if
///   it were somebody else's is the sort of thing that makes an app feel
///   broken.
/// * **A handle nobody holds** — the transient line on Home, which is
///   where a person who just followed a dead link is standing.
///
/// A guest is also remembered: the handle is kept locally so that if they
/// go on to make an account, the question "who invited you?" already knows
/// the answer.
class InviteLinkListener extends ConsumerStatefulWidget {
  const InviteLinkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InviteLinkListener> createState() =>
      _InviteLinkListenerState();
}

class _InviteLinkListenerState extends ConsumerState<InviteLinkListener> {
  /// One link at a time: two profiles stacked by a double-tapped link is
  /// nobody's intention.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The launch link, asked for ONCE. Awaited rather than listened to, so
    // a rebuild cannot act on it twice, and after the frame so the
    // navigator is there to push onto.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final launched = await ref.read(launchLinkProvider.future);
      if (launched != null && mounted) await _open(launched);
    });
  }

  @override
  Widget build(BuildContext context) {
    // And everything that arrives while the app is running.
    ref.listen<AsyncValue<Uri>>(liveLinksProvider, (_, next) {
      final uri = next.value;
      if (uri != null) unawaited(_open(uri));
    });
    return widget.child;
  }

  Future<void> _open(Uri uri) async {
    final handle = inviteHandleFrom(uri);
    // Not ours. The custom-scheme links the Lock Screen card sends arrive
    // here too, and belong to somebody else.
    if (handle == null || _busy) return;
    _busy = true;
    try {
      // Before anything that can fail: an account made later is still
      // owed the question, even if the lookup below never answers.
      if (ref.read(isGuestProvider)) {
        await ref.read(pendingInviterProvider).remember(handle);
      }

      final mine = ref.read(currentProfileProvider).value?.username ?? '';
      if (mine.isNotEmpty && mine == handle) {
        if (!mounted) return;
        ref.read(selectedTabProvider.notifier).set(kProfileTabIndex);
        return;
      }

      final lookup = ref.read(handleLookupProvider);
      final uid = lookup == null ? null : await lookup.uidFor(handle);
      if (!mounted) return;

      if (uid == null) {
        ref.read(homeNoticeProvider.notifier).say(kHandleNotFound);
        return;
      }
      if (uid == ref.read(currentUidProvider)) {
        // Their handle, our uid: the profile we would push is our own.
        ref.read(selectedTabProvider.notifier).set(kProfileTabIndex);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OtherProfileScreen(uid: uid, handle: handle),
        ),
      );
    } catch (e) {
      debugPrint('SONDR invite link failed: ${e.runtimeType}');
      if (mounted) {
        ref.read(homeNoticeProvider.notifier).say(kHandleNotFound);
      }
    } finally {
      _busy = false;
    }
  }
}
