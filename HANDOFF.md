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

**Last session:** _(name)_ — _(YYYY-MM-DD)_
**Branch:** RESURRECTION

## Done
<!-- Finished and working. Short bullets; the git log has the detail. -->
- _nothing recorded yet — this is the initial template_

## In progress (STOP HERE)
<!--
  Where the next person starts. Be specific:
    - lib/features/feed/feed_card.dart:180 — 5+ photo grid overflows on iPhone SE
    - Tried a GridView, made it worse. Probably wants a Wrap.
  Leave empty if the last session ended clean.
-->
- _(empty)_

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
- _(nothing)_
