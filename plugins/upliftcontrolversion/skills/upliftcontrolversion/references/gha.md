# GHA wiring — two workflow shapes

The tag-bump lives in different places depending on whether the workflow wraps
`scripts/deploy.sh` or runs explicit steps.

## Common to both

```yaml
    permissions:
      contents: write   # push the vX.Y.Z release tag
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # tags + history for `git describe`
```

## Wrapper workflow (admin-portal-style)

The job just runs `./scripts/deploy.sh deploy`. `deploy.sh` already does
`compute_version` (before build) and `tag_release` (after rollout) — but
`tag_release` only pushes the git tag, it does **not** publish a GitHub
Release (see (e) above for why that's a separate step). Add a
`publish_release` function next to `tag_release` in `deploy.sh` (same
curl-not-`gh` reasoning applies — the self-hosted runner has no `gh` CLI):

```bash
# Publish a GitHub Release from the tag `tag_release` just pushed. Best-effort
# — never fails the deploy. Needs GH_TOKEN (pass through from the calling
# workflow step: `env: { GH_TOKEN: ${{ github.token }} }`); GITHUB_REPOSITORY
# is already set by Actions.
publish_release() {
  [ -n "$RELEASE_TAG" ] || return 0
  [ -n "$GH_TOKEN" ] || { echo "No GH_TOKEN — skipping Release publish" >&2; return 0; }
  local payload
  payload="$(node -e 'console.log(JSON.stringify({tag_name: process.argv[1], name: process.argv[1], generate_release_notes: true}))' "$RELEASE_TAG")"
  if curl -sf -X POST \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases" \
      -d "$payload" >/dev/null; then
    echo "Published Release ${RELEASE_TAG}" >&2
  else
    echo "Could not publish Release ${RELEASE_TAG} (non-fatal)" >&2
  fi
}
```

Call it right after `tag_release` in the `deploy)` case, and make sure the
workflow step that invokes `./scripts/deploy.sh deploy` passes `GH_TOKEN:
${{ github.token }}` through `env:`. To cut a feature/breaking release, run
the job with `BUMP` set (e.g. a `workflow_dispatch` input piped into
`env: { BUMP: ... }`, or just deploy manually with
`BUMP=minor ./scripts/deploy.sh deploy`).

## Explicit-steps workflow (sso-style)

The job builds and registers the task-def itself (describe → jq patch → register),
so compute the version in the workflow and inject it via jq.

### a) Optional dispatch input for the bump level

```yaml
on:
  workflow_dispatch:
    inputs:
      bump:
        description: "Version bump for this deploy (git tag vX.Y.Z)"
        type: choice
        default: patch
        options: [patch, minor, major]
```

### b) Compute step (after the typecheck gate, before build)

Pass the input through `env:` (never interpolate `${{ github.event.inputs.* }}`
directly into a shell `run:` — injection risk):

```yaml
      - name: Compute release version
        id: ver
        env:
          BUMP: ${{ github.event.inputs.bump }}
        run: |
          git fetch --tags --quiet origin || true
          # sort -V = global highest semver; `describe --abbrev=0` is topology-
          # nearest and can pick a lower base → non-monotonic version.
          LATEST=$(git tag --list 'v*' | sort -V | tail -n1)
          LATEST=${LATEST:-v0.0.0}
          IFS='.' read -r MAJ MIN PAT <<< "${LATEST#v}"
          case "$BUMP" in
            major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
            minor) MIN=$((MIN+1)); PAT=0 ;;
            *)     PAT=$((PAT+1)) ;;   # default patch / push:main with no input
          esac
          TAG="v$MAJ.$MIN.$PAT"
          while git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; do PAT=$((PAT+1)); TAG="v$MAJ.$MIN.$PAT"; done
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=${TAG#v}" >> "$GITHUB_OUTPUT"
          echo "Release version: $TAG"
```

### c) Upsert APP_VERSION + OTEL_SERVICE_VERSION in the register-task-def jq

Extend the existing jq that patches the image. This removes any existing copies
of the two vars, then appends the fresh ones — so it works whether or not they're
already in the live task-def:

```bash
  | jq --arg IMG "${{ steps.img.outputs.image }}" --arg VER "${{ steps.ver.outputs.version }}" \
      'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
       | .containerDefinitions[0].image = $IMG
       | .containerDefinitions[0].environment = ((.containerDefinitions[0].environment // [])
           | map(select(.name != "APP_VERSION" and .name != "OTEL_SERVICE_VERSION"))
           + [{name: "APP_VERSION", value: $VER}, {name: "OTEL_SERVICE_VERSION", value: $VER}])' \
  > task-def.json
```

Validate the jq before shipping: pipe a sample task-def JSON through it and
confirm the two env vars appear and the rest is untouched.

### d) Push-tag step (only runs if everything above succeeded)

Put this after the smoke-test step. Because earlier steps `exit 1` on failure,
the job stops before here — so the tag is only pushed for a green deploy:

```yaml
      - name: Push release tag
        env:
          TAG: ${{ steps.ver.outputs.tag }}
        run: |
          # actions/checkout sets no git identity; annotated tags need one, or
          # `git tag -a` fails with "Committer identity unknown" on every run
          # (deploy still succeeds, but the tag never lands → version freezes).
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git tag -a "$TAG" -m "<service> $TAG — automated deploy (${GITHUB_SHA::7})"
          git push origin "$TAG"
          echo "Tagged $TAG"
```

### e) Publish GitHub Release step (right after the tag push, every deploy)

A git tag and a GitHub Release are two different things — the tag is a git
object, the Release is a GitHub-only surface layered on top of it, and
nothing creates the Release for you. Skipping this step is the single most
common half-finished state of this skill: the tag pushes fine on every
deploy, the Releases tab looks populated because someone once ran a
one-time backfill (see `uplift-repo-polish`'s Releases surface), and then
every deploy *after* that backfill silently produces a tag with no matching
Release — invisible until someone happens to compare `git tag` against
`gh release list`. Always wire this, not just the tag push:

```yaml
      - name: Publish GitHub Release
        continue-on-error: true   # never fail an otherwise-successful deploy
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ steps.ver.outputs.tag }}
        run: |
          curl -sf -X POST \
            -H "Authorization: Bearer $GH_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/releases" \
            -d "$(node -e 'console.log(JSON.stringify({tag_name: process.env.TAG, name: process.env.TAG, generate_release_notes: true}))')"
```

> **Use `curl` against the REST API, not `gh release create`.** The
> `[self-hosted, linux, arm64, uplift-deploy]` runner is a shared EC2 box
> without the `gh` CLI installed — `gh release create` fails with `command
> not found` (exit 127) there. `curl` + `GITHUB_TOKEN` (auto-provided as
> `github.token`, needs `permissions: contents: write` — the same
> permission the tag push already requires) has no extra dependency and
> works on both self-hosted and `ubuntu-latest`. `generate_release_notes:
> true` gets you the same commit-summary notes `gh release create
> --generate-notes` would, without needing the binary.
> `GITHUB_REPOSITORY` is a default Actions env var — no need to set it.

## First-run checklist for a newly-wired explicit workflow

1. Keep `push: main` commented; trigger one `workflow_dispatch` (bump=patch).
2. Confirm the run is green and the tag was pushed.
3. `curl /version` (backend) or check the task-def OTEL value.
4. Only then arm `push: main` for auto-deploy.
