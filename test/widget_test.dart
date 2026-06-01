import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/shared/ring/mini_ring.dart';
import 'package:sondr/shared/ring/ring_dial.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: const [GreyscaleTokens.dark]),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('RingDial renders its centre and a segmented ring', (tester) async {
    await tester.pumpWidget(
      host(
        const RingDial(
          taskSegments: [3, 2, 1],
          highlightedSegment: 0,
          habitProgress: 0.5,
          center: Text('13 hrs'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('13 hrs'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('RingDial copes with no tasks (empty segments)', (tester) async {
    await tester.pumpWidget(host(const RingDial(taskSegments: [], habitProgress: 0)));
    await tester.pumpAndSettle();
    expect(find.byType(RingDial), findsOneWidget);
  });

  testWidgets('MiniRing renders a day split', (tester) async {
    await tester.pumpWidget(host(const MiniRing(segments: [1, 1], size: 26)));
    await tester.pumpAndSettle();
    expect(find.byType(MiniRing), findsOneWidget);
  });
}
