import SwiftUI
import WidgetKit

/// Everything this extension offers the system.
///
/// It exists for one thing: the running timer, on the Lock Screen and in the
/// Dynamic Island. There are no home-screen widgets — the app has nothing to
/// say when a session is not running.
@main
struct SondrWidgetsBundle: WidgetBundle {
  var body: some Widget {
    SondrSessionActivity()
  }
}
