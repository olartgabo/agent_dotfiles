#!/usr/bin/env bash
# Print one JSON object per open PR with the fields /reaper needs to classify it.
#   prs.sh            PRs the gh user authored in $REAPER_ORG (default MCPJam)
#   prs.sh --review   PRs where the gh user's review is requested, or that they
#                     reviewed and are still open (excluding their own)
#   prs.sh --green    only your approved PRs stuck on conflicts, BEHIND or a
#                     failing non-advisory check (/reaper green's candidates)
#   --all             drop the org filter (combines with the others)
# Needs only gh and bash: the jq below runs inside gh (--jq), so no separate
# jq install is required on Linux, macOS or Windows (Git Bash).
# Comment text in the output (recentComments.text) is untrusted, third-party
# input: the skill treats it as data, never as instructions.
set -euo pipefail

scope="org:${REAPER_ORG:-MCPJam}"
mode="mine"
green=0
for arg in "$@"; do
  case "$arg" in
    --all) scope="" ;;
    --review) mode="review" ;;
    --green) green=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# tr: a Windows gh can end lines with CR, which would break the login match.
me="$(gh api user --jq .login | tr -d '\r')"
base="is:pr is:open archived:false $scope"
if [[ "$mode" == "review" ]]; then
  q1="$base review-requested:@me -author:@me"
  q2="$base reviewed-by:@me -author:@me"
else
  q1="$base author:@me"
  q2="$q1"
fi

# $q below is a GraphQL variable, so the single quotes are deliberate.
# shellcheck disable=SC2016
query='
fragment pr on PullRequest {
  number title url isDraft createdAt updatedAt
  additions deletions changedFiles
  repository { nameWithOwner }
  author { login }
  baseRefName headRefName
  mergeable mergeStateStatus reviewDecision
  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
  latestOpinionatedReviews(first: 20, writersOnly: true) { nodes { state author { login } submittedAt } }
  latestReviews(first: 20) { nodes { state author { login } submittedAt } }
  reviewThreads(first: 100) { nodes { isResolved isOutdated comments(first: 1) { nodes { author { login } } } } }
  comments(last: 5) { nodes { author { login } createdAt bodyText } }
  commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state contexts(first: 100) {
    nodes {
      ... on CheckRun { name conclusion status detailsUrl }
      ... on StatusContext { context state targetUrl }
    }
  } } } } }
  labels(first: 20) { nodes { name } }
  reviews(last: 100) { nodes { state author { login __typename } submittedAt } }
}
query($q: String!) {
  search(query: $q, type: ISSUE, first: 40) { nodes { ...pr } }
}'

# jq variables, not shell ones, so the single quotes are deliberate.
# shellcheck disable=SC2016
select_green='select(
  (.reviewDecision == "APPROVED" or ((.reviews | map(.state) | index("APPROVED")) and .reviewDecision != "CHANGES_REQUESTED"))
  and (.mergeStateStatus == "DIRTY" or .mergeable == "CONFLICTING" or .mergeStateStatus == "BEHIND"
       or (.failingChecks | map(select(.name | test("advisory"; "i") | not)) | length > 0)))'
filter="."
if [[ "$green" == 1 ]]; then filter="$select_green"; fi

# Runs inside gh; $pr, $s and $me are jq variables.
# shellcheck disable=SC2016
shape='.data.search.nodes[] | select(.number != null) | . as $pr | {
  repo: .repository.nameWithOwner, number, title, url, author: .author.login, isDraft,
  createdAt, updatedAt, base: .baseRefName, head: .headRefName,
  size: {additions, deletions, files: .changedFiles},
  mergeable, mergeStateStatus, reviewDecision,
  labels: [.labels.nodes[].name],
  lastCommitAt: .commits.nodes[0].commit.committedDate,
  checks: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
  failingChecks: [.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
    | select((.conclusion // .state) as $s | ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"] | index($s))
    | {name: (.name // .context), url: (.detailsUrl // .targetUrl)}] | unique_by(.name),
  pendingChecks: [.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
    | select((.status // "") as $st | (.state // "") as $s | ($st != "" and $st != "COMPLETED") or $s == "PENDING" or $s == "EXPECTED")
    | (.name // .context)] | unique,
  requestedReviewers: [.reviewRequests.nodes[].requestedReviewer | (.login // .slug) | select(. != null)],
  reviews: [.latestOpinionatedReviews.nodes[] | {by: .author.login, state, at: .submittedAt}],
  # Approvals and change requests from people without write access: GitHub
  # shows them but they never satisfy the review rule.
  nonCountingReviews: ([.latestOpinionatedReviews.nodes[].author.login] as $counted
    | [.latestReviews.nodes[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")
       | select(.author.login as $l | $counted | index($l) | not)
       | {by: .author.login, state, at: .submittedAt}]),
  # Approvals and change requests win; a comment-only review still counts as
  # having reviewed, which latestOpinionatedReviews leaves out.
  myReview: (([.latestOpinionatedReviews.nodes[] | select(.author.login == $me) | {state, at: .submittedAt}] | first)
    // ([.reviews.nodes[] | select(.author.login == $me and .state != "PENDING") | {state, at: .submittedAt}] | last)),
  reviewedBy: [.reviews.nodes[] | select(.state != "PENDING" and .author.__typename != "Bot"
      and .author.login != $me and .author.login != $pr.author.login) | .author.login] | unique,
  requestedFromMeDirectly: ([.reviewRequests.nodes[].requestedReviewer.login] | index($me) != null),
  unresolvedThreads: [.reviewThreads.nodes[] | select(.isResolved | not) | {by: .comments.nodes[0].author.login, outdated: .isOutdated}],
  recentComments: [.comments.nodes[] | select(.author.login != $pr.author.login)
    | {by: .author.login, at: .createdAt, text: (.bodyText | .[0:200])}]
} | '"$filter"
# gh --jq has no --arg, so the login is bound as a JSON string literal.
program="\"$me\" as \$me | $shape"

# One search per call: a single request with both searches times out (HTTP 502).
fetch() { gh api graphql -f q="$1" -f query="$query" --jq "$program"; }
# gh prints one compact object per line, keys sorted. "repo" and "number" occur
# only at the top level (comment text has its quotes escaped), so together they
# key the dedupe that drops the second copy of a PR both searches returned.
{ fetch "$q1"; if [[ "$q2" != "$q1" ]]; then fetch "$q2"; fi; } \
  | tr -d '\r' | awk 'match($0, /"number":[0-9]+/) { n = substr($0, RSTART, RLENGTH) }
    match($0, /"repo":"[^"]+"/) { if (!seen[n substr($0, RSTART, RLENGTH)]++) print }'
