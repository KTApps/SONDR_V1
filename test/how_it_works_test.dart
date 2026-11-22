import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/more_sheet.dart';
import 'package:sondr/features/shell/how_it_works.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/shared/blur_sheet.dart';

/// Holding a tab's name says how that tab works; More says it for all
/// three. A tap on a tab still only switches it.
void main() {
  // The 13 Pro: 390 × 844 logical, the reference phone.
  const w = 390.0, h = 844.0;

  late List<String> haptics;

  Future<void> pumpBar(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(child: Text('tab ${ref.watch(selectedTabProvider)}')),
              bottomNavigationBar: TextTabBar(
                currentIndex: ref.watch(selectedTabProvider),
                onSelect: ref.read(selectedTabProvider.notifier).set,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(of: find.byType(TextTabBar), matching: find.text(label));

  group('the words', () {
    test('each line starts with its lead phrase, as written', () {
      expect([for (final l in kHowHomeWorks) l.text], [
        'Pick a task at the top, then Start.',
        "Outer ring: today's time, split by task. Tap the centre for this month.",
        'Inner ring: tap it for your habits.',
        'Lock your phone: the timer keeps going.',
        'Stop to take a photo. Every 20 hours is a milestone.',
        'Swipe a task left to rename or archive it.',
      ]);
      expect([for (final l in kHowFeedWorks) l.text], [
        "Your friends' posts, newest first.",
        'Tap the right side of a milestone to see each photo, the left to go back.',
        'Tap a caption to read all of it.',
        'Hold your own post to delete it.',
        'Notifications are at the top right.',
      ]);
      expect([for (final l in kHowProfileWorks) l.text], [
        'Tap your photo to change it.',
        'Your total hours, streak and milestones.',
        'Milestones: tap one to see its photos.',
        'In progress: how close each task is to its next 20 hours.',
        'More has settings, camera access and sign out.',
      ]);
      expect([for (final l in [...kHowHomeWorks, ...kHowFeedWorks, ...kHowProfileWorks]) l.lead], [
        'Pick a task', 'Outer ring:', 'Inner ring:', 'Lock your phone:', 'Stop', 'Swipe a task left',
        "Your friends' posts", 'Tap the right side', 'Tap a caption', 'Hold your own post', 'Notifications',
        'Tap your photo', 'Your total hours', 'Milestones:', 'In progress:', 'More',
      ]);
    });
  });

  group('a long-press on a tab', () {
    for (final (label, title, lines) in [
      ('Home', 'How Home works', kHowHomeWorks),
      ('Feed', 'How Feed works', kHowFeedWorks),
      ('Profile', 'How Profile works', kHowProfileWorks),
    ]) {
      testWidgets('on $label opens "$title", with a light haptic, and switches nothing', (tester) async {
        await pumpBar(tester);
        await tester.longPress(tab(label));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        for (final l in lines) {
          expect(find.text(l.text, findRichText: true), findsOneWidget);
        }
        expect(find.text('tab 0'), findsOneWidget, reason: 'the tab did not change');
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
      });
    }

    testWidgets('a tap still switches tabs, and opens nothing', (tester) async {
      await pumpBar(tester);
      await tester.tap(tab('Feed'));
      await tester.pumpAndSettle();
      expect(find.text('tab 1'), findsOneWidget);
      expect(find.byType(BlurSheet), findsNothing);
      expect(haptics, isEmpty);
    });

    testWidgets('the lead in the text tone and bold, the rest in the supporting tone; left-aligned, 12 apart', (tester) async {
      await pumpBar(tester);
      await tester.longPress(tab('Home'));
      await tester.pumpAndSettle();
      final first = find.text(kHowHomeWorks[0].text, findRichText: true);
      final second = find.text(kHowHomeWorks[1].text, findRichText: true);
      final tokens = GreyscaleTokens.of(tester.element(first));
      final scale = figmaScale(tester.element(first));
      final rich = tester.widget<RichText>(first);
      // Text.rich wraps the line in a span carrying the merged style.
      final span = rich.text as TextSpan;
      final line = span.children!.single as TextSpan;
      final lead = line.children!.first as TextSpan;
      final rest = line.children!.last as TextSpan;
      expect(lead.text, 'Pick a task');
      expect(lead.style!.color, tokens.textPrimary);
      expect(lead.style!.fontWeight, FontWeight.w700);
      expect(rest.style, isNull, reason: 'the line\'s own style');
      expect(span.style!.color, tokens.textSecondary);
      expect(span.style!.fontSize, closeTo(kBlurExplanationSize * scale, 0.01));
      expect(rich.textAlign, TextAlign.left);
      final a = tester.getRect(first), b = tester.getRect(second);
      expect(a.left, closeTo(b.left, 0.01));
      expect(a.left, closeTo(kBlurSideInset * scale, 0.5), reason: 'the sheet\'s column');
      expect(b.top - a.bottom, closeTo(kHowToLineGap * scale, 0.5));
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts each sheet fits on the 13 Pro without clipping', (tester) async {
        for (final (label, lines) in [('Home', kHowHomeWorks), ('Feed', kHowFeedWorks), ('Profile', kHowProfileWorks)]) {
          await pumpBar(tester, textScale: ts);
          await tester.longPress(tab(label));
          await tester.pumpAndSettle();
          final scale = figmaScale(tester.element(find.byType(BlurSheet)));
          final title = tester.getRect(find.text('How $label works'));
          final top = tester.getRect(find.text(lines.first.text, findRichText: true));
          final bottom = tester.getRect(find.text(lines.last.text, findRichText: true));
          final back = tester.getRect(find.text('Back'));
          expect(top.top, greaterThan(title.bottom), reason: '$label under its title');
          expect(top.top, greaterThanOrEqualTo(kBlurListTop * scale - 0.5), reason: '$label in the list area');
          expect(bottom.bottom, lessThanOrEqualTo(kBlurListBottom * scale + 0.5), reason: '$label above the exit');
          expect(bottom.bottom, lessThan(back.top));
          // Nothing scrolled away: every line is on screen as it stands.
          final scroll = tester.state<ScrollableState>(find.descendant(of: find.byType(BlurSheet), matching: find.byType(Scrollable)).first);
          expect(scroll.position.maxScrollExtent, 0, reason: '$label needs no scrolling at $ts');
          expect(tester.takeException(), isNull);
          // ignore: avoid_print
          print('HOWTO $label ts=$ts title.bottom=${title.bottom.toStringAsFixed(1)} first.top=${top.top.toStringAsFixed(1)} last.bottom=${bottom.bottom.toStringAsFixed(1)} back.top=${back.top.toStringAsFixed(1)}');
          await tester.tap(find.text('Back'));
          await tester.pumpAndSettle();
        }
      });
    }
  });

  group('How sondr works, in More', () {
    Future<void> openMore(WidgetTester tester, {double textScale = 1.0}) async {
      tester.view.physicalSize = const Size(w * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () => showMoreSheet(context, ref, signedIn: true),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a row after Camera access, in the pages\' style', (tester) async {
      await openMore(tester);
      final row = find.text(kHowSondrWorks);
      expect(row, findsOneWidget);
      expect(tester.getRect(row).top, greaterThan(tester.getRect(find.textContaining('Camera access')).bottom));
      expect(tester.getRect(row).bottom, lessThan(tester.getRect(find.text('Sign out')).top));
      expect(tester.widget<Text>(row).style, tester.widget<Text>(find.text('Terms')).style);
    });

    testWidgets('opens the three sets under Home, Feed and Profile', (tester) async {
      await openMore(tester);
      await tester.tap(find.text(kHowSondrWorks));
      await tester.pumpAndSettle();
      expect(find.text(kHowSondrWorks), findsOneWidget, reason: 'the title now');
      final home = tester.getRect(find.text('Home'));
      final feed = tester.getRect(find.text('Feed'));
      final profile = tester.getRect(find.text('Profile'));
      expect(home.top, lessThan(feed.top));
      expect(feed.top, lessThan(profile.top));
      expect(find.text(kHowHomeWorks.first.text, findRichText: true), findsOneWidget);
      expect(find.text(kHowProfileWorks.last.text, findRichText: true), findsOneWidget);
      expect(find.text('Support'), findsNothing, reason: 'in place of the list');
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts it scrolls if it must, and reaches the last line', (tester) async {
        await openMore(tester, textScale: ts);
        await tester.tap(find.text(kHowSondrWorks));
        await tester.pumpAndSettle();
        final last = find.text(kHowProfileWorks.last.text, findRichText: true);
        await tester.scrollUntilVisible(last, 40, scrollable: find.descendant(of: find.byType(BlurSheet), matching: find.byType(Scrollable)).first);
        await tester.pumpAndSettle();
        final scale = figmaScale(tester.element(last));
        expect(tester.getRect(last).bottom, lessThanOrEqualTo(kBlurListBottom * scale + 0.5));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
