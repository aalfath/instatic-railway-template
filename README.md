[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/instatic-2?utm_medium=integration&utm_source=button&utm_campaign=instatic)

# Instatic on Railway

One-click Railway template for [Instatic](https://github.com/CoreBunch/Instatic) **0.0.23**, an open-source, self-hosted visual CMS (an alternative to Webflow, Framer and WordPress) that publishes clean static pages.

This repo is the build source of the template's Instatic service. Its `Dockerfile` starts from the official image, pinned by version **and** digest:

```
ghcr.io/corebunch/instatic:0.0.23@sha256:ca64fbd5928c652fb2b5fa21104d2f7bb451c81495f9b5d692e30e75e1037953
```

## What the template deploys

| Service | Source | Data | What it does |
|---|---|---|---|
| **Instatic** | this repo (`Dockerfile`) | volume at `/app/storage` (uploads, fonts, plugins, runtime package cache) | the editor at `/admin` and the published site at `/`; health check `/health` |
| **Postgres** | Railway PostgreSQL | its own volume | pages, components, users, settings |

The wrapper (`start.sh`, `bootstrap.ts`) adds only what a one-click deploy needs:

- **Owner account on first boot.** Upstream's first-run setup page is public until an owner exists, so the first visitor to a fresh install would own it. Here the start script runs Instatic on `127.0.0.1` first, runs the database migrations, creates the owner from `ADMIN_EMAIL` / `ADMIN_PASSWORD`, and only then opens the public port. If that fails, the service stops with an error instead of opening an unclaimed site.
- **Volume permissions.** Railway mounts volumes as `root`; the script gives `/app/storage` to the image's `bun` user and runs the server as `bun` (no `RAILWAY_RUN_UID=0`).
- **Checks.** It refuses to start without a Postgres `DATABASE_URL` or a 32-byte `INSTATIC_SECRET_KEY`.
- **Small-plan sizing.** Image-processing threads follow the service's CPU limit, not the host's, and Railway's proxy ranges (`100.64.0.0/10`, `152.233.0.0/16`) are trusted, so login rate limits see real client IPs.
- A crash exits non-zero, so Railway's on-failure restart policy brings it back.

It runs on Railway's Free plan: Instatic used about 120 MB idle and under 200 MB while uploading and publishing, with a 0.5 GB / 1 vCPU limit.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_EMAIL` | *(you enter it)* | email of the owner account created on first boot |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | generated; read it in the service's Variables tab. Change it later in the editor (Account) |
| `INSTATIC_SECRET_KEY` | generated base64 32-byte key | encrypts stored AI-provider keys and MFA secrets. Never change it after the first deploy |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | private network |
| `PUBLIC_ORIGIN` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | add a custom domain as a second comma-separated entry |
| `PORT` | `8080` | |

`ADMIN_EMAIL` and `ADMIN_PASSWORD` are only used while no owner exists; changing them later does nothing.

## Updates

Railway tells everyone who deployed this template when `main` of this repo changes ("update available" in the project). Each change bumps the pinned tag and digest together and gets an entry in [CHANGELOG.md](CHANGELOG.md), with breaking changes first. Read it, then apply the update from your project. Instatic runs its own database migrations on start. Back up the Postgres service and the `/app/storage` volume before applying an update.

## Local test

```sh
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=$(openssl rand -hex 16) \
INSTATIC_SECRET_KEY=$(openssl rand -base64 32) docker compose -f compose.test.yml up --build
```

Instatic is MIT-licensed by CoreBunch. This repo only packages it for Railway.
