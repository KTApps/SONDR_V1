import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/friends_screen.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/profile/profile_photo.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// Choosing a profile photo: the square copy, where the choice is kept and
/// published, the picker sheet, and the face it puts on a search result.
void main() {
  Photo photo(int ts, {String task = 't'}) => Photo(
    taskId: task,
    taskName: 'Golf',
    dayKey: '2026-11-0${ts % 9 + 1}',
    timestamp: ts,
    sessionSeconds: 600,
    photoUrl: 'https://example.invalid/$ts.jpg',
    storagePath: 'users/me/photos/${task}_$ts.jpg',
  );

  group('the copy', () {
    test('is the centred square of the photo, 600 across, as a JPEG', () {
      // A 3:4 capture: black above and below the middle square, white in it.
      final source = img.Image(width: 300, height: 400);
      img.fill(source, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(source, x1: 0, y1: 50, x2: 299, y2: 349, color: img.ColorRgb8(255, 255, 255));
      final out = squareProfileJpeg(Uint8List.fromList(img.encodePng(source)))!;
      expect(out.sublist(0, 2), [0xFF, 0xD8], reason: 'a JPEG');
      final back = img.decodeJpg(out)!;
      expect(back.width, kProfilePhotoSize);
      expect(back.height, kProfilePhotoSize);
      expect(kProfilePhotoSize, 600);
      // The black bands were cut away: top and bottom rows are white.
      for (final y in [2, 300, 597]) {
        expect(back.getPixel(300, y).r, greaterThan(200), reason: 'row $y');
      }
    });

    test('bytes that are not an image are refused', () {
      expect(squareProfileJpeg(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('the chooser', () {
    late FakeFirebaseFirestore db;
    late _Files files;
    late int published;
    late int changed;
    late FirebaseProfilePhotoChooser chooser;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.doc('users/me/meta/profile').set({'username': 'ada', 'displayName': 'Ada'});
      files = _Files();
      published = 0;
      changed = 0;
      chooser = FirebaseProfilePhotoChooser(
        uid: 'me',
        profiles: ProfileRepository(db),
        files: files,
        publish: () async => published++,
        changed: () => changed++,
        square: (b) async => Uint8List.fromList([0xFF, 0xD8, ...b]),
      );
    });

    Future<Map<String, dynamic>> profileDoc() async =>
        (await db.doc('users/me/meta/profile').get()).data()!;

    test('a photo already taken: read from its original, copied, recorded, published', () async {
      final p = photo(1);
      expect(await chooser.choose(p), isTrue);
      expect(files.read, [p.storagePath]);
      expect(files.stored.keys, ['users/me/profile/photo.jpg']);
      final doc = await profileDoc();
      expect(doc['photoUrl'], 'https://storage.invalid/users/me/profile/photo.jpg');
      expect(doc['photoPath'], 'users/me/profile/photo.jpg');
      expect(doc['photoSourceId'], p.id);
      expect(doc['username'], 'ada', reason: 'the rest of the profile untouched');
      expect(changed, 1);
      expect(published, 1);
      final read = Profile.fromMap('me', doc);
      expect(read.photoUrl, doc['photoUrl']);
      expect(read.photoSourceId, p.id);
    });

    test('a shot just taken: its own bytes, no read', () async {
      expect(await chooser.choose(photo(2), bytes: Uint8List.fromList([9])), isTrue);
      expect(files.read, isEmpty);
      expect(files.stored.values.single, [0xFF, 0xD8, 9]);
    });

    test('a failed upload records nothing and publishes nothing', () async {
      files.failPut = true;
      expect(await chooser.choose(photo(3)), isFalse);
      expect((await profileDoc()).containsKey('photoUrl'), isFalse);
      expect(published, 0);
    });

    test('the newest again: the choice forgotten, published, the copy taken down', () async {
      await chooser.choose(photo(4));
      expect(await chooser.clear(), isTrue);
      final doc = await profileDoc();
      expect(doc.containsKey('photoUrl'), isFalse);
      expect(doc.containsKey('photoPath'), isFalse);
      expect(doc.containsKey('photoSourceId'), isFalse);
      expect(files.removed, ['users/me/profile/photo.jpg']);
      expect(published, 2);
      expect(Profile.fromMap('me', doc).photoUrl, isNull);
    });

    test('the original deleted later leaves the copy', () async {
      final p = photo(5);
      await chooser.choose(p);
      // The private photo goes; nothing here touches the profile's file.
      await db.doc('users/me/photos/${p.id}').delete();
      expect(files.removed, isEmpty);
      expect((await profileDoc())['photoUrl'], isNotNull);
    });
  });

  group('the sheet', () {
    late _Chooser chooser;
    final photos = [for (var i = 6; i >= 1; i--) photo(i)];

    Future<void> open(WidgetTester tester, {String? chosen}) async {
      final before = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = before);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      chooser = _Chooser();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profilePhotoChooserProvider.overrideWithValue(chooser),
            profilePhotoChoicesProvider.overrideWith((ref) async => photos),
            currentProfileProvider.overrideWith(
              (ref) async => Profile(
                uid: 'me',
                username: 'ada',
                displayName: 'Ada',
                photoUrl: chosen == null ? null : 'https://x/p.jpg',
                photoPath: chosen == null ? null : 'users/me/profile/photo.jpg',
                photoSourceId: chosen,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(currentProfileProvider);
                  return Center(
                    child: TextButton(
                      onPressed: () => showProfilePhotoSheet(context, ref),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder cell(Photo p) => find.byKey(ValueKey('profile-photo-${p.id}'));
    Color? tone(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style?.color;
    Border? ringOf(WidgetTester tester, Photo p) {
      final box = tester.widget<DecoratedBox>(find.descendant(of: cell(p), matching: find.byType(DecoratedBox)).first);
      return (box.decoration as BoxDecoration).border as Border?;
    }

    testWidgets('titled, your photos three across as circles, newest first, the chosen one ringed', (tester) async {
      await open(tester, chosen: photos[1].id);
      expect(find.text(kProfilePhotoTitle), findsOneWidget);
      final a = tester.getRect(cell(photos[0]));
      final b = tester.getRect(cell(photos[1]));
      final c = tester.getRect(cell(photos[2]));
      final d = tester.getRect(cell(photos[3]));
      expect(a.top, b.top);
      expect(b.top, c.top);
      expect(d.top, greaterThan(a.bottom), reason: 'the fourth starts the next row');
      expect(a.left, lessThan(b.left));
      expect(a.width, closeTo(a.height, 0.01));
      expect(find.descendant(of: cell(photos[0]), matching: find.byType(ClipOval)), findsOneWidget);
      final ring = ringOf(tester, photos[1])!;
      expect(ring.top.width, 2);
      expect(ring.top.color, const Color(0xFFFAFAFA));
      expect(ringOf(tester, photos[0]), isNull);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('Use this photo is grey and inert until a different one is picked', (tester) async {
      await open(tester, chosen: photos[1].id);
      final tokens = GreyscaleTokens.of(tester.element(find.text(kUseThisPhoto)));
      expect(tone(tester, kUseThisPhoto), tokens.textTertiary);
      await tester.tap(find.text(kUseThisPhoto));
      await tester.pumpAndSettle();
      expect(chooser.chosen, isEmpty);

      await tester.tap(cell(photos[3]));
      await tester.pumpAndSettle();
      expect(ringOf(tester, photos[3]), isNotNull);
      expect(ringOf(tester, photos[1]), isNull);
      expect(tone(tester, kUseThisPhoto), tokens.textPrimary);
      await tester.tap(find.text(kUseThisPhoto));
      await tester.pumpAndSettle();
      expect(chooser.chosen, [photos[3].id]);
      expect(find.text(kProfilePhotoTitle), findsNothing, reason: 'done, and closed');
    });

    testWidgets('Use my newest photo clears the choice, in the supporting tone', (tester) async {
      await open(tester, chosen: photos[1].id);
      final tokens = GreyscaleTokens.of(tester.element(find.text(kUseMyNewestPhoto)));
      expect(tone(tester, kUseMyNewestPhoto), tokens.textSecondary);
      expect(tone(tester, kTakeANewOne), tokens.textPrimary);
      await tester.tap(find.text(kUseMyNewestPhoto));
      await tester.pumpAndSettle();
      expect(chooser.cleared, 1);
      expect(find.text(kProfilePhotoTitle), findsNothing);
    });

    testWidgets('with nothing chosen there is nothing to clear', (tester) async {
      await open(tester);
      expect(find.text(kUseMyNewestPhoto), findsNothing);
      expect(find.text(kUseThisPhoto), findsOneWidget);
      expect(find.text(kTakeANewOne), findsOneWidget);
      for (final p in photos) {
        expect(ringOf(tester, p), isNull);
      }
    });

    testWidgets('a failure says so and keeps the sheet', (tester) async {
      await open(tester);
      chooser.ok = false;
      await tester.tap(cell(photos[0]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kUseThisPhoto));
      await tester.pumpAndSettle();
      expect(find.text(kProfilePhotoFailed), findsOneWidget);
      expect(find.text(kProfilePhotoTitle), findsOneWidget);
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts the answers clear the grid and Back', (tester) async {
        await open(tester, chosen: photos[0].id);
        tester.platformDispatcher.textScaleFactorTestValue = ts;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        final lastRow = tester.getRect(cell(photos[5]));
        final use = tester.getRect(find.text(kUseThisPhoto));
        final newest = tester.getRect(find.text(kUseMyNewestPhoto));
        final back = tester.getRect(find.text('Back'));
        expect(use.top, greaterThan(lastRow.bottom));
        expect(newest.bottom, lessThan(back.top));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a search result', () {
    Future<void> search(WidgetTester tester, {PublicProfile? published, bool friends = false}) async {
      final before = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = before);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final db = FakeFirebaseFirestore();
      await db.doc('usernames/cass').set({'uid': 'u_cass'});
      final repo = FriendsRepository(db: db, uid: 'me', pruner: _NoPrune());
      await tester.pumpWidget(ProviderScope(overrides: [
        currentUidProvider.overrideWithValue('me'),
        friendsRepositoryProvider.overrideWithValue(repo),
        currentProfileProvider.overrideWith((ref) async => const Profile(uid: 'me', username: 'ada', displayName: 'Ada')),
        blockedAccountsProvider.overrideWith((ref) => Stream.value(const <Block>[])),
        friendshipsProvider.overrideWith((ref) => Stream.value(friends
            ? const [
                Friendship(
                  id: 'me_u_cass',
                  users: ['me', 'u_cass'],
                  requestedBy: 'me',
                  status: FriendshipStatus.accepted,
                  profiles: {
                    'me': FriendIdentity(username: 'ada', displayName: 'Ada'),
                    'u_cass': FriendIdentity(username: 'cass', displayName: 'Cass'),
                  },
                ),
              ]
            : const <Friendship>[])),
        publicProfileProvider.overrideWith((ref, uid) async => uid == 'u_cass' ? published : null),
      ], child: MaterialApp(theme: AppTheme.dark(), home: const FriendsScreen())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ca');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    Finder avatar() => find.byType(SearchResultAvatar);
    // The row's own padding is the first one around the circle.
    Rect row(WidgetTester tester) =>
        tester.getRect(find.ancestor(of: avatar(), matching: find.byType(Padding)).first);

    const cassPhoto = PublicProfile(
      uid: 'u_cass', handle: 'cass', displayName: 'Cass', hours: 3,
      photoUrl: 'https://example.invalid/cass.jpg', photoPath: 'users/u_cass/profile/photo.jpg',
    );

    testWidgets('shows the photo they chose, clipped to the circle, cover', (tester) async {
      await search(tester, published: cassPhoto);
      final photo = tester.widget<SondrPhoto>(find.descendant(of: avatar(), matching: find.byType(SondrPhoto)));
      expect(photo.url, 'https://example.invalid/cass.jpg');
      expect(photo.fit, BoxFit.cover);
      expect(find.descendant(of: avatar(), matching: find.byType(ClipOval)), findsOneWidget);
    });

    // The pre-branch measurements on the 13 Pro (390x844, scale 0.9906).
    for (final withPhoto in [true, false]) {
      final label = withPhoto ? 'with a photo' : 'without one';
      testWidgets('$label: circle 35.66, handle at 71.32, Add row 61.59', (tester) async {
        await search(tester, published: withPhoto ? cassPhoto : null);
        final a = tester.getRect(avatar());
        expect(a.width, closeTo(35.66, 0.01));
        expect(a.height, closeTo(35.66, 0.01));
        expect(tester.getRect(find.text('cass')).left, closeTo(71.32, 0.01));
        expect(row(tester).height, closeTo(61.59, 0.01));
      });

      testWidgets('$label: a Friends row is 55.47', (tester) async {
        await search(tester, published: withPhoto ? cassPhoto : null, friends: true);
        expect(find.text('Friends'), findsWidgets);
        expect(tester.getRect(avatar()).width, closeTo(35.66, 0.01));
        expect(row(tester).height, closeTo(55.47, 0.01));
      });
    }

    testWidgets('without one, the same empty circle as before — no initial', (tester) async {
      await search(tester, published: const PublicProfile(uid: 'u_cass', handle: 'cass', displayName: 'Cass', hours: 3));
      expect(find.descendant(of: avatar(), matching: find.byType(SondrPhoto)), findsNothing);
      expect(find.descendant(of: avatar(), matching: find.byType(Text)), findsNothing);
      final box = tester.widget<Container>(find.descendant(of: avatar(), matching: find.byType(Container)));
      expect((box.decoration! as BoxDecoration).shape, BoxShape.circle);
    });
  });
}

class _Files implements ProfilePhotoFiles {
  final List<String> read = [];
  final Map<String, Uint8List> stored = {};
  final List<String> removed = [];
  bool failPut = false;

  @override
  Future<Uint8List?> bytesOf(Photo photo) async {
    read.add(photo.storagePath);
    return Uint8List.fromList([1]);
  }

  @override
  Future<String> put(String path, Uint8List jpeg) async {
    if (failPut) throw StateError('no network');
    stored[path] = jpeg;
    return 'https://storage.invalid/$path';
  }

  @override
  Future<void> remove(String path) async => removed.add(path);
}

class _Chooser implements ProfilePhotoChooser {
  final List<String> chosen = [];
  int cleared = 0;
  bool ok = true;

  @override
  Future<bool> choose(Photo photo, {Uint8List? bytes}) async {
    if (ok) chosen.add(photo.id);
    return ok;
  }

  @override
  Future<bool> clear() async {
    cleared++;
    return ok;
  }
}

class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}
