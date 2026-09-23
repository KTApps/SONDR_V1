# Design punchlist

The cohesion pass, grouped by screen and ordered so the cascading work lands
first. Standard is [DESIGN.md](DESIGN.md) — every item below is measured
against it.

Tick items off as they land. Keep the order: buttons set the vocabulary the
later screens reuse.

---

## 1. Buttons — do first, everything downstream inherits it

- [x] **Start** — was a solid white filled button, the loudest thing on Home
      and a direct breach of the no-white-fill rule.
- [x] **Pause / Resume / Stop** — same treatment.
- [x] **One shared style** for all of them, minimal and non-white, so there is a
      single button vocabulary to reuse everywhere else.

Files: [`timer_screen.dart`](lib/features/timer/timer_screen.dart)
(`_TimerControls`, `_SondrControl`).

Doing this first is what makes the rest of the list cheap.

**Shipped as uniform white text; revisit if a stronger primary-action idea
comes.** Bare text, an outline and a dark pill were all tried on the simulator,
along with a heavier/uppercase/tracked treatment for the primary action. The
decision was uniformity: every action uses the standard 15/bold/`textPrimary`
style and hierarchy comes from position.

## 2. Focus mode

- [x] **Entry popup** — minimal.
- [x] **Timer page** — minimal, reusing the new button style.

Files: [`focus_view.dart`](lib/features/focus/focus_view.dart),
[`sondr_action.dart`](lib/shared/sondr_action.dart).

**The popup became an inline choice.** Rather than a sheet asking whether to
focus, tapping "Start" splits the control into "Focus / Start"; a tap anywhere
else on Home closes it again. `SondrActionPair` is the shared treatment for
any two text actions side by side — available for the feed's delete blur. A
hairline divider between the pair was tried and dropped; the gap alone
separates them.

## 3. Progress circles

- [x] **Drop "of 20h"** — and the milestone count with it; the ring and the
      figure say enough.
- [x] **Rings build toward the next milestone.** Decided the opposite way to
      the original note: rather than pinning full past 20h, every ring climbs
      through its current 20-hour block, resets on each milestone and climbs
      again. The dropdown pills were pinning full and now build too, so a ring
      means the same thing everywhere.
- [x] **Neaten** the ring and its figure — hardcoded hexes moved to
      `GreyscaleTokens` (which also fixes light mode), centre figure on the
      12/bold type-table style, tile and ring scaled with `figmaScale()`.
- [x] **The centre figure floors.** It was rounding, so a task 90 seconds
      short of 20h read "20h" beside a ring that had not reset — claiming a
      milestone it had not reached. `Task.wholeHours` now rounds down.

**Not covered by a test:** the profile tile's own rendering. `ProfileScreen`
pulls in the account/Firebase providers and cannot be pumped without
scaffolding well beyond this change, so the "of 20h" removal and the floored
figure were verified by inspection and on the simulator. **Extracting
`_TaskTile` into its own widget would make it testable** — worth doing when
that screen is next touched. The dropdown pill and the `Task` maths are
covered.

## 4. Guest

- [x] **Shortened, not removed.** The two-sentence explainer became one line:
      *"Your progress is lost if you delete the app."*

Files: [`account_screen.dart`](lib/features/auth/account_screen.dart).

**Why it was kept.** This is the app's only *standing* statement that a guest's
data is at risk. The other three carriers are all transient — the first-hour
nudge fires once at the crossing, the milestone prompt only on tapping share,
and the sign-in warning only when replacing guest data with an existing
account. Dismiss the nudge and there would have been nowhere left to read it.
The line was also written deliberately last session as an honesty fix
(HANDOFF.md), not left behind as clutter.

## 5. Auth

- [x] **Simplify sign-in.**
- [x] **Simplify choose-a-handle**, and remove the "e.g." from the handle field.
- [x] **Align the typography to Home** — these are the known drifters.

