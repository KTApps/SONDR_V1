/// Dev-only affordances, off in every normal build. Enable with
/// `flutter run --dart-define=DEBUG_TOOLS=true`.
///
/// Currently gates the timer's "prime to milestone edge" control, which pushes
/// the selected task to just below its first 20h milestone so a short session
/// crosses it — making the milestone → post → feed loop testable without
/// logging 20 real hours.
const bool kDebugTools = bool.fromEnvironment('DEBUG_TOOLS');
