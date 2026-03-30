#!/bin/sh
set -e

# Compare against the merge base with main to catch all changes in the branch.
# Falls back to HEAD~1 for commits directly on main.
BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "HEAD~1")
CHANGED=$(git diff --name-only "$BASE"..HEAD)

echo "Changed files since $BASE:"
echo "$CHANGED"
echo "---"

UPLOADED=0

if echo "$CHANGED" | grep -q "^services/catalog/"; then
  echo "Catalog changed — uploading catalog pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.catalog.yml
  UPLOADED=1
fi

if echo "$CHANGED" | grep -q "^services/shipping/"; then
  echo "Shipping changed — uploading shipping pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.shipping.yml
  UPLOADED=1
fi

if echo "$CHANGED" | grep -q "^apollo/"; then
  echo "Apollo changed — uploading apollo pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.apollo.yml
  UPLOADED=1
fi

if [ "$UPLOADED" -eq 0 ]; then
  echo "No service changes detected — skipping child pipelines"
fi
