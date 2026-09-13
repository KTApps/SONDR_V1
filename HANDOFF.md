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
- Task picker: bars thicker (28pt); thin sliver shows once ≥1 min logged — `lib/features/timer/widgets/task_dropdown.dart`
- Photo capture screen now centred — `lib/features/photos/photo_capture_flow.dart`
- Friends: handle suggestions as you type, with Add on each result (tested) — `lib/features/friends/friends_screen.dart`, `friends_repository.dart`
- Habits page: tap any empty space to close — `lib/features/habits/habits_overlay.dart`
- `CLAUDE.md`: new "How to reply to us" rule (plain-English bullets)
- `.gitignore`: ignore `.widget_preview/`

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
- _(nothing queued)_

## Notes
<!--
  Anything the other person needs before they start: a new dependency (run
  `flutter pub get`), a simulator quirk, a Firebase change, a failing test that
  is known and expected.
-->
- FYI: friend search now lets any signed-in user see handles by typing letters (before, you had to know the exact handle)
- Firebase console: the right project ID is `sondr-cd439` (not "ProdApp")
- `.firebaserc` still points at `prodapp-b90ac` — don't deploy from the CLI
- Firebase stops publishing CocoaPods releases after Oct 2026 — a move will be needed eventually
- "Last 10 days" on Home starts at yesterday — confirm that's intended
- No new dependencies; 81 tests passing
