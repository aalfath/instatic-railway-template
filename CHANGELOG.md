# Changelog

## 0.0.23 (2026-11-24)

First release of the Railway template.

- Instatic 0.0.23, `ghcr.io/corebunch/instatic:0.0.23@sha256:ca64fbd5928c652fb2b5fa21104d2f7bb451c81495f9b5d692e30e75e1037953`.
- Railway PostgreSQL, Instatic data on a volume at `/app/storage`.
- The owner account is created on first boot from `ADMIN_EMAIL` / a generated `ADMIN_PASSWORD` before the public port opens.
