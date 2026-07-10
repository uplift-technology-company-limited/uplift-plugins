---
name: uplift-repo-polish
description: >-
  Polish a GitHub repository's presentation so it reads like a well-maintained
  project — README badges (static ones for private repos) + scannable structure,
  the About sidebar (description, topics, homepage), a LICENSE it always asks
  about first (OSS, or an explicit proprietary one for private/internal repos),
  GitHub Releases cut/backfilled from existing
  tags, and — with a small deploy-pipeline change — real GitHub Deployment
  records so the Deployments tab isn't empty. Use this WHENEVER the user wants to
  make a repo "look professional / more legit / เรียบร้อย", add shields/badges,
  fill in the About section or topics/tags, add a license, turn vX.Y.Z tags into
  Releases so the Releases sidebar shows up, make the Deployments tab reflect real
  deploys, or points at a nice reference repo and says "make mine look like that".
  Trigger on phrases like "ตกแต่ง repo", "แต่ง readme ให้สวย", "ใส่ badge",
  "set up the About section", "add topics", "add a license", "make a release",
  "wire deployments", "polish this repo", "ทำ repo ให้ดูดี" — works on private
  repos too — even if they don't name every element; infer the rest and fill gaps.
version: 1.0.0
---

# Uplift Repo Polish

Make a GitHub repo's first impression match the quality of the code inside it.
A repo that a stranger lands on is judged in seconds by its **README**, its
**About sidebar** (description + topics + link), whether it has a **license**,
and whether **Releases** (and **Deployments**) look alive. This skill fills those
surfaces — detecting what's already there and only touching what's missing or
weak, so you never clobber good existing content. It adapts to **private**
repos (static badges, no OSS license) as readily as public ones.

## Why detect-first matters

Repos arrive in every state — some already have a great README and just need
badges + a Release; some are bare. Blindly rewriting throws away work and
annoys maintainers. So **always read the current state before writing**, then
fill gaps. The `gh` CLI gives you everything in one call:

```bash
gh repo view <owner>/<repo> --json name,description,homepageUrl,repositoryTopics,licenseInfo,primaryLanguage,languages,latestRelease
git -C <repo> tag --sort=-v:refname | head   # existing vX.Y.Z tags
```

Read the existing `README.md` too. Decide per-surface: **keep / augment / add**.

## The surfaces

### 1. README — badges + structure

