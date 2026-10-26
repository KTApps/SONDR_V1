import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/audience_widen.dart';

/// Letting a new friend into what was posted before they were one.
void main() {
  const me = 'me';
  late _Audiences store;
  late Set<String> blocked;

  AudienceWidener widener() => AudienceWidener(
    uid: me,
    audiences: store,
    blocked: () async => blocked,
  );

  setUp(() {
    blocked = {};
    store = _Audiences(
      posts: {
        'posts/p1': [me, 'old'],
        'posts/p2': [me, 'old', 'new'],
      },
      comments: {
        'posts/p1/comments/c1': ('posts/p1', [me, 'old']),
        // My comment on somebody else's post — follows THAT post.
        'posts/x9/comments/c2': ('posts/x9', [me, 'other']),
      },
      others: {'posts/x9': [me, 'other']},
    );
  });

  test('a new friend is added to every post that lacks them', () async {
    await widener().widenFor({'new'});
    expect(store.posts['posts/p1'], [me, 'old', 'new']);
    expect(store.posts['posts/p2'], [me, 'old', 'new'], reason: 'already in');
    expect(store.postBatches, 1);
  });

  test('my comments follow their posts, exactly', () async {
    await widener().widenFor({'new'});
    expect(store.comments['posts/p1/comments/c1']!.$2, [me, 'old', 'new']);
    // The other person's post did not change, so neither does my comment on it.
    expect(store.comments['posts/x9/comments/c2']!.$2, [me, 'other']);
  });

  test('running it again changes nothing', () async {
    await widener().widenFor({'new'});
    final after = store.snapshot();
    final batches = store.postBatches + store.commentBatches;
    await widener().widenFor({'new'});
    expect(store.snapshot(), after);
    expect(store.postBatches + store.commentBatches, batches);
  });

  test('the launch reconcile fixes drift for everyone at once', () async {
    await widener().widenFor({'old', 'new', 'newer'});
    expect(store.posts['posts/p1'], [me, 'old', 'new', 'newer']);
    expect(store.posts['posts/p2'], [me, 'old', 'new', 'newer']);
  });

  test('someone I have blocked is never let in', () async {
    blocked = {'new'};
    await widener().widenFor({'new'});
    expect(store.posts['posts/p1'], [me, 'old']);
    expect(store.postBatches, 0);
  });

  test('myself and nobody are not additions', () async {
    await widener().widenFor({me, ''});
    expect(store.postBatches, 0);
  });

  test('large sets are batched under the limit', () async {
    store = _Audiences(
      posts: {for (var i = 0; i < 1000; i++) 'posts/p$i': [me]},
      comments: const {},
      others: const {},
    );
    await widener().widenFor({'new'});
    expect(store.postBatches, 3);
    expect(store.largestBatch, lessThanOrEqualTo(AudienceWidener.batchLimit));
  });
}

class _Audiences implements WidenableAudiences {
  _Audiences({
    required this.posts,
    required Map<String, (String, List<String>)> comments,
    required this.others,
  }) : comments = {for (final e in comments.entries) e.key: (e.value.$1, [...e.value.$2])};

  final Map<String, List<String>> posts;
  final Map<String, (String postPath, List<String> audience)> comments;

  /// Posts that are not mine, by path.
  final Map<String, List<String>> others;

  int postBatches = 0;
  int commentBatches = 0;
  int largestBatch = 0;

  Map<String, Object> snapshot() => {
    'posts': {for (final e in posts.entries) e.key: [...e.value]},
    'comments': {for (final e in comments.entries) e.key: [...e.value.$2]},
  };

  @override
  Future<List<OwnPost>> myPosts() async => [
    for (final e in posts.entries) OwnPost(path: e.key, audience: [...e.value]),
  ];

  @override
  Future<List<OwnComment>> myComments() async => [
    for (final e in comments.entries)
      OwnComment(path: e.key, postPath: e.value.$1, audience: [...e.value.$2]),
  ];

  @override
  Future<List<String>> audienceOf(String postPath) async =>
      [...?(posts[postPath] ?? others[postPath])];

  @override
  Future<void> addToPosts(List<(String, List<String>)> updates) async {
    postBatches++;
    if (updates.length > largestBatch) largestBatch = updates.length;
    for (final (path, add) in updates) {
      final a = posts[path]!;
      for (final u in add) {
        if (!a.contains(u)) a.add(u);
      }
    }
  }

  @override
  Future<void> setComments(List<(String, List<String>)> updates) async {
    commentBatches++;
    for (final (path, audience) in updates) {
      comments[path] = (comments[path]!.$1, [...audience]);
    }
  }
}
