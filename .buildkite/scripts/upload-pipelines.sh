#!/bin/sh
set -e

# On main: compare against previous commit
# On branches: compare against merge base with main
if [ "$BUILDKITE_BRANCH" = "main" ]; then
  CHANGED=$(git diff --name-only HEAD~1)
else
  BASE=$(git merge-base HEAD origin/main)
  CHANGED=$(git diff --name-only "$BASE"..HEAD)
fi

echo "Changed files:"
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
