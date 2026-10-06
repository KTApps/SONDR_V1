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

- [x] **Collapsing count headers** — "1 Request", "2 Friends", "1 Pending",
      inline like TTM, in our 15/Bold. Requests and Pending collapse and are
      mutually exclusive; Friends is always open and fills the page.
- [x] **Rows are placeholder photo + username**, no "@" prefix. The photo is a
      surface-toned **circle** — TTM's is a solid white square, and white fills
      are banned here.
- [x] **Remove / Block revealed on swipe-left.** TTM keeps them visible on the
      row and tells them apart with red; we summon them and keep both white, at
      the username's own size and weight so they read as part of the row.
- [x] **Live handle search, restored.** An earlier pass removed it in favour of
      submit-to-add; this one brings TTM's behaviour back — typing filters
      live, the results replace all three sections, and you add by tapping a
      result. Enter only dismisses the keyboard.
- [x] **Symmetric edge spacing** — 24 throughout.
- [x] **Drop "No friends yet…"** and the other empty-state explainers. Search
      keeps one quiet "No one found".
- [x] **Invite**, pinned at the bottom with **Back** beneath it, which replaces
      the top chevron the screen used to carry.

**Spacing follows TTM, type follows Sondr.** The gaps are TTM's — 8 between
sections, 12 in a header — with rows a little looser (10 either side) because
our 36 photo is taller than TTM's 30, and tuned so six friends sit on the
reference screen.

**Which actions are visible is the rule worth keeping:** an action that IS the
row's purpose stays on the row, and management actions hide behind the swipe.
A request is a decision, so Accept (white) and Decline (grey) are both visible;
removing, blocking and withdrawing are summoned.

**The invite copies a link rather than sharing it.** The app has no OS share
mechanism and adding one means a new dependency, so the TestFlight link goes to
the clipboard with a "Copied" confirmation. Worth revisiting with `share_plus`.

### Block — CODE COMPLETE, DEPLOYMENT PENDING

**Not done until the rules are live on `sondr-cd439`.** The client code and the
rules are written and committed; the rules have NOT been deployed, so a
modified client can still create a friendship across a block. Until then,
blocking is enforced only in the app.

**Deploy with the project named explicitly:**

    firebase deploy --only firestore:rules --project sondr-cd439

**Never deploy from here without `--project`.** `.firebaserc` says
`prodapp-b90ac` while `firebase.json` points every app target at
`sondr-cd439` — so a bare `firebase deploy` publishes Sondr's rules to the
wrong project, silently, and overwrites whatever that project is running. The
app's own rules would never arrive, and the block would look deployed while
being unenforced.

**What was built.** A directional `blocks/{blocker}__{blocked}` document,
readable by the blocker alone and carrying the blocked person's denormalised
handle so the Blocked screen renders without an owner-only cross-read. The id
is derived rather than random precisely so the rules can `exists()` a document
the asking user cannot read. `blockUser` batches the unfriend and the block
together so neither can half-complete; `unblockUser` deletes the record and
does not restore the friendship. Requests, accepts and handle search all refuse
across a block in either direction, and the request refusal reuses the "no one
found" wording — telling someone they have been blocked is itself information.
Friends' swipe Block now blocks, retiring the alias-to-Remove liability.

### Follow-ups from the block work

- **A blocked person's existing posts stay in the feed.** The feed is
  friends-only via an `audience` array **written at post-creation time**, not a
  live join against the friends list — so unfriending does not retroactively
  remove the reader from posts that already exist. The assumption that blocked
  posts drop out via the unfriend is wrong. Fixing it needs either a client
  filter against the blocked set or an audience rewrite on unfriend.
- **Comments by a blocked person on a mutual friend's post are still shown.**
  Deferred deliberately.
- **`.firebaserc` should probably be corrected to `sondr-cd439`**, but it was
  left alone: nobody has confirmed whether `prodapp-b90ac` is still wanted for
  something. Until that is answered, always pass `--project`.

### The original note, kept for history

**`Block` currently calls `remove`.** There is no block in the data model and no
backend for it, so the button unfriends and nothing more. Shipping that would
be misleading: a blocked person would still be able to find and re-add you.

Needs: a block record (blocker, blocked, timestamp), enforcement in the
friend-request path and in the handle lookup so a blocked user cannot send or
search, and a way to unblock. Until then the UI is in place and the behaviour
is not.

Files: [`friends_screen.dart`](lib/features/friends/friends_screen.dart).

