---
description: Safely sync this repo with GitHub before starting work
---

You are my "start session" assistant. Sync this repo with GitHub with ZERO surprises,
then tell me where my co-founder left off.

**Context: two people, one shared branch, never at the same time.**
We do not create branches. We pull at the start of every session and push at the
end of every session. The whole system depends on that ritual being unbroken, so
any sign that it *was* broken (diverged history, unpushed commits, a stale
`HANDOFF.md`) is a real problem — say so loudly rather than quietly fixing it.

**Hard rules:**
- Never force push.
- Never create merge commits.
- Never rebase unless I explicitly say "yes, rebase".
- Never switch branches without asking me first.
- If anything is unclear or risky, STOP and ask.

**Target branch:** `$1` — if I gave no argument, use `RESURRECTION`.
**Remote:** `origin`

**Known-noise files** (do not block sync):
- `.DS_Store`
- any path ending in `.xcuserstate`

**Flutter build churn** (generated, treat as noise but MENTION it rather than
silently ignoring — `pubspec.lock` and `ios/Podfile.lock` can carry real changes):
- `analysis_options.yaml`, `pubspec.lock`, `ios/Podfile.lock`
- `linux/flutter/generated_plugins.cmake`, `windows/flutter/generated_plugins.cmake`
- `macos/Flutter/Flutter-Debug.xcconfig`, `macos/Flutter/Flutter-Release.xcconfig`
- `macos/Flutter/GeneratedPluginRegistrant.swift`

---

## Step 0 — Confirm we are in the repo root
Run `git rev-parse --show-toplevel`. If it fails, STOP and tell me I opened the
wrong folder.

## Step 1 — Check for local changes
Run `git status --porcelain`.

- Empty → continue.
- Not empty → show me the full list, then filter out the known-noise files.
  - Nothing left after filtering → treat as clean, continue.
  - Only Flutter build churn left → say so, offer `git restore .`, continue once I answer.
  - Real changes left → STOP and ask: (a) commit them now, (b) stash them,
    (c) abort. Do not proceed until I choose. Prefer (a): a stash is local-only
    and invisible to my co-founder, so it is not a safe place to leave work.

  Note: real uncommitted changes at the *start* of a session mean the last
  `/end-session` did not finish. Point that out — whatever is sitting here was
  invisible to my co-founder while they worked.

## Step 2 — Fetch
Run `git fetch --prune origin`.

## Step 3 — Confirm branch
Run `git branch --show-current`. If it is not the target branch, STOP and ask
whether to switch. Only `git checkout <target>` if I say yes.

## Step 4 — Confirm tracking
Run `git branch -vv`. If the target branch is not tracking `origin/<target>`,
fix with `git branch --set-upstream-to=origin/<target> <target>`.

## Step 5 — Check ahead/behind BEFORE pulling
Run `git status -sb`.

- behind → safe to fast-forward, continue.
- up to date → continue, but say so: it means nobody has pushed since my last session.
- ahead → STOP. This means the last `/end-session` did not push. Show me the
  unpushed commits (`git log origin/<target>..HEAD --oneline`) and tell me my
  co-founder has been working without them. Ask whether to push now. Do NOT pull.
- diverged → STOP and ask (merge vs rebase). Do NOT proceed automatically.
  Say plainly that this means we both edited the branch without syncing — the one
  thing this workflow exists to prevent.
- unclear → STOP and ask.

## Step 6 — Pull
Only if behind and not ahead/diverged: `git pull --ff-only origin <target>`.
If `--ff-only` fails, STOP and explain why.

## Step 7 — Dependencies
If `pubspec.yaml` or `ios/Podfile` changed in the pulled commits, run
`flutter pub get` (and `cd ios && pod install` if the Podfile changed).
Note that this will re-dirty the build-churn files — that is expected.

## Step 8 — Read the handoff
Read `HANDOFF.md` at the repo root and show it to me **in full**. This is the
most important step — it is how I pick up unfinished work.

Then add your own read of it:
- Who wrote it and when (compare against `git log -1 --format='%an %ar' -- HANDOFF.md`).
- If the "In progress" section is non-empty, that is where I should start.
  Open the files it names so they are ready.
- If `HANDOFF.md` is missing, say so and offer to create it from the template.
- If it is stale (unchanged for several sessions, or it still describes work that
  the git log shows as finished), say so — do not read it out as if it were current.

## Step 9 — Final state
Run `git status -sb` and `git status --porcelain`, apply the same filtering,
then summarise:
- current branch
- ahead / behind / diverged
- clean or dirty after filtering
- what the handoff says I should pick up
- any required action
