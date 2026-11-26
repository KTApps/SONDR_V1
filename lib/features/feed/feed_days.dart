import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_format.dart';
import '../../core/utils/relative_time.dart';
import 'models/post.dart';

/// The Posts tab as days: each friend's photos from the last 24 hours on
/// one card, and every milestone on a card of its own. Pure, so the
/// grouping, the order and the lines are tested without a widget.

/// How long a photo stays in the feed after it was posted.
const Duration kFeedDay = Duration(hours: 24);

/// How often the last day is asked for again while the app is open.
const Duration kFeedRefresh = Duration(minutes: 5);

/// How many milestones a page of the feed reads.
const int kMilestonePageSize = 20;

/// The clock the feed reads. A provider so a test can hold it still.
final feedNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// When a post sorts, and how old it is. A post whose server time has not
/// come back yet is the one just written here: it is now.
DateTime feedTimeOf(Post post, DateTime now) => post.createdAt ?? now;

/// The last day's posts and the paged milestones as one list, newest
/// first. A milestone in both appears once.
List<Post> mergeFeedPosts(
  List<Post> recent,
  List<Post> milestones, {
  required DateTime now,
}) {
  final seen = <String>{};
  final all = <Post>[
    for (final p in [...recent, ...milestones])
      if (seen.add(p.id)) p,
  ];
  all.sort((a, b) => feedTimeOf(b, now).compareTo(feedTimeOf(a, now)));
  return all;
}

/// One card in the feed.
sealed class FeedItem {
  const FeedItem();

  /// Where it sorts: a day by its newest photo, a milestone by its own.
  DateTime timeAt(DateTime now);

  /// What keys it in the list.
  String get key;
}

/// One person's last 24 hours: their photos, newest first.
@immutable
class DayItem extends FeedItem {
  const DayItem(this.posts);

  final List<SessionPost> posts;

  String get authorUid => posts.first.authorUid;
  PostAuthor get author => posts.first.author;

  @override
  DateTime timeAt(DateTime now) => feedTimeOf(posts.first, now);

  @override
  String get key => 'day-$authorUid';
}

@immutable
class MilestoneItem extends FeedItem {
  const MilestoneItem(this.post);

  final MilestonePost post;

  @override
  DateTime timeAt(DateTime now) => feedTimeOf(post, now);

  @override
  String get key => 'milestone-${post.id}';
}

/// The cards: a day per person from their posts of the last [kFeedDay],
/// newest first within the day; every milestone on its own. Ordered by
/// time, a day by its newest post — so a new post brings its person's day
/// to the top. A post older than a day is not shown; a day with none left
/// is gone.
List<FeedItem> feedItems(List<Post> posts, {required DateTime now}) {
  final cutoff = now.subtract(kFeedDay);
  final days = <String, List<SessionPost>>{};
  final items = <FeedItem>[];
  for (final p in posts) {
    switch (p) {
      case final MilestonePost m:
        items.add(MilestoneItem(m));
      case final SessionPost s:
        if (!feedTimeOf(s, now).isAfter(cutoff)) continue;
        days.putIfAbsent(s.authorUid, () => []).add(s);
    }
  }
  for (final day in days.values) {
    day.sort((a, b) => feedTimeOf(b, now).compareTo(feedTimeOf(a, now)));
    items.add(DayItem(day));
  }
  items.sort((a, b) => b.timeAt(now).compareTo(a.timeAt(now)));
  return items;
}

/// How long ago, as the line above a card says it: "20m ago", or "now".
String timeSince(DateTime when, {required DateTime now}) {
  final at = RelativeTime.of(when, now: now);
  return at == 'now' ? at : '$at ago';
}

/// The line above a day: "3 photos · 4h 30m · 20m ago".
String dayLine(DayItem day, {required DateTime now}) {
  final n = day.posts.length;
  final seconds = day.posts.fold<int>(0, (sum, p) => sum + p.sessionSeconds);
  return [
    n == 1 ? '1 photo' : '$n photos',
    DurationFormat.hm(Duration(seconds: seconds)),
    timeSince(day.timeAt(now), now: now),
  ].join(' · ');
}

/// The line above a milestone: "Guitar · 4w ago". The ring says the hours.
String milestoneLine(MilestonePost post, {required DateTime now}) =>
    '${post.taskName} · ${timeSince(feedTimeOf(post, now), now: now)}';

/// The name above a card: the handle without "@", or the name they gave.
String feedName(PostAuthor author) {
  final handle = author.username.startsWith('@')
      ? author.username.substring(1)
      : author.username;
  return handle.isNotEmpty ? handle : author.displayName;
}
