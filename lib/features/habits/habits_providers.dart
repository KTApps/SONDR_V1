import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Today's habit completion as 0..1 (checked ÷ total), which the inner ring
/// renders.
///
/// Placeholder for step 2: habits don't exist yet, so this is 0. Step 3 builds
/// the global habit list with per-day snapshotting and replaces this with a
/// provider derived from today's record. The inner ring already reads from here
/// so wiring it up later is a no-op on the timer screen.
final habitsTodayProgressProvider = Provider<double>((ref) => 0.0);
