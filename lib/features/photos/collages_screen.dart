import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// from the saved photo ids.
class _CollageEntry extends ConsumerWidget {
  const _CollageEntry({required this.collage});

  final Collage collage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final task = tasks.where((t) => t.id == collage.taskId).firstOrNull;
    // Graceful when the task was deleted: drop the name, keep the milestone.
    final label = task != null
        ? '${task.name} · ${collage.milestoneHours} hours'
        : '${collage.milestoneHours} hours';

    final photos = ref
            .watch(collagePhotosProvider(collage.photoIds.join(',')))
            .value ??
        const <Photo>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        // Empty only while resolving (the list excludes photoless collages).
        if (photos.isNotEmpty) CollageGrid(photos: photos),
      ],
    );
  }
}
