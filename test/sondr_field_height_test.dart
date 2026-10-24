import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/spacing.dart';
import 'package:sondr/shared/sondr_field.dart';

import 'support/app_viewport.dart';

/// SondrField takes exactly the room its content needs.
///
/// Reported as reserving a taller box than it uses. It does not: in every
/// shape a caller asks for, at every text size, the field measures its
/// label, the gap under it, its own capsule padding, and one line of text
/// — and nothing else. These are those numbers, so that a Material
/// default creeping in later shows up here rather than as a screen that
/// has quietly grown.
///
/// The filled capsule's 14 either side is not slack. It is the capsule,
/// and the only caller that asks for one is the auth screen.
void main() {
  /// The shapes the seven call sites ask for, named by where they are.
  final shapes = <String, SondrField Function(TextEditingController)>{
    'handle screen': (c) =>
        SondrField(controller: c, label: 'Handle', prefix: '@'),
    'auth email': (c) => SondrField(controller: c, label: 'Email'),
    'auth password': (c) =>
        SondrField(controller: c, label: 'Password', obscureText: true),
    'invited screen': (c) =>
        SondrField(controller: c, label: 'Their handle', prefix: '@'),
    'habits name': (c) => SondrField(
      controller: c,
      filled: false,
      centered: true,
      fontSize: 15,
    ),
    'comments composer': (c) => SondrField(
      controller: c,
      filled: false,
      centered: true,
      minLines: 1,
      maxLines: 3,
      fontSize: 14,
    ),
    'add a friend': (c) =>
        SondrField(controller: c, filled: false, centered: true),
    'prompt card': (c) =>
        SondrField(controller: c, filled: false, centered: true),
  };

  Future<({double field, double text, double below})> measure(
    WidgetTester tester,
    SondrField field,
    double textScale,
  ) async {
    useReferenceViewport(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(kRefWidth, kRefHeight),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const Text('BELOW')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      field: tester.getRect(find.byType(SondrField)).height,
      text: tester.getRect(find.byType(EditableText)).height,
      below: tester.getRect(find.text('BELOW')).top,
    );
  }

  group('the box is the content', () {
    for (final entry in shapes.entries) {
      for (final ts in [0.824, 1.0, 1.235]) {
        testWidgets('${entry.key} at $ts', (tester) async {
          final controller = TextEditingController(text: 'Golf');
          addTearDown(controller.dispose);
          final field = entry.value(controller);
          final m = await measure(tester, field, ts);

          // What the field is entitled to: the label and its gap where
          // there is one, the capsule's padding where it is filled, and
          // one line of the text being typed.
          final labelled = field.label != null;
          final capsule = field.filled ? 28.0 : 0.0;
          final label = labelled
              ? tester.getRect(find.text(field.label!)).height +
                    kSpacingPair
              : 0.0;
          expect(
            m.field,
            closeTo(label + capsule + m.text, 0.5),
            reason: 'reserved more than its content',
          );
          // And whatever follows starts the moment it ends.
          expect(m.below, closeTo(m.field, 0.5));
        });
      }
    }
  });

  group('and it tracks the text size', () {
    testWidgets('an unfilled field is one line, whatever that line is', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Golf');
      addTearDown(controller.dispose);
      SondrField plain() =>
          SondrField(controller: controller, filled: false, centered: true);

      final small = await measure(tester, plain(), 0.824);
      final normal = await measure(tester, plain(), 1.0);
      final large = await measure(tester, plain(), 1.235);

      expect(small.field, 17);
      expect(normal.field, 21);
      expect(large.field, 26);
      for (final m in [small, normal, large]) {
        expect(m.field, m.text, reason: 'the box left room spare');
      }
    });

    testWidgets('a filled one adds its capsule and nothing more', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Golf');
      addTearDown(controller.dispose);
      final m = await measure(tester, SondrField(controller: controller), 1.0);
      expect(m.field, 49);
      expect(m.field - m.text, 28, reason: '14 above and 14 below');
    });
  });
}
