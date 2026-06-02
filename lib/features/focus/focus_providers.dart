import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Focus Mode is active for the current session. Focus quietens the app
/// down to just the running task and pause/stop — reinforcing the "locked into
/// the effort" ethos. It is offered when a session starts and cleared when the
/// session stops.
class FocusMode extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;
  void disable() => state = false;
}

final focusModeProvider = NotifierProvider<FocusMode, bool>(FocusMode.new);
