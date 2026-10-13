---
name: upliftgha
description: >-
  Set up, migrate, or audit GitHub Actions CI/CD for an Uplift repo — including
  converting an existing Jenkins pipeline to GHA, or building a pipeline from
  scratch when there's no CI at all yet. Orchestrates the deploy-target-specific
  skills: hands off to `upliftvercel` for Vercel frontends, and always invokes
  `upliftcontrolversion` to wire the git-tag version contract, regardless of
  target. Owns the AWS EC2 (docker-compose) and ECS (Fargate + ECR) deploy
  shapes directly. Use this WHENEVER the user wants to: set up GitHub Actions
  for a repo, migrate/convert a Jenkinsfile to GHA, replace Jenkins with GitHub
  Actions, add a first-time CI/CD pipeline, choose between a self-hosted runner
  and GitHub-hosted, or figure out how a repo without a pipeline should deploy
  (Vercel vs AWS, EC2 vs ECS). Trigger on phrases like "ทำ repo เป็น GHA",
  "แปลง jenkins เป็น github actions", "ย้ายจาก jenkins ไป gha", "ตั้ง ci/cd ให้
  repo นี้", "set up github actions", "convert this jenkinsfile", "this repo has
  no pipeline yet", even if the user doesn't name the skill or say which cloud
  target they want — resolving that ambiguity by asking is exactly this skill's
  job.
---

# Uplift GHA — CI/CD setup, Jenkins migration, and deploy-target routing

Gets a repo onto GitHub Actions, however it's starting out: migrating off
Jenkins, auditing a half-built workflow, or starting from nothing. This skill
is a **router**, not a reimplementation — two shapes already have dedicated
owners:

- **Vercel** → hand off entirely to the `upliftvercel` skill (bootstrap,
  secrets convention, deploy.sh, workflow template — all of it).
- **The version contract** (git tag `vX.Y.Z` → baked into the artifact → shown
  to humans → synced to telemetry) → always invoke `upliftcontrolversion`,
  regardless of target. Every pipeline this skill sets up should end up
  version-tagged.

What's genuinely new ground here — and what this skill owns directly — is
**Jenkins→GHA translation** and the two **AWS deploy shapes** (EC2
docker-compose, ECS+ECR) that don't have a skill yet.

## The model

- **One branch-gate, one first-run convention, everywhere.** Whatever the
  target, deploy only fires from `main`, and a newly-wired workflow's first
  run is a manual `workflow_dispatch` — `push: main` gets armed only after
  that run is verified green. This is the same convention `upliftvercel` and
  `upliftcontrolversion` already use; a fourth, different convention here
  would just be confusing.
- **Ask before assuming the target.** "Set up CI for this repo" doesn't say
  whether it deploys to Vercel, sits behind an ALB on ECS, or lives on a
  single EC2 box — and guessing wrong means redoing the whole pipeline. Ask
  once, up front, and reuse the answer.
- **AWS infra is Terraform's job, not this skill's.** If a target needs
  infrastructure that doesn't exist yet (an ECR repo, a new ECS service, a
  security group), this skill's job is to say so and point at Terraform — not
  to run `aws ecr create-repository` or anything else that mutates AWS
  directly. See the Uplift-wide deployment policy: application deploys go
  through pipelines, infra goes through Terraform, always.

## Step 0 — Detect state

```bash
find . -maxdepth 2 -iname 'Jenkinsfile*'
ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
```

Three starting points, three paths — all converge at Step 4:

| Found | Path |
|---|---|
| A `Jenkinsfile` | Step 1 — Jenkins → GHA conversion |
| `.github/workflows/*.yml` but no Jenkinsfile | Step 2 — Audit existing |
| Neither | Step 3 — Greenfield interview |

## Step 1 — Jenkins → GHA conversion

Read the whole Jenkinsfile before writing anything. Then read
[references/jenkins-to-gha.md](references/jenkins-to-gha.md) for the
construct-by-construct mapping (`agent`/`environment`/`stages`/
`withCredentials`/`parallel`/`post`/`when`/`triggers`) before drafting the new
workflow.

Two things matter more than speed here:

- **Preserve the actual stage sequence.** Don't reorder or merge stages for
  tidiness — a Jenkinsfile's order usually encodes real dependencies (tests
  before build, build before push) that aren't always obvious from reading a
  single stage in isolation.
- **Don't silently guess at things with no clean mapping.** Shared libraries
  (`@Library(...)`), heavy Groovy scripting, or an `input` manual-approval
  step don't translate mechanically. Read what a shared library actually does
  (it usually lives in its own repo) before proposing a translation, and if
  something genuinely needs redesigning rather than porting, say that to the
  user instead of shipping a plausible-looking guess.

A parsed Jenkinsfile usually already answers "what does this build/deploy, and
to where" — use that to shortcut Step 3's target questions, but **confirm**
with the user rather than assuming; Jenkinsfiles accumulate cruft (stages that
no longer run, deploy targets that moved) more often than you'd expect. Same
goes for the runner: a Jenkins `agent { label '...' }` doesn't map 1:1 to a
GHA runner label, so don't silently reuse it — if it looks like the user
clearly wants to keep using the same physical box, confirm that explicitly in
Step 4 rather than inferring it.

## Step 2 — Audit existing GHA workflows

Read every file under `.github/workflows/`. Summarize back to the user: what
triggers each workflow, what runner it uses, what it builds/deploys, whether
it already tags a version, whether it already guards on `main`. **Ask what
they specifically want changed** — don't take "set up CI" as license to
rewrite a working pipeline from scratch.

## Step 3 — Greenfield interview

Nothing exists yet. Use `AskUserQuestion` (skip anything Step 1 already
established from a Jenkinsfile parse):