Shared components came out of this: `SondrField` (a surface-tone capsule with a
still label, replacing Material's underline + floating label), `SondrHeader`
(20/bold heading + a 44pt back target, replacing both `AppBar`s), and a
`supporting` variant on `SondrAction` for exit actions. The spinner was
inheriting `ColorScheme.primary` — the near-white ring fill — and now uses the
inner-ring tone.

Error copy consolidated to one message per real condition; the two invalid-email
variants and the two password-length variants merged, and the trailing "Please
try again." trimmed.

**The Apple button is custom-toned** — see the note above. **Handle now scrolls
for the keyboard**; it did not before, and with a 336 keyboard the field sits at
185-261 against a 516 viewport bottom.

**Item-8 carryover: resolved by keeping.** The guest footer keeps its scoped
scroll. It is the one transient state that cannot be sized — a guest may or may
not have photos, which shows or hides two 74-tall doorways, so the space
available to the footer swings by 148 with no way to know in advance. The scroll
is the safety valve for that, scoped to the guest branch inside `AccountBody`,
so the signed-in page still has no vertical scrollable at all.

Files: [`auth_screen.dart`](lib/features/auth/auth_screen.dart),
[`handle_screen.dart`](lib/features/auth/handle_screen.dart).

**The Apple button is intentionally custom-toned.** It is a `surface`-tone
capsule matching the Sondr fields and the Friends row, not Apple's black
style — a black block reads as foreign in a greyscale app. **Apple's official
mark is kept** (`AppleLogoPainter` from the `sign_in_with_apple` package, never
Material's `Icons.apple`, which is not Apple's mark) along with the approved
wording "Sign in with Apple", so recognisability is intact. The auth call is
unchanged: `SignInWithApple.getAppleIDCredential`, only the presentation is
ours. **If App Review ever flags it, reverting to Apple's official black style
is a one-line change** — swap the custom capsule back for
`SignInWithAppleButton(style: SignInWithAppleButtonStyle.black)`.

## 6. Friends — rebuild to match TTM

Reference: `~/DevWork/TTMusic`, `TTMusic/Views/Profile/FriendsView.swift`.
Read it, then rebuild the behaviour in Flutter — port the interaction, not the
SwiftUI.

- [ ] **Tappable count headers** — "X Friends", "Y Pending", "Z Requests".
      Tapping expands the section; tapping again collapses it.
- [ ] **Three rows visible when expanded**, scrollable beyond that.
- [ ] **Rows are placeholder photo + username**, no "@" prefix.
- [ ] **Remove / Block revealed on swipe-left**, not permanently on the row.
      In TTM these sit visible at the row's trailing edge, and **Block is red —
      do not copy that.** Greyscale, per DESIGN.md.
- [ ] **Remove the add-by-search button.**
- [ ] **Symmetric edge spacing.**
- [ ] **Drop "No friends yet…"** and the other empty-state explainers.

Files: [`friends_screen.dart`](lib/features/friends/friends_screen.dart).

## 7. Feed

- [ ] **Cleaner delete-blur.** "Delete" as plain greyscale text — no white
      button, no border, no symbol.
- [ ] **Restyle the comments page** to match the app.
- [ ] **Restyle the comments themselves.**

Files: [`deletable_post_card.dart`](lib/features/feed/widgets/deletable_post_card.dart),
[`comments_sheet.dart`](lib/features/feed/widgets/comments_sheet.dart).

## 8. Profile — non-scrollable, labels matched to the in-ring figure

- [x] **Task labels match the in-ring figure.** Both now take the *same*
      `TextStyle` object (12 / bold), hoisted into one `figureStyle` local, so
      the two cannot drift apart. The label was 15 and not bold.
- [x] **The page fits the 393x852 reference without scrolling.**
- [x] **The effort summary lost its container** — see the new "A container
      means tappable" rule in [DESIGN.md](DESIGN.md). It was the only
      non-interactive block on the screen wearing one.

**Measured, not estimated.** Height available to the account section at
393x852, read off the render tree:

| Stage | Account section gets |
|---|---|
| Before | 235 |
| After the strip + label fix | 301 |
| After dropping the card chrome | **349** |

- **66** came from the in-progress strip, which declared 260 for content that
  measures 222 (tiles are 101, or 97 once the label shrank to 12).
- **48** came from the effort summary's card padding (24 top + 24 bottom).
- The five page gaps were normalised to one 12 unit, which is on-rule anyway.
- The grid was not touched and no circles were capped.

Confirmed on an iPhone 15 Pro simulator (1179x2556 = exactly 393x852), signed
in, with the real account's tasks: **no overflow warning in the log, "Sign out"
fully visible**, roughly 45-55pt of clearance left at the bottom.

**Not covered by a test.** `ProfileScreen` renders far enough to measure but
`AccountBody` needs `FirebaseAuth` and throws, so a widget test asserting the
shared `figureStyle` is not possible yet. The guarantee is structural — one
`TextStyle` object, two uses. Extracting `_TaskTile` would make it testable.

**Spacing.** The page is on the two tiers (`kSpacingBase` 12 /
`kSpacingSection` 24, see [DESIGN.md](DESIGN.md)), and the in-progress strip's
row gap moved 20 → 12, which was neither tier. The footer is pinned to the
bottom with `Spacer()` and sets its own 12 bottom margin; the page adds no
padding beneath it.

**No vertical scroll.** The page is a fixed `Column`; only the in-progress
strip scrolls, and only sideways. Verified on the live render tree: no
`axisDirection: down` anywhere in the Profile subtree.

**It is an EXACT fit at 393x852 — 703 of content in 703 of space, zero
buffer.** Measured on the live bounded tree, not a harness. Anything added to
this screen must take something else out.

### Known edges, accepted

- **Dynamic Type / bold text.** With the vertical scroll gone, `figmaScale()`
  keeps the layout inside smaller screens, but it scales to the *screen*, not
  to the OS text-size or bold-text accessibility settings. A large Dynamic Type
  setting can hard-overflow this page. Accepted deliberately: the ask was a
  fixed, non-scrolling page.
- **The guest footer keeps its own scroll view.** It is far taller than the
  signed-in one — heading, two actions, a divider and the Apple button — and
  genuinely does not fit. Scoped to the guest branch inside `AccountBody`, so
  the signed-in page has no vertical scrollable at all. Its real fix is item 5.
- **Sign out stays a Material `TextButton`** with its ~48 minimum tap target.
  It is off-standard (should be `SondrAction`) but the target is an
  accessibility floor and was explicitly not used as a source of pixels.

**The test harness lied by 40.** Early fit checks put the column at 743 when it
is 703, because they modelled the safe area but not the shell's tab bar, which
takes its own height plus the bottom inset before the body is measured. The
correction lives in [`test/support/app_viewport.dart`](test/support/app_viewport.dart)
so the next screen's fit check starts from the right number.

## Parked

- **Camera / capture** — skipped for now; designs and references to come.

## Done

- **Task dropdown** — spacing reworked, "Select your task" header removed.
