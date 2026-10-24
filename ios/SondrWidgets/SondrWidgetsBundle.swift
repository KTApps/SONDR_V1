import SwiftUI
import WidgetKit

/// Everything this extension offers the system.
///
/// Two things: the running timer on the Lock Screen and in the Dynamic
/// Island, and the Home Screen widget — what you are tracking, and one
/// tap to start it.
@main
struct SondrWidgetsBundle: WidgetBundle {
  var body: some Widget {
    SondrSessionActivity()
    if #available(iOS 17.0, *) {
      SondrTaskWidget()
    }
  }
}
