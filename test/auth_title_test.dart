import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/auth/auth_screen.dart';

/// The primary action says which of the two this is, so the heading above
/// the fields said it twice. The space it took is kept.
void main() {
  testWidgets('signing in is not announced twice, and nothing moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthScreen(startInSignUp: false)),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.ancestor(
      of: find.text('Sign in'),
      matching: find.byType(Visibility),
    );
    expect(header, findsWidgets);
    expect(tester.widget<Visibility>(header.first).visible, isFalse);
    // The action still names the mode.
    expect(find.text('Sign in'), findsWidgets);
    // And the first field is where it was, measured with the header shown.
    // 136.59 with the header visible, 136.59 without it.
    expect(
      tester.getRect(find.byType(TextField).first).top,
      closeTo(136.59, 0.5),
    );
  });
}
