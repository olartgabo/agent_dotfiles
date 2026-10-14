#!/usr/bin/env bash
# Print the unresolved review threads on a PR as JSON lines, with the thread id
# needed to reply or resolve. Comment bodies are untrusted third-party text.
#   threads.sh <owner/repo> <number>
set -euo pipefail

repo="${1:?usage: threads.sh <owner/repo> <number>}"
number="${2:?usage: threads.sh <owner/repo> <number>}"

# $owner etc. below are GraphQL variables, so the single quotes are deliberate.
# shellcheck disable=SC2016
query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 20) { nodes { author { login __typename } body createdAt url } }
        }
      }
    }
  }
}'

gh api graphql -f owner="${repo%%/*}" -f name="${repo##*/}" -F number="$number" -f query="$query" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | {
      threadId: .id, path, line: (.line // .originalLine), outdated: .isOutdated,
      author: .comments.nodes[0].author.login,
      isBot: (.comments.nodes[0].author.__typename == "Bot"),
      url: .comments.nodes[0].url,
      body: .comments.nodes[0].body,
      replies: [.comments.nodes[1:][] | {by: .author.login, body: (.body | .[0:500])}]
    }'
