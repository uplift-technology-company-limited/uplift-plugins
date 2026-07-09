# Backend (Bun/Elysia) — inject + expose

For runtime services (sso, account, payment, media, message, subscription). The
version is read at **runtime** from `process.env.APP_VERSION` (injected into the
ECS task-def), so there's no build-arg and no rebuild needed to change it.
Requires `resolveJsonModule: true` in tsconfig to import package.json (Uplift
services already have it).

## 1. `src/lib/version.ts` — single accessor

```ts
import pkg from '../../package.json';

/**
 * The running version. Source of truth is the git tag (vX.Y.Z), injected into
 * the ECS task-def as APP_VERSION by the deploy pipeline; package.json is the
 * local-dev fallback.
 */
export function getVersion(): string {
  return process.env.APP_VERSION || pkg.version || 'dev';
}
```

Adjust the `../../package.json` depth to the file's location.

## 2. `src/interfaces/routes/version.ts` — the public endpoint

```ts
import { Elysia } from 'elysia';
import { getVersion } from '../../lib/version';

/** GET /version -> { service, version }. Public — lets ops/monitoring/other
 * services check the live version without shelling into the container. */
export const versionRoutes = new Elysia().get('/version', () => ({
  service: '<service-name>',
  version: getVersion(),
}));
```

A prefixed route group can't escape its prefix, so use a **separate** Elysia
instance (no prefix) for a clean root `/version`.

## 3. Mount it + add version to `/health`

In `src/app.ts` (or wherever routes are `.use()`d), mount next to health:

```ts
import { versionRoutes } from './interfaces/routes/version';
// ...
  .use(healthRoutes)
  .use(versionRoutes)
```

And include the version in the health payload so a single `/health` call shows
both liveness and version:

```ts
import { getVersion } from '../../lib/version';

  .get('/', () => ({
    status: 'healthy',
    service: '<service-name>',
    version: getVersion(),
    timestamp: new Date().toISOString(),
  }))
```

## 4. Inject `APP_VERSION` into the task-def

- **deploy.sh path** (inline task-def): already covered by Step 1 in SKILL.md —
  the `environment` array gains `APP_VERSION` + `OTEL_SERVICE_VERSION` = `${APP_VERSION}`.
- **explicit-steps GHA path** (describe → jq → register): the jq must *upsert*
  those two env vars into the live task-def's environment. See
  [gha.md](gha.md#explicit-steps-workflow-sso-style).

## Verify (backend)

```bash
curl -s https://<service-host>/version    # -> {"service":"...","version":"X.Y.Z"}
curl -s https://<service-host>/health      # version field present
```

Plus the task-def `OTEL_SERVICE_VERSION` == the new tag. Because the backend
reads `APP_VERSION` at runtime, a task-def env change alone updates `/version`
on the next task — no image rebuild required.