## 7. Feed

- [x] **Cleaner delete-blur.** Delete is plain white text — the solid white
      `ElevatedButton` with its bin glyph is gone — and Close sits beneath it
      in the grey supporting tone. The blur and scrim are unchanged, and a
      scrim tap still dismisses.
- [x] **Restyle the comments page** — `SondrField` composer, a grey "Post"
      action in place of the send glyph, the divider dropped, type on the
      table.
- [x] **Restyle the comments themselves** — avatar on the named scale,
      author 15/Bold, timestamp 12/Bold metadata, body 13, and the delete
      glyph replaced by text.
- [x] **No icons anywhere in the feed.** Like/Comment are words, with the Like
      state carried by tone and weight rather than a filled heart. Counts sit
      beside the word as 12/Bold metadata and are hidden at zero. The
      empty-state glyph went too. Codified in DESIGN.md.
- [x] **On-photo whites tokenised** — `kOnPhoto` / `kOnPhotoDim` /
      `kOnPhotoFill`. They are the only literal whites left in the app and the
      token file says why: a photo is not on the brightness ladder.
- [x] **Named avatar scale** — `kAvatarList` 36 / `kAvatarPost` 32 /
      `kAvatarComment` 28, circular everywhere.

**One thing the tests caught:** the delete overlay had a slim-card layout that
put Delete and Close side by side. Stacking them overflowed a session card by
16, so the overlay's padding is tighter rather than the layout branching.

### Follow-ups from item 7 — neither blocking

- **Comments sheet has no loading timeout.** The sheet handles loading, error
  and empty correctly, and a null repository falls back to an empty stream. But
  a stream that attaches and never emits — offline, a hung listener, rules
  rejecting a read without erroring — leaves the spinner running forever. A
  few-second timeout falling through to the empty state would close it.
  Pre-existing, not introduced here.
- **The milestone ring's two paths have diverged.** Off a photo it draws through
  `ProgressRing`, which got brighter when item 3 moved it onto
  `GreyscaleTokens`; over a photo it bypasses `ProgressRing` entirely and draws
  a near-white ring with a halo and scrim. Side by side they no longer look
  like the same component. Worth deciding whether to tone the off-photo one or
  converge the two.

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

## Off-system audit — 6 October 2026

Taken after the greyscale pass closed out (`59fe74b`…`bbc3198`). Those commits
cleared every Material **spinner**, **navigation chevron**, **SnackBar** and
**filled button** from `lib/`; verified zero at the time of writing. No hue
anywhere either — every `Color(0x……)` literal in `lib/` decodes to R==G==B.

What follows is everything still off-system, with locations, so it can be
cleared in planned batches rather than piecemeal. Line numbers are as of
`bbc3198` and will drift.

**Excluded as sanctioned:** the Apple mark (`AppleLogoPainter`), the on-photo
tokens and `RingPainter`'s `onPhoto` halo, and anything behind `kDebugTools`
(the debug panel, the prime-milestone control).

### 1. Material screens the chevron sweep missed

Three screens still use `AppBar` rather than `SondrHeader`, so they kept both
the Material bar **and** an `arrow_back_ios_new` icon. The sweep only reached
`SondrHeader`'s callers.

- [ ] `features/milestone/share_caption_screen.dart:86` + `:91`
- [ ] `features/photos/collages_screen.dart:24` + `:35`
- [ ] `features/history/calendar_screen.dart:34` + `:48`

Each wants the `SondrHeader` + grey "Back" treatment the rest of the app uses.

### 2. The two prompt dialogs — one replacement

Both are `AlertDialog`s doing the same job: a title, one text field, cancel and
confirm. Neither should exist.

- [ ] `features/timer/widgets/task_dropdown.dart:130` — "Add task". Partly
      converted: a hand-rolled `Container` + bare `TextField` (its own
      `lerp(surface, ringTrack, .5)` base, 24 radius, 20/15 padding — none of
      it `SondrField`), a `hintText`, off-tier `actionsPadding`, and a
      half-converted action pair (Material `TextButton` "Cancel" beside a
      `SondrAction` "Add").
- [ ] `features/habits/habits_overlay.dart:132` — "Add habit". The same dialog,
      less converted: default background, bare `TextField` with
      `InputDecoration(hintText:)`, **both** actions still `TextButton`.

