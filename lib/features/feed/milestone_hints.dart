import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../timer/session_store.dart' show kSessionAppGroup;

/// The one-time hint on a milestone with several photos: "Tap the right
/// side to see each session", with the right third glowing twice. Shown on
/// the first three such posts a person sees, and never again once they
/// have tapped the right side of any post.

/// How many multi-photo posts carry the hint before it is given up on.
const int kMilestoneHintPosts = 3;

/// What has been shown and done so far.
@immutable
class MilestoneHintState {
  const MilestoneHintState({this.seen = const [], this.tapped = false});

  /// The posts the hint has been shown on, oldest first.
  final List<String> seen;

  /// Whether the right side has ever been tapped.
  final bool tapped;

  /// Whether the hint belongs on [postId]: not once the gesture has been
  /// found, and only on the posts it was already shown on or while there
  /// is still room for another.
  bool showFor(String postId) =>
      !tapped && (seen.contains(postId) || seen.length < kMilestoneHintPosts);

  @override
  bool operator ==(Object other) =>
      other is MilestoneHintState &&
      other.tapped == tapped &&
      listEquals(other.seen, seen);

  @override
  int get hashCode => Object.hash(tapped, Object.hashAll(seen));
}

abstract class MilestoneHints {
  Future<MilestoneHintState> read();

  /// The hint was shown on [postId].
  Future<void> markSeen(String postId);

  /// The right side was tapped: the hint has done its job.
  Future<void> markTapped();
}

/// The hint's state in the App Group container, beside the running session
/// and the other things this app keeps on the device.
class PrefsMilestoneHints implements MilestoneHints {
  PrefsMilestoneHints({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(
              suiteName: kSessionAppGroup,
            ),
          );

  static const String seenKey = 'sondr.milestoneHint.seen';
  static const String tappedKey = 'sondr.milestoneHint.tapped';

  final SharedPreferencesAsync _prefs;

  @override
  Future<MilestoneHintState> read() async {
    try {
      return MilestoneHintState(
        seen: await _prefs.getStringList(seenKey) ?? const [],
        tapped: await _prefs.getBool(tappedKey) ?? false,
      );
    } catch (e) {
      debugPrint('SONDR milestone hint read error: ${e.runtimeType}');
      return const MilestoneHintState();
    }
  }

  @override
  Future<void> markSeen(String postId) async {
    final now = await read();
    if (now.seen.contains(postId) || now.seen.length >= kMilestoneHintPosts) {
      return;
    }
    try {
      await _prefs.setStringList(seenKey, [...now.seen, postId]);
    } catch (e) {
      debugPrint('SONDR milestone hint write error: ${e.runtimeType}');
    }
  }

  @override
  Future<void> markTapped() async {
    try {
      await _prefs.setBool(tappedKey, true);
    } catch (e) {
      debugPrint('SONDR milestone hint write error: ${e.runtimeType}');
    }
  }
}

/// The same, in memory — for tests, and for a run with nothing to keep.
class MemoryMilestoneHints implements MilestoneHints {
  MemoryMilestoneHints([this.state = const MilestoneHintState()]);

  MilestoneHintState state;

  @override
  Future<MilestoneHintState> read() async => state;

  @override
  Future<void> markSeen(String postId) async {
    if (state.seen.contains(postId) || state.seen.length >= kMilestoneHintPosts) {
      return;
    }
    state = MilestoneHintState(seen: [...state.seen, postId], tapped: state.tapped);
  }

  @override
  Future<void> markTapped() async {
    state = MilestoneHintState(seen: state.seen, tapped: true);
  }
}

final milestoneHintsProvider = Provider<MilestoneHints>((_) {
  try {
    return PrefsMilestoneHints();
  } catch (e) {
    // No preferences on this platform (a test, a preview): the hint is
    // simply never shown, and a card never fails for it.
    debugPrint('SONDR milestone hints unavailable: ${e.runtimeType}');
    return MemoryMilestoneHints(const MilestoneHintState(tapped: true));
  }
});

/// What the cards read. Refreshed by whoever writes, so every card on
/// screen follows the first right-side tap at once.
final milestoneHintStateProvider = FutureProvider<MilestoneHintState>(
  (ref) => ref.watch(milestoneHintsProvider).read(),
);
