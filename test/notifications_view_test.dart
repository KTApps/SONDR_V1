import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/notifications/notifications_repository.dart';
import 'package:sondr/features/notifications/notifications_view.dart';

/// What the notifications page shows, and the dot that leads to it.
void main() {
  final now = DateTime(2026, 10, 26, 18);
  AppNotification n(
    String id,
    NotificationType type, {
    DateTime? at,
    String? postId,
    String handle = 'cass',
    String? task,
    int? hours,
  }) => AppNotification(
    id: id,
    type: type,
    actorUid: 'u_$handle',
    actorHandle: handle,
    at: at ?? now,
    postId: postId,
    taskName: task,
    hours: hours,
  );

  group('grouping', () {
    test('today, yesterday, earlier', () {
      expect(groupOf(now.subtract(const Duration(hours: 1)), now), NotificationGroup.today);
      expect(groupOf(DateTime(2026, 10, 25, 23), now), NotificationGroup.yesterday);
      expect(groupOf(DateTime(2026, 10, 24, 23, 59), now), NotificationGroup.earlier);
      expect(groupTitle(NotificationGroup.earlier), 'Earlier');
    });
  });

  group('rows', () {
    test('newest first', () {
      final rows = rowsOf([
        n('a', NotificationType.comment, at: DateTime(2026, 10, 26, 9), postId: 'p'),
        n('b', NotificationType.accepted, at: DateTime(2026, 10, 26, 12)),
      ], now: now);
      expect(rows.map((r) => r.lead.id), ['b', 'a']);
    });

    test('likes on one post within a day fold into the newest', () {
      final rows = rowsOf([
        n('l1', NotificationType.like, at: DateTime(2026, 10, 26, 9), postId: 'p', handle: 'ann'),
        n('l2', NotificationType.like, at: DateTime(2026, 10, 26, 10), postId: 'p', handle: 'bea'),
        n('l3', NotificationType.like, at: DateTime(2026, 10, 26, 11), postId: 'p', handle: 'cass'),
        // Another post, and the same post on another day: separate lines.
        n('l4', NotificationType.like, at: DateTime(2026, 10, 26, 8), postId: 'q'),
        n('l5', NotificationType.like, at: DateTime(2026, 10, 25, 8), postId: 'p'),
      ], now: now);
      expect(rows.length, 3);
      expect(rows.first.lead.id, 'l3');
      expect(rows.first.others, 2);
      expect(rowText(rows.first), 'and 2 others liked your post');
      expect(rows[1].lead.id, 'l4');
      expect(rowText(rows[1]), 'liked your post');
      expect(rows[2].lead.id, 'l5');
    });

    test('one other is singular', () {
      final rows = rowsOf([
        n('l1', NotificationType.like, postId: 'p'),
        n('l2', NotificationType.like, at: now.subtract(const Duration(hours: 1)), postId: 'p'),
      ], now: now);
      expect(rowText(rows.single), 'and 1 other liked your post');
    });

    test('the copy, sentence case', () {
      String text(NotificationType t, {String? task, int? hours}) =>
          rowText(rowsOf([n('x', t, task: task, hours: hours)], now: now).single);
      expect(text(NotificationType.request), 'wants to be friends');
      expect(text(NotificationType.accepted), 'accepted your request');
      expect(text(NotificationType.comment), 'commented on your post');
      expect(text(NotificationType.reply), 'replied to your comment');
      expect(text(NotificationType.milestone, task: 'Spanish', hours: 20), 'reached 20 hours of Spanish');
      expect(text(NotificationType.invite), 'joined from your invite');
      expect(acceptedText('cass'), "You're now friends with cass");
    });

    test('where a tap goes', () {
      expect(destinationOf(NotificationType.like), NotificationDestination.post);
      expect(destinationOf(NotificationType.comment), NotificationDestination.post);
      expect(destinationOf(NotificationType.reply), NotificationDestination.post);
      expect(destinationOf(NotificationType.milestone), NotificationDestination.post);
      expect(destinationOf(NotificationType.request), NotificationDestination.profile);
      expect(destinationOf(NotificationType.accepted), NotificationDestination.profile);
      expect(destinationOf(NotificationType.invite), NotificationDestination.profile);
    });
  });

  group('the dot', () {
    test('anything newer than seenAt is new; nothing is nothing', () {
      final items = [n('a', NotificationType.like, at: DateTime(2026, 10, 26, 10), postId: 'p')];
      expect(hasUnread(items, null), isTrue);
      expect(hasUnread(items, DateTime(2026, 10, 26, 9)), isTrue);
      expect(hasUnread(items, DateTime(2026, 10, 26, 11)), isFalse);
      expect(hasUnread(const [], null), isFalse);
    });
  });
}
