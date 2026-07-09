# Commit-author gate (silent Vercel production block)

Some teams configure their Vercel project so a **production** deploy only
proceeds when the **HEAD commit's author email** is on an allow-list. When the
author isn't allowed, Vercel's build finishes almost instantly (~0 ms) and
**nothing ships** — the deploy looks "successful" but the site doesn't change.
This is the most confusing failure mode, because there's no red error; the old
version just stays live.

This is a team/project-specific policy — it only applies if you've set it up
(e.g. via an `ignoredBuildStep` / a "Deploy only if author is X" guard). If you
haven't, skip this note.

## How to diagnose

```bash
git log -1 --format='%an <%ae>'          # who authored HEAD?
```

If that email isn't your project's allowed author, the gate is why prod didn't
update.

## How to satisfy it

- **Set the repo's git identity** to the allowed author before committing the
  change that will ship:
  ```bash
  git config user.email "<allowed@email>"
  git config user.name  "<name>"
  ```
- **On PR merges**, use **"Rebase and merge"** (or a squash that preserves the
  allowed author). A standard merge commit is authored by whoever clicked merge
  and will fail the gate — so HEAD must end up authored by the allowed identity.
- If the author is already correct and prod still won't update, re-check that the
  merge to `main` actually left the allowed commit at HEAD (a later commit on top
  with a different author re-triggers the block).

## Why teams use it

It's a lightweight guard so only intended identities can publish production —
cheaper than full branch protection for small marketing/landing repos. The
tradeoff is the silent-no-op failure mode above, which is why this note exists.
