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

    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    // Idle by default → the resume affordance is shown, not pause.
    expect(find.text('Resume'), findsOneWidget);
  });
}
