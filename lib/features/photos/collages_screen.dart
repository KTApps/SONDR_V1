import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'collages_repository.dart';
import 'models/collage.dart';
import 'models/photo.dart';
import 'widgets/collage_grid.dart';

/// The milestone collages, newest first — each an auto-composed (or curated)
/// grid of that milestone's photos, labelled by task and milestone. Reached from
/// the profile Milestones doorway.
class CollagesScreen extends ConsumerWidget {
  const CollagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final collages = ref.watch(collagesListProvider).value ?? const <Collage>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        iconTheme: const IconThemeData(size: 20),
        leadingWidth: 44,
        leading: IconButton(
          padding: const EdgeInsets.only(left: 22),
          alignment: Alignment.centerLeft,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Milestones',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          itemCount: collages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 28),
          itemBuilder: (_, i) => _CollageEntry(collage: collages[i]),
        ),
      ),
    );
  }
}

/// One collage: its "{task} · {hours} hours" label and the grid, resolved live
/// from the saved photo ids. Edit is inline and removal-only: tap "Edit" to mark
/// photos out (dimmed ×, no reflow, min 1 kept), then Save (writes edited:true)
/// or Cancel — each collage edits independently.
class _CollageEntry extends ConsumerStatefulWidget {
  const _CollageEntry({required this.collage});

  final Collage collage;

  @override
  ConsumerState<_CollageEntry> createState() => _CollageEntryState();
}

class _CollageEntryState extends ConsumerState<_CollageEntry> {
  bool _editing = false;
  bool _saving = false;
  final Set<String> _removed = {};

  Collage get _collage => widget.collage;

  void _toggle(Photo p) {
    setState(() {
      if (!_removed.remove(p.id)) _removed.add(p.id);
    });
  }

  void _cancel() => setState(() {
        _removed.clear();
        _editing = false;
      });

  Future<void> _save(List<Photo> photos) async {
    final repo = ref.read(collagesRepositoryProvider);
    if (repo == null) return;
    final kept = [for (final p in photos) if (!_removed.contains(p.id)) p.id];
    if (kept.isEmpty) return; // guarded by min-1, belt-and-braces
    setState(() => _saving = true);
    try {
      await repo.saveEdited(_collage.taskId, _collage.milestoneHours, kept);
      ref.invalidate(collagesListProvider); // re-fetch → entry rebuilds curated
      if (mounted) {
        setState(() {
          _removed.clear();
          _editing = false;
          _saving = false;
        });
      }
    } catch (e) {
      debugPrint('SONDR collage edit save error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = GreyscaleTokens.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final task = tasks.where((t) => t.id == _collage.taskId).firstOrNull;
    final label = task != null
        ? '${task.name} · ${_collage.milestoneHours} hours'
        : '${_collage.milestoneHours} hours';

    final photos = ref
            .watch(collagePhotosProvider(_collage.photoIds.join(',')))
            .value ??
        const <Photo>[];
    final keptCount = photos.length - _removed.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            if (photos.isNotEmpty && !_editing)
              TextButton(
                onPressed: () => setState(() => _editing = true),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  textStyle: theme.textTheme.labelLarge,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (photos.isNotEmpty)
          CollageGrid(
            photos: photos,
            removedIds: _editing ? _removed : null,
            onToggleRemove: _editing ? _toggle : null,
            // Un-marked tiles can be marked only while >1 would remain.
            canMark: _editing ? (_) => keptCount > 1 : null,
          ),
        if (_editing) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text('$keptCount kept',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textSecondary)),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : _cancel,
                style: TextButton.styleFrom(foregroundColor: tokens.textTertiary),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _saving ? null : () => _save(photos),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  textStyle: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
