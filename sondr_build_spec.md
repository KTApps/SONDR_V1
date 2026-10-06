# Sondr — Build Spec

A social effort-tracking app. Like Strava, but for any pursuit (revision, instrument practice, sport drills, languages, any hobby) rather than fitness. Built in Flutter for iOS and Android.

The driving philosophy: it takes ~20 hours to reach competence and ~10,000 hours to reach mastery. Sondr measures effort against those milestones. It is not a competition — it is a diary of effort. You vs. your past self. Friends exist to motivate, not to compete.

---

## Core principles (the things that must not drift)

1. **The ring is the hero, everywhere.** The dual-ring progress dial is the signature visual. It appears on the home screen, in every feed post, and on profiles. Build it once as a reusable component and reuse it.
2. **Effort is the content, not the person.** Unlike Instagram, the unit of social currency is hours and streaks, not faces or aesthetics. Photos are optional evidence, never the main event.
3. **Pure greyscale.** No accent colour. Contrast comes from brightness, not hue. This is the deliberate identity — a confident monochrome effort diary, not another orange-accent app.
4. **Not gamified (yet).** No leaderboards, no rankings, no competition at launch. If users ask for it later, revisit. For now it is a personal record that friends can witness and encourage.

---

## Visual design language

### Colour: pure greyscale, three-tone brightness ladder

There is no colour. Legibility comes from keeping three greys far apart on the brightness ladder:

- **Background / card surface** — near-black (dark mode) / near-white (light mode)
- **Ring track (empty portion)** — muted mid-grey
- **Ring fill (progress)** — near-white (dark mode) / near-black (light mode)

The hard rule: protect the brightness spread between these three. If track and fill drift toward each other, the ring goes mushy. Keep them far apart.

Two rings on one dial are distinguished by brightness, not colour: the **outer (task) ring is brightest**, the **inner (habit) ring is one step dimmer**.

Light and dark mode both supported — the ladder simply inverts (dark arc on light track in light mode).

### The dual ring

- **Outer ring** = time logged toward the current task today, filling toward the active milestone (first milestone = 20 hours).
- **Inner ring** = daily habits completed today (completed ÷ total habits).
- Centre of the dial shows the task's time figure (e.g. "13 hrs · today").

### Photos on feed posts (optional)

A post can have a photo or not. Same card layout either way — only the background surface changes:

- **With photo:** the photo is a full-bleed backdrop filling the whole card. Everything (profile pic, milestone badge, ring, caption, likes/comments) layers on top.
- **Without photo:** the same card on a dark-grey surface.

**Three techniques keep greyscale rings legible over ANY photo** (these are mandatory for the photo case):

1. **Double-stroke ring.** Under the white progress arc, lay a slightly wider semi-transparent dark stroke (and a faint light stroke under the track). Each ring carries its own contrast halo so it never relies on the photo cooperating. Same idea as the dark outline on film subtitles.
2. **Gradient scrim.** A vertical gradient over the photo — darker at top and bottom (where text/icons sit), lighter in the middle (where the ring sits). Not a flat dim. This guarantees readability over bright or busy photos.
3. **Text shadows** on all overlaid text (caption, username, like/comment counts).

On no-photo cards, the under-stroke can be dropped (near-white on near-black needs no help). The milestone badge flips to a white pill with dark text on photos (the grey badge would get lost on a busy image).

### Typography

Inter, used across the Figma. Weights kept to regular + medium/bold. Sentence case.

---

## App structure

### Phase 1 — Core tracker (build this first, no social)

