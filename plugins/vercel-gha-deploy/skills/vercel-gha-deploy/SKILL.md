---
name: vercel-gha-deploy
description: >-
  Set up (or fix) deploying a Next.js / frontend repo to Vercel from a GitHub
  Actions workflow — with an org-level VERCEL_TOKEN, a main-only branch gate, and
  an auto-bumped vX.Y.Z version tag baked into the build and shown in the UI. Use
  this WHENEVER the user wants to add a Vercel deploy pipeline via GitHub Actions,
  move a repo from manual `vercel --prod` to CI deploy, run the build on a
  self-hosted runner, wire auto-versioning onto Vercel deploys, or bootstrap a
  not-yet-set-up repo (git init → GitHub → vercel link → deploy) — even if they
  don't name this skill. NOT for: fixing app/code bugs that happen to surface in a
  Vercel build, one-off manual `vercel --prod` runs, Vercel dashboard settings
  (env vars, domains, rollbacks), Vercel's native git integration (this skill uses
  GitHub Actions instead), or deploys to other targets (AWS ECS, Docker, a VPS).
---

# Vercel + GitHub Actions Deploy (with auto-versioning)

Wires a frontend repo so it **deploys to Vercel from a GitHub Actions workflow**,
and every deploy **auto-bumps a `vX.Y.Z` git tag** that gets baked into the build
and shown in the UI. Also **bootstraps** a repo that isn't ready yet (no git, no
GitHub remote, not linked to Vercel).

Why this instead of Vercel's native git integration? Running the deploy from
GitHub Actions lets you gate on `typecheck`/`lint`, bake a build-time version into
the client bundle, cut a git tag per release, and (optionally) build on your own
self-hosted runner. If you just want push-to-deploy with none of that, Vercel's
built-in git integration is simpler and this skill is overkill.

## The model (why it's built this way)

- **The token lives once, centrally.** Store `VERCEL_TOKEN` as a **GitHub
  org-level secret** (visible to all repos) so every repo inherits it and you
  never paste it per-repo. Only the project identity — `VERCEL_ORG_ID` (your team)
  and `VERCEL_PROJECT_ID` (this project, from `.vercel/project.json`) — is per-repo,
  and those aren't secret. (Repo-level `VERCEL_TOKEN` also works if you don't have
  org secrets; org-level just scales better.)
- **git tag `vX.Y.Z` is the source of truth for what shipped**, auto-bumped once
  per deploy and pushed only AFTER a successful rollout — so a failed build leaves
  no orphan tag. The number is computed before the build (to bake it in) and the
  tag is created at the very end.
- **Deploy from `main` only.** The workflow hard-fails on any other ref, because
  the tag is cut on `HEAD` and you don't want to tag a feature branch. First run
  is a manual `workflow_dispatch`; `push: main` is armed only after the first run
  is verified green.
- **Build on a runner, or on Vercel.** Building on the runner lets you inject
  `NEXT_PUBLIC_*` build-time env (like the version). Building on Vercel is lighter
  but you'd wire the version through a Vercel env var instead.

---

## Step 0 — Detect state, and bootstrap what's missing

Don't assume the repo is ready. Check three things and fill any gap before
touching the deploy layer.

```bash
git rev-parse --is-inside-work-tree 2>/dev/null   # is it a git repo?
git remote -v                                      # is there a GitHub remote?
cat .vercel/project.json 2>/dev/null               # is it linked to Vercel?
```

| Missing | Do this |
|---|---|
| **git repo** | `git init -b main`, add `.gitignore` (must ignore `node_modules`, `.next`, `.vercel`, `.env*` with `!.env.example`), initial commit |
| **GitHub remote** | **Secret-scan first** (below), then `gh repo create <owner>/<name> --source=. --remote=origin --push` (private unless the user wants public) |
| **Vercel link** | `vercel link` → writes `.vercel/project.json` with `orgId` + `projectId` you'll need for the secrets |

**Secret scan before the first push** — a fresh repo push exposes whatever's
tracked:

```bash
git ls-files | grep -iE '\.env$|\.env\.|secret|\.pem|\.key$' || echo "no secret files tracked"
# also sweep tracked text files for sk-… / AKIA… / ghp_… / AIza… / xox…- tokens
```

Confirm `node_modules` / `.next` / `.vercel` / `.env` are not tracked. Proceed
only once clean.

---

## Step 1 — Pick the build style

- **build-on-runner** (DEFAULT): the runner runs `vercel pull → vercel build →
  vercel deploy --prebuilt --prod`. The build happens on the runner, so
  `NEXT_PUBLIC_APP_VERSION` (and any `NEXT_PUBLIC_*`) can be injected at build time.
  Needed for the version label.
- **build-on-Vercel** (lighter): the workflow just calls `vercel deploy --prod
  --token …` and Vercel builds remotely. Less runner load, but you can't inject
  build-time env from the runner — the version has to come from a Vercel env var.

Default to build-on-runner because the version label is part of the standard
package. Choose build-on-Vercel only if you don't want the runner to build.

---

## Step 2 — `scripts/deploy.sh`

Copy [assets/deploy.sh](assets/deploy.sh) into the repo at `scripts/deploy.sh`,
fill the `<PROJECT_NAME>` header, and `chmod +x`. It:

