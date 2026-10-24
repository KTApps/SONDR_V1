import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/focus/focus_providers.dart';
import 'package:sondr/features/focus/focus_view.dart';

void main() {
  test('focusModeProvider enables and disables', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(c.read(focusModeProvider), isFalse);
    c.read(focusModeProvider.notifier).enable();
    expect(c.read(focusModeProvider), isTrue);
    c.read(focusModeProvider.notifier).disable();
    expect(c.read(focusModeProvider), isFalse);
  });

  testWidgets('FocusView shows the quietened surface with pause/stop',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: FocusView(onStop: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No "FOCUS" heading: the bare screen, the task name and the running
    // clock say what this is without restating it.
    expect(find.text('FOCUS'), findsNothing);
    expect(find.text('Stop'), findsOneWidget);
    // Idle by default → the going-again affordance is shown, not pause.
    // It reads "Start", as it does on Home and on the widget, and a
    // screen reader is told what it really does.
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(tester.widget<Text>(find.text('Start')).semanticsLabel, 'Resume');
    // Stop on the left, the primary on the right.
    expect(
      tester.getCenter(find.text('Stop')).dx,
      lessThan(tester.getCenter(find.text('Start')).dx),
    );
  });
}
