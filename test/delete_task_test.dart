import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/delete_task.dart';

/// The confirm prompt names exactly what goes — one clause per thing with a
/// count, none for a zero, singular and plural right — and always ends on
/// what cannot be undone.
void main() {
  group('deleteTaskBody', () {
    test('all three clauses, plural', () {
      expect(
        deleteTaskBody(hours: 3, milestones: 2, photos: 4),
        "3h of logged time, 2 milestones and 4 photos will be deleted. This can't be undone.",
      );
    });

    test('singular where the count is one', () {
      expect(
        deleteTaskBody(hours: 21, milestones: 1, photos: 1),
        "21h of logged time, 1 milestone and 1 photo will be deleted. This can't be undone.",
      );
    });

    test('a zero clause is left out', () {
      expect(
        deleteTaskBody(hours: 3, milestones: 0, photos: 4),
        "3h of logged time and 4 photos will be deleted. This can't be undone.",
      );
      expect(
        deleteTaskBody(hours: 0, milestones: 0, photos: 2),
        "2 photos will be deleted. This can't be undone.",
      );
      expect(
        deleteTaskBody(hours: 1, milestones: 0, photos: 0),
        "1h of logged time will be deleted. This can't be undone.",
      );
    });

    test('nothing logged at all: only the warning', () {
      expect(deleteTaskBody(hours: 0, milestones: 0, photos: 0), "This can't be undone.");
    });
  });
}
