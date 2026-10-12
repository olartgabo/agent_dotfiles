#!/usr/bin/env bash
# Print one JSON object per open PR with the fields /reaper needs to classify it.
#   prs.sh            PRs the gh user authored in $REAPER_ORG (default MCPJam)
#   prs.sh --review   PRs where the gh user's review is requested, or that they
#                     reviewed and are still open (excluding their own)
#   --all             drop the org filter (combines with --review)
set -euo pipefail

scope="org:${REAPER_ORG:-MCPJam}"
mode="mine"
for arg in "$@"; do
  case "$arg" in
    --all) scope="" ;;
    --review) mode="review" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

me="$(gh api user --jq .login)"
base="is:pr is:open archived:false $scope"
if [[ "$mode" == "review" ]]; then
  q1="$base review-requested:@me -author:@me"
  q2="$base reviewed-by:@me -author:@me"
else
  q1="$base author:@me"
  q2="$q1"
fi

query='
fragment pr on PullRequest {
  number title url isDraft createdAt updatedAt
  additions deletions changedFiles
  repository { nameWithOwner }
  author { login }
  baseRefName headRefName
  mergeable mergeStateStatus reviewDecision
  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
  latestOpinionatedReviews(first: 20) { nodes { state author { login } submittedAt } }
  reviewThreads(first: 100) { nodes { isResolved isOutdated comments(first: 1) { nodes { author { login } } } } }
  comments(last: 5) { nodes { author { login } createdAt bodyText } }
  commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state contexts(first: 100) {
    nodes {
      ... on CheckRun { name conclusion status detailsUrl }
      ... on StatusContext { context state targetUrl }
    }
  } } } } }
  labels(first: 20) { nodes { name } }
}
query($q: String!) {
  search(query: $q, type: ISSUE, first: 40) { nodes { ...pr } }
}'

# One search per call: a single request with both searches times out (HTTP 502).
fetch() { gh api graphql -f q="$1" -f query="$query" --jq '.data.search.nodes'; }
{ fetch "$q1"; if [[ "$q2" != "$q1" ]]; then fetch "$q2"; fi; } \
  | jq -sc --arg me "$me" '
    add | map(select(.number != null)) | unique_by(.url)[] | . as $pr | {
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
      myReview: ([.latestOpinionatedReviews.nodes[] | select(.author.login == $me) | {state, at: .submittedAt}] | first),
      requestedFromMeDirectly: ([.reviewRequests.nodes[].requestedReviewer.login] | index($me) != null),
      unresolvedThreads: [.reviewThreads.nodes[] | select(.isResolved | not) | {by: .comments.nodes[0].author.login, outdated: .isOutdated}],
      recentComments: [.comments.nodes[] | select(.author.login != $pr.author.login)
        | {by: .author.login, at: .createdAt, text: (.bodyText | .[0:200])}]
    }'
