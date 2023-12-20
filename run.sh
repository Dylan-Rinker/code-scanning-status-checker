#!/bin/bash
set -e

TOKEN=$1
PR_NUMBER=$2
ORG_REPO=$3

IFS='/' read -ra SPLIT_REPO <<< "$ORG_REPO"
ORG=${SPLIT_REPO[0]}
REPO=${SPLIT_REPO[1]}

gh auth login --with-token <<< "$TOKEN"

get_codeql_conclusion() {
  local response
  response=$(gh api graphql -f query='
    {
        repository(owner: "'$ORG'", name: "'$REPO'") {
        pullRequest(number: '$PR_NUMBER') {
          commits(last: 1) {
            nodes {
              commit {
                checkSuites(first: 1, filterBy: {checkName: "dependency-review"}) {
                  nodes {
                    checkRuns(first: 1) {
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
  echo $response | jq -r '.data.repository.pullRequest.commits.nodes[0].commit.checkSuites.nodes[0].checkRuns.nodes[0].conclusion'
}

conclusion=$(get_codeql_conclusion)
echo "Conclusion: $conclusion"
if [ "$conclusion" != "SUCCESS" ]; then
  echo "Dependency Review check failed"
  exit 1
fi

echo "Dependency Review check passed"
