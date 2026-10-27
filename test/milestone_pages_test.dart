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

  group('what the ring says', () {
    final p = post(
      photos: [photo('crossing', session: 2), photo('early', session: 0), photo('lost')],
      segments: sessions,
      unit: SegmentUnit.session,
    );

    test('the hours on the cover', () {
      expect(ringCentre(milestonePages(p).first, p), (figure: '20', unit: 'hours'));
      expect(sessionOf(milestonePages(p).first, p), isNull);
    });

    test('a photo\'s session: its length over its day', () {
      final pages = milestonePages(p);
      expect(sessionOf(pages[1], p), 2);
      expect(ringCentre(pages[1], p), (figure: '1h 20m', unit: '9 Oct'));
      expect(sessionOf(pages[2], p), 0);
      expect(ringCentre(pages[2], p), (figure: '2h', unit: '6 Oct'));
    });

    test('a photo with no session says the hours, as the cover does', () {
      final pages = milestonePages(p);
      expect(sessionOf(pages[3], p), isNull);
      expect(ringCentre(pages[3], p), (figure: '20', unit: 'hours'));
    });

    test('an old post says the hours on every page', () {
      final old = post(photos: [photo('a', session: 1), photo('b')]);
      for (final page in milestonePages(old)) {
        expect(ringCentre(page, old).figure, '20');
      }
    });

    test('the no-photo frame says the hours', () {
      final none = post(photos: const [], segments: sessions, unit: SegmentUnit.session);
      expect(ringCentre(milestonePages(none).single, none), (figure: '20', unit: 'hours'));
    });
  });

  test('a session\'s date reads "6 Oct"', () {
    expect(segmentDate(sessions[0]), '6 Oct');
    expect(
      segmentDate(PostSegment(at: DateTime(2026, 5, 31).millisecondsSinceEpoch, seconds: 1)),
      '31 May',
    );
  });
}
