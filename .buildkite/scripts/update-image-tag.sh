#!/usr/bin/env bash
# Updates a service's image tag in its Helm values file and pushes the change.
# This commit is what triggers ArgoCD to sync the new image into the cluster.
#
# Usage: ./update-image-tag.sh <service-name> <image-tag>
# Example: ./update-image-tag.sh catalog sha-a3075d4
set -euo pipefail

SERVICE="$1"
TAG="$2"
VALUES_FILE="charts/releases/${SERVICE}.yaml"

# Ensure the values file exists before attempting to modify it
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: $VALUES_FILE not found"
  exit 1
fi

# Replace the image tag in the Helm values file (e.g. tag: latest → tag: sha-a3075d4)
sed -i '' "s/  tag: .*/  tag: ${TAG}/" "$VALUES_FILE"

# Commit and push the tag change — this is the GitOps trigger for ArgoCD
# Retry with pull-rebase in case another pipeline pushed first
git config user.name "buildkite-ci"
git config user.email "ci@buildkite.com"
git add "$VALUES_FILE"
git commit -m "ci: update ${SERVICE} image tag to ${TAG} [skip ci]"

MAX_RETRIES=5
for i in $(seq 1 $MAX_RETRIES); do
  if git push origin HEAD:refs/heads/${BUILDKITE_BRANCH}; then
    echo "Push succeeded"
    exit 0
  fi
  echo "Push failed (attempt $i/$MAX_RETRIES), rebasing and retrying..."
  git pull --rebase origin "${BUILDKITE_BRANCH}"
done

echo "Error: push failed after $MAX_RETRIES attempts"
exit 1
