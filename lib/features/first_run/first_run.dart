import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app says before Home on the opens that need it: onboarding once
/// per install, then "What's new" once on the first open after an update
/// that has notes.

/// The notes, by build number. A build without an entry has nothing to say,
/// and an update to it shows nothing.
const Map<int, List<String>> kWhatsNewNotes = {
  // The build family testers move to from 107; 111 went to internal
  // testing only, so its notes are folded in here.
  112: [
    "Tap Tasks above the dial to pick what you're working on.",
    "A friend's day is one card now: swipe through it.",
    'See how many friends are in a session too. Turn yours off in More.',
    'Tap a day on your calendar for a simpler view of it.',
  ],
};

/// The most lines "What's new" shows, however many builds were skipped.
const int kWhatsNewMaxLines = 4;

const String kOnboardingTitle = 'sondr';
const String kWhatsNewTitle = "What's new";

const List<String> kOnboardingLines = [
  'Track the time you put into the things you do.',
  'Pick a task and press Start. When you stop, take a photo.',
  'Every 20 hours on a task is a milestone to share with your friends.',
];

enum FirstRunKind { onboarding, whatsNew }

/// One screen to show: its kind, title and lines.
@immutable
class FirstRunView {
  const FirstRunView.onboarding()
    : kind = FirstRunKind.onboarding,
      lines = kOnboardingLines;

  const FirstRunView.whatsNew(this.lines) : kind = FirstRunKind.whatsNew;

  final FirstRunKind kind;
  final List<String> lines;

  String get title =>
      kind == FirstRunKind.onboarding ? kOnboardingTitle : kWhatsNewTitle;
}

/// The lines of every build after [lastSeen] up to [current], newest build
/// first, each build's own lines in order, at most [kWhatsNewMaxLines].
/// A null [lastSeen] is a phone that has never stored one: every note up to
/// [current] is new to it.
List<String> whatsNewLines({
  required int? lastSeen,
  required int current,
  Map<int, List<String>> notes = kWhatsNewNotes,
}) {
  final builds = [
    for (final b in notes.keys)
      if ((lastSeen == null || b > lastSeen) && b <= current) b,
  ]..sort((a, b) => b.compareTo(a));
  return [
    for (final b in builds) ...notes[b]!,
  ].take(kWhatsNewMaxLines).toList();
}

/// What this open shows, and what is stored for the next one.
@immutable
class FirstRunDecision {
  const FirstRunDecision({
    required this.view,
    required this.onboardingSeen,
    required this.lastSeenBuild,
  });

  final FirstRunView? view;
  final bool onboardingSeen;
  final int? lastSeenBuild;
}

/// The rule.
///
/// [onboardingSeen] is null on a phone that has never stored it — a fresh
/// install, or a phone updating from a build before this one. The two are
/// told apart by [accountBeforeLaunch]: whether an account, guest or not,
/// was already signed in when this launch began. A fresh install has none
/// until the launch signs in a guest; anyone who has opened Sondr before
/// does. False (not null) is a reset: onboarding again.
///
/// Onboarding stores the current build as seen, so "What's new" does not
/// follow it. Every open stores the current build, notes or not.
FirstRunDecision decideFirstRun({
  required bool? onboardingSeen,
  required int? lastSeenBuild,
  required int? currentBuild,
  required bool accountBeforeLaunch,
  Map<int, List<String>> notes = kWhatsNewNotes,
}) {
  final onboarding =
      onboardingSeen == false || (onboardingSeen == null && !accountBeforeLaunch);
  if (onboarding) {
    return FirstRunDecision(
      view: const FirstRunView.onboarding(),
      onboardingSeen: true,
      lastSeenBuild: currentBuild ?? lastSeenBuild,
    );
  }
  // No build number to read: nothing to compare, nothing to store.
  if (currentBuild == null) {
    return FirstRunDecision(
      view: null,
      onboardingSeen: true,
      lastSeenBuild: lastSeenBuild,
    );
  }
  final lines = whatsNewLines(
    lastSeen: lastSeenBuild,
    current: currentBuild,
    notes: notes,
  );
  return FirstRunDecision(
    view: lines.isEmpty ? null : FirstRunView.whatsNew(lines),
    onboardingSeen: true,
    lastSeenBuild: currentBuild,
  );
}

/// The two flags, on the phone: they are about this install, not the
/// account.
abstract class FirstRunStore {
  Future<bool?> onboardingSeen();
  Future<int?> lastSeenBuild();
  Future<void> save({required bool onboardingSeen, int? lastSeenBuild});

  /// Onboarding on the next open.
  Future<void> resetOnboarding();

  /// "What's new" on the next open, with every note up to this build.
  Future<void> resetWhatsNew();
}

class PrefsFirstRunStore implements FirstRunStore {
  static const String onboardingKey = 'sondr.onboardingSeen';
  static const String lastSeenBuildKey = 'sondr.lastSeenBuild';

  @override
  Future<bool?> onboardingSeen() async =>
      (await SharedPreferences.getInstance()).getBool(onboardingKey);

  @override
  Future<int?> lastSeenBuild() async =>
      (await SharedPreferences.getInstance()).getInt(lastSeenBuildKey);

  @override
  Future<void> save({required bool onboardingSeen, int? lastSeenBuild}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, onboardingSeen);
    if (lastSeenBuild != null) await prefs.setInt(lastSeenBuildKey, lastSeenBuild);
  }

  @override
  Future<void> resetOnboarding() async =>
      (await SharedPreferences.getInstance()).setBool(onboardingKey, false);

  @override
  Future<void> resetWhatsNew() async =>
      (await SharedPreferences.getInstance()).remove(lastSeenBuildKey);
}

final firstRunStoreProvider = Provider<FirstRunStore>(
  (ref) => PrefsFirstRunStore(),
);

/// Whether an account was signed in when this launch began. Set by
/// `main()`, which knows before it signs a guest in; false everywhere else.
final accountBeforeLaunchProvider = Provider<bool>((ref) => false);

/// This build's number, from the bundle. Null if it cannot be read.
final currentBuildProvider = FutureProvider<int?>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber);
});

/// What this open shows before Home, or null. Decided once per launch, and
/// stored as it is decided: shown once means once, even if the app is
/// closed on it.
final firstRunProvider = FutureProvider<FirstRunView?>((ref) async {
  final store = ref.read(firstRunStoreProvider);
  int? build;
  try {
    build = await ref.read(currentBuildProvider.future);
  } catch (_) {
    build = null;
  }
  final decision = decideFirstRun(
    onboardingSeen: await store.onboardingSeen(),
    lastSeenBuild: await store.lastSeenBuild(),
    currentBuild: build,
    accountBeforeLaunch: ref.read(accountBeforeLaunchProvider),
  );
  await store.save(
    onboardingSeen: decision.onboardingSeen,
    lastSeenBuild: decision.lastSeenBuild,
  );
  return decision.view;
});
