# SONDR

Flutter iOS app (habit / milestone tracking). Firebase project `sondr-cd439`,
bundle id `com.tanakabere.sondr`, Apple team `X378ZZ9NQ8`.

## Layout

- `lib/core/` — theme, utils, backend abstraction
- `lib/features/<feature>/` — one folder per feature (feed, habits, milestone, focus, …)
- `lib/shared/` — shared widgets
- `test/` — widget/unit tests, one file per feature

State management is Riverpod. Firebase Auth signs in anonymously on boot
(`lib/main.dart`) so there is always a user.

## Commands

```bash
flutter pub get
flutter test                        # 80 tests, all passing
flutter analyze                     # clean — keep it that way
flutter run -d "iPhone 17 Pro"      # run in a terminal with a TTY so hot reload works
cd ios && pod install
```

## Testing changes

- Build, install, and launch the app on the simulator.
- Tell the user what to tap / navigate to in order to verify the change.
- Wait for user feedback before proceeding.

## Gotchas

**Swift Package Manager must stay disabled.** Flutter 3.47+ enables SPM by
default. With it on, the 8 iOS plugins bypass CocoaPods, `pod install` installs
only the `Flutter` pod, and `ios/Runner.xcodeproj/project.pbxproj` gets
rewritten. Fix: `flutter config --no-enable-swift-package-manager`, then
`flutter pub get` and `pod install` (should give 28 pods). Check
`swift_package_manager_enabled` in `.flutter-plugins-dependencies` if iOS
plugins fail to link.

**Toolchain is user-local.** No Homebrew on this machine and `sudo` needs a
password. Flutter is at `~/development/flutter`, Node at `~/development/node`,
`gh` at `~/.local/bin`. CocoaPods runs through a Bundler shim at
`~/.local/bin/pod` because macOS system Ruby is 2.6 — use
`~/.cocoapods-bundle/Gemfile` + `bundle install`, never `gem install cocoapods`.

**`Prod1/` and `Prod1.xcodeproj/` are legacy.** A predecessor native SwiftUI app,
not part of the Flutter build. Don't edit them as if they were live code.

**`.firebaserc` points at `prodapp-b90ac`**, but the app uses `sondr-cd439`
(see `lib/firebase_options.dart` and `ios/Runner/GoogleService-Info.plist`).
Anything deployed via the Firebase CLI from this repo would hit the wrong
project. Unresolved — ask before acting on it.

## Build churn — do not commit

Every `flutter pub get` / `flutter build` rewrites these. They are generated,
not edits:

```
analysis_options.yaml            ios/Podfile.lock
pubspec.lock                     macos/Flutter/Flutter-{Debug,Release}.xcconfig
linux/flutter/generated_plugins.cmake     macos/Flutter/GeneratedPluginRegistrant.swift
windows/flutter/generated_plugins.cmake
```

`git restore .` to clear them. Never `git add -A` in this repo — stage files by
name. Local-only ignores live in `.git/info/exclude` (not shared with the team).

## Git

Never push without being asked. Never force push, rebase, or rewrite history.
