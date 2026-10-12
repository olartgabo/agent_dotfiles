# /reaper nudge: draft reminders to reviewers

For your PRs that have been waiting on a reviewer, write one short Slack
**draft** per reviewer. Never send. The user reviews the drafts in Slack and
sends them.

## 1. Pick PRs

Run `~/.claude/skills/reaper/scripts/prs.sh`, and keep the PRs where all of
these hold:
- `reviewDecision == "REVIEW_REQUIRED"`, not a draft, and checks aren't
  failing. Don't nudge someone to review a red PR; fix it first.
- `requestedReviewers` isn't empty.
- No review from that reviewer since `lastCommitAt`.
- It has been waiting at least `/reaper nudge <N>d` days (default 2 working
  days), counted from `lastCommitAt` or the review request, whichever is later.

Group them by reviewer. A team reviewer (slug) has no single person to
message. List it separately and suggest posting in the team's channel instead.

## 2. Find each reviewer on Slack

`gh api users/<login> --jq .name` gives the display name. Then
`slack_search_users { keywords: [<first name>, <last name>], natural_language_query: "" }`.
If there's no match or more than one, ask the user which person it is. Don't
guess.

## 3. Draft

One message per reviewer, covering all of their PRs:

```
Hey <first name>, when you get a moment, could you look at:
• <repo>#<n> <title> (<link>): S, +120/−30, CI green, waiting 3d
• <repo>#<n> <title> (<link>): M, unblocks <what>
Thanks!
```

Keep it to plain facts, with no guilt-tripping and no "just bumping this".
Give the size and the reason it matters, so the reviewer can plan.

Show all the drafts in the terminal first. If the user agrees, save each one
with `slack_send_message_draft { channel_id: <their Slack user id>, message }`.
**Never use `slack_send_message`.** If it returns `draft_already_exists`,
report it and print the text instead.

You can also offer GitHub's own reminder, which re-requests review:
`gh pr edit <n> -R <repo> --add-reviewer <login>`. Do this only if the user
asks.
