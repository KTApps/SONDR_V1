/// Dev-only affordances, off in every normal build. Enable with
/// `flutter run --dart-define=DEBUG_TOOLS=true`.
///
/// Currently gates the timer's "prime to milestone edge" control, which pushes
/// the selected task to just below its first 20h milestone so a short session
/// crosses it — making the milestone → post → feed loop testable without
/// logging 20 real hours.
const bool kDebugTools = bool.fromEnvironment('DEBUG_TOOLS');

/// The accounts the debug tools show for, by uid, in a build made with
/// DEBUG_TOOLS. The founders' shared test account (sondr@test.com),
/// resolved once from the project's auth export; add a uid here to let
/// another account in. Everyone else — the founders' own accounts, the
/// review accounts, guests — sees exactly what a release build shows.
const List<String> kDebugUids = ['RgWBT8ypZYMoT2tVXyLKZtMoNpQ2'];

/// Whether the debug tools show: a DEBUG_TOOLS build, AND one of the
/// listed accounts signed in. [build] is the define, a parameter so the
/// rule can be tested where the define is off.
bool debugToolsFor(String? uid, {bool build = kDebugTools}) =>
    build && uid != null && kDebugUids.contains(uid);
