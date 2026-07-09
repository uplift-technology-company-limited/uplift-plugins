#!/usr/bin/env bash
# Publish a new version of the vercel-gha-deploy plugin.
#
# This repo has no build or runtime — it's a Claude Code plugin (markdown +
# templates + manifests) fetched by `/plugin install`. So there's nothing to
# "deploy"; publishing a version means: bump the git tag (vX.Y.Z) and keep
# plugins/vercel-gha-deploy/.claude-plugin/plugin.json's "version" field in
# sync with it, so both agree on what a fresh install resolves to.
#
#   ./scripts/release.sh release              # patch bump (default)
#   BUMP=minor ./scripts/release.sh release   # new feature in the skill
#   BUMP=major ./scripts/release.sh release   # breaking change to the workflow contract
#
# The tag is only pushed AFTER the manifest-bump commit succeeds — a failed
# bump leaves no orphan tag. marketplace.json intentionally does NOT carry its
# own version field: if a version exists in both places, plugin.json wins
# silently, so this repo keeps exactly one source of truth for the number.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PLUGIN_JSON="$PROJECT_DIR/plugins/vercel-gha-deploy/.claude-plugin/plugin.json"

BUMP="${BUMP:-patch}"
RELEASE_TAG=""
APP_VERSION=""

# Next semver tag from the GLOBAL highest vX.Y.Z (sort -V, not git describe —
# describe is topological and can pick a lower base → non-monotonic version).
compute_version() {
  git fetch --tags --quiet origin 2>/dev/null || true
  local latest major minor patch
  latest="$(git tag --list 'v*' | sort -V | tail -n1)"
  latest="${latest:-v0.0.0}"
  IFS='.' read -r major minor patch <<< "${latest#v}"
  major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
  case "$BUMP" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    *)     patch=$((patch + 1)) ;;
  esac
  RELEASE_TAG="v${major}.${minor}.${patch}"
  while git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null 2>&1; do
    patch=$((patch + 1)); RELEASE_TAG="v${major}.${minor}.${patch}"
  done
  APP_VERSION="${RELEASE_TAG#v}"
  echo "Version: ${RELEASE_TAG} (bump=${BUMP})" >&2
}

bump_manifest() {
  node -e "
    const fs = require('fs');
    const p = '${PLUGIN_JSON}';
    const j = JSON.parse(fs.readFileSync(p, 'utf8'));
    j.version = '${APP_VERSION}';
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + '\n');
  "
}

# Commit the manifest bump, then tag + push — in that order, so a push failure
# never leaves a tag pointing at an unpushed commit.
commit_and_tag() {
  git config user.name  >/dev/null 2>&1 || git config user.name  "uplift-deploy"
  git config user.email >/dev/null 2>&1 || git config user.email "deploy@uplifttech.co"
  git add "$PLUGIN_JSON"
  # [skip ci] — this commit is pushed straight to main by the release workflow
  # itself; without this, a push-triggered workflow would re-trigger on its
  # own bump commit.
  git commit -q -m "chore(release): ${RELEASE_TAG} [skip ci]"
  git tag -a "$RELEASE_TAG" -m "$RELEASE_TAG"
  git push origin HEAD:main
  git push origin "$RELEASE_TAG"
  echo "✓ Released ${RELEASE_TAG}"
}

release() {
  compute_version
  bump_manifest
  commit_and_tag
}

case "${1:-}" in
  release) release ;;
  *) echo "usage: $0 release"; exit 1 ;;
esac
