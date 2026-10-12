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

Needs the [`gh`](https://cli.github.com/) CLI (logged in) and `jq`.

| Command | What it does |
|---|---|
| `/reaper` | Every open PR you authored, sorted into **blocked on you** (conflicts, red CI, changes requested, unresolved threads, no reviewers asked), **ready to merge**, and **waiting on others**. Each PR gets one next action. |
| `/reaper assigned` | Every PR waiting on your review, in the order to take them: re-reviews, PRs requested from you by name, team requests, bot PRs. Shows size, age and CI state. |
| `/reaper green [PR numbers…]` | For your *approved* PRs that are stuck on merge conflicts or failing CI: one subagent per PR merges the base branch in, fixes the failures, pushes, and watches CI. Never merges, and never force-pushes without a lease. |

Add `all` to any of these to search every org.

| Env var | Default | Purpose |
|---|---|---|
| `REAPER_ORG` | `MCPJam` | GitHub org the searches are scoped to |
| `REAPER_CLONE_ROOTS` | *(searches `~`)* | Colon-separated dirs where `/reaper green` looks for existing local clones |

### `/kestral`: Kestral task audit

Needs the [Kestral](https://kestral.ai) MCP server connected, and `gh` to check
linked PRs. For each open task assigned to you it gives one verdict: **Act
now**, **Close**, **Update** (wrong status or stale), **Waiting**, or **Fine**,
with the evidence for it. It proposes status, due-date and comment changes, and
applies them only after you confirm.
