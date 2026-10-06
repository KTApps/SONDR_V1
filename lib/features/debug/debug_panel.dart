import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/utils/date.dart';
import '../history/calendar_screen.dart';
import '../history/day_detail_sheet.dart';
import '../photos/collage_selection.dart';
import '../photos/collages_repository.dart';
import '../photos/collages_screen.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';

/// QA-only debug panel. Reached solely from the `kDebugTools`-gated entry on the
/// Profile screen, so this file's code tree-shakes out of any release build
/// where `kDebugTools` is const-false (no `--dart-define=DEBUG_TOOLS=true`).
///
/// **Every action seeds through the REAL repositories** — no mocked milestones,
/// collages, or feed logic; only the wait time is skipped. All writes are
/// uid-scoped (owner-only rules), so nothing here can touch another account.
///
/// Which button does what, honestly:
///  * **Prime to ~1 min below next milestone** → a real short session then
///    crosses → real celebration + real auto-composed collage.
///  * **Add 20h (state only)** → pushes past a milestone for gate/empty-state
///    testing; deliberately does NOT auto-compose (only a real crossing does).
///  * **Seed N photos / populated collage** → real photo docs (+ a real
///    `saveAuto` over the real band) for mosaic/edit display — not auto-compose.
class DebugPanel extends ConsumerStatefulWidget {
  const DebugPanel({super.key});

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  String? _taskId;
  int _photoCount = 12;
  bool _busy = false;
  String _status = 'Ready.';

  Task? get _task {
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    return tasks.where((t) => t.id == _taskId).firstOrNull;
  }

