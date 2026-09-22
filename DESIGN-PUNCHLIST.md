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

- [ ] **Entry popup** — minimal.
- [ ] **Timer page** — minimal, reusing the new button style.

Files: [`focus_view.dart`](lib/features/focus/focus_view.dart).

## 3. Progress circles

- [ ] **Drop "of 20h"** — the ring already communicates proportion.
- [ ] **Past 20h, show accumulated time against a full ring.** Currently
      progress resets into further 20-hour bands; instead, once the first
      milestone is passed the ring reads full and the figure keeps climbing.
      **This is a logic change, not just styling** — small, but it touches
      milestone/progress calculation, so it needs its own check.
- [ ] **Neaten** the ring and its figure.

## 4. Guest

- [ ] **Remove the explainer text** under the guest account.

Files: [`account_screen.dart`](lib/features/auth/account_screen.dart).

## 5. Auth

- [ ] **Simplify sign-in.**
- [ ] **Simplify choose-a-handle**, and remove the "e.g." from the handle field.
- [ ] **Align the typography to Home** — these are the known drifters.

Files: [`auth_screen.dart`](lib/features/auth/auth_screen.dart),
[`handle_screen.dart`](lib/features/auth/handle_screen.dart).

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

## Parked

- **Camera / capture** — skipped for now; designs and references to come.

## Done

- **Task dropdown** — spacing reworked, "Select your task" header removed.
