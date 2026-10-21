import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/features/photos/photo_viewer_text.dart';
import 'package:sondr/shared/cached_photo.dart';

Photo _photo({
  int session = 45 * 60,
  int? cumulative = 3 * 3600 + 200,
  int? milestone,
  int ts = 1_760_000_000_000_000,
  String task = 'Piano',
}) => Photo(
      taskId: 't', taskName: task, dayKey: '2025-10-09', timestamp: ts,
      sessionSeconds: session, photoUrl: 'https://x/$ts.jpg', storagePath: 'p',
      cumulativeSeconds: cumulative, milestoneHours: milestone,
    );

void main() {
  // 2025-10-09 08:53:20 UTC, in the test's local zone.
  final when = DateTime.fromMicrosecondsSinceEpoch(1_760_000_000_000_000);
  String h24(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String h12(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }

  group('the three lines', () {
    test('line 1: task and session length, hours and minutes', () {
      expect(viewerLine1(_photo(session: 45 * 60)), 'Piano · 45m');
      expect(viewerLine1(_photo(session: 80 * 60)), 'Piano · 1h 20m');
      expect(viewerLine1(_photo(session: 2 * 3600)), 'Piano · 2h');
    });

    test('line 1 without a session length is the task alone, never 0m', () {
      expect(viewerLine1(_photo(session: 0)), 'Piano');
      expect(viewerLine1(_photo(session: 30)), 'Piano');
    });

    test('line 2: date, device-format time, and the hours on the task', () {
      final p = _photo(cumulative: 3 * 3600 + 200);
      expect(viewerLine2(p, time: h24), '${viewerDate(when)}, ${h24(when)} · 3h on Piano');
      expect(viewerLine2(p, time: h12), '${viewerDate(when)}, ${h12(when)} · 3h on Piano');
      expect(viewerDate(DateTime(2025, 10, 14)), 'Tue 14 Oct');
    });

    test('line 2 says <1h under an hour, and drops the hours when unknown', () {
      expect(viewerLine2(_photo(cumulative: 1800), time: h24), endsWith(' · <1h on Piano'));
      expect(viewerLine2(_photo(cumulative: null), time: h24), '${viewerDate(when)}, ${h24(when)}');
    });

    test('line 3 only for a crossing photo', () {
      expect(viewerLine3(_photo(milestone: 20)), 'Milestone photo · 20h');
      expect(viewerLine3(_photo()), isNull);
    });

    test('the counter only for a set of more than one', () {
      expect(viewerCounter(2, 7), '3 of 7');
      expect(viewerCounter(0, 1), isNull);
    });
  });

  group('the viewer', () {
    setUp(() {
      // Nothing on the network in a test: a tiny decodable stand-in.
      photoImageProviderFactory = (_) => MemoryImage(_tinyPng);
    });

    Future<void> open(WidgetTester tester, List<Photo> photos, int index) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPhotoViewer(context, photos: photos, index: index),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the start index and swipes in set order', (tester) async {
      final set = [_photo(ts: 1), _photo(ts: 2), _photo(ts: 3)];
      await open(tester, set, 1);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);

      // A page-width drag each way: the next photo, then back.
      final width = tester.getSize(find.byType(PageView)).width;
      await tester.drag(find.byType(PageView), Offset(-width, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), Offset(width, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), Offset(width, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('a set of one shows no counter, and Close leaves', (tester) async {
      await open(tester, [_photo()], 0);
      expect(find.textContaining(' of '), findsNothing);
      expect(find.text('Delete'), findsNothing, reason: 'no delete handler, no Delete');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewer), findsNothing);
    });

    testWidgets('the photo is shown in full colour', (tester) async {
      await open(tester, [_photo()], 0);
      final shown = tester.widget<SondrPhoto>(find.byType(SondrPhoto).first);
      expect(shown.saturation, isNull);
    });
  });
}

final _tinyPng = Uint8List.fromList(const [
  0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
  0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
  0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0xF8,0xCF,0xC0,0x00,
  0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
  0x44,0xAE,0x42,0x60,0x82,
]);
