---
name: standup
description: >
  Draft the user's standup from what actually happened: PRs merged, opened and
  reviewed since the last working day, Kestral tasks closed or moved, and
  what's blocked and on whom. Optionally saves it as a Slack draft and never
  sends it. Use when the user runs /standup, or asks "write my standup", "what
  did I do yesterday", "daily update". /standup <N>d covers the last N days.
---

# Standup

Write a three-part update (**Done / Next / Blocked**) from evidence, not
memory. Every item has a link. Keep it short enough to read in 20 seconds.

## 1. Window

Default: since the start of the previous working day. On Monday, that means
since Friday. `/standup 3d` overrides it. Work out `SINCE` as a `YYYY-MM-DD`
date and state the window in the output.

## 2. Gather (run in parallel)

GitHub, scoped to `$REAPER_ORG` (default `MCPJam`) unless the user says otherwise:

```bash
gh search prs --author=@me --merged-at=">=$SINCE" --owner "$ORG" --json number,title,url,repository --limit 50
gh search prs --author=@me --created=">=$SINCE" --state=open --owner "$ORG" --json number,title,url,repository --limit 50
gh search prs --reviewed-by=@me --updated=">=$SINCE" --owner "$ORG" --json number,title,url,repository,author --limit 50
```

Drop your own PRs from the reviewed list.

Blockers: run `~/.claude/skills/reaper/scripts/prs.sh` if the reaper skill is
installed. Classify with reaper's rules, and keep only **waiting on others**
(reviews pending for more than a day) and anything blocked on an outside
decision.

Kestral (if connected):
- `execute_operation search_tasks_recently_updated { timeWindow: <window>, assigneeFilter: "me" }`
  gives tasks you moved or completed.
- `execute_operation list_my_active_tasks { limit: 50 }` gives what's next.
  Pick the top 2–3 by priority that aren't waiting.

## 3. Write

```
*Standup — <date>* (since <SINCE>)
*Done*
• Merged <repo>#<n> <short title> (<link>)
• Reviewed <author>'s <repo>#<n>
• Closed <TASK-1> <title>
*Next*
• <top task or PR in progress>, <one clause on the concrete step>
*Blocked*
• <repo>#<n> waiting on review from <name> (2d)
```

Rules:
- Group related PRs into one line ("Merged 3 PRs for the billing rework (#1, #2, #3)").
- Use plain words, and no internal codes the team wouldn't recognize.
- If a section is empty, write "nothing" rather than padding it.
- **Next** comes from the active Kestral tasks and in-progress PRs. Don't
  invent plans. If there's no source, ask the user for one line.

Show the draft in the terminal first.

## 4. Slack draft (optional)

Offer it once. If the user says yes, the channel is `$STANDUP_SLACK_CHANNEL`
if set; otherwise ask, and find it with `slack_search_channels`. Save it with
`slack_send_message_draft { channel_id, message }`. That only creates a draft.
**Never use `slack_send_message`.** If it returns `draft_already_exists`,
say so and print the text to paste instead.
