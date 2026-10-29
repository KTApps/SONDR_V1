import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'debug_flags.dart';

/// Whether the debug tools show for whoever is signed in now: the
/// DEBUG_TOOLS build, and a listed account. Follows the account, so
/// signing out of the test account hides everything at once.
final debugToolsProvider = Provider<bool>((ref) => debugToolsFor(ref.watch(currentUidProvider)));
