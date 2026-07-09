---
name: uplift-repo-polish
description: >-
  Polish a GitHub repository's public presentation so it reads like a
  well-maintained OSS project — README badges + scannable structure, the About
  sidebar (description, topics, homepage), a detected LICENSE, and a published
  GitHub Release cut from an existing tag. Use this WHENEVER the user wants to
  make a repo "look professional / more legit", add shields/badges, fill in the
  About section or topics/tags, add a license, turn a vX.Y.Z tag into a real
  Release so the Releases sidebar shows up, or points at a nice reference repo
  and says "make mine look like that". Trigger on phrases like "ตกแต่ง repo",
  "แต่ง readme ให้สวย", "ใส่ badge", "set up the About section", "add topics",
  "add a license", "make a release", "polish this repo", "ทำ repo ให้ดูดี",
  even if they don't name every element — infer the missing ones and fill gaps.
version: 1.0.0
---

# Uplift Repo Polish

Make a GitHub repo's first impression match the quality of the code inside it.
A repo that a stranger lands on is judged in seconds by its **README**, its
**About sidebar** (description + topics + link), whether it has a **license**,
and whether **Releases** look alive. This skill fills those four surfaces —
detecting what's already there and only touching what's missing or weak, so you
never clobber good existing content.

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

## The four surfaces

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

### 3. LICENSE — so GitHub detects it

If `licenseInfo` is null, there's no license and GitHub shows nothing in the
sidebar (and the repo is legally "all rights reserved"). Confirm the license
choice with the user (**MIT** is the common default for tooling), then add a
real `LICENSE` file with the correct year + copyright holder — GitHub
auto-detects the SPDX id and renders the sidebar badge. The `github/license`
README badge then resolves too.

### 4. Releases — publish a Release from a tag

A repo with tags but no **GitHub Releases** shows an empty Releases sidebar. If a
`vX.Y.Z` tag exists, turn it into a Release with real notes:

```bash
gh release create vX.Y.Z --repo OWNER/REPO --title "vX.Y.Z" --notes "…"
```

Write notes that summarize what's in the release (features / components / how to
install) — not just "initial release". If there's no tag yet, don't invent one;
suggest the repo's release process (or a first `v1.0.0`) and let the user drive.

> **Publishing a Release is a public, outward-facing action** (it creates a
> surface others will see and get notified about). **Always confirm with the
> user before running `gh release create`** — state the tag and show the notes
> you'd publish, and wait for an explicit go-ahead. The same applies to changing
> a public repo's description/topics if the user hasn't clearly asked for it.

## Working order

Do the safe, reversible edits first and the public one last:

1. **Detect** state (the `gh repo view` + tag read above). Report what's present
   vs missing so the user sees the plan.
2. **README** — commit the badge row + structure on a branch or straight to the
   default branch per the repo's convention (a README change is low-risk; match
   how the team works).
3. **About** — `gh repo edit` description/homepage/topics (fill gaps only).
4. **LICENSE** — add if missing (confirm the license).
5. **Release** — **confirm, then** `gh release create` from the existing tag.

Finish by reporting each surface's before→after so the user can see the repo now
matches the reference they had in mind.

## Not for

- Writing the project's actual technical docs / API reference (that's content
  work, not presentation polish).
- Fixing code, CI failures, or the build.
- Inventing version numbers or cutting tags out of thin air — publish from tags
  that exist; defer tag creation to the repo's release process.
