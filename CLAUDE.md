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

## Firestore rules

**Rules are not filters.** A query succeeds only if the rules can prove that
*every* document it could match is readable. A read rule that depends on
per-document data the query does not constrain does not quietly omit those
rows — it fails the whole query with `permission-denied`. So "hide A's posts
from B" cannot be done with a rule; it is done by taking B out of the
`audience` array that every post and every comment carries, and querying
`where('audience', arrayContains: myUid)`.

Audiences are frozen at write time and can only ever narrow. A comment
copies its post's audience when it is created.

**Test rules against the emulator, never by reasoning about them.** The
tests in [test/rules/](test/rules/) assert the thing that matters: a pruned
reader gets a *shorter* feed, not an error.

```bash
cd test/rules && npm install
npx -y firebase-tools@13.35.1 emulators:exec --only firestore,storage \
  --project demo-sondr "npm test"
```

**The 13.35.1 pin is deliberate.** The installed CLI is 15.x, which needs
Java 21, and this machine has Java 11 — the emulator simply will not start
under it. The pin affects the emulator only; the installed CLI is still what
deploys. Drop the pin if a JDK 21 ever arrives.

**Indexes.** A query on one field never needs a composite index, and
declaring one is rejected (`this index is not necessary`). But a
*collection-group* query on one field does need that field's single-field
index built at collection-group scope, and the automatic ones are
collection-scoped — that is a `fieldOverrides` entry in
`firestore.indexes.json`, not an `indexes` entry. An override replaces the
automatic indexing for the field, so declare the collection-scoped orders
alongside the collection-group one or they are lost.

**Order of operations when the rules get stricter.** Deploy indexes and wait
for them to report `READY`, then backfill the documents that predate the new
field, then deploy the rules. Rules last: the moment they land, anything
missing the field they require is invisible to everyone, its own author
included.

## Public profiles

`users/{uid}/**` is owner-only, so **nothing about another person is readable
from it** — not their handle, not their hours. A profile for other people is
built from two additions instead.

**`publicProfiles/{uid}`** holds `handle`, `displayName`, whole `hours` and
`updatedAt`. Any signed-in user can read it; only its owner can write it, and
the write rule checks the handle against `usernames/{handle}.uid`, so a
public doc cannot claim someone else's name. The owner's own client publishes
it — at launch, when the handle or name is claimed, after a session is logged
(which covers every milestone crossing), and when the app goes to the
background. Never per tick: `profileToPublish` writes nothing unless the
whole-hour figure, the handle or the name has actually changed.

It is deliberately **not** block-aware. A read that failed for one person and
succeeded for another would be the tell that they had been blocked; blocks
stay enforced on the writes, whose refusals are worded identically to "no one
found".

**`publicProfiles/{uid}/friends/{friendUid}`** is the friend list, mirrored,
id-only (`{since}` — nothing else is allowed). `friendships` cannot answer
"who are their friends": a rule asking whether the reader is a friend of one
of a document's two participants would have to look up a path built from that
document's own data, which a list query cannot prove, so the whole query
would fail. **The mirror's path names the owner**, so the rule's lookup comes
from the path — the same shape as a comment's rule reaching its parent post.
A friend can list it; a stranger and a pending relationship are denied, which
is the "friends only" answer, not an error to show.

**Writes use `getAfter`, not `get`.** An entry is allowed only where the
friendship is accepted *after* the write lands, which is what lets the
accepter write the acceptance and both halves of the mirror in one batch —
`get` would refuse the very write that makes it true. Either party may write
or delete either half, so unfriending and blocking clear the mirror in the
same batch that clears the friendship. The delete rule reads only the path,
never the document, so deleting a half that was never written is a no-op a
declined request needs no branch for.

Because both halves always move together, **"my half exists" means both
exist** — which is what lets the launch reconcile
(`reconcileFriendMirror`) be one query rather than one read per friend. It
covers everything accepted before the mirror existed and anything a batch
could not land, and it is idempotent.

**The pair id must stay byte-identical** across `Friendship.pairId`,
`pairId()` in `firestore.rules`, and the emulator test's own copy. A test
writes with one and reads under another; if they drift, every friend list
silently stops being readable.

**A profile's posts need a composite index**: `authorUid` ASC + `audience`
CONTAINS + `createdAt` DESC. The query is
`where('authorUid').where('audience', arrayContains: me).orderBy('createdAt')`
— the audience filter is what makes the read rule provable, so without it the
profile does not show fewer posts, it errors. Type is split in Dart rather
than in a second index, and counts come from that one bounded query (100,
shown as "100+" at the cap): `count()` is server-only and would leave a cold
profile with no figures.

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
