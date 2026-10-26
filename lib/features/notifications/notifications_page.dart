import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../core/utils/relative_time.dart';
import '../feed/posts_repository.dart';
import '../feed/single_post_screen.dart';
import '../friends/friends_repository.dart';
import '../friends/models/friendship.dart';
import '../profile/other_profile_screen.dart';
import '../profile/profile_action_bar.dart';
import 'notifications_repository.dart';
import 'notifications_view.dart';

/// The word at the top of the Feed: "Notifications", with a dot when there
/// is something new. Quiet grey when there is nothing, white when there
/// is. Tapping it opens the page and marks everything seen.
class NotificationsEntry extends ConsumerWidget {
  const NotificationsEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final unread = ref.watch(hasUnreadNotificationsProvider);
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openNotifications(context, ref),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 8 * scale),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w600,
                  color: unread ? tokens.textPrimary : tokens.textTertiary,
                ),
              ),
              if (unread) ...[
                SizedBox(width: 6 * scale),
                Container(
                  width: 6 * scale,
                  height: 6 * scale,
                  decoration: BoxDecoration(
                    color: tokens.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openNotifications(BuildContext context, WidgetRef ref) {
  ref.read(notificationsRepositoryProvider)?.markSeen();
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const NotificationsPage()),
  );
}

/// Everything written to me, newest first, by day.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  /// Requests accepted from this page, so their rows can say so.
  final Set<String> _accepted = {};
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final items = ref.watch(myNotificationsProvider).value ?? const <AppNotification>[];
    final now = DateTime.now();
    final rows = rowsOf(items, now: now);

    final children = <Widget>[];
    NotificationGroup? group;
    for (final row in rows) {
      final g = groupOf(row.at, now);
      if (g != group) {
        group = g;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              24 * scale,
              children.isEmpty ? 0 : kSpacingSection * scale,
              24 * scale,
              kSpacingPair * scale,
            ),
            child: Text(
              groupTitle(g),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textTertiary,
              ),
            ),
          ),
        );
      }
      children.add(_row(context, row, scale));
    }

    return Scaffold(
      body: SafeArea(
        child: rows.isEmpty
            ? Center(
                child: Text(
                  'Nothing yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textTertiary,
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsets.symmetric(vertical: kSpacingSection * scale),
                children: children,
              ),
      ),
      // Back where the tab bar's centre slot is, as every pushed page.
      bottomNavigationBar: ProfileActionBar(
        slots: [
          null,
          ProfileBarSlot(
            label: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          null,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, NotificationRow row, double scale) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final n = row.lead;
    final accepted = _accepted.contains(n.id);
    final text = accepted ? acceptedText(n.actorHandle) : rowText(row);
    final isRequest = n.type == NotificationType.request && !accepted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context, row),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24 * scale,
          vertical: kSpacingPair * scale,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14 * scale,
                    color: tokens.textSecondary,
                  ),
                  children: [
                    if (!accepted)
                      TextSpan(
                        text: '${n.actorHandle} ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    TextSpan(text: text),
                  ],
                ),
              ),
            ),
            SizedBox(width: kSpacingBase * scale),
            if (isRequest)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy == n.id ? null : () => _accept(n),
                child: Text(
                  'Accept',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              )
            else
              Text(
                RelativeTime.of(row.at),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  color: tokens.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(AppNotification n) async {
    final friends = ref.read(friendsRepositoryProvider);
    if (friends == null) return;
    setState(() => _busy = n.id);
    try {
      await friends.accept(Friendship.pairId(friends.uid, n.actorUid));
      if (mounted) setState(() => _accepted.add(n.id));
    } catch (e) {
      debugPrint('SONDR accept from notifications: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _open(BuildContext context, NotificationRow row) async {
    final n = row.lead;
    switch (destinationOf(n.type)) {
      case NotificationDestination.profile:
        openProfile(context, ref, n.actorUid, handle: n.actorHandle, displayName: '');
      case NotificationDestination.post:
        final id = n.postId;
        final repo = ref.read(postsRepositoryProvider);
        if (id == null || repo == null) return;
        final post = await repo.fetchPost(id);
        if (post == null || !context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SinglePostScreen(post: post)),
        );
    }
  }
}
