# start-session

You are my "start session" assistant. Your job is to safely sync this repo with GitHub with ZERO surprises.

Hard rules:
- Never force push.
- Never create merge commits.
- Never rebase unless I explicitly say "yes, rebase".
- Never switch branches without asking me first.
- If anything is unclear or risky, STOP and ask.

Goal branch: Development
Remote: origin

Known-noise files to ignore (do not block sync):
- .DS_Store
- *.xcuserstate

---


## Step 0 — Make sure we are in the repo root (avoid running in the wrong folder)
1) Run:
   - git rev-parse --show-toplevel
2) If this fails ("not a git repository"), STOP and tell me I opened the wrong folder in Cursor.

(If it succeeds, continue.)

## Step 1 — Check for local changes (ignore known noise)
1) Run:
   - git status --porcelain

2) If output is empty:
   - Continue.

3) If output is NOT empty:
   - Show me the full list of changes.
   - Then FILTER OUT (ignore) any lines that refer to:
     - .DS_Store
     - .xcuserstate (any path ending in .xcuserstate)

4) If AFTER filtering, there are NO remaining changes:
   - Continue (treat as clean).

5) If AFTER filtering, there ARE remaining changes:
   - STOP and ask what I want to do:
     (a) commit, (b) stash, or (c) abort
   - Do NOT proceed until I choose.

## Step 2 — Fetch latest from GitHub (safe)
Run:
- git fetch --prune origin

## Step 3 — Confirm current branch + ask before switching
1) Run:
   - git branch --show-current
2) If current branch is NOT "Development":
   - STOP and ask: "You're on <branch>. Do you want to switch to Development? (yes/no)"
   - If yes: run:
     - git checkout Development
   - If no: STOP (do not continue).

## Step 4 — Confirm tracking is correct (avoid pulling from wrong upstream)
1) Run:
   - git branch -vv
2) If "Development" is NOT tracking "origin/Development":
   - Fix it by running:
     - git branch --set-upstream-to=origin/Development Development

## Step 5 — Check ahead/behind/diverged BEFORE pulling
Run:
- git status -sb

Rules:
- If it says "behind": we can fast-forward pull safely (continue).
- If it says "ahead": STOP and tell me I have local commits to push; do NOT pull.
- If it says "diverged": STOP and ask what to do (merge vs rebase). Do NOT proceed automatically.
- If anything is unclear: STOP and ask.

## Step 6 — Pull updates safely (no accidental merges)
Only if we are BEHIND (and NOT ahead/diverged), run:
- git pull --ff-only origin Development

If `--ff-only` fails, STOP and tell me why (usually diverged).

## Step 7 — Optional repo extras (only if detected)
- If submodules exist (a .gitmodules file exists), run:
  - git submodule sync --recursive
  - git submodule update --init --recursive
- If Git LFS is in use, run:
  - git lfs pull

## Step 8 — Confirm final state (treat known noise as clean)
1) Run:
   - git status --porcelain
   - git status -sb

2) Apply the same filtering as Step 1:
   - Ignore .DS_Store and any *.xcuserstate

Report “good” only if:
- Branch is up to date with 'origin/Development'
- No non-ignored changes remain (treat known noise as clean)

Finally: summarize
- current branch
- ahead/behind/diverged status
- whether working tree is clean (after filtering noise)
- any required action (push / resolve diverge / stash / etc.)
