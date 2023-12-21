#!/bin/bash
set -e

TOKEN=$1
PR_NUMBER=$2
ORG_REPO=$3

IFS='/' read -ra SPLIT_REPO <<< "$ORG_REPO"
ORG=${SPLIT_REPO[0]}
REPO=${SPLIT_REPO[1]}

gh auth login --with-token <<< "$TOKEN"

CHECKS_PASSED=true

get_codeql_conclusion() {
  local response
  response=$(gh api graphql -f query='
    {
        repository(owner: '"$ORG"', name: '"$REPO"') {
        pullRequest(number: '"$PR_NUMBER"') {
          commits(last: 1) {
            nodes {
              commit {
                checkSuites(first: 100) {
                  nodes {
                    checkRuns(first: 1, filterBy: {checkName: "CodeQL"}) {
                      nodes {
                        name
                        status
                        conclusion
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ')
  echo "$response" | jq -r '.data.repository.pullRequest.commits.nodes[0].commit.checkSuites.nodes[7].checkRuns.nodes[0].conclusion'
}

get_most_recent_commit_SHA() {
  local response
  response=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/$ORG/$REPO/pulls/$PR_NUMBER/commits)
  echo "$response" | jq -r '.[0].sha'
}

get_run_ID() {
  local commit_sha=$1
  local response
  response=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/$ORG/$REPO/commits/$commit_sha/check-runs)
  echo "$response" | jq -r '.check_runs[] | select(.name == "dependency-review") | .id'
}

get_dependency_review_conclusion() {
  local check_run_ID=$1
  local response
  response=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/"$ORG"/"$REPO"/check-runs/"$check_run_ID")
  echo "$response" | jq -r '.conclusion'
}

codeql_conclusion=$(get_codeql_conclusion)
echo "CodeQL Conclusion: $codeql_conclusion"

if [ "$codeql_conclusion" != "SUCCESS" ]; then
  echo "CodeQL check failed"
  CHECKS_PASSED=false
fi

most_recent_commit_SHA=$(get_most_recent_commit_SHA)
echo "Most recent commit SHA: $most_recent_commit_SHA"

run_ID=$(get_run_ID "$most_recent_commit_SHA")
echo "Run ID: $run_ID"

dependency_review_conclusion=$(get_dependency_review_conclusion "$run_ID")
echo "Dependency Review Conclusion: $dependency_review_conclusion"

if [ "$CHECKS_PASSED" == "false" ]; then
  exit 1
fi

echo "All checks passed"
