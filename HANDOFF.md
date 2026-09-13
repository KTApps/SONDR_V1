# Handoff

<!--
  The baton for our shared-branch workflow. One of us works at a time; this file
  is how the next person knows where to pick up.

  Rules:
  - OVERWRITE this file every session — it is not a log. Only the current state
    matters, and rewriting it whole means it never really conflicts.
  - `/end-session` rewrites it and commits it. `/start-session` reads it back.
  - "In progress" is the section that actually matters. Name files and line
    numbers. Say what you already tried that did NOT work — that is the part
    that saves the other person an hour.
  - Clear out sections that no longer apply. A stale handoff is worse than none.
-->

**Last session:** Kelvin — 2026-09-13
**Branch:** RESURRECTION

## Done
<!-- Finished and working. Short bullets; the git log has the detail. -->
- Guest accounts (commit d16b094):
  - Profile guest text now honest: data is online and lost if the app is deleted — `lib/features/auth/account_screen.dart`
  - Friends needs an account (guests get a "Create account" pop-up) — `lib/features/profile/profile_screen.dart`
  - Sharing milestones/sessions needs an account — `milestone_celebration.dart`, `timer_screen.dart`
  - "Create account" nudge after a guest's first hour tracked, and on the milestone screen — `lib/features/auth/guest_prompts.dart`
  - Warning before signing into an existing account throws away guest progress (email + Apple) — `auth_screen.dart`, `auth_repository.dart`
- Sondr Test Plan (52-week TestFlight plan) published as a private claude.ai page — not in the repo

## In progress (STOP HERE)
<!--
  Where the next person starts. Be specific:
    - lib/features/feed/feed_card.dart:180 — 5+ photo grid overflows on iPhone SE
    - Tried a GridView, made it worse. Probably wants a Wrap.
  Leave empty if the last session ended clean.
-->
- _(empty — session ended clean)_

## Don't touch
<!-- Mid-refactor areas that will conflict if the other person edits them. -->
- _(nothing)_

## Next
<!-- The obvious next move, so nobody re-decides it from scratch. -->
- Try the guest flows on the simulator; the milestone and 1-hour prompts need `--dart-define=DEBUG_TOOLS=true` to reach quickly
- Before first testers: intro screen explaining the 20-hour idea, usage + crash reports, "Send feedback" button, shared-photo link privacy fix, Delete account

## Notes
<!--
  Anything the other person needs before they start: a new dependency (run
  `flutter pub get`), a simulator quirk, a Firebase change, a failing test that
  is known and expected.
-->
- Guest gating is switched off in tests and offline mode (no Firebase = not a guest)
- Simulator showed an empty task list after relaunch — probably a fresh guest session; not investigated
- Firebase console: the right project ID is `sondr-cd439` (not "ProdApp")
- `.firebaserc` still points at `prodapp-b90ac` — don't deploy from the CLI
- Firebase stops publishing CocoaPods releases after Oct 2026 — a move will be needed eventually
- "Last 10 days" on Home starts at yesterday — confirm that's intended
- No new dependencies; 81 tests passing, analyze clean
