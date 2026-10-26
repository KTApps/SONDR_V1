import 'package:flutter/foundation.dart';

import '../../core/utils/date.dart';
import 'notifications_repository.dart';

/// What the page shows: notices grouped by day, likes on one post within a
/// day folded into one line, and where a tap goes. Pure, so every rule is
/// tested without a widget.

enum NotificationGroup { today, yesterday, earlier }

/// One line on the page — a notice, or several likes folded into one.
@immutable
class NotificationRow {
  const NotificationRow({
    required this.lead,
    required this.others,
    required this.at,
  });

  /// The notice shown — for a folded line, the newest of them.
  final AppNotification lead;

  /// How many more liked the same post that day.
  final int others;
  final DateTime at;

  NotificationType get type => lead.type;
}

/// Where a tap on a row goes.
enum NotificationDestination { post, profile }

NotificationDestination destinationOf(NotificationType type) => switch (type) {
  NotificationType.like ||
  NotificationType.comment ||
  NotificationType.reply ||
  NotificationType.milestone => NotificationDestination.post,
  NotificationType.request ||
  NotificationType.accepted ||
  NotificationType.invite => NotificationDestination.profile,
};

NotificationGroup groupOf(DateTime at, DateTime now) {
  final day = DayKey.of(at);
  if (day == DayKey.of(now)) return NotificationGroup.today;
  if (day == DayKey.of(DateTime(now.year, now.month, now.day - 1))) {
    return NotificationGroup.yesterday;
  }
  return NotificationGroup.earlier;
}

String groupTitle(NotificationGroup g) => switch (g) {
  NotificationGroup.today => 'Today',
  NotificationGroup.yesterday => 'Yesterday',
  NotificationGroup.earlier => 'Earlier',
};

/// Newest first, likes on the same post within one day folded into the
/// newest of them. Items with no time yet (a local write) are shown first.
List<NotificationRow> rowsOf(List<AppNotification> items, {required DateTime now}) {
  final sorted = [...items]..sort((a, b) {
    final x = a.at, y = b.at;
    if (x == null && y == null) return 0;
    if (x == null) return -1;
    if (y == null) return 1;
    return y.compareTo(x);
  });
  final out = <NotificationRow>[];
  final likeIndex = <String, int>{}; // "day|post" → index in out
  for (final n in sorted) {
    final at = n.at ?? now;
    if (n.type == NotificationType.like && n.postId != null) {
      final key = '${DayKey.of(at)}|${n.postId}';
      final i = likeIndex[key];
      if (i != null) {
        final r = out[i];
        out[i] = NotificationRow(lead: r.lead, others: r.others + 1, at: r.at);
        continue;
      }
      likeIndex[key] = out.length;
    }
    out.add(NotificationRow(lead: n, others: 0, at: at));
  }
  return out;
}

/// The words after the handle, sentence case.
String rowText(NotificationRow row) {
  final n = row.lead;
  return switch (n.type) {
    NotificationType.request => 'wants to be friends',
    NotificationType.accepted => 'accepted your request',
    NotificationType.like =>
      row.others == 0
          ? 'liked your post'
          : 'and ${row.others} ${row.others == 1 ? 'other' : 'others'} liked your post',
    NotificationType.comment => 'commented on your post',
    NotificationType.reply => 'replied to your comment',
    NotificationType.milestone =>
      'reached ${n.hours ?? 0} hours of ${n.taskName ?? 'a task'}',
    NotificationType.invite => 'joined from your invite',
  };
}

/// After the request in a row has been accepted.
String acceptedText(String handle) => "You're now friends with $handle";
