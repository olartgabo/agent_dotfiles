---
name: sweep
description: >
  Clean up after merged work: find git worktrees, local branches and Orca
  workspaces whose PRs are merged or closed, list them with the evidence, and
  delete only what the user approves. Never touches dirty worktrees or unpushed
  work. Use when the user runs /sweep, or says "clean up my branches",
  "prune worktrees", "remove merged worktrees".
---

# Sweep

List first, delete second, and only with approval. A wrong delete loses work,
so every candidate needs proof that its work is safe somewhere else.

## 1. Scope

The repo is the current repo by default. `/sweep all` covers every repo Orca
manages (`orca worktree list --json` if the `orca` CLI exists), plus the
directories in `$REAPER_CLONE_ROOTS`.

## 2. Collect

For each repo:

```bash
git fetch --prune origin
git worktree list --porcelain
git for-each-ref refs/heads --format='%(refname:short) %(upstream:short) %(upstream:track) %(committerdate:relative)'
```

For each branch other than the default, check whether its PR is done:
`gh pr list --head <branch> --state all --json number,state,mergedAt,url --limit 1`.

## 3. Classify

**Safe to remove** (all of these must be true):
- The PR is `MERGED`, or `CLOSED` and the user confirms it's abandoned.
- Unpushed commits: `git log origin/<branch>..<branch>` is empty, or the
  remote branch is gone because the PR merged and every local commit is in
  the PR (`gh pr view <n> --json commits`).
- The worktree is clean: `git -C <path> status --porcelain` is empty.
- It isn't the current directory, the main worktree, or the default branch.

**Keep and report:**
- **dirty**: has uncommitted changes. List the files.
- **unpushed**: has commits that aren't in any PR. Show
  `git log --oneline origin/<base>..<branch>`.
- **no PR**: a branch with no PR that's older than 30 days. Report it, and
  never delete it.

Don't touch stashes. The stash stack is shared across worktrees and sessions.
Report the count only (`git stash list | wc -l`).

## 4. Confirm

```
Safe to remove (5):
  [x] ~/wt/feature-a   branch feature-a   PR #120 merged 3d ago
  [x] branch old-fix (no worktree)        PR #98 merged 2w ago
Kept (2):
  feature-b  dirty: 2 files modified
  spike-x    unpushed: 3 commits, no PR
```

Ask: "remove these 5?" The user may deselect items.

## 5. Remove

- Orca-managed worktree:
  `orca worktree rm --worktree path:<path>`. This also deletes the local
  branch when Orca can prove it's merged. Don't pass `--force` unless the user
  asks.
- Any other worktree: `git worktree remove <path>` (without `--force`), then
  `git branch -d <branch>`. Squash merges make `-d` refuse. Use `-D` only for
  branches classified as safe in step 3.
- Remote branches: GitHub usually deletes merged branches. If one remains,
  list it and delete it only on a separate yes:
  `git push origin --delete <branch>`.

Report what you removed and anything that failed, with the error.
