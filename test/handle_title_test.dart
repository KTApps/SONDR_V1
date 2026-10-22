import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/auth/handle_screen.dart';

/// A page that names itself twice says it once too often: the line under
/// the header already explains the screen, and the field is labelled.
/// What the header cost in height, it still costs — nothing below it moves.
void main() {
  testWidgets('choosing a handle is not announced, and nothing moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HandleScreen())),
    );
    await tester.pumpAndSettle();

    // Hidden, not deleted: a maintained-size Visibility, the way the
    // Blocked screen already does it, so the gap stays exactly one header
    // tall even if the header's type changes.
    final header = find.ancestor(
      of: find.text('Choose a handle'),
      matching: find.byType(Visibility),
    );
    expect(tester.widget<Visibility>(header.first).visible, isFalse);
    // Measured with the header still visible, on a 13 Pro.
    expect(
      tester.getRect(find.textContaining('This is how friends')).top,
      closeTo(95.77, 0.5),
    );
  });
}
