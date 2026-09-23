import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Height of the shell's text-only tab bar — see `_TextTabBar` in
/// `lib/features/shell/main_shell.dart`.
const double kTabBarHeight = 40;

/// The Figma reference canvas.
const double kRefWidth = 393;
const double kRefHeight = 852;

/// Safe-area insets of the reference device (iPhone 15 Pro).
const double kRefTopInset = 59;
const double kRefBottomInset = 34;

/// The height a tab screen's body ACTUALLY gets, which is not the screen
/// height and not the safe area either.
///
/// A fit check that forgets the tab bar is wrong by 40 and reads comfortable
/// when the page is overflowing — that mistake cost two rounds on Profile. The
/// shell's tab bar sits in its own `SafeArea`, so it eats its own height plus
/// the bottom inset before the body is measured; the screen's own `SafeArea`
/// then removes only the top inset.
///
///     852 − (40 tab bar + 34 bottom inset) = 778 body
///     778 − 59 top inset                   = 719 inside SafeArea
///
/// Subtract the screen's own page padding from that to get the column budget.
double refBodyHeight() => kRefHeight - (kTabBarHeight + kRefBottomInset);

/// Height available inside a tab screen's [SafeArea], before its own padding.
double refSafeAreaHeight() => refBodyHeight() - kRefTopInset;

/// Points the tester at the reference canvas with the reference insets.
///
/// Note this sizes the WHOLE screen: pump the shell, or subtract
/// [kTabBarHeight] yourself when pumping a tab screen in isolation, or the
/// budget will be 40 too generous.
void useReferenceViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(kRefWidth * 3, kRefHeight * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(
    top: kRefTopInset * 3,
    bottom: kRefBottomInset * 3,
  );
  addTearDown(tester.view.reset);
}
