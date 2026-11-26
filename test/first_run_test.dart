import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/debug/debug_panel.dart';
import 'package:sondr/features/first_run/first_run.dart';
import 'package:sondr/features/first_run/first_run_screen.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/shell/how_it_works.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/features/splash/boot_gate.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/session_log.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/home_metrics.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/blur_sheet.dart';

/// Onboarding once per install, "What's new" once per build with notes,
/// both before Home and both pointing at the tab bar they leave behind.
void main() {
  const notes = {
    108: ['108 a'],
    110: ['110 a', '110 b'],
    111: ['111 a', '111 b', '111 c'],
  };

  group('the rule', () {
    test('a fresh install: onboarding, with this build stored as seen', () {
      final d = decideFirstRun(
        onboardingSeen: null,
        lastSeenBuild: null,
        currentBuild: 111,
        accountBeforeLaunch: false,
        notes: notes,
      );
      expect(d.view?.kind, FirstRunKind.onboarding);
      expect(d.view?.title, 'sondr');
      expect(d.onboardingSeen, isTrue);
      expect(d.lastSeenBuild, 111, reason: "so What's new does not follow it");
    });

    test('the next open after onboarding: nothing, not What\'s new', () {
      final d = decideFirstRun(
        onboardingSeen: true,
        lastSeenBuild: 111,
        currentBuild: 111,
        accountBeforeLaunch: true,
        notes: notes,
      );
      expect(d.view, isNull);
    });

    test('an existing user on their first 112 (no flags, an account already there): What\'s new, not onboarding', () {
      final d = decideFirstRun(
        onboardingSeen: null,
        lastSeenBuild: null,
        currentBuild: 112,
        accountBeforeLaunch: true,
        notes: kWhatsNewNotes,
      );
      expect(d.view?.kind, FirstRunKind.whatsNew);
      expect(d.view?.title, "What's new");
      expect(d.view?.lines, kWhatsNewNotes[112]);
      expect(d.onboardingSeen, isTrue);
      expect(d.lastSeenBuild, 112);
    });

    test('once per build: the same build again shows nothing', () {
      final again = decideFirstRun(
        onboardingSeen: true,
        lastSeenBuild: 111,
        currentBuild: 111,
        accountBeforeLaunch: true,
        notes: notes,
      );
      expect(again.view, isNull);
    });

    test('a build without notes shows nothing, and is still stored as seen', () {
      final d = decideFirstRun(
        onboardingSeen: true,
        lastSeenBuild: 110,
        currentBuild: 112,
        accountBeforeLaunch: true,
        notes: const {110: ['old']},
      );
      expect(d.view, isNull);
      expect(d.lastSeenBuild, 112);
    });

    test('skipped builds: every one newer than the last seen, newest first, at most 4 lines', () {
      expect(
        whatsNewLines(lastSeen: 107, current: 111, notes: notes),
        ['111 a', '111 b', '111 c', '110 a'],
      );
      expect(whatsNewLines(lastSeen: 109, current: 111, notes: notes).length, kWhatsNewMaxLines);
      // 109 has no notes: skipped, not an empty section.
      expect(whatsNewLines(lastSeen: 108, current: 110, notes: notes), ['110 a', '110 b']);
      // A note for a build not yet installed is not news.
      expect(whatsNewLines(lastSeen: 107, current: 108, notes: notes), ['108 a']);
      expect(whatsNewLines(lastSeen: 111, current: 111, notes: notes), isEmpty);
    });

    test('the notes for 112, and none for 111', () {
      expect(kWhatsNewNotes[112], [
        "Tap Tasks above the dial to pick what you're working on.",
        "A friend's day is one card now: swipe through it.",
        'See how many friends are in a session too. Turn yours off in More.',
        'Tap a day on your calendar for a simpler view of it.',
      ]);
      expect(kWhatsNewNotes.containsKey(111), isFalse);
      // A tester coming from 107 sees all four, within the cap.
      expect(whatsNewLines(lastSeen: null, current: 112), kWhatsNewNotes[112]);
      expect(whatsNewLines(lastSeen: 107, current: 112).length, kWhatsNewMaxLines);
      // An internal tester who saw 111's screen still gets 112's.
      expect(whatsNewLines(lastSeen: 111, current: 112), kWhatsNewNotes[112]);
    });

    test('a reset onboarding flag is onboarding again, even with an account already there', () {
      final d = decideFirstRun(
        onboardingSeen: false,
        lastSeenBuild: 111,
        currentBuild: 111,
        accountBeforeLaunch: true,
        notes: notes,
      );
      expect(d.view?.kind, FirstRunKind.onboarding);
    });
  });

  group('the phone\'s flags', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<FirstRunView?> open(FirstRunStore store, {bool account = true, int build = 112}) async {
      final c = ProviderContainer(
        overrides: [
          firstRunStoreProvider.overrideWithValue(store),
          accountBeforeLaunchProvider.overrideWithValue(account),
          currentBuildProvider.overrideWith((ref) async => build),
        ],
      );
      addTearDown(c.dispose);
      return c.read(firstRunProvider.future);
    }

    test('a fresh install: onboarding on the first open, never again', () async {
      final store = PrefsFirstRunStore();
      expect((await open(store, account: false))?.kind, FirstRunKind.onboarding);
      // The guest the first launch signed in is "an account already there"
      // from now on; onboarding still never comes back.
      expect(await open(store), isNull);
      expect(await open(store), isNull);
      expect(await open(store, account: false), isNull);
    });

    test("What's new once on the first open of a new build with notes", () async {
      SharedPreferences.setMockInitialValues({
        PrefsFirstRunStore.onboardingKey: true,
        PrefsFirstRunStore.lastSeenBuildKey: 110,
      });
      final store = PrefsFirstRunStore();
      expect((await open(store))?.lines, kWhatsNewNotes[112]);
      expect(await open(store), isNull);
    });

    test('Reset onboarding and Reset what\'s new each bring theirs back on the next open', () async {
      final store = PrefsFirstRunStore();
      await open(store, account: false);
      expect(await open(store), isNull);

      await store.resetOnboarding();
      expect((await open(store))?.kind, FirstRunKind.onboarding);
      expect(await open(store), isNull);

      await store.resetWhatsNew();
      final next = await open(store);
      expect(next?.kind, FirstRunKind.whatsNew);
      expect(next?.lines, kWhatsNewNotes[112]);
      expect(await open(store), isNull);
    });
  });

  group('the reset buttons', () {
    testWidgets('in the debug panel, each resets its own flag', (tester) async {
      final store = _Store();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firstRunStoreProvider.overrideWithValue(store),
            tasksRepositoryProvider.overrideWithValue(_Tasks(const [])),
            sessionStoreProvider.overrideWithValue(_NoStore()),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const DebugPanel()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapRow(String label) async {
        final row = find.text(label);
        await tester.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).first);
        await tester.tap(row);
        await tester.pumpAndSettle();
      }

      await tapRow('Reset onboarding');
      expect(store.resets, ['onboarding']);
      await tapRow("Reset what's new");
      expect(store.resets, ['onboarding', 'whatsNew']);
    });
  });

  group('before Home', () {
    Widget app(_Store store, {bool account = false, Key? key}) => ProviderScope(
      key: key,
      overrides: [
        currentUidProvider.overrideWithValue('me'),
        authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
        currentProfileProvider.overrideWith(
          (ref) async => const Profile(uid: 'me', username: 'me', displayName: 'Me'),
        ),
        friendshipsProvider.overrideWith((ref) => Stream.value(const <Friendship>[])),
        sessionStoreProvider.overrideWithValue(_NoStore()),
        milestoneStripProvider.overrideWith((ref) async => const <MilestoneStripEntry>[]),
        galleryPreviewProvider.overrideWith((ref) async => const <Photo>[]),
        bootPrecacheProvider.overrideWith((ref) => (_, _) async {}),
        firstRunStoreProvider.overrideWithValue(store),
        accountBeforeLaunchProvider.overrideWithValue(account),
        currentBuildProvider.overrideWith((ref) async => 112),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const BootGate()),
    );

    testWidgets('a fresh install sees onboarding once, over Home, and Continue fades it in 300ms', (tester) async {
      _ignoreFirebaseAbsence();
      final store = _Store();
      await tester.pumpWidget(app(store));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FirstRunScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(kFirstRunTitleKey)).data, 'sondr');
      for (final line in kOnboardingLines) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(kFirstRunHint), findsOneWidget);
      // No tab bar of its own: the names only.
      expect(find.descendant(of: find.byType(FirstRunScreen), matching: find.byType(GestureDetector)).evaluate()
          .where((e) => (e.widget as GestureDetector).onLongPress != null), isEmpty);

      await tester.tap(find.byKey(kFirstRunContinueKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(FirstRunScreen), findsOneWidget, reason: 'mid-fade');
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(FirstRunScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);

      // The next open: Home, straight away.
      await tester.pumpWidget(app(store, account: true, key: UniqueKey()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FirstRunScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets("an existing user updating sees What's new, with the same hint", (tester) async {
      _ignoreFirebaseAbsence();
      final store = _Store();
      await tester.pumpWidget(app(store, account: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Text>(find.byKey(kFirstRunTitleKey)).data, "What's new");
      for (final line in kWhatsNewNotes[112]!) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(kFirstRunHint), findsOneWidget);
      expect(find.byKey(kFirstRunTabNamesKey), findsOneWidget);
    });
  });

  group('layout', () {
    Future<void> sized(WidgetTester tester, double textScale, Widget child, {List overrides = const []}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          // A fresh scope each time: the overrides differ between screens.
          key: UniqueKey(),
          overrides: [
            sessionStoreProvider.overrideWithValue(_NoStore()),
            ...overrides.cast(),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: child,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Widget screen() => FirstRunScreen(view: const FirstRunView.onboarding(), onContinue: () {});

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts the tab names sit exactly on the tab bar\'s labels', (tester) async {
        await sized(tester, ts, const MainShell(tabs: [SizedBox(), SizedBox(), SizedBox()]));
        final real = {for (final l in ['Home', 'Posts', 'Profile']) l: tester.getRect(find.text(l))};

        await sized(tester, ts, screen());
        final tokens = GreyscaleTokens.of(tester.element(find.byType(FirstRunScreen)));
        for (final l in ['Home', 'Posts', 'Profile']) {
          final name = find.descendant(of: find.byKey(kFirstRunTabNamesKey), matching: find.text(l));
          final at = tester.getRect(name);
          expect(at.center.dx, closeTo(real[l]!.center.dx, 0.01), reason: '$l x');
          expect(at.center.dy, closeTo(real[l]!.center.dy, 0.01), reason: '$l y');
          final style = tester.widget<Text>(name).style!;
          expect(style.color, tokens.textPrimary, reason: 'every name in the text tone');
          expect(style.fontSize, 13);
        }
        // Posts and Profile are unselected on the real bar: the very same box.
        for (final l in ['Posts', 'Profile']) {
          final name = find.descendant(of: find.byKey(kFirstRunTabNamesKey), matching: find.text(l));
          expect(tester.getRect(name), real[l]);
        }
        // The hint sits above them, and none of them is a tap target.
        expect(tester.getRect(find.byKey(kFirstRunHintKey)).bottom,
            lessThan(tester.getRect(find.byKey(kFirstRunTabNamesKey)).top + 0.01));
        expect(find.descendant(of: find.byKey(kFirstRunTabNamesKey), matching: find.byType(GestureDetector)), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the copy: on the 24 gutter from 176, 18 between lines and 6 more under the title', (tester) async {
      await sized(tester, 1.0, screen());
      final scale = figmaScale(tester.element(find.byType(FirstRunScreen)));
      final title = tester.getRect(find.byKey(kFirstRunTitleKey));
      expect(title.top, closeTo(176 * scale, 0.01));
      expect(title.left, closeTo(24 * scale, 0.01));
      final lines = [for (final l in kOnboardingLines) tester.getRect(find.text(l))];
      expect(lines.first.top - title.bottom, closeTo(24 * scale, 0.01));
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].top - lines[i - 1].bottom, closeTo(18 * scale, 0.01));
        expect(lines[i].left, closeTo(24 * scale, 0.01));
      }
      final ctx = tester.element(find.byType(FirstRunScreen));
      final tokens = GreyscaleTokens.of(ctx);
      // The how-to sheets' type exactly: their title, and their line.
      final titleStyle = tester.widget<Text>(find.byKey(kFirstRunTitleKey)).style!;
      expect(titleStyle, blurTitleStyle(ctx));
      expect(titleStyle.fontSize, 20);
      expect(titleStyle.fontWeight, FontWeight.w700);
      for (var i = 0; i < kOnboardingLines.length; i++) {
        final style = tester.widget<Text>(find.text(kOnboardingLines[i])).style!;
        final line = howToLineStyle(ctx)!;
        expect(style.fontSize, line.fontSize);
        expect(style.fontWeight, line.fontWeight);
        expect(style.fontFamily, line.fontFamily);
        expect(style.height, line.height);
        expect(style, line.copyWith(color: i == 0 ? tokens.textPrimary : tokens.textSecondary));
      }
      expect(tester.widget<Text>(find.text(kOnboardingLines[0])).style!.color, tokens.textPrimary);
      expect(tester.widget<Text>(find.text(kOnboardingLines[1])).style!.color, tokens.textSecondary);
      expect(tester.widget<Text>(find.text(kOnboardingLines[2])).style!.color, tokens.textSecondary);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xFF0A0A0A));
    });

    testWidgets("Continue stands on the line of Home's Pause and Stop", (tester) async {
      await sized(
        tester,
        1.0,
        const TimerScreen(),
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_Tasks([Task(id: 'a', name: 'Golf', secondsByDay: const {})])),
          sessionLogProvider.overrideWithValue(_Log()),
          liveActivityProvider.overrideWithValue(_SilentCard()),
        ],
      );
      final c = ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
      c.read(selectedTaskIdProvider.notifier).select('a');
      await tester.pumpAndSettle();
      await c.read(timerControllerProvider.notifier).start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final pause = tester.getRect(find.text('Pause'));
      final stop = tester.getRect(find.text('Stop'));
      expect(pause.center.dy, closeTo(stop.center.dy, 0.01));

      await sized(tester, 1.0, screen());
      final go = tester.getRect(find.text('Continue'));
      expect(go.center.dy, closeTo(pause.center.dy, 0.01));
      expect(go.center.dx, closeTo(195, 0.01), reason: 'centred');
      expect(tester.widget<Text>(find.text('Continue')).style!.fontWeight, FontWeight.w700);
      expect(kHomeActionTop, 448);
    });

    testWidgets('Home, idle with tasks: "Tap Tasks to start a session"', (tester) async {
      await sized(
        tester,
        1.0,
        const TimerScreen(),
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_Tasks([Task(id: 'a', name: 'Golf', secondsByDay: const {})])),
        ],
      );
      expect(find.text('Tap Tasks to start a session'), findsOneWidget);
      expect(find.text('Pick a task to start a session'), findsNothing);
      expect(kHomeIdleLine, 'Tap Tasks to start a session');
    });
  });
}

