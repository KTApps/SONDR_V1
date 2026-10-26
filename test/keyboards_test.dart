import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/friends_screen.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/shared/sondr_field.dart';

/// Two fields that open ready to type, say what they take, and let a pull
/// on the list put the keyboard away.
void main() {
  group('the comments sheet', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('me'),
            postCommentsProvider.overrideWith(
              (ref, postId) => AsyncValue.data([
                Comment(
                  id: 'c1',
                  authorUid: 'them',
                  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
                  text: 'hi',
                  createdAt: DateTime(2026, 10, 1),
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showCommentsSheet(context, 'p1'),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens with the field focused and its placeholder', (tester) async {
      await open(tester);
      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.autofocus, isTrue);
      expect(field.hint, 'Add a comment');
      expect(field.textInputAction, TextInputAction.done);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ??
            FocusManager.instance.primaryFocus != null,
        isTrue,
      );
    });

    testWidgets('pulling the list puts the keyboard away', (tester) async {
      await open(tester);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
    });
  });

  group('add friends', () {
    testWidgets('opens with the handle field focused, says what it takes, '
        'and the lists dismiss on drag', (tester) async {
      final db = FakeFirebaseFirestore();
      final repo = FriendsRepository(db: db, uid: 'me', pruner: _NoPrune());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('me'),
            friendsRepositoryProvider.overrideWithValue(repo),
            currentProfileProvider.overrideWith(
              (ref) async =>
                  const Profile(uid: 'me', username: 'ada', displayName: 'Ada'),
            ),
            blockedAccountsProvider.overrideWith(
              (ref) => Stream.value(const <Block>[]),
            ),
            friendshipsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const FriendsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.autofocus, isTrue);
      expect(field.hint, 'Their handle');
      expect(field.textInputAction, TextInputAction.done);
      expect(FocusManager.instance.primaryFocus, isNotNull);

      for (final list in tester.widgetList<ListView>(find.byType(ListView))) {
        expect(list.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
      }
    });
  });
}

class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}
