# Sondr design language

How Sondr looks and why. This is the standard every screen is held to — read it
before building or restyling any UI, and treat a conflict between this file and
an existing screen as a bug in the screen.

## The canvas

Near-black greyscale. Contrast comes from brightness, never hue.

The tones are fixed tokens in
[`lib/core/theme/greyscale_tokens.dart`](lib/core/theme/greyscale_tokens.dart) —
`background`, `surface`, `ringTrack`, `ringFillOuter`, `ringFillInner`, and
three text tones. Read them from `GreyscaleTokens.of(context)`. Never hardcode a
hex value in a widget, and never nudge two tones closer together: the rings stop
reading as distinct and the whole screen goes mushy.

## No colour. Anywhere.

There is no accent colour in Sondr, and no exceptions for emphasis, state, or
severity.

**This includes destructive actions.** Remove, Block and Delete are greyscale
like everything else. They are told apart by their label and their placement —
never by red, and never by any other hue. A red tint is not a shortcut to
"serious"; if an action needs weight, give it a confirmation step, not a colour.

## White is text, not a surface

White is the brightest end of the brightness ladder, and it is reserved for text
that must dominate: a heading, the live timer value, the active tab.

**Actions are white.** Every text action on a screen — Start, Stop, Add Task,
View your progress — uses the same standard action style: 15, bold,
`textPrimary`, no tracking, no uppercase, no bespoke weight. Actions are
uniform, and hierarchy comes from **position**, not from weight or tone. A
control that needs to shout is a symptom of a screen that has too much on it.

**Grey is for supporting text.** `textSecondary` and `textTertiary` are for the
copy around an action — labels, units, captions, metadata like the "today"
under the live figure.

**One class of action is grey too: the exit.** Sign out, and later Remove,
Block and Delete, use the supporting treatment — **grey and regular weight**,
at the same size and with the same tap target as any other action. They sit
below the primary actions, which stay white and bold.

This is not a breach of "actions are white"; it is the supporting clause
applied to an action whose job is to be findable, not inviting. Hierarchy
still comes from position first — the exit goes last — with tone reinforcing
it rather than replacing it.

**The thing to watch:** grey can read as disabled. It stays legible here
because these actions sit in their normal place in the flow and are the only
grey item in a column of white ones. A genuinely disabled control is dimmed by
opacity, not by switching to the supporting tone.

**White is never a fill.** No white buttons, no white pills, no white cards. A
solid white shape on a near-black canvas is the loudest thing on the screen, and
it pulls attention away from the rings — which are the thing worth looking at.

## A container means "tappable"

A filled rounded rectangle is an affordance, not decoration. **Only interactive
surfaces get one** — the Friends row, the gallery and milestones doorways, list
items. Anything you can tap may sit on a `surface`-toned panel; anything you
cannot, may not.

**Static and summary content sits bare on the background**, at the page's own
gutter. The effort summary on Profile — lifetime hours, day streak, milestones
— is read-only, so it has no panel: three figures and their labels, divided by
hairlines, directly on the page.

The test is simple: if a block wears a container but nothing happens when you
press it, the container is lying. Take it off.

## Actions are minimal

An action is one of three things, in order of preference:

1. **Light text on the canvas** — the default. "Add Task", "View your progress".
2. **A subtle outline** — when the tap target needs a visible edge.
3. **A restrained dark shape** — a `surface`-toned container, for the rare
   action that must read as a solid object.

Never a bold filled button. If an action feels like it needs a heavy fill to be
noticed, the surrounding screen is too busy — quieten the screen instead.

## Spacing is airy, generous and even

Space is the main compositional tool on a monochrome canvas, so it carries more
weight here than in a colourful app.

Use **one spacing unit throughout a component** rather than tuning each gap
separately — above the first item, between items, below the last, and inside the
container's edges. The reworked task dropdown
([`task_dropdown.dart`](lib/features/timer/widgets/task_dropdown.dart)) is the
reference: a single `_spacing` constant drives every gap, and that evenness is
what makes it feel light.

**Across a whole screen there are two tiers**, in
[`lib/core/theme/spacing.dart`](lib/core/theme/spacing.dart):

