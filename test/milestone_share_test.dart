import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/milestone/milestone_share_flow.dart';
import 'package:sondr/features/photos/models/photo.dart';

Photo _p(String taskId, int ts) => Photo(
  taskId: taskId,
  taskName: 'T',
  dayKey: '2026-08-12',
  timestamp: ts,
  sessionSeconds: 3600,
  photoUrl: 'u/$ts.jpg',
  storagePath: 'users/u1/photos/${taskId}_$ts.jpg',
);

void main() {
  group('selectedBandInOrder', () {
    final pool = [_p('t', 1), _p('t', 2), _p('t', 3), _p('t', 4)];

    test('empty selection -> empty', () {
      expect(selectedBandInOrder(pool, <String>{}), isEmpty);
    });

    test('keeps pool order regardless of selection insertion order', () {
      final selected = {pool[3].id, pool[0].id, pool[2].id};
      final result = selectedBandInOrder(pool, selected);
      expect(result.map((p) => p.timestamp), [
        1,
        3,
        4,
      ]); // chronological pool order
    });

    test('select-all returns the whole pool in order', () {
      final all = {for (final p in pool) p.id};
      expect(selectedBandInOrder(pool, all).map((p) => p.timestamp), [
        1,
        2,
        3,
        4,
      ]);
    });

    test('ids not in the pool are ignored', () {
      expect(
        selectedBandInOrder(pool, {'nope', pool[1].id}).single.timestamp,
        2,
      );
    });
  });
}
