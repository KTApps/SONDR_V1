import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date.dart';
import 'habits_repository.dart';
import 'models/daily_habits.dart';
import 'models/habit.dart';

/// Firestore-backed [HabitsRepository].
///
///  * Live ordered list → `users/{uid}/meta/habitList` = `{ items: [{id,name}] }`.
///  * Per-day records → `users/{uid}/habitDays/{dayKey}` = `{ ticks: [...] }`.
///
/// Immutable history is preserved the same way as the local repository:
/// [_syncToday] only ever writes **today's** day document (rebuilt from the
/// live list, preserving which habits were checked). Past day documents are
/// read but never rewritten, so renaming or removing a habit can't alter the
/// past.
class FirestoreHabitsRepository implements HabitsRepository {
  FirestoreHabitsRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get _listDoc =>
      db.collection('users').doc(uid).collection('meta').doc('habitList');

  CollectionReference<Map<String, dynamic>> get _daysCol =>
      db.collection('users').doc(uid).collection('habitDays');

  Future<List<Habit>> _readLive() async {
    final doc = await _listDoc.get();
    final items = (doc.data()?['items'] as List?) ?? const [];
    return [
      for (final i in items)
        if (i is Map) Habit.fromMap(Map<String, dynamic>.from(i)),
    ];
  }

  Future<void> _writeLive(List<Habit> live) async {
    await _listDoc.set({'items': [for (final h in live) h.toMap()]});
  }

  Future<Map<String, DailyHabits>> _readDays() async {
    final snap = await _daysCol.get();
    return {
      for (final d in snap.docs) d.id: DailyHabits.fromMap(d.id, d.data()),
    };
  }

  /// Rebuild today's record from the live list (preserving checks) and persist
  /// it. Mutates [days] in place and returns the synced record. Past days are
  /// left untouched.
  Future<DailyHabits> _syncToday(
    List<Habit> live,
    Map<String, DailyHabits> days,
  ) async {
    final today = DayKey.of(DateTime.now());
    final existing = days[today];
    final done = <String>{
      if (existing != null)
        for (final t in existing.ticks)
          if (t.done) t.habitId,
    };
    final synced = DailyHabits(
      dayKey: today,
      ticks: [
        for (final h in live)
          HabitTick(habitId: h.id, name: h.name, done: done.contains(h.id)),
      ],
    );
    await _daysCol.doc(today).set(synced.toMap());
    days[today] = synced;
    return synced;
  }

  Future<HabitsState> _state() async {
    final live = await _readLive();
    final days = await _readDays();
    await _syncToday(live, days);
    return HabitsState(liveList: live, days: days);
  }

  @override
  Future<HabitsState> fetch() => _state();

  @override
  Future<HabitsState> toggle(String habitId) async {
    final live = await _readLive();
    final days = await _readDays();
    final today = DayKey.of(DateTime.now());
    final synced = await _syncToday(live, days);
    final toggled = synced.withToggled(habitId);
    await _daysCol.doc(today).set(toggled.toMap());
    days[today] = toggled;
    return HabitsState(liveList: live, days: days);
  }

  @override
  Future<HabitsState> addHabit(String name) async {
    final live = await _readLive();
    live.add(Habit(id: _daysCol.doc().id, name: name.trim()));
    await _writeLive(live);
    final days = await _readDays();
    await _syncToday(live, days);
    return HabitsState(liveList: live, days: days);
  }

  @override
  Future<HabitsState> removeHabit(String habitId) async {
    final live = await _readLive()
      ..removeWhere((h) => h.id == habitId);
    await _writeLive(live);
    final days = await _readDays();
    await _syncToday(live, days);
    return HabitsState(liveList: live, days: days);
  }
}
