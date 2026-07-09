---
name: upliftcontrolversion
description: >-
  Set up and manage the Uplift auto-increment version system in an Uplift repo
  (account, the sso service, admin-portal, payment, media, message, subscription,
  cms, and siblings). Use this WHENEVER the user wants to: add version tags that
  bump automatically on every deploy, show the running version in the UI or
  expose it via a /version API, stop OTEL_SERVICE_VERSION from drifting (the
  hardcoded "1.0.0" bug), make git tags the source of truth for what's deployed,
  or answer "what version is prod running?". Trigger on phrases like "version
  bump on deploy", "show the app version", "add a /version endpoint",
  "auto-increment version", "tag every release", "wire up versioning", even if
  the user doesn't say the skill name. Mirrors upmove's auto-bump on top of the
  sso service's existing SemVer/tag convention. (Not about Single Sign-On.)
---

# Uplift Control Version

Wires a repo up so that **every deploy auto-bumps a git tag (`vX.Y.Z`)**, the
number is **baked into the artifact**, **shown to humans** (UI label and/or a
`/version` API), and **kept in sync with telemetry** (`OTEL_SERVICE_VERSION`).

## The model (why it's built this way)

- **git tag `vX.Y.Z` is the source of truth**, not `package.json`. `package.json`
  drifts because people forget to bump it; a tag is created by the deploy itself,
  so it can't lie about what shipped.
- **Auto-bump `patch` on every deploy** (a de-facto build counter), like upmove.
  `BUMP=minor` / `BUMP=major` for meaningful feature/breaking releases, keeping
  the sso service's SemVer meaning intact.
- **Tag is pushed only AFTER a successful rollout.** The number is *computed*
  before the build (so it can be baked in), but the tag is created+pushed at the
  very end — a failed build/migration leaves no orphan tag, and the counter
  doesn't burn.
- **One number, everywhere.** The same `APP_VERSION` feeds the UI label, the
  `/version`/`/health` API, and `OTEL_SERVICE_VERSION`, so a trace in Grafana and
  the sidebar always agree on what's live.

## Step 0 — Identify the repo shape

Two shapes, different injection + display. Most repos are one or the other; a
Next.js app that also has API routes still counts as **frontend**.

| Shape | Examples | Inject via | Show via | Read this |
|---|---|---|---|---|
| **Frontend** (Next.js in Docker) | admin-portal, saas, Mainwebsite | `--build-arg NEXT_PUBLIC_APP_VERSION` (baked at build) | UI label (footer/sidebar) | [references/frontend-nextjs.md](references/frontend-nextjs.md) |
| **Backend** (Bun/Elysia, runtime) | sso, account, payment, media, message | ECS task-def env `APP_VERSION` (read at runtime) | `GET /version` + `/health` | [references/backend-bun.md](references/backend-bun.md) |

Both shapes share the deploy.sh + GHA tag-bump mechanics below. Do Steps 1–2
first (shared), then the shape-specific reference, then Step 4 (verify).

## Step 1 — Add the tag-bump to `scripts/deploy.sh`

Most Uplift repos deploy through `scripts/deploy.sh` (build → ECR → register
task def → update ECS). Add the two functions and wire them into the `deploy`
path. Keep `compute_version` **pure** (no push) so a failed deploy leaves no tag.

Near the top, after `PROJECT_DIR=...`:

```bash
# Version. Source of truth = git tag (vX.Y.Z), auto-bumped once per deploy.
# APP_VERSION feeds the artifact + OTEL_SERVICE_VERSION. BUMP: patch|minor|major.
BUMP="${BUMP:-patch}"
APP_VERSION="$(node -p "require('${PROJECT_DIR}/package.json').version" 2>/dev/null || echo "0.0.0")"
RELEASE_TAG=""
```

Add the functions (next to `get_image_tag`):