| Tier | Value | Use |
|---|---|---|
| pairing | 6 | binds a label to its value |
| `kSpacingBase` | 12 | rhythm WITHIN a group |
| `kSpacingSection` | 24 | separation BETWEEN zones |

**Pairing (6) is deliberate, not a stray value.** A label and the value it
labels — a field's label above its capsule, "Signed in" above the email,
"Guest account" above its line — sit a half-base apart so they read as one
thing. It is *meant* to be below the base: the ceiling below caps the maximum,
never the minimum. Do not "normalise" these to 12 — on Profile, which fits its
screen exactly, that alone would overflow the page.

Twice the base, so the two read as different tiers rather than a nudge. Profile
is the reference: its four zones — stats, doorways, in-progress, account footer
— are separated by the section break, and everything inside a zone uses the
base. Nothing in between: if a gap is not clearly one tier or the other, the
grouping is wrong, not the number.

**No vertical gap exceeds the section unit.** 24 is a ceiling, not a
suggestion. If a screen needs to fill space, use a flexible spacer — as
Profile's pinned footer does — never an inflated fixed gap, and never a
`MainAxisAlignment.spaceEvenly` / `spaceBetween` that distributes the surplus
into several large voids. Empty space belongs in one deliberate place, not
smeared between the controls.

**Mind a component's own padding.** The gap you SEE is what has to be on-tier,
not the number in the source. `SondrAction` carries 12 of vertical padding as
its tap target, so a declared 24 above one renders as 36 — over the ceiling.
Subtract the component's padding when setting the gap, and note that two
stacked actions already meet at 24 with nothing between them.

**A pinned footer sets its own bottom margin.** Where a block is pinned to the
bottom of the safe area, the page stops adding padding beneath it and the
footer's own trailing space is the single thing setting that distance — two
sources for one gap is how it drifts.

Panels fit their contents. A fixed-height container with a void in it — and a
control stranded at the bottom — is the failure mode to avoid.

## One type system

Every screen uses the same scale. The Home screen is the reference; any page
that has drifted gets aligned to it, not the other way round.

| Role | Size | Weight |
|---|---|---|
| Hero figure | 44 | Bold |
| Section heading | 20 | Bold |
| Body / label / action | 15 | Bold |
| Supporting text | 13 | Regular |
| Metadata, in-ring figures | 12 | Bold |

**Hero figure** is for a dominant standalone figure, like the Focus clock,
where there is no ring to give it scale. Home's dial figure stays at 20 because
the ring around it supplies the scale; used alone on an empty screen, 20 reads
as small. One hero figure per screen at most.

Size alone never carries meaning — pair it with the right text tone
(`textPrimary` / `textSecondary` / `textTertiary`).

The auth pages are the known drifters. Align them.

## Cut every redundant word

If a label restates what the screen already makes obvious, delete it. Empty
states that explain the obvious ("No friends yet — add some friends to get
started"), units the ring already shows, hints in fields whose purpose is plain
from the label — all go.

Shorter is not terser. It is calmer.

## Sondr's own components

Build Sondr's components. Never ship an iOS default because it was quicker: no
stock `CupertinoButton`, no default `AlertDialog` chrome, no system switch.
Filled Material buttons (`FilledButton`, `ElevatedButton`) are banned outright by
the rules above.

**The concentric ring is the signature.** Two rings — outer for tasks, inner for
habits — one brightness step apart. It appears at hero size on Home, small in
the "Last 10 days" cells, and as a motif elsewhere. Keep it subtle: it should
read as the app's fingerprint, not as decoration applied on top.

## Checklist before shipping a screen

- No colour, including on destructive actions
- No white or otherwise filled buttons
- Containers only on tappable surfaces; static content sits bare
- Actions are white and bold; only exit actions (Sign out, Remove, Block,
  Delete) take the grey + regular supporting treatment
- One spacing unit, evenly applied
- Type sizes from the table above
- Tones read from `GreyscaleTokens`, nothing hardcoded
- Every word earns its place
- Scales with `figmaScale()` rather than fixed pixel positions
