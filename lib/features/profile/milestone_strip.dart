import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photos/collage_selection.dart';
import '../photos/collages_repository.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';

/// One crossed milestone in the Profile strip: the task, the stretch, and the
/// one photo that stands for it.
class MilestoneStripEntry {
  const MilestoneStripEntry({
    required this.task,
    required this.bandHours,
    required this.photo,
    required this.crossedAt,
  });

  final Task task;
  final int bandHours;
  final Photo photo;

  /// When the milestone was crossed, as best the record can say: the crossing
  /// photo's capture instant when there is one, else the newest photo in the
  /// stretch. Microseconds since epoch, the same clock as [Photo.timestamp].
  final int crossedAt;
}

/// The Profile strip: one entry per crossed milestone across every task, the
/// most recently crossed first, each with its representative photo — the photo
/// taken at the crossing when there is one, else the newest in its stretch.
///
/// Membership is [bandIndexOf], the same rule the stretches, the collage and
/// the task row's count use. A milestone whose stretch holds no photo has
/// nothing to show and is left out — the strip is photos, and the count
/// beside the heading still says how many milestones there are.
///
/// It used to show the newest collage's photos: every photo of ONE milestone,
/// chronological — a preview of a single stretch, not the milestones.
final milestoneStripProvider =
    FutureProvider.autoDispose<List<MilestoneStripEntry>>((ref) async {
  if (ref.watch(photosRepositoryProvider) == null) return const [];
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  // Profile is mounted from launch, so reading the Milestones page's own
  // providers here resolves them before anyone taps — and keeps them so.
  // The strip is built from exactly the data the page will show.
  ref.watch(collagesListProvider);
  ref.watch(earliestPhotoMonthProvider);
  final out = <MilestoneStripEntry>[];
  for (final task in tasks) {
    final reached = task.milestonesReached;
    if (reached < 1) continue;
    final photos = await ref.watch(taskBandPhotosProvider(task.id).future);
    for (var b = 1; b <= reached; b++) {
      final hours = b * Task.milestoneStepHours;
      final rep = representativePhoto(bandPhotos(photos, hours), hours);
      if (rep == null) continue;
      out.add(MilestoneStripEntry(
        task: task,
        bandHours: hours,
        photo: rep,
        crossedAt: rep.timestamp,
      ));
    }
  }
  out.sort((a, b) => b.crossedAt.compareTo(a.crossedAt));
  return out;
});
