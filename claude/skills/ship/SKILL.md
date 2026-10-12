---
name: ship
description: >
  Take the current branch from "done locally" to an open PR in one pass: run the
  repo's own checks, commit, push, open the PR with the repo's template filled
  in, check reviewers, and link the Kestral task if one exists. Use when the
  user runs /ship, or says "ship it", "open the PR", "put this up for review".
  /ship draft opens it as a draft.
---

# Ship

Running `/ship` authorizes this sequence: commit, push the current branch, and
open a PR. It doesn't authorize merging, force-pushing, pushing to the default
branch, or skipping hooks (`--no-verify`).

## 1. Preconditions

- The current branch isn't the default branch. If it is, propose a branch
  name and ask.
- `git status`: list what will be committed. If you see unrelated files, such
  as scratch notes, `.env` files or build output, ask before including them.
- If this branch already has a PR (`gh pr view --json url,state`), switch to
  update mode: push, then refresh the PR body only if the change is material.
- If the branch's base is another open PR's branch, this is a stacked PR. Use
  that base, and update the stack table the `/stack` skill describes.

## 2. Verify

Read the repo's `AGENTS.md` / `CLAUDE.md` for a "before you finish" or
"before a PR" list, and run exactly those commands. If the `preflight-ci`
skill is installed, follow it instead. A failure blocks the ship: fix it if
it's caused by this branch, or report it and stop. Don't open a red PR to
"see what CI says".

## 3. Commit and push

- Follow the `commit-style` skill if it's installed, and otherwise the repo's
  conventions. The message says why, not only what.
- `git push -u origin HEAD`. If a hook rejects the push, read the hook's output
  and fix the cause.

## 4. Open the PR

- **Title:** short and imperative, in the repo's style. Check
  `gh pr list --state merged --limit 10 --json title`.
- **Body:** if `.github/pull_request_template.md` (or
  `.github/PULL_REQUEST_TEMPLATE/*`) exists, fill in every section. Where a
  section doesn't apply, use the text its comment asks for. Otherwise use
  Summary / Why / How it was tested. Name the commands you ran in step 2.
- `gh pr create --title … --body-file <tmp> [--draft] [--base <base>]`

## 5. Reviewers

Check `gh pr view --json reviewRequests` after creating the PR, because
CODEOWNERS may have requested reviewers automatically. If nobody is
requested, suggest 1–2 people: the most frequent recent authors of the
changed files (`git log --since=90.days --format=%an -- <files> | sort | uniq -c | sort -rn`),
minus the user. Request them only after the user agrees.

## 6. Kestral (only if the Kestral MCP is connected)

`execute_operation sync_after_push { branchName, prUrl, summary }`, where
`summary` is one line on what the PR does.
- It returns `needsDecision`, with no task found for this branch: find
  candidates with `search_tasks_with_comments { query: <PR topic> }`, and ask
  which one to link (`link_pr_to_task { taskId, prUrl }`). Offer
  `create_task` only if none fits.
- Don't create tasks or change statuses without asking.

## 7. Report

Report the PR link, the checks you ran and their result, reviewers
(requested or suggested), and the Kestral task linked (or "none"). End with
"Run `/reaper` later to see where it stands."
