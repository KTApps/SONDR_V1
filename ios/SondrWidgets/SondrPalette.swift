import SwiftUI

/// The app's greyscale, repeated here because an extension cannot see the
/// app's Dart. Kept to the same five values as lib/core/theme — a drift
/// between them would read as two apps.
enum Ink {
  static let background = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)
  static let ringTrack = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255)
  static let ringFill = Color(red: 0xAD / 255, green: 0xAD / 255, blue: 0xAD / 255)
  static let primary = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
  static let secondary = Color(red: 0xB0 / 255, green: 0xB0 / 255, blue: 0xB0 / 255)
  static let tertiary = Color(red: 0x6E / 255, green: 0x6E / 255, blue: 0x6E / 255)
}

/// Inter, bundled with the extension, because a widget renders in its own
/// process and gets none of the app's fonts.
///
/// One variable file carries every weight; `Font.custom` plus `.weight` picks
/// the named instance, the same arrangement the Flutter side uses.
extension Font {
  static func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    .custom("Inter", fixedSize: size).weight(weight)
  }
}
