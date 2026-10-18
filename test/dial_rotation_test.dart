import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/ring/dial_geometry.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// The home dial must never appear to run backwards.
///
/// The outer band is a pie of today's time, and a pie slice shrinks when
/// the pie gains filling. In task order, logging time on a second task slid
/// every earlier boundary ANTICLOCKWISE while nothing had been taken from
/// the task it belonged to.
void main() {
  const slit = 0.04;

  List<double> starts(List<double> weights, {int? selected}) =>
      outerSegmentStarts(
        weights: weights,
        slitAngle: slit,
        selectedSegment: selected,
      );

  group('where the slices begin', () {
    test('the selected slice opens at 12', () {
      for (var i = 0; i < 3; i++) {
        expect(
          starts([3, 5, 2], selected: i)[i],
          closeTo(0, 1e-12),
          reason: 'slice $i is not at the top',
        );
      }
    });

    test('nothing selected keeps the first slice at 12', () {
      expect(starts([3, 5, 2]).first, 0);
    });

    test('the cyclic order survives the turn', () {
      // A, B, C with C selected reads C, A, B around the circle.
      final turned = starts([3, 5, 2], selected: 2);
      expect(turned[2], closeTo(0, 1e-12));
      expect(turned[0], greaterThan(turned[2]));
      expect(turned[1], greaterThan(turned[0]));
    });

    test('a selected task with no time today sits at 12 with no width', () {
      final turned = starts([0, 5, 2], selected: 0);
      expect(turned[0], closeTo(0, 1e-12));
      // Its neighbour begins immediately after it: nothing between them
      // but the slit.
      expect(turned[1], closeTo(slit, 1e-12));
    });
  });

  group('while a session runs', () {
    test('every boundary moves clockwise, and 12 never moves', () {
      // A and B are fixed; C is the selected task, accruing.
      List<double>? previous;
      for (var live = 0.0; live <= 7200; live += 60) {
        final now = starts([1800, 2400, live], selected: 2);
        expect(now[2], closeTo(0, 1e-12), reason: 'the top boundary moved');
        if (previous != null) {
          for (var i = 0; i < now.length; i++) {
            expect(
              now[i],
              greaterThanOrEqualTo(previous[i] - 1e-12),
              reason: 'boundary $i went anticlockwise at live=$live',
            );
          }
        }
        previous = now;
      }
    });

    test('in task order it DID go backwards — the bug this fixes', () {
      // The same run, unrotated: the boundary after A slides back toward
      // 12 as C grows, though A never lost a second.
      final before = starts([1800, 2400, 60])[1];
      final after = starts([1800, 2400, 7200])[1];
      expect(after, lessThan(before));
    });
  });

  group('turning to a new selection', () {
    test('it goes the short way round', () {
      // 350° to 10° is 20° clockwise, not 340° back.
      final turn = shortestTurn(math.pi * 2 - 0.2, 0.2);
      expect(turn, closeTo(0.4, 1e-9));
      expect(shortestTurn(0.2, math.pi * 2 - 0.2), closeTo(-0.4, 1e-9));
      expect(shortestTurn(1, 1), 0);
    });

    testWidgets('selecting another task turns over 300ms', (tester) async {
      Widget dial(int? selected) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SegmentedDial(
              taskTodaySeconds: const [1800, 2400, 600],
              selectedTaskIndex: selected,
              habitStates: const [],
            ),
          ),
        ),
      );

      await tester.pumpWidget(dial(2));
      await tester.pumpAndSettle();
      dynamic painterFor() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(SegmentedDial),
              matching: find.byType(CustomPaint),
            ).first,
          )
          .painter!;
      final settled = painterFor().outerRotation as double;

      await tester.pumpWidget(dial(1));
      await tester.pump();
      final atStart = painterFor().outerRotation as double;
      expect(atStart, closeTo(settled, 1e-9), reason: 'it jumped');

      await tester.pump(const Duration(milliseconds: 150));
      final midway = painterFor().outerRotation as double;
      expect(midway, isNot(closeTo(settled, 1e-6)));

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final ended = painterFor().outerRotation as double;
      expect(ended, isNot(closeTo(midway, 1e-9)));
      // And it has arrived where slice 1 opens at 12.
      final expected = starts([1800, 2400, 600])[1];
      expect(ended % (2 * math.pi), closeTo(expected, 0.02));
    });
  });

  group('the Last 10 days dials are untouched', () {
    testWidgets('no selection means no turn', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Center(
              child: SegmentedDial(
                taskTodaySeconds: [1800, 2400, 600],
                habitStates: [true, false],
                compact: true,
                size: 57,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter = tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(SegmentedDial),
                  matching: find.byType(CustomPaint),
                ).first,
              )
              .painter!
          as dynamic;
      expect(
        painter.outerRotation as double,
        0,
        reason: 'a day cell was rotated',
      );
    });
  });
}
