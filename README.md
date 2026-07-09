# Uplift Tech — Claude Code plugins

[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-6C4BF6?logo=anthropic&logoColor=white)](https://docs.claude.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/github/license/uplift-technology-company-limited/uplift-plugins?color=blue)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/uplift-technology-company-limited/uplift-plugins?label=release&sort=semver&color=success)](https://github.com/uplift-technology-company-limited/uplift-plugins/releases)
[![Top language](https://img.shields.io/github/languages/top/uplift-technology-company-limited/uplift-plugins?color=89e051)](https://github.com/uplift-technology-company-limited/uplift-plugins)
[![Plugins](https://img.shields.io/badge/plugins-3-orange)](#plugins)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](#contributing)

A [Claude Code](https://docs.claude.com/en/docs/claude-code) **plugin marketplace**
published by Uplift Tech. One repo, multiple plugins — each documents a real piece
of Uplift's engineering convention as a reusable Claude Code skill, so Claude ships
your deploys the way your team already does it.

> **No build, no runtime.** This is markdown + templates + manifests fetched by
> `/plugin install` — nothing to deploy. Versioning = a shared `vX.Y.Z` git tag
> across all plugins (see [Releases](#releases)).

## Quick start

```
/plugin marketplace add uplift-technology-company-limited/uplift-plugins
/plugin install <plugin-name>@uplift-plugins
```

Skills activate automatically when relevant. You can also invoke one explicitly,
e.g. `/vercel-gha-deploy:vercel-gha-deploy` or
`/upliftcontrolversion:upliftcontrolversion`.

**Requirements:** [Claude Code](https://docs.claude.com/en/docs/claude-code)
(the plugins are guidance + copy-paste templates; the deploy targets they wire up
need the usual `gh`, `vercel`, `aws`, or `docker` CLIs).

## Plugins

| Plugin | What it does | Install |
| ------ | ------------ | ------- |
| **`vercel-gha-deploy`** | Vercel deploys via GitHub Actions — `main`-only gate + auto-bumped `vX.Y.Z` version tags. Bootstraps a fresh repo. | `/plugin install vercel-gha-deploy@uplift-plugins` |
| **`upliftcontrolversion`** | Every deploy auto-bumps a git tag, bakes it into the artifact, shows it to humans, stops `OTEL_SERVICE_VERSION` drift. | `/plugin install upliftcontrolversion@uplift-plugins` |
| **`upliftgha`** | Set up / migrate / audit GitHub Actions CI/CD — incl. Jenkins → GHA. Routes to the two above; owns AWS EC2 + ECS shapes. | `/plugin install upliftgha@uplift-plugins` |

---

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

### `upliftgha`

Sets up, migrates, or audits **GitHub Actions CI/CD** for a repo — the router
that ties the other two plugins together, plus the ground they don't cover:

- **Jenkins → GHA conversion.** Reads a `Jenkinsfile` stage-by-stage and maps it
  to a GHA workflow (`agent`/`environment`/`withCredentials`/`parallel`/`post`/
  `when` → their GHA equivalents), flagging anything with no clean mapping
  (shared libraries, heavy Groovy) instead of guessing.
- **Greenfield interview.** No pipeline at all yet? It asks: what should it do,
  frontend or backend, Vercel or AWS, EC2 or ECS, does the ECR registry already
  exist.
- **Routes, doesn't reimplement.** Vercel target → hands off to
  `vercel-gha-deploy` entirely. Every target → always wires in
  `upliftcontrolversion`'s version-tag contract.
- **Owns AWS EC2 (docker-compose via SSM) and ECS (Fargate + ECR)** directly,
  with copy-paste templates for both.
- **Terraform-only for infra** — if a target needs AWS infrastructure that
  doesn't exist yet (like a fresh ECR repo), it says so and points at
  Terraform rather than provisioning anything itself.

Ask Claude to "set up GitHub Actions for this repo", "convert this Jenkinsfile
to GHA", "migrate off Jenkins", or "this repo has no CI yet" and it runs the
decision tree: detect state → runner choice (self-hosted vs GitHub-hosted) →
target-specific setup → version wiring → branch gate.

## Repository layout

```
.claude-plugin/marketplace.json   # marketplace manifest (name, owner, plugin list)
plugins/
  vercel-gha-deploy/              # each plugin: skills/ + .claude-plugin/plugin.json
  upliftcontrolversion/
  upliftgha/
scripts/release.sh                # shared vX.Y.Z release (bumps tag + plugin.json versions)
.github/workflows/release.yml     # release automation
```

## Releases

All plugins in this marketplace share **one release cadence** — a single
`vX.Y.Z` git tag, kept in sync with every `plugins/*/.claude-plugin/plugin.json`
`version` field, so a fresh `/plugin install` always resolves to the number the
tag says.

```bash
./scripts/release.sh release              # patch bump (default)
BUMP=minor ./scripts/release.sh release   # new feature in a skill
BUMP=major ./scripts/release.sh release   # breaking change to a workflow contract
```

See the [releases page](https://github.com/uplift-technology-company-limited/uplift-plugins/releases).

## Contributing

PRs welcome. Each plugin lives under `plugins/<name>/` with its own
`.claude-plugin/plugin.json` and a `skills/` directory. To add or change one:

1. Edit the skill markdown / templates under `plugins/<name>/`.
2. Keep `.claude-plugin/marketplace.json` in sync (name, source, description).
3. Cut a release with `./scripts/release.sh` so tag + `plugin.json` versions match.

## License

MIT — see [LICENSE](LICENSE).
