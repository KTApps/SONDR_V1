import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/links/invite_link.dart';
import 'package:sondr/features/links/invite_link_listener.dart';
import 'package:sondr/features/profile/other_profile_screen.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/features/timer/home_notice.dart';

/// Following an invite link.
///
/// The link is the only part of the app a stranger can aim, so the parsing
/// is pure and tested on its own, and the routing is tested with the
/// lookup behind a seam.

class _Lookup implements HandleLookup {
  _Lookup(this.uids, {this.throws = false});

  final Map<String, String> uids;
  final bool throws;
  final List<String> asked = [];

  @override
  Future<String?> uidFor(String handle) async {
    asked.add(handle);
    if (throws) throw StateError('no network');
    return uids[handle];
  }
}

/// Both sources, driven by the test. [initial] is what the plugin would
/// report as the link that launched the process.
class _Source implements IncomingLinks {
  _Source(this.live, {this.launchedWith});

  final Stream<Uri> live;
  final Uri? launchedWith;
  int initialAsked = 0;

  @override
  Future<Uri?> initial() async {
    initialAsked++;
    return launchedWith;
  }

  @override
  Stream<Uri> stream() => live;
}

/// Outlives a launch, as the real one does.
class _LastLaunch implements LastLaunchLink {
  _LastLaunch([this.held]);

  String? held;

  @override
  Future<String?> read() async => held;

  @override
  Future<void> write(String link) async => held = link;
}

class _Inviter implements PendingInviter {
  String? held;

  @override
  Future<String?> read() async => held;

  @override
  Future<void> remember(String handle) async => held = handle;

  @override
  Future<void> clear() async => held = null;
}

