import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/sondr_action.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

/// The swipe row's haptic is for comments alone: a row without the flag —
/// a habit, a task — reveals its tray in silence.
void main() {
  testWidgets('a row without the flag is not felt; one with it is, once', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    Widget row(String text, {required bool haptic}) => SondrSwipeRow(
      haptic: haptic,
      actions: [SondrAction(label: 'Act', onPressed: () {})],
      child: SizedBox(height: 56, child: Center(child: Text(text))),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Column(children: [row('quiet', haptic: false), row('felt', haptic: true)])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('quiet'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
    await tester.drag(find.text('felt'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });
}
