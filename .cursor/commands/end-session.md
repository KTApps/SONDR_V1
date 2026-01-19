# end-session

You are my "end session" assistant. Your job is to help me end work safely with ZERO surprises:
- Do not lose work.
- Do not commit/push noise files.
- Do not force push.
- Do not rebase.
- Ask before any action that modifies history or changes files.

Known-noise files to ignore:
- .DS_Store
- *.xcuserstate

Goal: leave the repo in a clear state: committed OR stashed OR intentionally left dirty.

---

## Step 0 — Confirm we are in the repo
Run:
- git rev-parse --show-toplevel
If this fails, STOP and tell me I opened the wrong folder.

## Step 1 — Check working tree (ignore known noise)
Run:
- git status --porcelain

If empty: continue.
If not empty:
- Show me the full list.
- Filter out lines for .DS_Store and any *.xcuserstate.
- If nothing remains after filtering: treat as clean and continue.
- If changes remain: continue to Step 2.

## Step 2 — If meaningful changes exist, ask how to finish
If there are meaningful changes, STOP and ask me to choose ONE:
A) Commit (recommended)
B) Stash (recommended for WIP)
C) Leave as-is (no changes)

### If I choose A) Commit
1) Show:
   - git diff --stat
2) Ask if I want to review full diff:
   - git diff
3) Ask what to stage:
   - Option 1: stage everything: git add -A
   - Option 2: interactive: git add -p
4) Confirm staged:
   - git status
5) Ask for a commit message, then commit:
   - git commit -m "<message>"
6) Check ahead/behind:
   - git status -sb
7) If ahead, ask if I want to push now:
   - If yes: git push
   - If no: stop.

### If I choose B) Stash
Run:
- git stash push -u -m "wip: end-session"
Then show:
- git stash list | head -n 5

### If I choose C) Leave as-is
- Do nothing.
- Warn that repo will be considered dirty next time (excluding noise) and start-session may stop.

## Step 3 — Final state summary
Run:
- git status -sb
- git status --porcelain

Apply the same noise filtering.
Summarize:
- current branch
- clean/dirty (after filtering)
- ahead/behind/diverged
- what actions were taken (commit/stash/left)
- any next steps (push later, pop stash later, etc.)
