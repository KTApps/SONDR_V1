import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A line for Home to say once, raised by something that happened on
/// another tab.
///
/// Home's notice is its own state and says its piece for two seconds — the
/// right shape, but private to the screen. Deleting an account happens on
/// the Profile tab and lands the person on Home, so the message has to
/// outlive the screen it was raised from. Home takes it on its next build
/// and clears it, so it is said exactly once and never again on a rebuild.
class HomeNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void say(String message) => state = message;

  /// Home has it. Clearing here rather than on a timer: the two seconds
  /// belong to Home's own line.
  void taken() => state = null;
}

final homeNoticeProvider = NotifierProvider<HomeNotice, String?>(
  HomeNotice.new,
);
