# Pages CMS container image

A container image for [Pages CMS](https://pagescms.org) ([source](https://github.com/pagescms/pagescms)), built from the upstream release tags.

Image tags match upstream release numbers: `pagescms:2.1.8` contains Pages CMS `2.1.8`.

Prebuilt multi-arch images (`linux/amd64`, `linux/arm64`) are published to the GitHub Container Registry:

```bash
docker pull ghcr.io/<owner>/pagescms:2.1.8
```

`<owner>` is the GitHub user or organization that hosts this repository.

## Quick start

```bash
cp .env.example .env     # fill in secrets and GitHub App values
make run                 # builds the image, starts it with PostgreSQL on :3000
```

Or build the image on its own:

```bash
make build               # -> pagescms:<version>
```

## Dependencies

| Service | Required | Notes |
|---|---|---|
| **PostgreSQL** | Yes | Upstream develops against PostgreSQL 16. Set the connection string in `DATABASE_URL`. Pages CMS stores sessions, collaborators and a cache of repository content here. Each container opens up to `POSTGRES_MAX_CONNECTIONS` connections (default 5). |
| **GitHub App** | Yes | Pages CMS reads and writes content through a GitHub App you create. See [Create the GitHub App](https://pagescms.org/docs/guides/installing/github-app/). Set its callback and webhook URLs to `BASE_URL`. GitHub must be able to reach `${BASE_URL}/api/webhook/github` for webhooks. |
| **Email provider** | Optional | Used for collaborator invites and email sign-in. Use [Resend](https://resend.com) (`RESEND_API_KEY`) or any SMTP server (`SMTP_*`). |
| **Outbound HTTPS** | Yes | To `api.github.com` and `github.com`, plus `raw.githubusercontent.com` for the in-app "new version available" check. |

No other services (Redis, object storage, etc.) are needed. Media is stored in the GitHub repositories themselves.

## Configuration

Configure everything through environment variables. [.env.example](.env.example) lists them, and the upstream [environment variable reference](https://pagescms.org/docs/development/environment-variables/) explains each one.

Required: `BASE_URL`, `DATABASE_URL`, `BETTER_AUTH_SECRET`, `CRYPTO_KEY`, `GITHUB_APP_ID`, `GITHUB_APP_NAME`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_CLIENT_ID`, `GITHUB_APP_CLIENT_SECRET`, `GITHUB_APP_WEBHOOK_SECRET`.

`CRYPTO_KEY` encrypts stored GitHub tokens. If you change it, existing encrypted data becomes unreadable.

Variables that only apply to this image:

| Variable | Default | Purpose |
|---|---|---|
| `MIGRATE_ON_START` | `true` | Apply database migrations before the server starts. |
| `PORT` | `3000` | HTTP listen port. |
| `BIND_HOST` | `0.0.0.0` | Listen address. |

## Running in production

- **Process and user.** The image runs as UID/GID `1000` (non-root) with `tini` as PID 1. It shuts down cleanly on `SIGTERM`.
- **Stateless.** All state lives in PostgreSQL and GitHub, so you can run multiple replicas behind a load balancer. Size your Postgres `max_connections` for `replicas × POSTGRES_MAX_CONNECTIONS`.
- **Migrations.** By default every container applies pending migrations on start. A Postgres advisory lock serializes concurrent runs, so this is safe with several replicas. To run migrations as a separate step instead, set `MIGRATE_ON_START=false` and run the image with the `migrate` command (`docker run ... pagescms:<version> migrate`) before you roll out a new version.
- **Health checks.** `GET /api/auth/ok` returns `200 {"ok":true}` once the server is up. It doesn't touch the database or GitHub, so it works for liveness and readiness probes. The image has no Docker `HEALTHCHECK`; configure checks in your orchestrator.
- **Read-only root filesystem.** Supported. The only path that needs to be writable is `/app/.next/cache`, so mount a writable volume (e.g. tmpfs) there.
- **TLS and proxy.** The app serves plain HTTP. Terminate TLS in front of it. `BASE_URL` must be the single public URL users and GitHub use. Non-GET `/api/*` requests are rejected unless the `Origin` header matches the `Host` header, so the proxy must preserve `Host`.
- **Secrets.** `GITHUB_APP_PRIVATE_KEY` is a multi-line PEM. Inject it from a secret store as an environment variable.

## Commands

The image entrypoint accepts:

| Command | Action |
|---|---|
| `serve` (default) | Run migrations (unless `MIGRATE_ON_START=false`), then start the server. |
| `migrate` | Apply database migrations and exit. |
| anything else | Executed as-is (e.g. `sh`). |

## Known limitations

- The static 404 page's metadata (canonical/OpenGraph URLs) uses a build-time placeholder (`http://build.invalid`) instead of `BASE_URL`. All other pages render at request time and use the runtime `BASE_URL`.
- Upstream maintenance scripts that need `tsx` (`npm run db:clear-cache`, collaborator import/export) aren't included in the image. Run them from an upstream checkout pointed at the same `DATABASE_URL`.

## License

Pages CMS is MIT licensed by its authors. This repository only contains packaging.
