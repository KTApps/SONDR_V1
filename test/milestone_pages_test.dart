import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/milestone_pages.dart';
import 'package:sondr/features/feed/models/post.dart';

/// What a milestone card steps through, and what the ring says on each.
void main() {
  const author = PostAuthor(username: 'cass', displayName: 'Cass');

  PostPhoto photo(String id, {int? session}) =>
      PostPhoto(url: 'https://x/$id.jpg', storagePath: id, sessionIndex: session);

  MilestonePost post({
    required List<PostPhoto> photos,
    List<PostSegment> segments = const [],
    SegmentUnit? unit,
  }) => MilestonePost(
    id: 'm',
    authorUid: 'u',
    author: author,
    createdAt: DateTime(2026, 10, 6),
    caption: null,
    photos: photos,
    taskName: 'Spanish',
    milestoneHours: 20,
    totalHours: 20,
    segments: segments,
    unit: unit,
  );

  final sessions = [
    PostSegment(at: DateTime(2026, 10, 6, 9).millisecondsSinceEpoch, seconds: 7200, photo: true),
    PostSegment(at: DateTime(2026, 10, 7, 18).millisecondsSinceEpoch, seconds: 2400),
    PostSegment(at: DateTime(2026, 10, 9, 7).millisecondsSinceEpoch, seconds: 4800, photo: true),
  ];

  group('the pages', () {
    test('the cover, then every photo in STORED order', () {
      // Stored newest-first: the pages follow the store, as the collage does.
      final p = post(
        photos: [photo('crossing', session: 2), photo('early', session: 0)],
        segments: sessions,
        unit: SegmentUnit.session,
      );
      expect(milestonePages(p), const [
        MilestonePage(MilestonePageKind.cover),
        MilestonePage(MilestonePageKind.photo, photoIndex: 0),
        MilestonePage(MilestonePageKind.photo, photoIndex: 1),
      ]);
    });

    test('one photo is the cover alone; none is the frame', () {
      expect(milestonePages(post(photos: [photo('a')])), const [
        MilestonePage(MilestonePageKind.cover),
      ]);
      expect(milestonePages(post(photos: const [])), const [
        MilestonePage(MilestonePageKind.noPhoto),
      ]);
    });

    test('an old post with several photos pages through them too', () {
      final p = post(photos: [photo('a'), photo('b'), photo('c')]);
      expect(milestonePages(p), hasLength(4));
      expect(milestonePages(p).first.kind, MilestonePageKind.cover);
    });
  });

  group('what a page says of its session', () {
    final p = post(
      photos: [photo('crossing', session: 2), photo('early', session: 0), photo('lost')],
      segments: sessions,
      unit: SegmentUnit.session,
    );

    test('the cover: the task alone, no ring', () {
      expect(pageSession(milestonePages(p).first, p), isNull);
      expect(pageTaskLine(milestonePages(p).first, p), 'Spanish');
      expect(sessionOf(milestonePages(p).first, p), isNull);
    });

    test('a photo\'s session: the band before it, its own length, and the task line with the length', () {
      final pages = milestonePages(p);
      expect(sessionOf(pages[1], p), 2);
      expect(pageSession(pages[1], p), (before: 7200 + 2400, seconds: 4800));
      expect(pageTaskLine(pages[1], p), 'Spanish · 1h 20m');
      expect(sessionOf(pages[2], p), 0);
      expect(pageSession(pages[2], p), (before: 0, seconds: 7200));
      expect(pageTaskLine(pages[2], p), 'Spanish · 2h');
    });

    test('a photo with no session: the task alone, no ring', () {
      final pages = milestonePages(p);
      expect(sessionOf(pages[3], p), isNull);
      expect(pageSession(pages[3], p), isNull);
      expect(pageTaskLine(pages[3], p), 'Spanish');
    });

    test('an old post: the task alone on every page', () {
      final old = post(photos: [photo('a', session: 1), photo('b')]);
      for (final page in milestonePages(old)) {
        expect(pageSession(page, old), isNull);
        expect(pageTaskLine(page, old), 'Spanish');
      }
    });

    test('the no-photo frame: the task alone', () {
      final none = post(photos: const [], segments: sessions, unit: SegmentUnit.session);
      expect(pageTaskLine(milestonePages(none).single, none), 'Spanish');
    });
  });
}
