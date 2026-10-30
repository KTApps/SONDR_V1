import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/blur_sheet.dart';

/// A blur sheet closes itself when the account changes hands under it —
/// a sign-out, a deletion, a sign-in — however deep the flow it was
/// holding; the guest state is what is left, with no blur over it.
void main() {
  Future<_Uid> pump(WidgetTester tester) async {
    final uid = _Uid('me');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _uidProvider.overrideWith(() => uid),
          currentUidProvider.overrideWith((ref) => ref.watch(_uidProvider)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showBlurSheet(
                      context,
                      (handle) => BlurView(
                        title: 'Question?',
                        items: [
                          BlurItem(label: 'Deeper', onTap: () => handle.show(const BlurView(title: 'Deeper?'))),
                        ],
                      ),
                    ),
                    child: const Text('open'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('a page on top'))),
                    ),
                    child: const Text('push'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return uid;
  }

  testWidgets('the account changes: the sheet is gone, nothing is left over', (tester) async {
    final uid = await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BlurSheet), findsOneWidget);
    uid.set(null);
    await tester.pumpAndSettle();
    expect(find.byType(BlurSheet), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'the page beneath, untouched');
  });

  testWidgets('deep in a flow — a second view in the same sheet — it still goes', (tester) async {
    final uid = await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deeper'));
    await tester.pumpAndSettle();
    expect(find.text('Deeper?'), findsOneWidget);
    uid.set('someone-else');
    await tester.pumpAndSettle();
    expect(find.byType(BlurSheet), findsNothing);
  });

  testWidgets('with a page pushed over it, the sheet goes and the page stays', (tester) async {
    final uid = await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(find.byType(BlurSheet));
    Navigator.of(sheetContext).push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('a page on top'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('a page on top'), findsOneWidget);
    uid.set(null);
    await tester.pumpAndSettle();
    expect(find.byType(BlurSheet), findsNothing);
    expect(find.text('a page on top'), findsOneWidget, reason: 'only the sheet went');
  });

  testWidgets('the same account, re-read: nothing happens', (tester) async {
    final uid = await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    uid.set('me');
    await tester.pumpAndSettle();
    expect(find.byType(BlurSheet), findsOneWidget);
  });
}

class _Uid extends Notifier<String?> {
  _Uid(this.initial);
  final String? initial;
  @override
  String? build() => initial;
  void set(String? uid) => state = uid;
}

final _uidProvider = NotifierProvider<_Uid, String?>(() => _Uid(null));
