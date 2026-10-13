import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/apple_sign_in_button.dart';
import 'package:sondr/features/auth/auth_screen.dart';

import 'support/app_viewport.dart';

/// The action stack under the email form.
///
/// "Back" had nothing declared above it, so it sat 12 below the Apple button
/// — its own tap padding and nothing else — where every other step in that
/// stack reads 24. A 44pt capsule with 12 under it looks like the button and
/// the exit belong together.
void main() {
  /// Auth pushed from a landing screen, because "Back" only renders when
  /// there is something to pop.
  Future<void> pumpAuth(WidgetTester tester) async {
    useReferenceViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AuthScreen(startInSignUp: false),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
  }

  testWidgets('"Back" sits 24 under the Apple button, as the stack above it '
      'does', (tester) async {
    await pumpAuth(tester);
    final button = tester.getRect(find.byType(AppleSignInButton));
    final back = tester.getRect(find.text('Back'));
    // 12 declared plus the 12 of tap padding SondrAction carries.
    expect(back.top - button.bottom, closeTo(24, 1));
    // And the button is still the 44 capsule it was.
    expect(button.height, closeTo(44, 0.5));
  });

  testWidgets('the gap above the button is the same 24', (tester) async {
    await pumpAuth(tester);
    final button = tester.getRect(find.byType(AppleSignInButton));
    final above = tester.getRect(find.text('Create a new account'));
    // The action's own 12 of padding below its label, plus the declared 12.
    expect(button.top - above.bottom, closeTo(24, 1));
  });
}
