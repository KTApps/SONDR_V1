import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/task_order.dart';

/// Tasks read in the order a person would look for them.
void main() {
  List<String> sorted(List<String> names) =>
      [...names]..sort(compareTaskNames);

  test('alphabetical, ignoring case', () {
    expect(
      sorted(['piano', 'Golf', 'spanish', 'Drawing']),
      ['Drawing', 'Golf', 'piano', 'spanish'],
    );
  });

  test('case differences do not reorder equal words', () {
    // Both spellings of the same word sit together, in a fixed order.
    final once = sorted(['piano', 'Piano', 'Golf']);
    final twice = sorted(['Piano', 'piano', 'Golf']);
    expect(once.first, 'Golf');
    expect(once, twice, reason: 'the order depends on the input order');
  });

  test('numbers compare as numbers, not as text', () {
    // The one place plain string order reliably surprises people: "10"
    // sorts before "9" because "1" is before "9".
    expect(
      sorted(['Test 10', 'Test 9', 'Test 1', 'Test 100', 'Test 20']),
      ['Test 1', 'Test 9', 'Test 10', 'Test 20', 'Test 100'],
    );
  });

  test('numbers inside a name, and more than one', () {
    expect(
      sorted(['Week 2 day 10', 'Week 2 day 2', 'Week 10 day 1']),
      ['Week 2 day 2', 'Week 2 day 10', 'Week 10 day 1'],
    );
  });

  test('leading zeros do not change the value', () {
    expect(sorted(['Task 007', 'Task 8', 'Task 6']).first, 'Task 6');
    expect(sorted(['Task 007', 'Task 8', 'Task 6']).last, 'Task 8');
  });

  test('a prefix comes before the longer name', () {
    expect(sorted(['Running club', 'Running']), ['Running', 'Running club']);
  });

  test('the order is total and stable', () {
    final names = ['b', 'A', 'a', 'B', '2', '10', 'a2', 'a10'];
    final once = sorted(names);
    expect(sorted(once), once, reason: 'sorting twice changed the order');
    // Every pair agrees with itself reversed.
    for (final x in names) {
      for (final y in names) {
        expect(
          compareTaskNames(x, y).sign,
          -compareTaskNames(y, x).sign,
          reason: '"$x" vs "$y" disagrees with itself',
        );
      }
    }
  });

  test('identical names tie', () {
    expect(compareTaskNames('Golf', 'Golf'), 0);
  });
}