1. Loads creds from a gitignored `.env` (or `~/.config/<repo>.env`, or
   `$DEPLOY_ENV_FILE`) **without clobbering** vars already set by CI — so
   `./scripts/deploy.sh deploy` just works locally, and a persistent runner can
   keep the token on-box.
2. `compute_version` — highest `vX.Y.Z` tag via `sort -V` (NOT `git describe`,
   which is topological and can mint a non-monotonic version) → bump
   `${BUMP:-patch}` → set `APP_VERSION`. Pure, no side effects.
3. Builds with `NEXT_PUBLIC_APP_VERSION` exported, deploys `--prebuilt --prod`.
4. `tag_release` — annotated tag + push, **only after** a successful deploy;
   non-fatal if the push fails.

---

## Step 3 — `.github/workflows/deploy.yml`

Copy [assets/deploy.yml](assets/deploy.yml), fill `<PROJECT_NAME>`, `<PROD_DOMAIN>`,
and your runner label. Key pieces that must survive edits:

```yaml
on:
  # push: { branches: [main] }   # ← COMMENTED until the first dispatch is green
  workflow_dispatch:
    inputs: { bump: { type: choice, default: patch, options: [patch, minor, major] } }

jobs:
  deploy:
    runs-on: ubuntu-latest         # or: [self-hosted, linux, arm64, <your-label>]
    permissions:
      contents: write              # push the auto-bumped vX.Y.Z tag
    env:
      VERCEL_TOKEN:      ${{ secrets.VERCEL_TOKEN }}      # org-level secret
      VERCEL_ORG_ID:     ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # full history + tags for the version bump
      - name: Guard main
        env: { GH_REF: ${{ github.ref }} }   # via env, never inline in run:
        run: '[ "$GH_REF" = "refs/heads/main" ] || { echo "::error::deploy from main only"; exit 1; }'
      - run: bun install --frozen-lockfile   # or npm ci / pnpm i --frozen-lockfile
      - run: bun run typecheck
      - name: Deploy
        env: { BUMP: ${{ github.event.inputs.bump }} }
        run: ./scripts/deploy.sh deploy
      - name: Smoke test   # curl https://<PROD_DOMAIN>/ until 200
```

Never interpolate `${{ github.* }}` directly inside a `run:` script — route it
through `env:` (command-injection safety). The choice input `bump` is already safe
via `env: BUMP`.

---

## Step 4 — Show the version

Make the baked version visible so the tag isn't just abstract:

- `next.config.ts` — read the tag-injected env, fall back to `package.json`:
  ```ts
  const APP_VERSION = process.env.NEXT_PUBLIC_APP_VERSION || PKG_VERSION;
  const nextConfig: NextConfig = { /* … */, env: { NEXT_PUBLIC_APP_VERSION: APP_VERSION } };
  ```
- A footer / about screen — render `v{process.env.NEXT_PUBLIC_APP_VERSION}` (guard
  for `undefined` in local dev). For a backend or API, expose it on a `/version`
  route and set your telemetry's service version from the same value.

---

## Step 5 — Secrets (almost none per repo)

If `VERCEL_TOKEN` is a **GitHub org secret** (recommended), a new repo needs only
the two non-sensitive IDs (from `.vercel/project.json`):

```bash
R=<owner>/<name>
gh secret set VERCEL_ORG_ID     -R $R --body "<orgId from project.json>"
gh secret set VERCEL_PROJECT_ID  -R $R --body "<projectId from project.json>"
# VERCEL_TOKEN — inherited from the org; only set per-repo if you don't use org secrets
```

**Runner-local alternative:** on a persistent self-hosted runner, the token can
instead live in `~/.config/<repo>.env` on the box (deploy.sh reads it) — then no
GitHub secret is needed for the token at all.

---

## Step 6 — First run, verify, then arm auto-deploy

```bash
gh workflow run deploy.yml -R $R -f bump=patch
```

Verify (don't claim done without this):
1. tag pushed — `git ls-remote --tags origin | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1`
2. the live site shows the new `vX.Y.Z`
3. `https://<PROD_DOMAIN>/` returns 200

Only then uncomment `push: { branches: [main] }` so future merges auto-deploy.

---

## Gotchas

- **A gitignored `.env` is NOT on the CI runner.** `actions/checkout` is a fresh
  clone, so a repo-tracked `.env` won't exist in CI. Creds come from GitHub
  secrets or a persistent on-box file — never from a committed `.env` (which would
  leak the token). `.env` support in deploy.sh is for local runs and on-box runner
  files only.
- **Commit-author gate (if you enabled one).** Some teams configure Vercel so a
  production deploy only proceeds when the HEAD commit's author is on an allow-list
  — otherwise the build finishes in ~0 ms and nothing ships (a silent no-op, no red
  error). If a deploy runs "green" but the site never changes, check the HEAD
  commit author first. See [references/commit-author-gate.md](references/commit-author-gate.md).
- **Deploy from `main` only** — the tag is cut on `HEAD`; a feature-branch deploy
  would tag the wrong commit.
- **`contents: write`** is required for the runner to push the tag.
- **Don't double-prefix the version.** The tag is `vX.Y.Z`; pass the numeric
  `X.Y.Z` as `NEXT_PUBLIC_APP_VERSION` and let the UI render `v{ver}`.