Add a **badge row** right under the H1 (badges are the fastest "this is
maintained" signal). Prefer shields.io badges that read live from the repo so
they stay correct without maintenance:

```markdown
[![License](https://img.shields.io/github/license/OWNER/REPO?color=blue)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/OWNER/REPO?label=release&sort=semver&color=success)](https://github.com/OWNER/REPO/releases)
[![Top language](https://img.shields.io/github/languages/top/OWNER/REPO)](https://github.com/OWNER/REPO)
[![Stars](https://img.shields.io/github/stars/OWNER/REPO?style=flat)](https://github.com/OWNER/REPO/stargazers)
```

Add 1–2 **domain badges** that say what the project *is* (a static
`img.shields.io/badge/LABEL-VALUE-COLOR` with the tool's logo — e.g. a language,
framework, "Claude Code plugin", "PRs welcome"). Don't overload it: ~4–6 badges,
one line. Use `github/v/tag` (not `github/v/release`) when a tag exists but no
GitHub Release does yet — the badge still resolves.

> **Private repos:** the dynamic `github/*` badges above read data shields.io
> can't fetch without auth, so on a private repo they render as `invalid`. Use
> **static** badges instead — `img.shields.io/badge/LABEL-VALUE-COLOR` for the
> stack (TypeScript, Bun, …), an "internal service" tag, and
> `versioning-SemVer%20vX.Y.Z` (prefer "uses SemVer" over a hardcoded number,
> which goes stale). Static badges render everywhere.

Then make the body **scannable** — a reader should grasp the project without
scrolling. A dependable spine (adapt, don't force every heading):

1. **Title + one-line tagline** — what it is, for whom, in a sentence.
2. **Quick start** — the copy-paste that gets someone from zero to running.
3. **Features / a table** — for multi-item repos (plugins, commands, packages) a
   table is far more scannable than prose.
4. **Repository layout** — a short annotated tree for anything non-obvious.
5. **Releases / Contributing / License** — short sections that signal a living project.

**Preserve good prose.** If the repo already explains itself well, keep that text
and wrap structure around it. You're polishing, not rewriting.

### 2. About sidebar — `gh repo edit`

The About box (description, topics, website) is separate from the README and set
via the API. Fill whatever's empty:

```bash
gh repo edit OWNER/REPO \
  --description "One crisp sentence: what it does + for whom." \
  --homepage "https://…"                          # if there's a site/docs
gh repo edit OWNER/REPO --add-topic topic-one,topic-two,topic-three
```

Topics: lowercase, hyphenated, **5–10** that a searcher would actually use
(language, framework, domain, "cli", "developer-tools"). This is real discovery
surface, not decoration — pick findable ones.

### 3. LICENSE — pick deliberately, never assume

A license is a **legal + business decision, not a cosmetic one** — so **ALWAYS
ask the user which license they want before adding one. Never default to MIT (or
anything) silently.** If `licenseInfo` is null there's no license and the repo is
legally "all rights reserved" with nothing stated; lay out the choice plainly and
let the user pick:

- **Open source** — permissive (**MIT**, **Apache 2.0**) if anyone may use it
  freely; copyleft (**GPL**) if forks must stay open. Add the SPDX `LICENSE` file
  (correct year + copyright holder) — GitHub auto-detects it, shows the sidebar
  badge, and the `github/license` README badge resolves.
- **Proprietary / private / internal** (a company service — auth, backend, …) —
  it is **not** open source, and MIT would wrongly license your code as
  free-to-use. Don't just leave it blank — make the terms **explicit**: add a
  proprietary `LICENSE` and set `package.json` `"license": "UNLICENSED"` (with
  `"private": true`). GitHub won't render an SPDX badge for a custom license —
  that's expected; the file stating the terms is the point.

Proprietary `LICENSE` template (swap `<YEAR>` + `<Company>`):

```
Copyright (c) <YEAR> <Company>. All rights reserved.

PROPRIETARY AND CONFIDENTIAL

This software and its source code are the proprietary and confidential property
of <Company>, licensed for internal use by <Company> and its authorized
personnel only. No part may be copied, modified, distributed, sublicensed, sold,
or made available to any third party without the prior written permission of
<Company>. Unauthorized use, reproduction, or distribution is strictly prohibited.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

> When you can't tell whether a repo is meant to be open or closed, **ask** — a
> public marketing/tooling repo usually wants an OSS license; an internal service
> almost always wants proprietary. Guessing wrong here is a legal mistake, not a
> style one.

### 4. Releases — publish a Release from a tag

A repo with tags but no **GitHub Releases** shows an empty Releases sidebar. If a
`vX.Y.Z` tag exists, turn it into a Release with real notes:

```bash
gh release create vX.Y.Z --repo OWNER/REPO --title "vX.Y.Z" --notes "…"
```

Write notes that summarize what's in the release (features / components / how to
install) — not just "initial release". If there's no tag yet, don't invent one;
suggest the repo's release process (or a first `v1.0.0`) and let the user drive.

**Backfilling a tag history.** A repo whose deploy pipeline pushes `vX.Y.Z` tags
but never publishes Releases has a long tag list and an empty Releases tab. You
can fill it in one pass — loop the tags oldest→newest, letting GitHub generate
the changelog from the commits/PRs since the previous tag:

```bash
for tag in $(git tag -l 'v*' --sort=v:refname); do
  gh release create "$tag" --repo OWNER/REPO --title "$tag" --generate-notes --latest=false
done   # then re-run the newest with --latest
```

> **Publishing a Release is an outward-facing "create surface" action** — even on
> a private repo (there it's visible to members, not the public, but it's still a
> new surface + notifications). **Always confirm with the user before
> `gh release create`** — state the tag(s) and show the notes — and wait for an
> explicit go-ahead. Same for changing a public repo's description/topics the
> user hasn't clearly asked for.

### 5. Deployments — reflect real deploys (needs pipeline wiring)

The **Deployments** tab is populated by the GitHub Deployments API — a deploy has
to *write* a record. Platforms with a native git integration (Vercel, Netlify)
do it automatically; a **script / ECS / EC2 deploy does not**, so the tab stays
empty even though the service ships constantly. Unlike the other surfaces this
isn't a one-off edit — it's a small change to the deploy pipeline:

- A shared helper (e.g. `scripts/gh-deployment.sh`) that `POST`s a deployment
  (`ref`, `environment: production`, `required_contexts: []`, `auto_merge: false`,
  `production_environment: true`) then a `success` status carrying an
  `environment_url`, via `gh api`. Make it **best-effort — always exit 0** so a
  tracking hiccup can never fail a deploy.
- Call it from **every** deploy path so the tab is complete: a local
  `scripts/deploy.sh` (Fast Deploy) after a successful rollout, AND the CI
  workflow after its deploy step (add `permissions: deployments: write`; pass
  values through `env:`, never inline `${{ }}` into `run:` — injection-safe).
- **Backfill** the current version once (run the helper for the live tag) so the
  tab isn't empty until the next deploy.

Because it touches the deploy pipeline, land it through the repo's normal
branch/deploy flow; it only shows new entries on the next real deploy.

## Working order

Do the safe, reversible edits first and the public one last:

1. **Detect** state (the `gh repo view` + tag read above). Report what's present
   vs missing so the user sees the plan.
2. **README** — commit the badge row + structure on a branch or straight to the
   default branch per the repo's convention (a README change is low-risk; match
   how the team works).
3. **About** — `gh repo edit` description/homepage/topics (fill gaps only).
4. **LICENSE** — if missing, **ask which license** (never assume MIT). Open → an
   SPDX file (MIT/Apache/GPL); proprietary/private → an explicit proprietary
   LICENSE + `package.json "license": "UNLICENSED"`.
5. **Release** — **confirm, then** `gh release create` from the existing tag(s)
   (backfill the whole tag history if the Releases tab is empty).
6. **Deployments** *(optional — only if the user wants the Deployments tab
   populated)* — wire the deploy pipeline (helper + deploy.sh + CI) and backfill
   the current version. This is a pipeline change, so land it through the repo's
   normal branch/deploy flow, not a one-off edit.

Finish by reporting each surface's before→after so the user can see the repo now
matches the reference they had in mind.

## Not for

- Writing the project's actual technical docs / API reference (that's content
  work, not presentation polish).
- Fixing code, CI failures, or the build.
- Inventing version numbers or cutting tags out of thin air — publish from tags
  that exist; defer tag creation to the repo's release process.
