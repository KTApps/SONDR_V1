import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Source;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/features/splash/boot_gate.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/shared/cached_photo.dart';

/// A cold start must paint Profile complete: the newest photo and the
/// strip read from the local cache, decoded behind the splash.
void main() {
  const photo = Photo(
    taskId: 't', taskName: 'T', dayKey: '2026-10-01', timestamp: 7,
    sessionSeconds: 60, photoUrl: 'https://x/hero.jpg', storagePath: 'p',
    cumulativeSeconds: 100,
  );

  group('local-first', () {
    test('the newest photo is answered from the cache, with no server wait', () async {
      final repo = _SourcePhotos(cache: [photo], server: [photo]);
      final c = ProviderContainer(
        overrides: [photosRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);

      final first = await c.read(galleryPreviewProvider.future);

      expect(first.map((p) => p.id), [photo.id]);
      expect(repo.cacheReads, 1, reason: 'answered from the cache');
      // The server is asked behind the answer, never before it.
      await Future<void>.delayed(Duration.zero);
      expect(repo.serverReads, 1);
      expect(repo.serverAwaitedBeforeAnswer, isFalse);
    });

    test('an empty cache asks the server outright', () async {
      final repo = _SourcePhotos(cache: const [], server: [photo]);
      final c = ProviderContainer(
        overrides: [photosRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);

      final first = await c.read(galleryPreviewProvider.future);

      expect(first.map((p) => p.id), [photo.id]);
      expect(repo.cacheReads, 1);
      expect(repo.serverReads, greaterThanOrEqualTo(1));
    });
  });

  group('the boot gate', () {
    Widget app({
      required Future<List<Photo>> Function(Ref) gallery,
      Future<void> Function(BuildContext, List<String>)? precache,
    }) =>
        ProviderScope(
          overrides: [
            // The shell's Profile tab, without Firebase: the same stand-ins
            // the profile page's own tests use.
            currentUidProvider.overrideWithValue('me'),
            authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
            currentProfileProvider.overrideWith(
              (ref) async => const Profile(uid: 'me', username: 'me', displayName: 'Me'),
            ),
            friendshipsProvider.overrideWith((ref) => Stream.value(const <Friendship>[])),
            sessionStoreProvider.overrideWithValue(_NoStore()),
            milestoneStripProvider.overrideWith((ref) async => const <MilestoneStripEntry>[]),
            galleryPreviewProvider.overrideWith(gallery),
            if (precache != null) bootPrecacheProvider.overrideWith((ref) => precache),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const BootGate()),
        );

    testWidgets('holds the splash for the precache, and no longer than its timeout', (
      tester,
    ) async {
      ignoreFirebaseAbsence();
      final never = Completer<void>();
      await tester.pumpWidget(app(
        gallery: (ref) async => [photo],
        precache: (context, urls) => never.future.timeout(kBootPrecacheTimeout, onTimeout: () {}),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('sondr'), findsOneWidget, reason: 'still decoding: splash');
      expect(find.byType(MainShell), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400)); // the fade
      expect(find.byType(MainShell), findsOneWidget, reason: 'timed out: lifted');
    });

    testWidgets('lifts as soon as the photos are decoded', (tester) async {
      ignoreFirebaseAbsence();
      var asked = <String>[];
      await tester.pumpWidget(app(
        gallery: (ref) async => [photo],
        precache: (context, urls) async => asked = urls,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MainShell), findsOneWidget);
      expect(asked, contains(photo.photoUrl), reason: 'the hero was asked for');
    });

    testWidgets('after boot, the hero photo is already in the image cache', (
      tester,
    ) async {
      ignoreFirebaseAbsence();
      // Stand in something decodable for the network provider.
      final tiny = Uint8List.fromList(const [
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
        0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0xF8,0xCF,0xC0,0x00,
        0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
        0x44,0xAE,0x42,0x60,0x82,
      ]);
      final was = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tiny);
      addTearDown(() => photoImageProviderFactory = was);
      resetPrecacheMemory();
      PaintingBinding.instance.imageCache.clear();

      await tester.pumpWidget(app(gallery: (ref) async => [photo]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MainShell), findsOneWidget);
      expect(
        PaintingBinding.instance.imageCache.containsKey(MemoryImage(tiny)),
        isTrue,
        reason: 'decoded behind the splash, so Profile paints it from memory',
      );
    });
  });
}

/// A photo store that answers by source and counts each.
class _SourcePhotos implements PhotosRepository {
  _SourcePhotos({required this.cache, required this.server});
  final List<Photo> cache;
  final List<Photo> server;
  int cacheReads = 0;
  int serverReads = 0;
  bool answered = false;
  bool serverAwaitedBeforeAnswer = false;

  @override
  Future<List<Photo>> photosRecentFrom(int limit, {Source source = Source.serverAndCache}) async {
    if (source == Source.cache) {
      cacheReads++;
      answered = true;
      return cache;
    }
    serverReads++;
    if (!answered) serverAwaitedBeforeAnswer = true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return server;
  }

  @override
  Future<List<Photo>> photosRecent(int limit) => photosRecentFrom(limit);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStore implements SessionStore {
  SessionClock? saved;
  @override
  Future<SessionClock?> read() async => saved;
  @override
  Future<void> write(SessionClock clock) async => saved = clock;
  @override
  Future<void> clear() async => saved = null;
}

/// The shell's Profile tab reaches FirebaseAuth for the account block; with
/// no Firebase in a test that block errors into its own subtree and nothing
/// else is affected. Keep that one error out of the test binding's ledger —
/// the same filter the profile page's own tests use.
void ignoreFirebaseAbsence() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('No Firebase App')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}
