import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/blur_sheet.dart';

import 'support/app_viewport.dart';

/// On a blur sheet the WORD is the target. A tap beside it on the row does
/// nothing; a tap on the blur dismisses; the way out is "Back".
void main() {
  testWidgets('a tap on the label acts; 60pt left of it does not', (tester) async {
    useReferenceViewport(tester);
    var acted = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBlurSheet(
                  context,
                  (_) => BlurView(
                    title: 'Choose',
                    items: [BlurItem(label: 'Do it', onTap: () => acted++)],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final label = tester.getRect(find.text('Do it'));
    await tester.tapAt(Offset(label.left - 60, label.center.dy));
    await tester.pumpAndSettle();
    expect(acted, 0, reason: 'the row beside the word acted');
    expect(find.byType(BlurSheet), findsOneWidget, reason: 'the row beside the word dismissed');

    await tester.tapAt(label.center);
    await tester.pumpAndSettle();
    expect(acted, 1);

    // The target: the word plus 12 above and below, at least 44 tall.
    final target = tester.getRect(
      find.ancestor(of: find.text('Do it'), matching: find.byType(ConstrainedBox)).first,
    );
    expect(target.height, greaterThanOrEqualTo(44 * 0.9906 - 0.5));
    expect(target.height, closeTo(label.height + 24 * 0.9906, 0.6));
    expect(target.width, closeTo(label.width + 48 * 0.9906, 0.6));

    // And the way out is Back.
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
