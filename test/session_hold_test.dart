import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// While a session runs the app is held on Home with the tabs away; a
/// paused session lets go, and running again brings Home forward.
void main() {
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester) async {
    c = ProviderContainer(overrides: [
      timerControllerProvider.overrideWith(_Timer.new),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const MainShell(tabs: [Text('home tab'), Text('posts tab'), Text('profile tab')]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  _Timer timer() => c.read(timerControllerProvider.notifier) as _Timer;
  Future<void> become(WidgetTester tester, TimerState next) async {
    timer().set(next);
    await tester.pumpAndSettle();
  }

  bool showing(String text) => find.text(text).hitTestable().evaluate().isNotEmpty;

  testWidgets('idle: the tabs are there and work', (tester) async {
    await pump(tester);
    expect(find.byType(TextTabBar), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(showing('profile tab'), isTrue);
  });

  testWidgets('running: no tabs, Home held', (tester) async {
    await pump(tester);
    await become(tester, const TimerState(status: TimerStatus.running));
    expect(find.byType(TextTabBar), findsNothing);
    expect(showing('home tab'), isTrue);
  });

  testWidgets('paused: the tabs come back and work', (tester) async {
    await pump(tester);
    await become(tester, const TimerState(status: TimerStatus.running));
    await become(tester, const TimerState(status: TimerStatus.paused));
    expect(find.byType(TextTabBar), findsOneWidget);
    await tester.tap(find.text('Posts').evaluate().isEmpty ? find.text('Feed') : find.text('Posts'));
    await tester.pumpAndSettle();
    expect(showing('posts tab'), isTrue);
  });

  testWidgets('resumed while another tab shows — in the app or from the Lock Screen — Home comes forward', (tester) async {
    await pump(tester);
    await become(tester, const TimerState(status: TimerStatus.paused));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(showing('profile tab'), isTrue);
    await become(tester, const TimerState(status: TimerStatus.running));
    expect(showing('home tab'), isTrue);
    expect(find.byType(TextTabBar), findsNothing);
    // And pausing again stays on Home, not the tab left behind.
    await become(tester, const TimerState(status: TimerStatus.paused));
    expect(showing('home tab'), isTrue);
  });

  testWidgets('stopping a paused session holds Home until it is gone', (tester) async {
    await pump(tester);
    await become(tester, const TimerState(status: TimerStatus.paused, stopping: true));
    expect(find.byType(TextTabBar), findsNothing);
    expect(showing('home tab'), isTrue);
    await become(tester, const TimerState());
    expect(find.byType(TextTabBar), findsOneWidget);
  });

  testWidgets('the jump to Posts after a shared session lands there', (tester) async {
    await pump(tester);
    await become(tester, const TimerState(status: TimerStatus.running, stopping: true));
    // The share flow runs after the session is gone, then moves the tab.
    await become(tester, const TimerState());
    c.read(selectedTabProvider.notifier).set(1);
    await tester.pumpAndSettle();
    expect(showing('posts tab'), isTrue);
    expect(find.byType(TextTabBar), findsOneWidget);
  });
}

class _Timer extends TimerController {
  @override
  TimerState build() => const TimerState();

  void set(TimerState next) => state = next;
}