class _Store implements FirstRunStore {
  bool? seen;
  int? last;
  final resets = <String>[];

  @override
  Future<bool?> onboardingSeen() async => seen;
  @override
  Future<int?> lastSeenBuild() async => last;
  @override
  Future<void> save({required bool onboardingSeen, int? lastSeenBuild}) async {
    seen = onboardingSeen;
    if (lastSeenBuild != null) last = lastSeenBuild;
  }

  @override
  Future<void> resetOnboarding() async {
    resets.add('onboarding');
    seen = false;
  }

  @override
  Future<void> resetWhatsNew() async {
    resets.add('whatsNew');
    last = null;
  }
}

void _ignoreFirebaseAbsence() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('No Firebase App')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

class _Tasks implements TasksRepository {
  _Tasks(this.tasks);
  List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<void> save(Task task) async =>
      tasks = [for (final t in tasks) t.id == task.id ? task : t];
  @override
  Future<void> rename(String taskId, String name) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
}

class _Log implements SessionLog {
  @override
  Future<void> record(SessionRecord session) async {}
  @override
  Future<List<SessionRecord>> forTask(String taskId) async => const [];
}

class _NoStore implements SessionStore {
  SessionClock? saved;
  @override
  Future<SessionClock?> read() async => saved;
  @override
  Future<void> write(SessionClock clock) async => saved = clock;
  @override
  Future<void> clear() async => saved = null;
}

class _SilentCard implements LiveActivity {
  @override
  Stream<String> get links => const Stream<String>.empty();
  @override
  Future<void> show(SessionClock clock) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> ready() async {}
}
