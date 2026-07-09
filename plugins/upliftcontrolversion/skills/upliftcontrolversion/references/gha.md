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
`compute_version` (before build) and `tag_release` (after rollout), so **nothing
else is needed** beyond the `permissions`/`fetch-depth` above. To cut a
feature/breaking release, run the job with `BUMP` set (e.g. a `workflow_dispatch`
input piped into `env: { BUMP: ... }`, or just deploy manually with
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

### d) Push-tag step (LAST — only runs if everything above succeeded)

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

## First-run checklist for a newly-wired explicit workflow

1. Keep `push: main` commented; trigger one `workflow_dispatch` (bump=patch).
2. Confirm the run is green and the tag was pushed.
3. `curl /version` (backend) or check the task-def OTEL value.
4. Only then arm `push: main` for auto-deploy.
