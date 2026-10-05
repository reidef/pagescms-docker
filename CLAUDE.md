# CLAUDE.md

This repo packages upstream [Pages CMS](https://github.com/pagescms/pagescms) (a Next.js app) as a container image. It contains no application code, only build and runtime glue. The image is meant for Kubernetes, but the docs here and in README.md stay generic. Don't add cluster- or deployment-specific details unless they help any user of the image.

## Layout

- `Dockerfile`: multi-stage build (source → deps → build → runtime).
- `docker/next.config.mjs`: wraps upstream's `next.config.mjs` to add `output: "standalone"`.
- `docker/migrate.mjs`: applies upstream's Drizzle migrations at runtime, under an advisory lock.
- `docker/entrypoint.sh`: dispatches `serve` (default) / `migrate` / any other command.
- `compose.yaml` + `.env.example`: local run with PostgreSQL. `.env` is gitignored.
- `Makefile`: `build`, `buildx`, `run`, `down`, `version`, `upstream-versions`.
- `.github/workflows/build.yml`: CI that builds amd64 + arm64 and pushes to GHCR.

## CI / publishing

- The workflow runs on pushes to `main` that touch build inputs (`Dockerfile`, `.dockerignore`, `docker/**`, the workflow itself), on PRs touching the same paths (build only, no push), and manually via `workflow_dispatch`.
- It publishes `ghcr.io/<repo owner, lowercased>/pagescms:<PAGESCMS_VERSION>`. The version comes from the Dockerfile `ARG` and must be `X.Y.Z`. Only the version tag is pushed. There's no `latest`, so consumers pin explicit versions.
- A rebuild without a version bump (e.g. a packaging fix) **overwrites the existing tag**. That's intentional: the tag means "this upstream release", not one specific build.
- Auth uses the built-in `GITHUB_TOKEN` (`packages: write`). No secrets need configuring. If the package already exists and wasn't created by this repo's workflow, grant this repo write access in the package settings.
- arm64 builds under QEMU on an `ubuntu-latest` runner. That's slower than native but needs no special runners. A local amd64 build under emulation takes about 1 minute. The `type=gha` build cache speeds up reruns.
- Docs-only changes (README, CLAUDE.md, compose, Makefile) don't trigger a build. Use `workflow_dispatch` to force one.

## Versioning

- `ARG PAGESCMS_VERSION` in the Dockerfile is the **single source of truth**. The Makefile reads it from there.
- Image tag = upstream git tag, exactly (e.g. `2.1.8`). Upstream tags have no `v` prefix.
- Upstream's GitHub repo is `pagescms/pagescms`. It redirects to `hunvreus/pagescms`, so REST API calls need `curl -L`. `git ls-remote` (`make upstream-versions`) is the simplest way to list releases.

## Bumping to a new upstream release

1. `make upstream-versions` to find the new tag.
2. Read the upstream diff for packaging-relevant changes: `git diff <old>..<new> -- package.json next.config.* db/ drizzle.config.ts .env.local.example lib/base-url.ts`. Look in particular for:
   - new or renamed env vars (update `.env.example` and README),
   - a change to `next.config` (the wrapper expects `next.config.mjs`; a rename to `.ts`/`.js` breaks the build on purpose),
   - Node engine requirements (`NODE_VERSION` arg),
   - migrations moving out of `db/migrations` or drizzle-orm gaining runtime deps (the runtime stage copies `drizzle-orm` and `postgres` whole).
3. Update `ARG PAGESCMS_VERSION`, then run `make build`.
4. Verify (see below), then commit with a message like `Bump Pages CMS to X.Y.Z`. Pushing to `main` publishes the new tag to GHCR.

## Verifying a build

"Done" means the image builds and runs. Minimum check:

```bash
make build
cp .env.example .env   # fill BETTER_AUTH_SECRET/CRYPTO_KEY with `openssl rand -base64 32`; dummy GitHub values are fine
docker compose up -d
curl -s localhost:3000/api/auth/ok          # {"ok":true}
curl -s -o /dev/null -w '%{http_code}' localhost:3000/sign-in   # 200
docker compose logs pagescms                # "[migrate] done", then "Ready"
docker compose down -v
```

Real sign-in needs a real GitHub App, which isn't required for a packaging check.

## Decisions and reasons

- **Source fetched with `ADD <git-url>#<tag>`** (BuildKit). No vendoring, no submodule. Requires the `# syntax=docker/dockerfile:1.7` line.
- **`npx next build`, not `npm run build`.** Upstream's `postbuild` hook runs `drizzle-kit migrate`, which needs a live DB at build time.
- **`BASE_URL=http://build.invalid` during the build only.** `app/layout.tsx` calls `getBaseUrl()` at module load, and it throws in production when the variable is unset. Server code reads the real runtime value. Only the prerendered 404 page keeps the placeholder in its metadata (documented in README).
- **Standalone output** keeps the image small (~260 MB, mostly the Node base) and avoids shipping dev dependencies.
- **Migrations via drizzle-orm's runtime migrator, not drizzle-kit.** drizzle-kit is a dev dependency. Both read the same `db/migrations/meta/_journal.json` and the same `drizzle.__drizzle_migrations` table, so they're interchangeable with upstream's `npm run db:migrate`.
- **Advisory lock (`pg_advisory_lock`, fixed id) around migrations**, using a single connection, so `MIGRATE_ON_START=true` is safe with many replicas. A separate `migrate` command exists for running migrations as their own step.
- **`HOSTNAME` is forced to `0.0.0.0` (override with `BIND_HOST`).** The Next standalone server binds to `$HOSTNAME`, and Kubernetes sets that to the pod name.
- **Numeric `USER 1000:1000`** (the `node` user), so `runAsNonRoot` can verify it. `/app/.next/cache` is pre-created and owned by the app user. It's the only path that must be writable.
- **`tini` as PID 1** for signal forwarding and zombie reaping. The entrypoint `exec`s node.
- **No Docker `HEALTHCHECK`.** Orchestrators define probes. `/api/auth/ok` (from better-auth) is the recommended probe because it touches neither the DB nor GitHub.
- **`.dockerignore` is an allowlist** (`*` then `!docker/`). The build context only needs `docker/`.
- **Upstream `tsx` scripts are not shipped** (clear-cache, collaborator import/export). They'd need dev deps plus source. Run them from an upstream checkout if needed.

## Possible follow-ups (not done)

- A scheduled workflow that opens a bump PR when a new upstream tag appears.
- Native arm64 runners (matrix build + manifest merge) if QEMU build times become a problem.
- Pinning base images by digest.
