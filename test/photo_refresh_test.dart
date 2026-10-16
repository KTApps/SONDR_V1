import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_refresh.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/shared/cached_photo.dart';

/// A saved photo shows up without restarting the app.
///
/// Every photo surface reads a one-shot FutureProvider. They are autoDispose,
/// which would clear a provider nobody watches — but the shell keeps all
/// three tabs alive in an IndexedStack so the running timer survives a tab
/// switch, so Profile is always watching and its cache was never dropped.
/// A photo saved after the first look at Profile did not appear until the
/// process died.
void main() {
  Photo photo(String id) => Photo(
    taskId: 't',
    taskName: 'Spanish',
    dayKey: '2026-10-15',
    timestamp: int.parse(id),
    sessionSeconds: 600,
    photoUrl: 'https://example.test/$id.jpg',
    storagePath: 'p/$id',
  );

  testWidgets('the newest capture reaches the screen on invalidation', (
    tester,
  ) async {
    // What the "repository" would return, and how often it was asked.
    var newest = photo('1');
    var reads = 0;

    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryPreviewProvider.overrideWith((ref) async {
            reads++;
            return (recent: <Photo>[newest], total: reads);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              final recent =
                  ref.watch(galleryPreviewProvider).value?.recent ??
                  const <Photo>[];
              return Scaffold(
                body: recent.isEmpty
                    ? const Text('none')
                    : SondrPhoto(url: recent.first.photoUrl),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String shownUrl() =>
        tester.widget<SondrPhoto>(find.byType(SondrPhoto)).url;
    expect(shownUrl(), contains('/1.jpg'));
    expect(reads, 1);

    // A photo is saved. Without the invalidation the screen keeps the first
    // read for the life of the process.
    newest = photo('2');
    await tester.pumpAndSettle();
    expect(shownUrl(), contains('/1.jpg'), reason: 'it refreshed by itself?');

    invalidatePhotoViews(captured);
    await tester.pumpAndSettle();
    expect(shownUrl(), contains('/2.jpg'), reason: 'the emblem is still stale');
    expect(reads, 2);
  });

  testWidgets('the strip and the collages are refreshed too', (tester) async {
    var collages = <Collage>[];
    var strip = <Photo>[];
    var collageReads = 0;
    var stripReads = 0;

    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collagesListProvider.overrideWith((ref) async {
            collageReads++;
            return collages;
          }),
          collagePhotosProvider.overrideWith((ref, ids) async {
            stripReads++;
            return strip;
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              ref.watch(collagesListProvider);
              ref.watch(collagePhotosProvider('a,b'));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(collageReads, 1);
    expect(stripReads, 1);

    collages = [
      const Collage(
        taskId: 't',
        milestoneHours: 20,
        photoIds: ['1'],
        edited: false,
      ),
    ];
    strip = [photo('1')];
    invalidatePhotoViews(captured);
    await tester.pumpAndSettle();

    expect(collageReads, 2, reason: 'the Milestones strip is stale');
    expect(stripReads, 2, reason: 'the strip photos are stale');
  });
}
