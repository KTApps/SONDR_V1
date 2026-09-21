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

**White is never a fill.** No white buttons, no white pills, no white cards. A
solid white shape on a near-black canvas is the loudest thing on the screen, and
it pulls attention away from the rings — which are the thing worth looking at.

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

Panels fit their contents. A fixed-height container with a void in it — and a
control stranded at the bottom — is the failure mode to avoid.

## One type system

Every screen uses the same scale. The Home screen is the reference; any page
that has drifted gets aligned to it, not the other way round.

| Role | Size | Weight |
|---|---|---|
| Section heading | 20 | Bold |
| Body / label / action | 15 | Bold |
| Supporting text | 13 | Regular |
| Metadata, in-ring figures | 12 | Bold |

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
- One spacing unit, evenly applied
- Type sizes from the table above
- Tones read from `GreyscaleTokens`, nothing hardcoded
- Every word earns its place
- Scales with `figmaScale()` rather than fixed pixel positions