**Main / timer screen**
- Task dropdown at top (switch between the user's tasks; "Add Task" option).
- Live manual timer (start / pause / stop). Manual, not GPS or sensor-based.
- Dual-ring dial (outer = task time today toward milestone; inner = today's habits).
- Task time figure in the centre.
- "Last 10 days" row of 10 mini-rings below.
- "View Your Progress" → opens calendar history view.
- Top-right buttons: one is settings, one leads to the (phase 1) friends/milestones section. **Note:** in phase 2 this moves into a dedicated profile tab and the top-right button is no longer needed.

**Milestone celebration**
- Triggered at each milestone (first at 20 hours, then every 20 hours for consistency — ties to the 20-hour philosophy).
- "Congratulations! You've reached your first milestone, 20 hours." + "Take a photo to mark the moment" (optional) → camera → becomes the seed of a feed post in phase 2.

**Focus mode**
- An optional state that quietens the app — the user is locked into the task they're doing, using the app only to pause/stop the timer when they break or finish. Reinforces the "locked into the effort" ethos. Prompt: "Would you like to enable Focus Mode during this task?"

**Daily habits (inner ring)**
- A single global habit list belonging to the user (e.g. "6AM Wake, Make Bed, Cold Shower, Morning Run, 50 Press Ups").
- Editable: add or remove habits.
- Independent of tasks — no coding relationship between habits and timed tasks.
- Each day tracks which habits were checked off; checkmarks reset daily, the list carries over.
- Shown as a daily checklist (the "Monday / Day 12" screens) with strike-throughs as completed.

**Calendar / progress history**
- Calendar view where each day is a ring you can look back on.
- Tapping a day shows that day's detail (date, time per task, the day's rings).

### Phase 2 — Social layer (slots in after profile tab exists)

- Friends-only. No global discovery, no strangers.
- **Tab structure** replaces the phase-1 top-right button: a Profile tab holds milestones, friends, settings.
- **Feed:** vertical scroll of posts with rhythm — big milestone cards, medium streak cards, tiny one-line session logs. Routine activity never drowns meaningful achievements.
- **Post types:**
  - *Milestone post* — the completed dual ring is the hero, big hours figure, optional photo backdrop, caption.
  - *Streak post* — streak number is the hero ("12-day habit streak"), habit list as small print.
  - *Session log* — deliberately tiny, single line ("Tom logged 2h 15m · Spanish"), only if non-milestone posting is enabled.
- **Post trigger:** milestone-triggered by default (every 20 hours). This keeps the feed alive automatically, makes each post meaningful, and reinforces the 20-hour philosophy. Optionally allow manual "share a session" later if users ask.
- **Profile:** NOT a photo grid. The hero is an effort summary — total lifetime hours, current streak, milestones hit — followed by tasks-in-progress shown as mini rings (e.g. Golf 20/20 done, Spanish 11/20, Piano 5/20). Answers "what is this person working on and how far have they got" — a question Instagram can't.
- **Interactions:** like + comment. Keep the familiar scroll/like/comment pattern — originality lives in what fills the card (rings, hours, streaks), not in inventing new interactions.

---

## Data model decisions (settled)

- **Habits and tasks are architecturally separate.** No foreign keys, no shared logic. A user has one ordered habit list + a per-day completion record. Each task accumulates total seconds over its lifetime and fills toward its current milestone.
- **Immutable history.** When a user edits the habit list (e.g. removes a habit after 40 days), past days still show what was actually true then. Edits apply going forward only. Implementation: snapshot the habit list per day rather than referencing one live list. This is the honest-diary spirit and is painful to retrofit, so build it this way from the start.
- **Task time:** stored as accumulated seconds per task; "today" figure is time logged since midnight for that task.

---

## Suggested build order

1. **The dual-ring component first.** It's the heart of the app and is reused on the home screen, feed cards, and profile. Get it right once — including the greyscale three-tone ladder and the double-stroke variant for photo backdrops.
2. **Main timer screen** — task dropdown, manual start/pause/stop timer, wire it to the outer ring.
3. **Daily habits** — global editable list, daily checklist, wire to the inner ring, with per-day snapshotting for immutable history.
4. **Last 10 days row + calendar history view.**
5. **Milestone celebration + optional photo capture.**
6. **Focus mode.**
7. *(Phase 2)* Profile tab, friends, then the feed and post types.

---

## Tech notes

- **Framework:** Flutter (Dart). Develop and preview on the iOS Simulator first (already set up), add Android testing later via Android Studio.
- **Backend:** Firebase is a natural fit (same as the previous app, TTM) — Firestore for tasks/habits/posts, Storage for photos, Auth for accounts.
- **The photo-backdrop card** in Flutter is a `Stack`: image layer → gradient scrim container → content `Column` on top. Trivial to build, but the scrim must be baked in as a fixed layer or bright photos will break legibility.
- **Greyscale tokens:** define background, track, and fill greys as fixed design tokens and never let them drift together. One set for dark mode, the inverse for light mode.

---

## Open questions to revisit later (not blockers)

- Should the ring on a feed post be interactive (tap to see the day-by-day climb) or static? Start static for the 100-user test; interactive is a v2 upgrade.
- Whether to allow non-milestone session posts. Launch milestone-only; let real user behaviour during the test decide.
- Whether friends ever get light competition/comparison. Launch without; revisit only if users ask.
