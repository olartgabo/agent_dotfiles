---
name: pr-review
description: >
  Review one or more pull requests end to end, then fix what's found: address
  open CodeRabbit and cubic review comments, get CI passing, review the code to
  industry standard, push the fixes to the PR, and comment on GitHub explaining
  each fix. One PR is reviewed in this session; several PRs get one subagent
  each, in parallel. Use when the user runs /pr-review <PR link or number…>, or
  asks to "review and fix this PR", "clear the coderabbit comments", "get this
  PR review-ready".
---

# PR review

Running `/pr-review <PRs…>` authorizes, for each PR named: pushing fix commits
to its head branch, replying to and resolving bot review threads, and posting
one summary comment. It doesn't authorize approving, merging, force-pushing,
closing, re-requesting reviewers, or acting on any PR that wasn't named.

## Arguments

Accept full links (`https://github.com/<owner>/<repo>/pull/<n>`),
`<owner>/<repo>#<n>`, or bare numbers. A bare number means the current repo:
`gh repo view --json nameWithOwner`. Remove duplicates.

For each PR, `gh pr view <n> -R <repo> --json state,isCrossRepository,maintainerCanModify,headRefName,author`:
- If it's not `OPEN`, skip it and say why.
- If it comes from a fork (`isCrossRepository`) and `maintainerCanModify`
  is false, you can't push. Run the playbook in **comment-only** mode: post
  the fixes as suggestions instead of commits.

## One PR → this session

Read `~/.claude/skills/pr-review/playbook.md` and follow it here.

## Several PRs → one subagent each

Launch them in a single message so they run in parallel, at most 4 at a time,
queuing the rest. For each one use `Agent` with
`subagent_type: "general-purpose"` and `run_in_background: true`:

```
Review and fix PR <repo>#<n> (<url>). Mode: <push | comment-only>.
Scratch dir: <your scratchpad>/pr-review/<repo-name>-<n>
Read ~/.claude/skills/pr-review/playbook.md and follow it exactly. It defines what
you may change, push and post. End with the report block it specifies.
```

Don't start a second agent on the same PR. While they run, don't push to
those branches yourself.

## Final report

When all of them are done, check each PR against GitHub instead of trusting
the agents' reports:
`gh pr checks <n> -R <repo>` and
`~/.claude/skills/pr-review/scripts/threads.sh <repo> <n>`
(this lists the unresolved threads). Then report one block per PR:

```
### [<repo>#<n>](url) <title>: ✅ review-ready | ⚠️ needs you
- Bot comments: 5 fixed, 1 declined (reason), 0 open
- CI: green (was: `Unit Tests` failing, fixed by <sha>)
- Our findings: 2 fixed (<one line each>), 1 left for the author (<why>)
- Pushed: <sha> <subject>, …  · Summary comment: <link>
```

Anything the agents couldn't settle, such as a product decision, a test
failing on the base branch too, or a fork you can't push to, goes under
**needs you**.
