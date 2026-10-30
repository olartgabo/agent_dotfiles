# agent_dotfiles

Claude Code skills I use day to day.

## Install

```bash
git clone https://github.com/olartgabo/agent_dotfiles.git ~/agent_dotfiles
~/agent_dotfiles/install.sh
```

`install.sh` symlinks each skill into `~/.claude/skills/`, so `git pull` updates them.

## Skills

### `/reaper`: open pull requests

Needs the [`gh`](https://cli.github.com/) CLI (logged in) and bash. The scripts run their jq inside `gh --jq`, so there is no separate `jq` install, and they work on Linux, macOS and Windows (Git Bash).

| Command | What it does |
|---|---|
| `/reaper` | Every open PR you authored, sorted into **blocked on you** (conflicts, red CI, changes requested, unresolved threads, no reviewers asked), **ready to merge**, and **waiting on others**. Each PR gets one next action. |
| `/reaper <PR link or number>` | Reviews one PR. Your own PR gets its status line; a PR you reviewed that changed since gets a delta re-review; anything else gets a full review: the `/engineering` record (Kestral task, approved specs and plan, honest evidence, size against the estimate), the code, and whether a simpler design would meet the spec. Drafts only; submits after you approve. |
| `/reaper assigned` | Every PR waiting on your review, in the order to take them: re-reviews, PRs nobody else has reviewed, PRs requested from you by name, team requests, bot PRs. Shows size, age and CI state. `/reaper assigned rereview` re-reviews the changed ones; `/reaper tome` (or `/reaper assigned needme`) reviews the ones nobody else has. |
| `/reaper orange` | Every PR you review, checked for whether it's stuck: waiting on your answer or re-review, author stuck on conflicts, red CI or requested changes, or nobody moving it. Lists each by full URL with the help it needs. Read-only. |
| `/reaper green [PR numbers…]` | For your *approved* PRs that are stuck on merge conflicts or failing CI: one subagent per PR merges the base branch in, fixes the failures, pushes, and watches CI. Never merges, and never force-pushes without a lease. |
| `/reaper red [PR numbers…]` | For your PRs that are *blocked on you*: shows one plan and asks once, then one subagent per PR fixes conflicts, failing CI, requested changes and valid bot findings, and pushes. In the session it requests or re-requests reviewers. Replies to people are drafted, never posted. Never merges or approves. |
| `/reaper nudge [Nd]` | For your PRs waiting on a reviewer for N+ days (default 2), drafts one Slack DM per reviewer. Saves drafts only, never sends. |
| `/reaper rereview [PR numbers…]` | For PRs you've reviewed that changed since: works out the delta (range-diff for rebases, so a pure rebase shows as one), checks each of your earlier asks against it, and drafts a re-review of only that delta. Submits a review only after you approve the draft. |
| `/reaper owner [PR numbers…]` | PRs waiting on your review that nobody has approved yet, so yours is the review that moves them. Reviewable ones come first, smallest first; red, changes-requested and dead PRs are grouped separately. Reviews inline and submits only after you approve the draft. |
| `/reaper cull [Nd] [PR numbers…]` | For PRs you authored or review with no activity in N days (default 14): checks for a replacement PR (same ticket ID or title), whether the change is already on the base (`git merge-tree`), and whether the code it touches still exists. Verdicts are superseded, obsolete, unclear or still relevant. Closes only the PRs you name after the report, with a one-line comment linking the replacement, and never deletes branches. |

Add `all` to any of these to search every org.

| Env var | Default | Purpose |
|---|---|---|
| `REAPER_ORG` | `MCPJam` | GitHub org the searches are scoped to; `all` searches every org |
| `REAPER_CLONE_ROOTS` | *(searches `~`)* | Colon-separated dirs where `/reaper green` and `/sweep all` look for local clones |

### `/kestral`: Kestral task audit

Needs the [Kestral](https://kestral.ai) MCP server connected, and `gh` to check
linked PRs. For each open task assigned to you it gives one verdict: **Act
now**, **Close**, **Update** (wrong status or stale), **Waiting**, or **Fine**,
with the evidence for it. It proposes status, due-date and comment changes, and
applies them only after you confirm.

### `/stack`: stacked PRs

`/stack` shows the chain of PRs, where each PR's base is the previous PR's
branch, and flags which ones are out of date. `/stack sync` handles a lower
PR merging: it rebases the rest with `git rebase --onto` (which works after
squash merges), retargets the bases, and force-pushes with a lease. It shows
the plan and asks first. `/stack new <branch>` adds a layer. Every PR in the
stack gets a stack table in its body.

### `/ship`: branch to PR

Runs the repo's own pre-PR checks (from `AGENTS.md`/`CLAUDE.md`, or the
`preflight-ci` skill), commits, pushes, and opens the PR with the repo's
template filled in. Then it checks reviewers (CODEOWNERS, or suggestions from
`git log`) and links the Kestral task if one exists. `/ship draft` opens a
draft. It never merges or skips hooks.

### `/standup`: daily update

Builds **Done / Next / Blocked** from PRs merged, opened and reviewed since
the last working day, plus Kestral tasks closed and active. Every line links
to its source. It can save the result as a Slack draft (`STANDUP_SLACK_CHANNEL`)
but never sends it.

### `/sentry-triage`: who's on it?

Finds escalating, new and regressed unresolved Sentry issues, then checks
each against Kestral tasks and GitHub PRs: tracked, fix in flight, regressed
after fix, or untracked. For untracked issues it drafts a Kestral task with
impact and evidence, and creates it only after you confirm. Needs the Sentry
MCP. Settings: `SENTRY_ORG`, `SENTRY_TRIAGE_MIN_USERS` (default 5) and
`KESTRAL_TRIAGE_PROJECT`.

### `/sweep`: clean up merged work

Lists worktrees and local branches whose PRs merged, with proof that nothing
unpushed or uncommitted is lost. It deletes only what you approve, and uses
`orca worktree rm` for Orca-managed worktrees. Dirty worktrees, unpushed
commits and stashes are reported and never touched. `/sweep all` covers every
Orca repo.

### `/pr-review`: review and fix PRs

`/pr-review <PR link or number…>` reviews one PR in the current session. With
several PRs, it runs one subagent per PR in parallel. For each PR it:
- checks every open CodeRabbit and cubic comment against the code, fixes the
  valid ones, explains the declined ones in the thread, and resolves it
- gets CI green: fixes failures caused by the PR, reruns flaky checks once,
  and reports failures that also happen on the base branch
- reviews the diff for correctness, security, error handling, tests, types
  and maintainability, and fixes small clear defects

It pushes the fixes as normal commits (never force) and posts one summary
comment explaining each change and why. It never approves or merges. Fork
PRs it can't push to get suggestions instead of commits.

## Repo checks

CI (`.github/workflows/check.yml`) runs `scripts/check_skills.py` (valid
front matter, no machine-specific paths), shellcheck and gitleaks. `main`
only changes through a pull request that passes `check`.