void main() {
  group('what a link names', () {
    test('an invite link gives up its handle', () {
      expect(inviteHandleFrom(Uri.parse('https://s-ndr.com/u/tanaka')),
          'tanaka');
      expect(inviteHandleFrom(Uri.parse('https://www.s-ndr.com/u/tanaka')),
          'tanaka');
      // Upper case is a handle shouted, not a different handle.
      expect(inviteHandleFrom(Uri.parse('https://s-ndr.com/u/TANAKA')),
          'tanaka');
      expect(inviteHandleFrom(Uri.parse('https://s-ndr.com/u/a_b_1')), 'a_b_1');
    });

    test('and everything else names nothing', () {
      for (final url in [
        // Not ours.
        'https://example.com/u/tanaka',
        'https://s-ndr.com.evil.test/u/tanaka',
        'http://s-ndr.com/u/tanaka',
        // Ours, but not an invite.
        'https://s-ndr.com/',
        'https://s-ndr.com/privacy',
        'https://s-ndr.com/u',
        'https://s-ndr.com/u/',
        'https://s-ndr.com/u/tanaka/extra',
        // An invite, but not a handle.
        'https://s-ndr.com/u/ab',
        'https://s-ndr.com/u/${'x' * 21}',
        'https://s-ndr.com/u/with%20space',
        'https://s-ndr.com/u/no-hyphens',
        'https://s-ndr.com/u/<script>',
        // The Lock Screen card's own link, which arrives here too.
        'sondr://stop',
      ]) {
        expect(inviteHandleFrom(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('where an invitation points, and what it says', () {
      expect(inviteUrlFor('tanaka'), 'https://s-ndr.com/u/tanaka');
      expect(inviteText('tanaka'), 'Join me on sondr: https://s-ndr.com/u/tanaka');
      // No handle, nobody to credit: the site itself.
      expect(inviteUrlFor(''), 'https://s-ndr.com');
      expect(inviteText(''), 'Join me on sondr: https://s-ndr.com');
    });

    test('a link round-trips through the parser', () {
      expect(inviteHandleFrom(Uri.parse(inviteUrlFor('tanaka'))), 'tanaka');
    });

    /// app_links observes every URL the app receives, including the Lock
    /// Screen card's own. It never claims one — its handler returns false
    /// by default, so Flutter's scene delegate carries on down the chain
    /// to SessionActivityChannel — but it does report them to Dart, and
    /// this is the line that keeps them from being acted on twice.
    ///
    /// Derived from the Swift the widget actually uses, so a fifth card
    /// URL is covered the day it is added.
    test("the Live Activity's own links are not invites", () {
      final swift = File(
        'ios/SondrWidgets/SondrSessionActivity.swift',
      ).readAsStringSync();
      final urls = RegExp(r'sondr://[a-z]+')
          .allMatches(swift)
          .map((m) => m.group(0)!)
          .toSet();
      expect(
        urls,
        {'sondr://home', 'sondr://stop', 'sondr://pause', 'sondr://resume'},
        reason: 'the card speaks a URL this test has not seen',
      );
      for (final url in urls) {
        expect(inviteHandleFrom(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  group('where a link goes', () {
    late StreamController<Uri> links;
    late _Lookup lookup;
    late _Inviter inviter;
    late _Source source;
    late _LastLaunch lastLaunched;
    late ProviderContainer container;

    setUp(() {
      links = StreamController<Uri>.broadcast();
      lookup = _Lookup({'cass': 'uid_cass', 'tanaka': 'uid_me'});
      inviter = _Inviter();
    });

    tearDown(() => links.close());

    /// The shell, with the listener around it exactly as the boot gate
    /// arranges them. [cold] delivers the link before the first frame, the
    /// way a link that launched the app does.
    Future<void> pump(
      WidgetTester tester, {
      Uri? cold,
      String myHandle = 'tanaka',
      bool guest = false,
      _LastLaunch? lastLaunch,
    }) async {
      source = _Source(links.stream, launchedWith: cold);
      lastLaunched = lastLaunch ?? _LastLaunch();
      // A launch is a fresh tree: without this the second pump updates the
      // first one in place and keeps its navigator stack, so a route
      // pushed by the previous launch would still be standing.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(guest ? 'uid_guest' : 'uid_me'),
            isGuestProvider.overrideWithValue(guest),
            handleLookupProvider.overrideWithValue(lookup),
            pendingInviterProvider.overrideWithValue(inviter),
            currentProfileProvider.overrideWith(
              (ref) async => myHandle.isEmpty
                  ? null
                  : Profile(
                      uid: 'uid_me',
                      username: myHandle,
                      displayName: 'Me',
                    ),
            ),
            incomingLinksSourceProvider.overrideWithValue(source),
            lastLaunchLinkProvider.overrideWithValue(lastLaunched),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const InviteLinkListener(child: _Shell());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester, String url) async {
      links.add(Uri.parse(url));
      await tester.pumpAndSettle();
    }

    testWidgets('somebody else: their profile, warm', (tester) async {
      await pump(tester);
      await send(tester, 'https://s-ndr.com/u/cass');
      expect(find.byType(OtherProfileScreen), findsOneWidget);
      expect(lookup.asked, ['cass']);
    });

    testWidgets('somebody else: their profile, cold', (tester) async {
      await pump(tester, cold: Uri.parse('https://s-ndr.com/u/cass'));
      expect(find.byType(OtherProfileScreen), findsOneWidget);
    });

    testWidgets('the same launch link, a second launch, does nothing', (
      tester,
    ) async {
      final remembered = _LastLaunch();
      // First launch: the link opens the profile and is remembered.
      await pump(
        tester,
        cold: Uri.parse('https://s-ndr.com/u/cass'),
        lastLaunch: remembered,
      );
      expect(find.byType(OtherProfileScreen), findsOneWidget);
      expect(remembered.held, 'https://s-ndr.com/u/cass');

      // Second launch, same restored activity, nothing tapped. This is the
      // bug: a launch from the Home Screen used to land on the inviter's
      // profile.
      await pump(
        tester,
        cold: Uri.parse('https://s-ndr.com/u/cass'),
        lastLaunch: remembered,
      );
      expect(
        find.byType(OtherProfileScreen),
        findsNothing,
        reason: 'a normal launch replayed the last link',
      );
      expect(container.read(homeNoticeProvider), isNull);
    });

    testWidgets('a different launch link still routes', (tester) async {
      final remembered = _LastLaunch('https://s-ndr.com/u/cass');
      await pump(
        tester,
        cold: Uri.parse('https://s-ndr.com/u/tanaka2'),
        lastLaunch: remembered,
      );
      // tanaka2 is not in the lookup, so the line goes up — which is proof
      // the link was acted on rather than skipped.
      expect(container.read(homeNoticeProvider), kHandleNotFound);
      expect(remembered.held, 'https://s-ndr.com/u/tanaka2');
    });

    testWidgets('a live link routes even when it is the remembered one', (
      tester,
    ) async {
      final remembered = _LastLaunch('https://s-ndr.com/u/cass');
      await pump(tester, lastLaunch: remembered);
      // Nothing on launch...
      expect(find.byType(OtherProfileScreen), findsNothing);
      // ...and tapping that very link still works, because somebody just
      // tapped it.
      await send(tester, 'https://s-ndr.com/u/cass');
      expect(find.byType(OtherProfileScreen), findsOneWidget);
    });

    testWidgets('no link at all lands on Home', (tester) async {
      await pump(tester);
      expect(find.byType(OtherProfileScreen), findsNothing);
      expect(container.read(homeNoticeProvider), isNull);
      expect(container.read(selectedTabProvider), 0);
      expect(lastLaunched.held, isNull);
    });

    testWidgets("the card's own links never spend the launch slot", (
      tester,
    ) async {
      // A cold start from a Lock Screen tap: app_links reports sondr://stop
      // as the launch link, and it is not ours to remember.
      await pump(tester, cold: Uri.parse('sondr://stop'));
      expect(lastLaunched.held, isNull);
      expect(find.byType(OtherProfileScreen), findsNothing);
    });

    testWidgets('the launch link is asked for once', (tester) async {
      await pump(tester, cold: Uri.parse('https://s-ndr.com/u/cass'));
      await tester.pumpAndSettle();
      expect(source.initialAsked, 1);
    });

    testWidgets('my own handle: the Profile tab, no push', (tester) async {
      await pump(tester, myHandle: 'tanaka');
      await send(tester, 'https://s-ndr.com/u/tanaka');
      expect(find.byType(OtherProfileScreen), findsNothing);
      expect(container.read(selectedTabProvider), kProfileTabIndex);
      // Not even looked up: we know our own handle.
      expect(lookup.asked, isEmpty);
    });

    testWidgets('my own uid under a handle I have not loaded', (tester) async {
      // The profile has not arrived yet, so the handle is resolved — and
      // comes back as us.
      lookup = _Lookup({'tanaka': 'uid_me'});
      await pump(tester, myHandle: '');
      await send(tester, 'https://s-ndr.com/u/tanaka');
      expect(find.byType(OtherProfileScreen), findsNothing);
      expect(container.read(selectedTabProvider), kProfileTabIndex);
    });

    testWidgets('a handle nobody holds: the line on Home', (tester) async {
      await pump(tester);
      await send(tester, 'https://s-ndr.com/u/ghost');
      expect(find.byType(OtherProfileScreen), findsNothing);
      expect(container.read(homeNoticeProvider), kHandleNotFound);
      expect(kHandleNotFound, "Couldn't find that account.");
    });

    testWidgets('a lookup that fails says the same thing', (tester) async {
      lookup = _Lookup(const {}, throws: true);
      await pump(tester);
      await send(tester, 'https://s-ndr.com/u/cass');
      expect(container.read(homeNoticeProvider), kHandleNotFound);
    });

    testWidgets('a malformed link does nothing at all', (tester) async {
      await pump(tester);
      for (final url in [
        'https://s-ndr.com/u/ab',
        'https://example.com/u/cass',
        // Every link the Lock Screen card sends, which app_links reports
        // to Dart as well as to the channel that acts on it.
        'sondr://stop',
        'sondr://pause',
        'sondr://resume',
        'sondr://home',
        'https://s-ndr.com/privacy',
      ]) {
        await send(tester, url);
      }
      expect(find.byType(OtherProfileScreen), findsNothing);
      expect(container.read(homeNoticeProvider), isNull);
      expect(lookup.asked, isEmpty);
      expect(inviter.held, isNull);
    });

    testWidgets('a guest is remembered, and still sees the profile', (
      tester,
    ) async {
      await pump(tester, guest: true, myHandle: '');
      await send(tester, 'https://s-ndr.com/u/cass');
      expect(inviter.held, 'cass');
      // A guest reads publicProfiles like anyone signed in, so the page is
      // the stranger's view of it — the same one an account without a
      // friendship sees.
      expect(find.byType(OtherProfileScreen), findsOneWidget);
    });

    testWidgets('an account is not remembered as invited', (tester) async {
      await pump(tester, guest: false);
      await send(tester, 'https://s-ndr.com/u/cass');
      expect(inviter.held, isNull);
    });

    testWidgets('two links in a row open one profile', (tester) async {
      await pump(tester);
      links.add(Uri.parse('https://s-ndr.com/u/cass'));
      links.add(Uri.parse('https://s-ndr.com/u/cass'));
      await tester.pumpAndSettle();
      expect(find.byType(OtherProfileScreen), findsOneWidget);
    });
  });
}

/// Stands in for MainShell: the real one builds three tabs and the Firebase
/// each of them wants. What matters here is that something is under the
/// listener, that the tab index is the shell's own, and that the profile is
/// being watched — the real shell's Profile tab watches it, which is what
/// lets a link recognise your own handle without a lookup.
class _Shell extends ConsumerWidget {
  const _Shell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentProfileProvider);
    final tab = ref.watch(selectedTabProvider);
    return Scaffold(body: Center(child: Text('tab $tab')));
  }
}
