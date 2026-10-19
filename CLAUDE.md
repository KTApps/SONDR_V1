# SONDR

Flutter iOS app (habit / milestone tracking). Firebase project `sondr-cd439`,
bundle id `com.tanakabere.sondr`, Apple team `X378ZZ9NQ8`.

## How to reply to us

Both of us (the co-founders) are non-technical and want to move fast.

- Reply in short, easy-to-understand bullet points.
- Plain English. Avoid jargon; if a technical term is unavoidable, explain it in a few words.
- Only what we need: the answer, why it matters, and what to do next. Skip deep detail unless we ask.
- Bold the key phrase at the start of a bullet so it can be skimmed.
- Link files so we can click them, but don't walk through code unless asked.

This is about replies only. Code, commit messages, and docs follow their own conventions.

## Design

**Read [DESIGN.md](DESIGN.md) before building or restyling any UI, and apply it
without being asked.** It is the standard for every screen: greyscale only (no
colour, not even for destructive actions), white as text and never a fill, no
filled buttons, even airy spacing, one type system, Sondr's own components.
Treat a conflict between DESIGN.md and an existing screen as a bug in the
screen.

[DESIGN-PUNCHLIST.md](DESIGN-PUNCHLIST.md) tracks the outstanding cohesion work,
screen by screen.

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
flutter test                        # 81 tests, all passing
flutter analyze                     # clean — keep it that way
flutter run -d "iPhone 17 Pro"      # run in a terminal with a TTY so hot reload works
cd ios && pod install
```

## Testing changes

- Build, install, and launch the app on the simulator.
- Tell the user what to tap / navigate to in order to verify the change.
- Wait for user feedback before proceeding.

## Live Activity

The running timer appears on the Lock Screen and in the Dynamic Island.

- **`ios/SondrWidgets/`** is the widget extension — bundle
  `com.tanakabere.sondr.widgets`, **iOS 17** (the app stays on 15, and
  ActivityKit and AppIntents are weak-linked so an iOS 15 phone still
  launches). It is a real Xcode target, so changes to `project.pbxproj`
  that add files or capabilities are committed.
- **`sondr.session` in App Group `group.com.tanakabere.sondr`** is the only
  thing the two processes share. One JSON object: `startedAt`, `pausedMs`,
  optional `pausedAt`, `taskId`, `taskName`, `taskSecondsBefore`,
  `confirmedMs`. Elapsed is always derived, never stored. Dart writes it in
  [session_store.dart](lib/features/timer/session_store.dart); Swift reads
  and writes the same bytes in `SessionSnapshot.swift` and
  `SessionMutation.swift`. **Both sides are checked against the same
  fixtures** in [test/fixtures/sessions.json](test/fixtures/sessions.json);
  change one number there and both suites fail.
- **Pause and Resume are App Intents**, not links. They run in whatever
  process the system picks, with no Flutter engine and possibly no app, and
  they change the session where it stands. Anything that transforms the
  session must preserve every other field, including ones it does not read.
  Stop is a link — `sondr://stop` — because the stop flow needs the app.
- **The stored session is the truth, the in-memory clock is a cache.**
  `TimerController` re-reads before every read and every write — start,
  pause, stop, the "Still going?" confirmation, and every foreground.
  Never act on `_clock` without `sync()` first.
- **A widget test that starts the timer must override
  `sessionStoreProvider`.** The real store is a platform channel with
  nothing on the other end in a test, and the read now happens before the
  session starts, so such a test **hangs** rather than failing. See
  `_NoStore` in [test/archive_test.dart](test/archive_test.dart).
- **Known edge:** the app and an intent can both write the session. Each
  writes a complete state in one atomic key update, so neither corrupts the
  other, but a simultaneous write is last-one-wins.

## Gotchas

**Swift Package Manager must stay disabled.** Flutter 3.47+ enables SPM by
default. With it on, the 8 iOS plugins bypass CocoaPods, `pod install` installs
only the `Flutter` pod, and `ios/Runner.xcodeproj/project.pbxproj` gets
rewritten. Fix: `flutter config --no-enable-swift-package-manager`, then
`flutter pub get` and `pod install` (29 pods as of the camera round). Check
`swift_package_manager_enabled` in `.flutter-plugins-dependencies` if iOS
plugins fail to link.

**Toolchain.** `sudo` needs a password. CocoaPods is installed and on the
path at `/opt/homebrew/bin/pod` — just run `pod install` from `ios/`. The
Bundler shim this file used to describe (`~/.local/bin/pod`,
`~/.cocoapods-bundle/Gemfile`) is **gone**; neither path exists any more.
Check `which` before believing a path in this section.

**`Prod1/` and `Prod1.xcodeproj/` are legacy.** A predecessor native SwiftUI app,
not part of the Flutter build. Don't edit them as if they were live code.

**The Firebase default is now correct.** `.firebaserc` says `sondr-cd439`,
which is what `firebase.json`, `lib/firebase_options.dart` and
`ios/Runner/GoogleService-Info.plist` have always said. It used to say
`prodapp-b90ac` — the predecessor app's project, see `Prod1/` above — so a
bare `firebase deploy` published Sondr's rules to ProdApp.

Still pass `--project sondr-cd439` on deploys. The two projects are both on
this machine's account and a default is one `firebase use` away from being
something else:

```bash
firebase deploy --only firestore:rules --project sondr-cd439
```

`firebase deploy --dry-run` validates and resolves without publishing.

## Build churn — do not commit

Every `flutter pub get` / `flutter build` rewrites these. They are generated,
not edits:

```
analysis_options.yaml            macos/Flutter/Flutter-{Debug,Release}.xcconfig
linux/flutter/generated_plugins.cmake     macos/Flutter/GeneratedPluginRegistrant.swift
windows/flutter/generated_plugins.cmake   ios/Runner.xcodeproj/project.pbxproj
```

**Never `git restore .`.** Run `git status` first, check that every tracked
file it lists really is churn, then restore those paths BY NAME:

```bash
git status --short
git restore linux macos windows ios/Runner.xcodeproj/project.pbxproj
```

`git restore .` reverts everything tracked, churn and work alike. It has
already silently thrown away three source files mid-round — the commit went
out with only its test in it, and nothing but a standalone worktree check
caught it. The churn is always in the same handful of generated directories;
naming them costs one line and cannot take anything else with it.

Never `git add -A` either — stage files by name. Local-only ignores live in
`.git/info/exclude` (not shared with the team).

**`pubspec.lock` and `ios/Podfile.lock` are the exception.** They are churn
when a build regenerates them unchanged, and they are NOT churn when the
dependency set actually changes — then they are the record of which versions
this branch was tested against, and they get committed with the pubspec
change that caused them.

**`ios/Runner.xcodeproj/project.pbxproj` is the same kind of exception.** A
build rewrites it with nothing in it — restore that. But a change that adds a
capability, a target, a file reference or a build setting is a real change, and
it is committed with the work that needed it. Read the diff before deciding:
if it only moves generated plugin lines around, it is churn.

## Git

Never push without being asked. Never force push, rebase, or rewrite history.

**Chain verification and commit with `&&`, never `;`.** `flutter test; git
commit` commits whether or not the tests passed, and has done exactly that
in this repo. `flutter test && git commit` cannot.

**Use `git worktree` to look at another commit, not `git stash`.** A stash
plus a checkout has twice left this repo in a state nobody asked for —
conflict markers in a test file, and a checkout that failed silently so a
per-commit verification measured the same tree three times and reported it
as three passes. A worktree is a clean, separate checkout that cannot
disturb the main one: `git worktree add ../wt <ref>`, work, `git worktree
remove ../wt`.