1. **What should the pipeline do?** — checks only (lint/typecheck/test) · build
   + checks · build + checks + deploy.
2. **Frontend, or a backend/API service?**
3. *(if frontend)* **Vercel, or AWS?**
4. *(if AWS, either shape)* **EC2** (docker-compose on a persistent instance)
   or **ECS** (Fargate + a container registry)?
5. *(if ECS)* **Does an ECR repository already exist** for this service?

## Step 4 — Runner choice (every path, always ask)

`AskUserQuestion`: self-hosted vs GitHub-hosted. Skip only if Step 1 already
confirmed the user wants to keep a specific self-hosted box from the
Jenkinsfile.

- **Self-hosted** (`[self-hosted, linux, arm64, uplift-deploy]`) — builds
  arm64 natively (no QEMU emulation tax), sits inside the prod VPC so it can
  reach internal-only endpoints. Tradeoff: it's **one shared box** across the
  whole org, so concurrent deploys from different repos queue behind each
  other.
- **GitHub-hosted** (`ubuntu-latest`) — no contention, nothing to keep
  online, simpler to reason about. Tradeoff: arm64 Docker builds run emulated
  (slower) unless the target accepts an x86 image.

## Step 5 — Target-specific setup

### Vercel

Don't write Vercel steps here — invoke the `upliftvercel` skill via the Skill
tool and hand it the repo. It owns bootstrap, the secrets convention, and the
whole workflow template for that shape already; reimplementing any of it here
just creates a second, drifting copy of the same logic.

### AWS EC2 (docker-compose)

Read [references/aws-ec2.md](references/aws-ec2.md). Start from
[assets/deploy-ec2.yml](assets/deploy-ec2.yml) +
[assets/deploy-ec2.sh](assets/deploy-ec2.sh).

### AWS ECS (Fargate + ECR)

**First, check the registry exists** — this is read-only and always safe to
run:

```bash
aws ecr describe-repositories --repository-names <service> --region <region>
```

If it **doesn't** exist: stop here and tell the user this needs a Terraform
change in the infra repo (`infra/terraform/`) that adds an ECR module — do
**not** run `aws ecr create-repository` or any other AWS write command
yourself. This holds even for a resource this small; the deployment policy
doesn't have a size exception.

Once the registry exists (or a Terraform PR is at least planned), read
[references/aws-ecs.md](references/aws-ecs.md) and start from
[assets/deploy-ecs.yml](assets/deploy-ecs.yml) +
[assets/deploy-ecs.sh](assets/deploy-ecs.sh).

## Step 6 — Wire the version contract (always, every target)

Once the deploy mechanics exist, invoke the `upliftcontrolversion` skill via
the Skill tool so `compute_version`/`tag_release`/`publish_release` and the
shape-specific inject/display (build-arg for a frontend, task-def env for a
backend) get wired in consistently. Do this even on the Vercel path —
`upliftvercel` calls into the same contract, but verify it actually happened
rather than assuming the hand-off covered it. The version contract isn't done
until the tag push **and** the matching GitHub Release publish are both in
the workflow — a tag with no Release is a common half-finished state (see
`upliftcontrolversion`'s own notes on this); don't sign off on Step 6 without
confirming both exist.

## Step 7 — Branch gate + first-run convention (always, every path)

```yaml
- name: Guard — must be on main
  env:
    GH_REF: ${{ github.ref }} # route through env — never inline github.* in run:
  run: '[ "$GH_REF" = "refs/heads/main" ] || { echo "::error::deploy from main only"; exit 1; }'
```

Route every `${{ github.* }}` value through `env:` before it reaches a `run:`
step, even ones that look safe (a `workflow_dispatch` `choice` input is
inherently constrained to its declared options, but keeping the `env:` habit
uniform beats having to remember which case was the safe one).

First run is a manual `workflow_dispatch` (with a `bump` choice input if
version-tagging is in play). Only uncomment `push: { branches: [main] }`
after that run is verified green — tag pushed if applicable, deploy actually
succeeded, smoke test passed.

## Verify (don't claim done without this)

- The new/converted workflow file parses as valid YAML.
- A `workflow_dispatch` run went green end-to-end.
- The deploy target actually reflects the change — curl the domain, check the
  ECS service's running task, or check the containers on the EC2 box,
  whichever applies.
- If version wiring was added: the tag pushed and the running artifact shows
  it (per `upliftcontrolversion`'s own verify steps — don't re-derive these,
  just run them).
- **If this was a Jenkins conversion**, walk the old Jenkinsfile stage-by-stage
  against the new workflow one more time before calling it done — the easiest
  way to lose something in a migration is to feel done after the happy path
  works once.

## Gotchas

- **Don't leave the Jenkinsfile running "just in case."** Two live pipelines
  deploying the same thing is how a team discovers months later that
  deploys have quietly been happening from two places with two different
  histories. Once the GHA workflow is verified, remove the Jenkinsfile (or at
  minimum neuter its deploy stage) in the same change, and say so explicitly
  — don't leave the old pipeline dormant-but-armed.
- **The self-hosted runner is a shared, finite resource.** Don't default every
  new repo onto it without asking (Step 4) — for a low-traffic repo,
  GitHub-hosted is often genuinely simpler and nobody has to think about
  queueing behind someone else's deploy.
- **Terraform-only extends beyond the ECR repo itself** — security groups,
  IAM roles, ALB target groups, ECS services/clusters all fall under the same
  rule. If the AWS shape implies infra beyond "run this container on
  something that already exists," that's a Terraform task, not something to
  solve with ad-hoc `aws` CLI writes.
- **A Jenkinsfile with `@Library(...)` or heavy Groovy** doesn't translate
  mechanically — go read what the shared library does before proposing a
  mapping.
