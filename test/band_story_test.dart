import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/tasks/session_log.dart';

/// The arithmetic a milestone story is built from.
void main() {
  const h = 3600;
  SessionRecord s(int at, int seconds) =>
      SessionRecord(taskId: 't', at: at, seconds: seconds);

  group('band coverage', () {
    test('a log that reaches the band start covers it', () {
      // Lifetime 20h, all of it logged: the first band is covered.
      final log = [for (var i = 0; i < 10; i++) s(i * 1000, 2 * h)];
      final out = sessionSegments(
        log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 20 * h,
      );
      expect(out, isNotNull);
      expect(out!.unit, SegmentUnit.session);
      expect(out.segments.length, 10);
      expect(out.totalSeconds, 20 * h);
    });

    test('a log that began mid-band does not cover it', () {
      // Lifetime 20h, only the last 8h logged: the first band is not
      // covered — 12h of it predate the log.
      final log = [for (var i = 0; i < 4; i++) s(i * 1000, 2 * h)];
      expect(
        sessionSegments(
          log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 20 * h,
        ),
        isNull,
      );
    });

    test('a log that began a minute late still covers (tolerance)', () {
      final log = [s(0, 20 * h - 30)];
      expect(
        sessionSegments(
          log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 20 * h,
        ),
        isNotNull,
      );
    });

    test('a log that began two minutes late does not', () {
      final log = [s(0, 20 * h - 120)];
      expect(
        sessionSegments(
          log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 20 * h,
        ),
        isNull,
      );
    });

    test('the second band is covered when the log began inside the first', () {
      // 40h lifetime; the log started at 15h — the band [20h, 40h) is whole.
      final log = [for (var i = 0; i < 5; i++) s(i * 1000, 5 * h)];
      final out = sessionSegments(
        log: log, bandStart: 20 * h, bandEnd: 40 * h, totalSeconds: 40 * h,
      );
      expect(out, isNotNull);
      expect(out!.totalSeconds, 20 * h);
    });
  });

  group('clipping at the band edges', () {
    test('a session straddling the start is cut to what fell in the band', () {
      // Unlogged 0; sessions: 18h then 4h → the second straddles 20h.
      final log = [s(0, 18 * h), s(1000, 4 * h)];
      final out = sessionSegments(
        log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 22 * h,
      )!;
      expect(out.segments.map((e) => e.seconds), [18 * h, 2 * h]);
      // And the next band gets the other 2h of it.
      final next = sessionSegments(
        log: log, bandStart: 20 * h, bandEnd: 40 * h, totalSeconds: 22 * h,
      )!;
      expect(next.segments.map((e) => e.seconds), [2 * h]);
    });

    test('sessions are laid down in time order whatever the log order', () {
      final log = [s(3000, h), s(1000, h), s(2000, h)];
      final out = sessionSegments(
        log: log, bandStart: 0, bandEnd: 20 * h, totalSeconds: 3 * h,
      )!;
      expect(out.segments.map((e) => e.at), [1000, 2000, 3000]);
    });
  });

  group('the day fallback', () {
    test('one segment per day, clipped to the band', () {
      final out = daySegments(
        secondsByDay: {
          '2026-10-01': 10 * h,
          '2026-10-02': 12 * h, // crosses 20h at 2h into this day
          '2026-10-03': 5 * h,
        },
        bandStart: 0,
        bandEnd: 20 * h,
      );
      expect(out.unit, SegmentUnit.day);
      expect(out.segments.map((e) => e.seconds), [10 * h, 10 * h]);
      expect(out.totalSeconds, 20 * h);
      expect(
        out.segments.first.at,
        DateTime(2026, 10, 1).millisecondsSinceEpoch,
      );
    });

    test('a later band starts where the earlier one stopped', () {
      final out = daySegments(
        secondsByDay: {'2026-10-01': 10 * h, '2026-10-02': 12 * h, '2026-10-03': 5 * h},
        bandStart: 20 * h,
        bandEnd: 40 * h,
      );
      expect(out.segments.map((e) => e.seconds), [2 * h, 5 * h]);
    });

    test('days are read in calendar order whatever the map order', () {
      final out = daySegments(
        secondsByDay: {'2026-10-03': h, '2026-10-01': h},
        bandStart: 0,
        bandEnd: 20 * h,
      );
      expect(
        out.segments.map((e) => e.at),
        [DateTime(2026, 10, 1), DateTime(2026, 10, 3)]
            .map((d) => d.millisecondsSinceEpoch),
      );
    });
  });

  group('photo → segment', () {
    test('by session: the last session that began before the photo', () {
      final segs = BandSegments(
        unit: SegmentUnit.session,
        segments: const [
          BandSegment(at: 1_000_000, seconds: h),
          BandSegment(at: 5_000_000, seconds: h),
          BandSegment(at: 9_000_000, seconds: h),
        ],
      );
      // Taken just after the second session ended: micros.
      final idx = segmentIndexForPhoto(
        photoTimestamp: (5_000_000 + h * 1000 + 30_000) * 1000,
        photoDayKey: 'x',
        segments: segs,
      );
      expect(idx, 1);
    });

    test('by session: a photo before every session belongs to none', () {
      final segs = BandSegments(
        unit: SegmentUnit.session,
        segments: const [BandSegment(at: 5_000_000, seconds: h)],
      );
      expect(
        segmentIndexForPhoto(
          photoTimestamp: 1_000_000 * 1000, photoDayKey: 'x', segments: segs,
        ),
        isNull,
      );
    });

    test('by day: its own day', () {
      final segs = BandSegments(
        unit: SegmentUnit.day,
        segments: [
          BandSegment(at: DateTime(2026, 10, 1).millisecondsSinceEpoch, seconds: h),
          BandSegment(at: DateTime(2026, 10, 2).millisecondsSinceEpoch, seconds: h),
        ],
      );
      expect(
        segmentIndexForPhoto(
          photoTimestamp: 0, photoDayKey: '2026-10-02', segments: segs,
        ),
        1,
      );
    });

    test('marking photos leaves the rest alone', () {
      const segs = [
        BandSegment(at: 1, seconds: 1),
        BandSegment(at: 2, seconds: 1),
      ];
      final marked = markPhotos(segs, [1, null, 7]);
      expect(marked.map((e) => e.photo), [false, true]);
    });
  });

  test('the band a milestone closed', () {
    expect(bandOf(20), (start: 0, end: 20 * h));
    expect(bandOf(60), (start: 40 * h, end: 60 * h));
  });
}
