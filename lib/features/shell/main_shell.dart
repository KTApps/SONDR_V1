import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../feed/feed_screen.dart';
import '../profile/profile_screen.dart';
import '../timer/timer_controller.dart';
import '../timer/timer_screen.dart';
import 'how_it_works.dart';

/// The selected bottom-tab index (0 Home · 1 Posts · 2 Profile). A provider so a
/// flow can jump the shell to a tab — e.g. landing on Posts after creating a
/// milestone post — not just the tab bar's own taps.
class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<SelectedTab, int>(SelectedTab.new);

/// Root tab shell: Home · Posts · Profile. Introduced in step 2, it replaces the
/// phase-1 top-right buttons on the timer with a bottom [NavigationBar].
///
/// An [IndexedStack] keeps each tab alive so the running timer (and any scroll
/// position) survives tab switches. While a session runs — and while it is
/// being stopped — the bar is hidden and the shell is held on Home. A paused
/// session lets go, so the tabs work; resuming brings Home forward again,
/// whether from Home or from the Lock Screen.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, @visibleForTesting this.tabs});

  static const _tabs = [TimerScreen(), FeedScreen(), ProfileScreen()];

  /// Stand-ins for the three screens, so a test can hold the shell without
  /// the Firebase each of them wants.
  final List<Widget>? tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(
      timerControllerProvider.select((t) => t.holdsHome),
    );
    final index = ref.watch(selectedTabProvider);
    // A session that starts running — Start, Resume, or a Resume from the
    // Lock Screen read on the way back in — brings Home forward, so letting
    // go on the next pause lands there rather than on the tab left behind.
    ref.listen(timerControllerProvider.select((t) => t.holdsHome), (was, now) {
      if (now && was != true) ref.read(selectedTabProvider.notifier).set(0);
    });

    return Scaffold(
      // Held on Home while the session runs, never another tab caught
      // behind the hidden bar.
      body: IndexedStack(index: held ? 0 : index, children: tabs ?? _tabs),
      // Slim, text-only tab bar (no icons) — reclaims vertical space and keeps
      // the minimal greyscale identity.
      bottomNavigationBar: held
          ? null
          : TextTabBar(
              currentIndex: index,
              onSelect: (i) => ref.read(selectedTabProvider.notifier).set(i),
            ),
    );
  }
}

/// A minimal text-only bottom tab bar: "Home · Posts · Profile" as labels, no
/// icons. Public only so a test can pump it without the three tab screens
/// (and the Firebase each of them wants) coming with it. The selected tab is brighter (white, bold) with a short underline;
/// unselected tabs are dim grey. Pure greyscale, surface-toned, and slim.
class TextTabBar extends StatelessWidget {
  const TextTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const List<String> _labels = ['Home', 'Posts', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Material(
      color: tokens.background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  // A GestureDetector, not an InkWell. Material ink draws a
                  // HIGHLIGHT across the whole of its bounds as well as the
                  // ripple, and the bounds here are the full tab cell — so a
                  // tap flashed a grey rectangle over the tab. Switching tabs
                  // is instant and the selected tab already says so with its
                  // weight and underline; there is nothing for a ripple to
                  // report.
                  //
                  // `opaque` keeps the tap target exactly what it was: the
                  // whole cell, label and padding alike, not just the glyphs.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    // Held: how this tab works. The tap is unchanged.
                    onLongPress: () {
                      HapticFeedback.lightImpact();
                      showHowToSheet(context, HowToTab.values[i]);
                    },
                    child: _TabLabel(
                      text: _labels[i],
                      selected: i == currentIndex,
                      style: theme.textTheme.labelLarge,
                      activeColor: tokens.textPrimary,
                      inactiveColor: tokens.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.text,
    required this.selected,
    required this.style,
    required this.activeColor,
    required this.inactiveColor,
  });

  final String text;
  final bool selected;
  final TextStyle? style;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: style?.copyWith(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? activeColor : inactiveColor,
          ),
        ),
        const SizedBox(height: 4),
        // Short underline only under the selected tab.
        Container(
          height: 2,
          width: 16,
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}
