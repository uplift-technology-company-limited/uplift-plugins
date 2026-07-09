# vercel-gha-deploy

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that teaches
Claude to set up **Vercel deploys via GitHub Actions** — with a `main`-only branch
gate and **auto-bumped `vX.Y.Z` version tags** baked into the build and shown in
your UI. It can also **bootstrap** a fresh repo (git init → GitHub → `vercel link`)
that isn't wired up yet.

This repo is both a **plugin** and a **plugin marketplace** you can install from.

## What the skill does

When you ask Claude to "set up Vercel deploy", "add a GitHub Actions deploy for
my Next.js app", "wire auto-versioning onto my Vercel deploys", or similar, the
skill guides Claude through:

- **Bootstrap** (if needed): git init, `.gitignore`, secret-scan, create the
  GitHub repo, `vercel link`.
- **`scripts/deploy.sh`**: `compute_version` (bump the highest `vX.Y.Z` tag) →
  `vercel pull/build/deploy --prebuilt --prod` with `NEXT_PUBLIC_APP_VERSION`
  baked in → push the tag **only after a successful deploy**.
- **`.github/workflows/deploy.yml`**: typecheck gate → deploy → smoke test, with a
  `main`-only guard and a `workflow_dispatch` bump input (arm `push: main` after
  the first green run).
- **Version display**: wire `NEXT_PUBLIC_APP_VERSION` into `next.config` and show
  `v{version}` in the footer.
- **Secrets**: `VERCEL_TOKEN` as a GitHub **org secret** (all repos inherit it) +
  per-repo `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID`.

It deliberately runs the deploy from **GitHub Actions** (not Vercel's native git
integration) so you can gate on checks, bake a build-time version, and cut a git
tag per release. It supports both GitHub-hosted and **self-hosted** runners.

## Install

```
/plugin marketplace add uplift-technology-company-limited/vercel-gha-deploy
/plugin install vercel-gha-deploy@uplift-plugins
```

The skill then activates automatically when relevant. You can also invoke it
explicitly with `/vercel-gha-deploy:vercel-gha-deploy`.

## Not for

- Fixing app/code bugs that surface in a Vercel build (that's a normal code task)
- One-off manual `vercel --prod` runs
- Vercel dashboard settings (env vars, domains, rollbacks)
- Vercel's **native** git integration (this skill uses GitHub Actions instead)
- Deploys to other targets (AWS ECS, Docker, a VPS)

## Templates

The skill ships copy-paste templates under
[`plugins/vercel-gha-deploy/skills/vercel-gha-deploy/assets/`](plugins/vercel-gha-deploy/skills/vercel-gha-deploy/assets):
`deploy.sh` and `deploy.yml`. Placeholders (`<PROJECT_NAME>`, `<PROD_DOMAIN>`,
runner label) are filled per repo.

## License

MIT — see [LICENSE](LICENSE).
