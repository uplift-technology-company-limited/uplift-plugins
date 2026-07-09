# Uplift Tech — Claude Code plugins

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace
published by Uplift Tech. One repo, multiple plugins — each documents a real
piece of Uplift's engineering convention as a reusable Claude Code skill.

## Plugins

### `vercel-gha-deploy`

Teaches Claude to set up **Vercel deploys via GitHub Actions** — with a
`main`-only branch gate and **auto-bumped `vX.Y.Z` version tags** baked into the
build and shown in your UI. Can also **bootstrap** a fresh repo (git init →
GitHub → `vercel link`) that isn't wired up yet.

When you ask Claude to "set up Vercel deploy", "add a GitHub Actions deploy for
my Next.js app", "wire auto-versioning onto my Vercel deploys", or similar, it
guides Claude through:

- **Bootstrap** (if needed): git init, `.gitignore`, secret-scan, create the
  GitHub repo, `vercel link`.
- **`scripts/deploy.sh`**: `compute_version` (bump the highest `vX.Y.Z` tag) →
  `vercel pull/build/deploy --prebuilt --prod` with `NEXT_PUBLIC_APP_VERSION`
  baked in → push the tag **only after a successful deploy**.
- **`.github/workflows/deploy.yml`**: typecheck gate → deploy → smoke test, with
  a `main`-only guard and a `workflow_dispatch` bump input (arm `push: main`
  after the first green run).
- **Version display**: wire `NEXT_PUBLIC_APP_VERSION` into `next.config` and show
  `v{version}` in the footer.
- **Secrets**: `VERCEL_TOKEN` as a GitHub **org secret** (all repos inherit it) +
  per-repo `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID`.

It deliberately runs the deploy from **GitHub Actions** (not Vercel's native git
integration) so you can gate on checks, bake a build-time version, and cut a git
tag per release. Supports both GitHub-hosted and **self-hosted** runners.

**Not for**: fixing app/code bugs that surface in a build, one-off manual
`vercel --prod` runs, Vercel dashboard settings, Vercel's native git
integration, or deploys to other targets (AWS ECS, Docker, a VPS).

```
/plugin install vercel-gha-deploy@uplift-plugins
```

Templates: [`plugins/vercel-gha-deploy/skills/vercel-gha-deploy/assets/`](plugins/vercel-gha-deploy/skills/vercel-gha-deploy/assets)
(`deploy.sh`, `deploy.yml` — fill in `<PROJECT_NAME>`, `<PROD_DOMAIN>`, runner label).

### `upliftcontrolversion`

Uplift's own playbook for wiring a repo so **every deploy auto-bumps a git tag
(`vX.Y.Z`)**, the number is baked into the artifact, shown to humans (a UI label
or a `/version` API), and kept in sync with telemetry (`OTEL_SERVICE_VERSION`) —
instead of drifting off a hand-edited, easily-stale `"1.0.0"`.

Covers two shapes with concrete, copy-paste guidance for each:

- **Frontend** (Next.js in Docker) — inject via a Docker build-arg, display as a
  UI label.
- **Backend** (a runtime service) — inject via a task-def env var, expose via
  `GET /version` and `/health`.

Ask Claude to "add version tags that bump automatically on every deploy", "show
the running version in the UI", "add a `/version` endpoint", or "stop
`OTEL_SERVICE_VERSION` from drifting" and it walks through both the shared
tag-bump mechanics and the shape-specific wiring.

```
/plugin install upliftcontrolversion@uplift-plugins
```

## Install the marketplace

```
/plugin marketplace add uplift-technology-company-limited/vercel-gha-deploy
/plugin install <plugin-name>@uplift-plugins
```

Skills activate automatically when relevant. You can also invoke one explicitly,
e.g. `/vercel-gha-deploy:vercel-gha-deploy` or
`/upliftcontrolversion:upliftcontrolversion`.

## License

MIT — see [LICENSE](LICENSE).
