import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/shared/ring/ring_dial.dart';

void main() {
  testWidgets('RingDial renders its centre figure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [GreyscaleTokens.dark],
        ),
        home: const Scaffold(
          body: Center(
            child: RingDial(
              taskProgress: 0.5,
              habitProgress: 0.5,
              centerValue: '13 hrs',
              centerLabel: 'today',
              animate: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('13 hrs'), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
  });
}