  Future<void> _run(String label, Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      final msg = await action();
      if (mounted) setState(() => _status = msg);
    } catch (e) {
      if (mounted) setState(() => _status = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Task / time (through the real logSeconds path stop() uses) ────────────

  Future<String> _createTask() async {
    final t = await ref
        .read(tasksProvider.notifier)
        .addTask('Test ${DateTime.now().second}');
    if (mounted) setState(() => _taskId = t.id);
    return 'Created "${t.name}" and selected it.';
  }

  Future<String> _primeBelowMilestone() async {
    final task = _task;
    if (task == null) return 'Pick a task first.';
    final needed = task.activeMilestoneHours * 3600 - 60 - task.totalSeconds;
    if (needed <= 0) return 'Already within ~1 min of the next milestone.';
    await ref
        .read(tasksProvider.notifier)
        .logSeconds(task.id, needed, DateTime.now());
    return 'Primed "${task.name}" to ~1 min below ${task.activeMilestoneHours}h — '
        'run a real short session to cross it.';
  }

  Future<String> _add20h() async {
    final task = _task;
    if (task == null) return 'Pick a task first.';
    await ref
        .read(tasksProvider.notifier)
        .logSeconds(task.id, 20 * 3600, DateTime.now());
    return 'Added 20h to "${task.name}" (state only — no crossing, no collage).';
  }

  // ── Photos / collage (real uploadPhoto + savePhoto + saveAuto) ────────────

  Future<({String url, String storagePath})> _upload(
    PhotosRepository repo,
    String id,
    String asset,
  ) async {
    final bytes = await rootBundle.load(asset);
    final dir = Directory.systemTemp.createTempSync('dbg');
    final f = File('${dir.path}/$id.jpg')
      ..writeAsBytesSync(bytes.buffer.asUint8List());
    return repo.uploadPhoto(f, photoId: id);
  }

  Future<String> _seedPhotos({required bool withCollage}) async {
    final task = _task;
    if (task == null) return 'Pick a task first.';
    final photos = ref.read(photosRepositoryProvider);
    if (photos == null) return 'No photos repo (sign in).';

    const milestone = 20; // band 0
    final u1 = await _upload(photos, 'dbg-1', 'assets/mock/sample1.jpg');
    final u2 = await _upload(photos, 'dbg-2', 'assets/mock/sample2.jpg');
    final n = _photoCount;
    final now = DateTime.now();
    for (var i = 1; i <= n; i++) {
      final cum = kMilestoneBandSeconds * i ~/ (n + 1); // spread in band 0
      await photos.savePhoto(
        Photo(
          taskId: task.id,
          taskName: task.name,
          dayKey: DayKey.of(now),
          timestamp: now.microsecondsSinceEpoch + i,
          sessionSeconds: 3600,
          photoUrl: i.isEven ? u1.url : u2.url,
          storagePath: i.isEven ? u1.storagePath : u2.storagePath,
          cumulativeSeconds: cum,
        ),
      );
    }
    if (!withCollage) return 'Seeded $n photos in "${task.name}" 20h band.';

    final collages = ref.read(collagesRepositoryProvider);
    if (collages == null) return 'Seeded $n photos (no collages repo).';
    // Compose over the REAL band via the real selector, then real saveAuto.
    final band = await photos.photosForBand(task.id, milestone);
    await collages.saveAuto(task.id, milestone, [for (final p in band) p.id]);
    return 'Seeded $n photos + collage on "${task.name}" (20h) — open Collages.';
  }

  // ── Wipe (self-scoped: only this signed-in account) ───────────────────────

  Future<String> _wipe() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return 'No uid.';
    final db = FirebaseFirestore.instance;
    final u = db.collection('users').doc(uid);
    var n = 0;

    final photoSnap = await u.collection('photos').get();
    for (final d in photoSnap.docs) {
      final sp = d.data()['storagePath'] as String?;
      if (sp != null && sp != 'unused') {
        try {
          await FirebaseStorage.instance.ref(sp).delete();
        } catch (_) {}
      }
      await d.reference.delete();
      n++;
    }
    for (final c in ['tasks', 'collages', 'habitDays']) {
      final snap = await u.collection(c).get();
      for (final d in snap.docs) {
        await d.reference.delete();
        n++;
      }
    }
    await u.collection('meta').doc('habitList').delete();

    // Own posts + their posts-space binaries.
    final posts = await db
        .collection('posts')
        .where('audience', arrayContains: uid)
        .get();
    for (final d in posts.docs) {
      if (d.data()['authorUid'] != uid) continue;
      for (final p in (d.data()['photos'] as List?) ?? const []) {
        final sp = (p as Map)['storagePath'] as String?;
        if (sp != null && sp.isNotEmpty) {
          try {
            await FirebaseStorage.instance.ref(sp).delete();
          } catch (_) {}
        }
      }
      await d.reference.delete();
      n++;
    }
    return 'Wiped $n docs — this account only.';
  }

  Future<void> _confirmWipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe your test data?'),
        content: const Text(
          'Deletes THIS account\'s tasks, photos, collages, habits and your '
          'posts. Cannot touch other accounts. Not undoable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wipe'),
          ),
        ],
      ),
    );
    if (ok == true) await _run('Wiping', _wipe);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    // Keep the selection valid.
    if (_taskId != null && tasks.every((t) => t.id != _taskId)) _taskId = null;
    _taskId ??= tasks.isNotEmpty ? tasks.first.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('DEBUG PANEL')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _section('Task'),
            DropdownButton<String>(
              isExpanded: true,
              value: _taskId,
              hint: const Text('No tasks — create one'),
              items: [
                for (final t in tasks)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.name} · ${(t.total.inMinutes / 60).toStringAsFixed(1)}h',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _taskId = v),
            ),
            _btn('＋ Create test task', () => _run('Creating', _createTask)),

            _section('Milestone / time (real logSeconds)'),
            _btn(
              'Prime to ~1 min below next milestone → then run a short session',
              () => _run('Priming', _primeBelowMilestone),
            ),
            _btn(
              'Add 20h (state only — gate/empty-state, no collage)',
              () => _run('Adding 20h', _add20h),
            ),

            _section('Photos / collage (real repos)'),
            Row(
              children: [
                const Text('N: '),
                for (final n in [12, 25, 42])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$n'),
                      selected: _photoCount == n,
                      onSelected: (_) => setState(() => _photoCount = n),
                    ),
                  ),
              ],
            ),
            _btn(
              'Seed N photos in 20h band',
              () =>
                  _run('Seeding photos', () => _seedPhotos(withCollage: false)),
            ),
            _btn(
              'Seed populated collage (N photos + collage doc)',
              () =>
                  _run('Seeding collage', () => _seedPhotos(withCollage: true)),
            ),

            _section('Quick nav'),
            _btn('Open Calendar', () => _push(const CalendarScreen())),
            _btn('Open Collages', () => _push(const CollagesScreen())),
            _btn(
              "Open today's day-detail",
              () => showDayDetailSheet(context, DayKey.of(DateTime.now())),
            ),

            _section('Danger'),
            _btn('Wipe my test data', _confirmWipe),

            const SizedBox(height: 24),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );

  Widget _btn(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        child: Text(label, textAlign: TextAlign.left),
      ),
    ),
  );
}
