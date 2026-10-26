import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/delete_photo.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

Photo _photo(int ts, {int? milestone}) => Photo(
      taskId: 't', taskName: 'Piano', dayKey: '2025-10-09', timestamp: ts,
      sessionSeconds: 45 * 60, photoUrl: 'https://x/$ts.jpg', storagePath: 'p/$ts',
      cumulativeSeconds: 3 * 3600, milestoneHours: milestone,
    );

/// A deleter that remembers: which collage each photo sat in, what it was
/// asked to remove, what it was asked to delete — and, if told to, holds
/// the delete until released.
class _FakeDeleter implements PhotoDeleter {
  _FakeDeleter({Map<String, int> inCollage = const {}, this.hold})
      : inCollage = Map.of(inCollage);
  final Map<String, int> inCollage; // photo id → milestone hours
  final Completer<void>? hold;
  final removed = <String>[];
  final deleted = <String>[];

  @override
  Future<int?> milestoneHoursOf(Photo photo) async => inCollage[photo.id];
  @override
  Future<void> removeFromCollages(Photo photo) async {
    removed.add(photo.id);
    inCollage.remove(photo.id);
  }
  @override
  Future<void> deletePhoto(Photo photo) async {
    if (hold != null) await hold!.future;
    deleted.add(photo.id);
  }
}

void main() {
  group('the prompt', () {
    test('names the milestone the photo sits in, or the task alone', () {
      expect(
        deletePhotoBody(_photo(1), milestoneHours: 20),
        "It will be removed from Piano's 20h milestone. This can't be undone.",
      );
      expect(
        deletePhotoBody(_photo(1), milestoneHours: null),
        "It will be removed from Piano. This can't be undone.",
      );
    });
  });

  group('deleting from the viewer', () {
    setUp(() => photoImageProviderFactory = (_) => MemoryImage(tinyPng));

    Future<void> open(
      WidgetTester tester,
      List<Photo> photos,
      int index,
      _FakeDeleter deleter,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [photoDeleterProvider.overrideWithValue(deleter)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPhotoViewer(context, photos: photos, index: index),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, naming the milestone; Delete removes the doc and the collage membership, then advances', (
      tester,
    ) async {
      final set = [_photo(1), _photo(2), _photo(3)];
      final deleter = _FakeDeleter(inCollage: {set[1].id: 20});
      await open(tester, set, 1, deleter);
      expect(find.text('2 of 3'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this photo?'), findsOneWidget);
      expect(
        find.text("It will be removed from Piano's 20h milestone. This can't be undone."),
        findsOneWidget,
      );
      expect(deleter.deleted, isEmpty, reason: 'nothing goes before the answer');

      await tester.tap(find.text('Delete').last); // the prompt's
      await tester.pumpAndSettle();
      expect(deleter.removed, [set[1].id]);
      expect(deleter.deleted, [set[1].id]);
      expect(deleter.inCollage, isEmpty, reason: 'out of its collage');
      // On to what was next: the set is now two, and we are on its second.
      final viewer = tester.widget<PhotoViewer>(find.byType(PhotoViewer));
      expect(viewer, isNotNull);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('Delete this photo?'), findsNothing);
    });

    testWidgets('a photo in no collage is removed from the task alone', (tester) async {
      final deleter = _FakeDeleter();
      await open(tester, [_photo(1), _photo(2)], 0, deleter);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text("It will be removed from Piano. This can't be undone."),
        findsOneWidget,
      );
    });

    testWidgets('the last photo gone, the viewer closes', (tester) async {
      final deleter = _FakeDeleter();
      await open(tester, [_photo(1)], 0, deleter);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleter.deleted, [_photo(1).id]);
      expect(find.byType(PhotoViewer), findsNothing);
    });

    testWidgets('Cancel touches nothing and stays put', (tester) async {
      final set = [_photo(1), _photo(2), _photo(3)];
      final deleter = _FakeDeleter(inCollage: {set[1].id: 20});
      await open(tester, set, 1, deleter);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(deleter.removed, isEmpty);
      expect(deleter.deleted, isEmpty);
      expect(deleter.inCollage, {set[1].id: 20});
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget, reason: 'not busy');
    });

    testWidgets('while the delete runs the action reads Deleting…', (tester) async {
      final hold = Completer<void>();
      final deleter = _FakeDeleter(hold: hold);
      await open(tester, [_photo(1), _photo(2)], 0, deleter);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Deleting…'), findsNothing, reason: 'a question, not yet a deletion');
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Deleting…'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('Deleting…'), findsNothing);
      expect(deleter.deleted, [_photo(1).id]);
    });
  });
}
