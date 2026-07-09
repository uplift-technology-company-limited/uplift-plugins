#!/usr/bin/env bash
# Deploy <PROJECT_NAME> to Vercel production + auto-bump the vX.Y.Z release tag.
# Runs in CI (GitHub Actions) or on a laptop.
#
#   ./scripts/deploy.sh deploy              # build (version baked) → vercel prod → tag
#   BUMP=minor ./scripts/deploy.sh deploy   # feature release
#   BUMP=major ./scripts/deploy.sh deploy   # breaking release
#
# Needs VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID — from the environment
# (GitHub secrets in CI) or a gitignored .env (see .env.example). The tag is
# pushed ONLY after a successful deploy, so a failed build leaves no orphan tag.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Load credentials from a gitignored .env if present (local convenience) or a
# persistent file on a self-hosted runner. Vars already set (e.g. GitHub secrets)
# win — a file only fills what's still empty, so CI is never overridden.
for _envf in "${DEPLOY_ENV_FILE:-}" "$HOME/.config/$(basename "$PROJECT_DIR").env" "$PROJECT_DIR/.env.local" "$PROJECT_DIR/.env"; do
  [ -n "$_envf" ] && [ -f "$_envf" ] || continue
  while IFS='=' read -r _k _v; do
    case "$_k" in ''|\#*) continue ;; esac
    _k="${_k// /}"; _v="${_v%\"}"; _v="${_v#\"}"; _v="${_v%\'}"; _v="${_v#\'}"
    [ -n "${!_k:-}" ] || export "$_k=$_v"
  done < "$_envf"
done

BUMP="${BUMP:-patch}"
APP_VERSION="$(node -p "require('${PROJECT_DIR}/package.json').version" 2>/dev/null || echo "0.0.0")"
RELEASE_TAG=""

: "${VERCEL_TOKEN:?VERCEL_TOKEN is required (GitHub secret, or set it in .env)}"
VERCEL="npx vercel@latest"   # or: bunx vercel@latest / pnpm dlx vercel@latest

# Next semver tag from the GLOBAL highest vX.Y.Z (sort -V, not git describe —
# describe is topological and can pick a lower base → non-monotonic version).
compute_version() {
  git -C "$PROJECT_DIR" fetch --tags --quiet origin 2>/dev/null || true
  local latest major minor patch
  latest="$(git -C "$PROJECT_DIR" tag --list 'v*' | sort -V | tail -n1)"
  latest="${latest:-v0.0.0}"
  IFS='.' read -r major minor patch <<< "${latest#v}"
  major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
  case "$BUMP" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    *)     patch=$((patch + 1)) ;;
  esac
  RELEASE_TAG="v${major}.${minor}.${patch}"
  while git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null 2>&1; do
    patch=$((patch + 1)); RELEASE_TAG="v${major}.${minor}.${patch}"
  done
  APP_VERSION="${RELEASE_TAG#v}"
  echo "Version: ${RELEASE_TAG} (bump=${BUMP})" >&2
}

# Annotated tag + push — ONLY after a successful deploy. Non-fatal.
tag_release() {
  [ -n "$RELEASE_TAG" ] || return 0
  git -C "$PROJECT_DIR" config user.name  >/dev/null 2>&1 || git -C "$PROJECT_DIR" config user.name  "ci-deploy"
  git -C "$PROJECT_DIR" config user.email >/dev/null 2>&1 || git -C "$PROJECT_DIR" config user.email "deploy@example.com"
  git -C "$PROJECT_DIR" tag -a "$RELEASE_TAG" -m "$RELEASE_TAG — automated Vercel deploy" 2>/dev/null || true
  if git -C "$PROJECT_DIR" push origin "$RELEASE_TAG" 2>/dev/null; then
    echo "Tagged ${RELEASE_TAG}" >&2
  else
    echo "Could not push tag ${RELEASE_TAG} (non-fatal)" >&2
  fi
}

deploy() {
  compute_version
  export NEXT_PUBLIC_APP_VERSION="$APP_VERSION"

  echo "→ Pulling Vercel project settings (production)…"
  $VERCEL pull --yes --environment=production --token="$VERCEL_TOKEN"

  echo "→ Building (NEXT_PUBLIC_APP_VERSION=${APP_VERSION})…"
  NEXT_PUBLIC_APP_VERSION="$APP_VERSION" $VERCEL build --prod --token="$VERCEL_TOKEN"

  echo "→ Deploying prebuilt to production…"
  $VERCEL deploy --prebuilt --prod --token="$VERCEL_TOKEN"

  tag_release
  echo "✓ Deployed <PROJECT_NAME> ${RELEASE_TAG}"
}

case "${1:-}" in
  deploy) deploy ;;
  *) echo "usage: $0 deploy"; exit 1 ;;
esac
