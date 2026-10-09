import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/photos/models/photo.dart';

/// `sharedAt` was added to a schema that already had photos in it, so the
/// round-trip and — more importantly — the ABSENCE of the field are what these
/// tests pin down. A photo written before the field existed must read back as
/// unshared rather than as anything else.
Photo _photo({int? sharedAt}) => Photo(
  taskId: 'task_1',
  taskName: 'Golf',
  dayKey: '2026-10-08',
  timestamp: 1759900000000000,
  sessionSeconds: 1800,
  photoUrl: 'https://example.invalid/p.jpg',
  storagePath: 'users/me/photos/task_1_1759900000000000.jpg',
  cumulativeSeconds: 72000 * 3,
  sharedAt: sharedAt,
);

void main() {
  test('a photo is unshared by default', () {
    final p = _photo();
    expect(p.sharedAt, isNull);
    expect(p.isShared, isFalse);
  });

  test('sharedAt round-trips through the map', () {
    final p = _photo(sharedAt: 1759999999000000);
    final back = Photo.fromMap(p.toMap());
    expect(back.sharedAt, 1759999999000000);
    expect(back.isShared, isTrue);
  });

  test('a null sharedAt round-trips as null, not as a zero', () {
    final back = Photo.fromMap(_photo().toMap());
    expect(back.sharedAt, isNull);
    expect(back.isShared, isFalse);
  });

  test('a document written before the field existed reads as unshared', () {
    // Exactly the old shape: no sharedAt key at all.
    final legacy = _photo().toMap()..remove('sharedAt');
    expect(legacy.containsKey('sharedAt'), isFalse);

    final back = Photo.fromMap(legacy);
    expect(back.isShared, isFalse);
    // And nothing else about it is disturbed.
    expect(back.taskId, 'task_1');
    expect(back.dayKey, '2026-10-08');
    expect(back.cumulativeSeconds, 72000 * 3);
    expect(back.id, 'task_1_1759900000000000');
  });

  test('the field is carried, not dropped, by a re-save of a shared photo', () {
    // savePhoto writes toMap() wholesale, so a shared photo read back and
    // written again must keep its tag rather than silently clearing it.
    final shared = Photo.fromMap(_photo(sharedAt: 1759999999000000).toMap());
    expect(Photo.fromMap(shared.toMap()).sharedAt, 1759999999000000);
  });

  test('a stored sharedAt arriving as a num widens to int', () {
    final map = _photo().toMap()..['sharedAt'] = 1759999999000000.0;
    expect(Photo.fromMap(map).sharedAt, 1759999999000000);
  });
}
