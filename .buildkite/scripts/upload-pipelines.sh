#!/bin/sh
set -e

CHANGED=$(git diff --name-only HEAD~1)

if echo "$CHANGED" | grep -q "^services/catalog/"; then
  echo "Catalog changed — uploading catalog pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.catalog.yml
fi

if echo "$CHANGED" | grep -q "^services/shipping/"; then
  echo "Shipping changed — uploading shipping pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.shipping.yml
fi

if echo "$CHANGED" | grep -q "^apollo/"; then
  echo "Apollo changed — uploading apollo pipeline"
  buildkite-agent pipeline upload .buildkite/pipeline.apollo.yml
fi