```bash
# Compute the next semver tag from the highest existing vX.Y.Z (NO side effects).
compute_version() {
  git -C "$PROJECT_DIR" fetch --tags --quiet origin 2>/dev/null || true
  local latest major minor patch
  # Use sort -V for the GLOBAL max, NOT `git describe --abbrev=0` — describe
  # returns the latest tag reachable from HEAD by topology, which can pick a
  # lower base and mint a non-monotonic version.
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

# Create + push the annotated tag — ONLY after a successful rollout. Non-fatal.
tag_release() {
  [ -n "$RELEASE_TAG" ] || return 0
  # Annotated tags need a git identity; CI runners may have none.
  git -C "$PROJECT_DIR" config user.name  >/dev/null 2>&1 || git -C "$PROJECT_DIR" config user.name  "uplift-deploy"
  git -C "$PROJECT_DIR" config user.email >/dev/null 2>&1 || git -C "$PROJECT_DIR" config user.email "deploy@uplifttech.co"
  git -C "$PROJECT_DIR" tag -a "$RELEASE_TAG" -m "$RELEASE_TAG — automated deploy ($(get_image_tag))" 2>/dev/null || true
  if git -C "$PROJECT_DIR" push origin "$RELEASE_TAG" 2>/dev/null; then
    echo "Tagged ${RELEASE_TAG}" >&2
  else
    echo "Could not push tag ${RELEASE_TAG} (non-fatal)" >&2
  fi
}
```

Wire into the `deploy)` case — `compute_version` first, `tag_release` last:

```bash
  deploy)
    compute_version                 # <-- added: sets APP_VERSION + RELEASE_TAG
    # ... existing build / ecr / push / register / update-service ...
    tag_release                     # <-- added: push tag only after success
    ;;
```

In the task-def `environment` array, add `APP_VERSION` and point
`OTEL_SERVICE_VERSION` at it (this kills the hardcoded `"1.0.0"` drift):

```jsonc
{ "name": "APP_VERSION",          "value": "${APP_VERSION}" },
{ "name": "OTEL_SERVICE_VERSION", "value": "${APP_VERSION}" }
```

## Step 2 — Let the GHA workflow push the tag

`.github/workflows/deploy.yml` needs write access + full history:

```yaml
    permissions:
      contents: write   # push the auto-bumped vX.Y.Z release tag
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history + tags for `git describe`
```

- If the workflow **wraps `scripts/deploy.sh`** (like admin-portal), that's all —
  deploy.sh does the bump/push.
- If the workflow uses **explicit steps** (like sso: describe-task-def → jq patch
  → register), the version must be computed in the workflow and injected via jq.
  See [references/gha.md](references/gha.md) for the compute step, the jq env
  upsert, and the push-tag step (with a `workflow_dispatch` bump input).

## Step 3 — Inject + display (shape-specific)

Now do the reference for the repo's shape:
- Frontend → [references/frontend-nextjs.md](references/frontend-nextjs.md)
  (Dockerfile `ARG`, `next.config` env, footer component).
- Backend → [references/backend-bun.md](references/backend-bun.md)
  (`src/lib/version.ts`, `/version` route, `version` in `/health`).

## Step 4 — Verify (don't claim done without this)

After the first deploy with the changes in:

```bash
# 1. the tag was auto-bumped + pushed
git ls-remote --tags origin | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail -3

# 2. the live task-def carries the version (OTEL no longer 1.0.0)
aws ecs describe-task-definition --task-definition <family> --region ap-southeast-1 \
  --query 'taskDefinition.containerDefinitions[0].environment[?name==`OTEL_SERVICE_VERSION`].value' --output text

# 3a. backend: the API answers
curl -s https://<service-host>/version   # -> {"service":"...","version":"X.Y.Z"}

# 3b. frontend: the UI label shows vX.Y.Z (baked NEXT_PUBLIC_APP_VERSION == the tag)
```

The strongest single check is #2: `OTEL_SERVICE_VERSION` == the new tag proves
`APP_VERSION` flowed through the whole pipe (it's the same variable that feeds
the build-arg / API).

## Conventions & gotchas (Uplift-specific)

- **Deploy from `main` only.** The bump tags whatever commit is `HEAD` — never
  run a deploy (and thus a tag) from a feature branch. `feature → dev → main`
  first, always.
- **First run of an explicit-steps workflow** (sso-style): do one manual
  `workflow_dispatch` (bump=patch) and verify green before arming `push: main`.
- **`package.json` version** becomes a **local-dev fallback only** — don't rely
  on hand-bumping it; the tag is authoritative. Optionally bump its major.minor
  when you cut a real release so dev shows a sensible floor.
- **Self-hosted runner** (`[self-hosted, linux, arm64, uplift-deploy]`) already
  has git creds via `actions/checkout` persist-credentials, so `git push` of the
  tag works once `contents: write` is granted.
- **Don't double-prefix.** The tag is `vX.Y.Z`; pass the numeric `X.Y.Z` to
  `APP_VERSION`/`NEXT_PUBLIC_APP_VERSION` and let the UI render the `v` (`v{ver}`),
  or pass `v...` and don't prepend — pick one, not both.
