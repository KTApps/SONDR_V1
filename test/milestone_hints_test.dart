import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/milestone_hints.dart';

/// The one-time hint: three posts, or until the right side is tapped.
void main() {
  test('shows on the first three multi-photo posts, and on those again', () {
    const fresh = MilestoneHintState();
    expect(fresh.showFor('a'), isTrue);
    const three = MilestoneHintState(seen: ['a', 'b', 'c']);
    expect(three.showFor('a'), isTrue, reason: 'one it was shown on');
    expect(three.showFor('d'), isFalse, reason: 'a fourth gets none');
    const two = MilestoneHintState(seen: ['a', 'b']);
    expect(two.showFor('c'), isTrue, reason: 'room for a third');
  });

  test('never again once the right side has been tapped', () {
    const tapped = MilestoneHintState(seen: ['a'], tapped: true);
    expect(tapped.showFor('a'), isFalse);
    expect(tapped.showFor('b'), isFalse);
  });

  test('the store counts to three and stops; a tap is for good', () async {
    final hints = MemoryMilestoneHints();
    for (final id in ['a', 'b', 'c', 'd']) {
      await hints.markSeen(id);
    }
    expect((await hints.read()).seen, ['a', 'b', 'c']);
    await hints.markSeen('a');
    expect((await hints.read()).seen, ['a', 'b', 'c'], reason: 'no duplicates');
    await hints.markTapped();
    expect((await hints.read()).tapped, isTrue);
    expect((await hints.read()).showFor('a'), isFalse);
  });
}