**Proposed: one `SondrPrompt`** — Sondr surface, 20/bold title, `SondrField`,
`SondrActionPair`-style actions. Retires both `AlertDialog`s, three
`TextButton`s, the hand-rolled field and the half-converted pair in one move.
`SondrField` would need a hint/placeholder option, which it has never had.

### 3. Material icons — 12, none sanctioned

Navigation (5) — should be text actions:
- [ ] `share_caption_screen.dart:91`, `collages_screen.dart:35`,
      `calendar_screen.dart:48` — `arrow_back_ios_new` (see §1)
- [ ] `profile_screen.dart:213`, `:266`, `:321` — `chevron_right` on the
      doorway rows. The sweep killed `chevron_left` in `SondrHeader`; these
      three survived.

Decorative (1):
- [ ] `profile_screen.dart:184` — `people_outline` on the Friends row.

Functional (6) — each needs a text or shape answer, not a glyph:
- [ ] `task_dropdown.dart:74` — `keyboard_arrow_down`, the selector affordance
- [ ] `milestone_share_flow.dart:346` — `check`, selection tick
- [ ] `photo_capture_flow.dart:170` — `camera_alt_outlined`
- [ ] `photo_capture_flow.dart:221` — `close`
- [ ] `collage_grid.dart:179` — `close`, remove-photo
- [ ] `day_detail_sheet.dart:357` — `broken_image_outlined`, image error

### 4. A token used as a fill on something untappable

- [ ] `profile_screen.dart:195` — the **"N new"** pending-requests badge fills
      with `ringFillOuter`. The last white fill in the app, and it is not a
      button. ("A container means tappable" does not cover it.)

### 5. Material ripple

`SondrAction` deliberately uses a `GestureDetector` so no ripple appears. These
four still ink:

- [ ] `shell/main_shell.dart:81` — the tab bar
- [ ] `profile_screen.dart:163`, `:246`, `:301` — the doorway rows

### 6. Palettes that bypass the tokens

- [ ] `shared/ring/segmented_dial.dart:70-71` — private
      `_filled = #777777` / `_empty = #232323`, commented "Exact Figma values".
      The dial runs its own palette instead of `ringFillInner`/`ringTrack`.
      These are the very hex values a stale `milestone_card` comment cited long
      after they stopped applying there.
- [ ] **19 ad-hoc black scrims across 12 distinct strengths**, no shared token:
      `0x1A` ×4, `0x22` ×2, `0x99` ×2, `0x9E`, `0xAA`, `0xCC`, and alphas
      `.3 .35 .4 .5`×3 `.55 .72` — in `milestone_card`, `post_collage`,
      `collage_grid`, `day_detail_sheet`, `calendar_screen`,
      `deletable_post_card`, `profile_screen`, `milestone_share_flow`.
      (`ring_painter`'s two `.45` halo values are the sanctioned on-photo case.)
      Wants a small scrim scale — three or four named steps.

### 7. Backend gap — reciprocal blocks

- [ ] `bbc3198` hides content by people **you** blocked. The reciprocal case —
      someone who blocked **you** — cannot be filtered client-side: their block
      document is readable by its author alone, and that is deliberate, since
      being able to read it would let you detect you had been blocked.
      **Needs a cloud function** that drops the blocker from the other party's
      post audiences on block creation. No client half-measure: any attempt
      either leaks the block or silently fails.

### 8. Device-verification backlog — 7 screens

Code-verified (analyzer + suite) but **never rendered by anyone**. The largest
untested surface on the branch.

From the SnackBar sweep (`c4da54f`) — inline errors never seen:
- [ ] delete overlay — `deletable_post_card`
- [ ] photo capture — `photo_capture_flow`
- [ ] share caption — `share_caption_screen`
- [ ] Apple landing — `apple_sign_in_button` (the no-`onError` branch)

From the pill conversion (`0806276`):
- [ ] milestone celebration primary
- [ ] the new-task dialog's "Add"
- [ ] photo-capture keep | retake

Also unobservable until the Firestore rules are deployed: **Block has never
worked end to end**, so the Blocked-accounts screen, the Friends entry and
`bbc3198`'s author filtering are all unexercised.

### Stale note elsewhere in this file

The item under Profile claiming **"Sign out stays a Material `TextButton`"** is
no longer true — it is a `SondrAction(supporting: true)` as of the auth work.
Left in place rather than edited silently; worth correcting next pass.

## Parked

- **Camera / capture** — skipped for now; designs and references to come.

## Done

- **Task dropdown** — spacing reworked, "Select your task" header removed.
