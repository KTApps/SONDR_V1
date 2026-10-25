import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/story_builder.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/session_log.dart';

/// What a milestone post stores about its band: sessions when the log
/// covers the band, days when it does not, and which segment each photo
/// belongs to.
void main() {
  const h = 3600;
  Photo photo(int at, {String day = '2026-10-02'}) => Photo(
    taskId: 't',
    taskName: 'Spanish',
    dayKey: day,
    timestamp: at * 1000, // micros
    sessionSeconds: 0,
    photoUrl: 'u',
    storagePath: 'p',
  );

  test('a covered band is told by session', () {
    const task = Task(
      id: 't',
      name: 'Spanish',
      secondsByDay: {'2026-10-01': 8 * h, '2026-10-02': 12 * h},
    );
    final log = [
      const SessionRecord(taskId: 't', at: 1_000_000, seconds: 8 * h),
      const SessionRecord(taskId: 't', at: 5_000_000, seconds: 12 * h),
    ];
    final story = buildMilestoneStory(
      task: task,
      log: log,
      milestoneHours: 20,
      photos: [photo(5_000_000 + 12 * h * 1000 + 1000)],
    );
    expect(story.unit, SegmentUnit.session);
    expect(story.segments.map((s) => s.seconds), [8 * h, 12 * h]);
    expect(story.photoIndices, [1]);
    expect(story.segments[1].photo, isTrue);
    expect(story.segments[0].photo, isFalse);
  });

  test('a band the log does not reach back to is told by day', () {
    const task = Task(
      id: 't',
      name: 'Spanish',
      secondsByDay: {'2026-10-01': 8 * h, '2026-10-02': 12 * h},
    );
    // Only the last session was logged.
    final log = [const SessionRecord(taskId: 't', at: 5_000_000, seconds: 12 * h)];
    final story = buildMilestoneStory(
      task: task,
      log: log,
      milestoneHours: 20,
      photos: [photo(0, day: '2026-10-02')],
    );
    expect(story.unit, SegmentUnit.day);
    expect(story.segments.map((s) => s.seconds), [8 * h, 12 * h]);
    // By day, a photo belongs to its own day.
    expect(story.photoIndices, [1]);
  });

  test('a photo that lands on no segment keeps no index', () {
    const task = Task(id: 't', name: 'Spanish', secondsByDay: {'2026-10-01': 20 * h});
    final log = [const SessionRecord(taskId: 't', at: 5_000_000, seconds: 20 * h)];
    final story = buildMilestoneStory(
      task: task,
      log: log,
      milestoneHours: 20,
      photos: [photo(1_000)], // before the session began
    );
    expect(story.unit, SegmentUnit.session);
    expect(story.photoIndices, [null]);
  });

  test('a session post\'s seconds into the band', () {
    expect(bandSecondsAfter(5 * h), 5 * h);
    expect(bandSecondsAfter(25 * h), 5 * h);
  });
}
