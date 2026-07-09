# Frontend (Next.js in Docker) — inject + display

For Next.js apps deployed as a Docker image (admin-portal, saas, Mainwebsite).
The version is a **build-time** value (`NEXT_PUBLIC_*` is inlined into the client
bundle at build), so it flows in as a Docker **build-arg**, not a runtime env.

## 1. Dockerfile — accept the build-arg

In the builder stage, next to the other `NEXT_PUBLIC_*` args, BEFORE `bun run build`:

```dockerfile
ARG NEXT_PUBLIC_APP_VERSION
ENV NEXT_PUBLIC_APP_VERSION=${NEXT_PUBLIC_APP_VERSION}
```

## 2. `scripts/deploy.sh` — pass the build-arg

In the `docker build` invocation (next to the other `--build-arg NEXT_PUBLIC_*`):

```bash
    --build-arg NEXT_PUBLIC_APP_VERSION="${APP_VERSION}" \
```

`APP_VERSION` is set by `compute_version` (Step 1 of SKILL.md) before the build.

## 3. `next.config.ts` — prefer the build-arg, fall back to package.json

This makes local dev show a sensible number when the build-arg is absent:

```ts
import { readFileSync } from "node:fs";

// Source of truth is the injected git tag (NEXT_PUBLIC_APP_VERSION build-arg);
// fall back to package.json in local dev. Inlined at build so the UI matches
// exactly what shipped.
const PKG_VERSION = (
  JSON.parse(readFileSync("./package.json", "utf8")) as { version: string }
).version;
const APP_VERSION = process.env.NEXT_PUBLIC_APP_VERSION || PKG_VERSION;

const nextConfig: NextConfig = {
  output: "standalone",
  env: {
    NEXT_PUBLIC_APP_VERSION: APP_VERSION,
  },
  // ...rest of config
};
```

## 4. Display it in the UI

Read `process.env.NEXT_PUBLIC_APP_VERSION` in any client component (it's inlined,
so no prop-drilling). Guard it so nothing renders when unset. Put it somewhere
low-key — a sidebar/menu footer is ideal. Example (matches admin-portal, version
sits just above the "Get Help" row):

```tsx
{process.env.NEXT_PUBLIC_APP_VERSION && (
  <p className="px-2 pb-1.5 text-[10px] tracking-wide text-muted-foreground/70">
    v{process.env.NEXT_PUBLIC_APP_VERSION}
  </p>
)}
```

Placement note: render the version **before** the nav items you want it to sit
above (JSX order = visual order in a column), not after.

## Verify (frontend)

- `git ls-remote --tags origin | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail` → new tag present.
- The live task-def's `OTEL_SERVICE_VERSION` equals the new tag (proves
  `APP_VERSION` == build-arg == what the UI baked).
- Load the app (authenticated pages included) → the `vX.Y.Z` label shows.
  There's no `/version` API for a pure frontend; the UI label + the task-def
  OTEL value are the checks.
