# /reaper green: get approved PRs mergeable

Take your own PRs that **already have approval** but can't merge because of a
merge conflict, a branch that's behind, or failing CI. Send one subagent per
PR to make it green. Invoking `/reaper green` authorizes pushing fixes to your
own PR branches. It never authorizes merging, force-pushing without a lease,
or touching anyone else's branch.

## 1. Pick candidates

```bash
~/.claude/skills/reaper/scripts/prs.sh | jq -c 'select(
  (.reviewDecision == "APPROVED" or ((.reviews | map(.state) | index("APPROVED")) and .reviewDecision != "CHANGES_REQUESTED"))
  and (.mergeStateStatus == "DIRTY" or .mergeable == "CONFLICTING" or .mergeStateStatus == "BEHIND"
       or (.failingChecks | map(select(.name | test("advisory"; "i") | not)) | length > 0)))'
```

If the user named PR numbers (`/reaper green 12 34`), use only those, and
still check that each one is approved. If an approved PR is already green and
clean, it isn't a candidate. List it as ready to merge.

For each candidate, look up the base branch's rules once per repo:
`gh api repos/<repo>/rules/branches/<base>`. Note these:
- `required_status_checks`: the check names that actually gate the merge.
  These are the ones to fix.
- `dismiss_stale_reviews_on_push`: if true, pushing will drop the approval.
  Tell the user before you launch the agents and wait for a go-ahead on those PRs.
- `required_linear_history`: if present, conflicts get a rebase, not a merge.
- `merge_queue`: if present, "ready" means "can be enqueued".

Show the candidate list (link, what's wrong) in one short block, then launch.
There's nothing to launch if it's empty. Say so and stop.

## 2. Launch one subagent per PR

Use the `Agent` tool with `subagent_type: "general-purpose"` and
`run_in_background: true`. Send every launch in a single message so they run
in parallel. Launch at most 4 at a time; queue the rest. Don't use
`isolation: "worktree"`, because these PRs live in different repos. Each
agent makes its own worktree. Fill this prompt in for each PR:

```
Make PR <repo>#<n> (<url>) mergeable. It is approved; do not change what it does.
Problems: <conflict with <base> | behind <base> | failing checks: <name — url>, ...>
Required checks on <base>: <list>. Linear history required: <yes/no>.
Scratch dir: <your scratchpad>/green/<repo-name>-<n>

1. Repo: reuse an existing local clone whose origin is <repo>. Look in each directory
   of $REAPER_CLONE_ROOTS (colon-separated) for <repo-name>; if that is unset, run
   `find ~ -maxdepth 4 -type d -name <repo-name> -not -path '*/node_modules/*'` and check
   `git -C <dir> remote get-url origin`. If none, `gh repo clone <repo> <scratch>/clone`.
   Never edit or switch branches in that clone's main checkout. Never use git stash.
   `git -C <clone> fetch origin <head> <base>`
   `git -C <clone> worktree add --detach <scratch>/wt origin/<head>` and work only there.
   Read the repo's AGENTS.md / CLAUDE.md first and follow them.
2. Conflicts/behind: `git merge origin/<base>` (or rebase onto it if linear history
   is required). Resolve each conflict by understanding both sides: keep the PR's
   intent and the base's newer changes. If a conflict is a real product decision
   (both sides changed the same behavior differently), stop and report it with
   both versions — do not guess.
3. Failing checks: read the failure (`gh run view <run-id> -R <repo> --log-failed`).
   - Infra/flaky (runner timeout, network, cancelled, unrelated test that passes on
     <base>): rerun once with `gh run rerun <run-id> -R <repo> --failed`.
   - Real failure caused by this PR or by the merge: fix it in the worktree, smallest
     change that keeps the PR's behavior. Reproduce locally first with the repo's own
     test/typecheck commands, and run them again after the fix.
   - Failure that also happens on <base> (pre-existing): don't fix it here; report it.
   Ignore checks with "advisory" in the name.
4. Commit with a message following the commit-style skill (load it), then
   `git push origin HEAD:<head>`. For a rebase only:
   `git push --force-with-lease=<head>:<old head sha> origin HEAD:<head>`.
   Never push to <base>, never --no-verify, never merge the PR, never dismiss or
   re-request reviews, never comment on the PR.
5. Watch CI: `gh pr checks <n> -R <repo> --required --watch --fail-fast` (re-run the
   command if your Bash call times out). If it fails again, do at most one more fix
   round, then stop.
6. Clean up: `git -C <clone> worktree remove <scratch>/wt`.

Report back in this shape:
STATUS: green | still-failing | needs-decision
PUSHED: <sha> <subject> (one per commit, or "nothing")
WHAT CHANGED: <one line per fix: conflict in <file> resolved by …, test fixed by …>
REMAINING: <failing check + cause, or the decision needed, or "none">
```

## 3. Report

When every agent has finished, run `prs.sh` again for the candidate PRs. That
checks the agents' claims against GitHub instead of trusting them. Then
report:

```
## 🟢 Green now (2)
- [api#12](url) — merged main (conflict in src/schema.ts), fixed Unit Tests 4/4 · pushed a1b2c3d
## 🟠 Still failing (1)
- [app#56](url) — `Run Tests` fails on main too (pre-existing): <cause>
## ⚪ Needs your decision (1)
- [web#34](url) — conflict in docs routes: PR deletes /guides/old, main renamed it; keep which?
```

If an agent's claim disagrees with GitHub (it said green, but checks are still
running or red), report what GitHub shows. Then offer the merges in one line,
for example "merge api#12? (app uses the merge queue:
`gh pr merge <n> --auto`)". Don't merge until the user says so.
