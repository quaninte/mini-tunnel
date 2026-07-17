# Deployment registry

Index of mini-tunnel deployments fronted by OpenResty on `local-sbase-dev-openresty`.
Each row has a matching `deployments/<name>.env` record. Free-form notes live below.

## Index

| Name | Hostname | Status | Upstream | Auth | Notes |
|------|----------|--------|----------|------|-------|
| example | quinmini.leanflag.net | pending | 10.29.0.99 (docs only) | oauth2 | Reference record + source of nginx/examples/quinmini.leanflag.net.conf; do not apply |
| product-app-chat | product-app-chat.leanflag.net | active | 10.29.0.69:3101 | oauth2 | lo runtime; OpenWebUI off; opencode :4197 loopback; no ALLOW_CIDRS |
| quinmini | quinmini.leanflag.net | pending | `__FILL_ME__` | oauth2 | Blocked on UPSTREAM_HOST, CF_TOKEN_REF (ALLOW_CIDRS optional) |

## Notes

### product-app-chat

Runtime host: SSH alias `lo` (`10.29.0.69`), checkout at `~/product-app/mini-tunnel`
(GitLab origin + read-only deploy key `product-app-chat@lo`).

Ports: OpenChamber `3101` (bind `10.29.0.69`), opencode `4197` (loopback only).
`ENABLE_OPENWEBUI=false`, `ENABLE_CF_TUNNEL=false`, `ENABLE_CODE_STACK=true`.
`ALLOW_CIDRS` omitted — public path is OAuth2-only (do not pair with `AUTH_MODE=none`).
`PASS_KEY` lives only in remote `.env` (never in Git).
CF token: `op://DevOps/cloudflare-leanflag-net-dns/credential` (local `op` only).

OpenResty origin: `195.85.88.187` (SSH `local-sbase-dev-openresty`, internal `10.29.0.50`).
Wildcard cert `*.leanflag.net` covers the hostname.

**Rollout (2026-07-17):** vhost applied via `bin/expose.sh` (`nginx -t` ok). Upstream
`10.29.0.69:3101/health` → 200 from OpenResty. Cloudflare DNS upserted locally with
`OP_ACCOUNT=my.1password.com`: A record proxied to `195.85.88.187`. Public HTTPS and
direct origin HTTPS both return 302 to SSO oauth2 sign-in. DNS resolves via Cloudflare.

### example

Reference schema for agents and humans. Not a live deployment. Copy to a new
`<name>.env` and fill real values before `bin/render.sh` / `bin/expose.sh`.

### quinmini

Existing mini-tunnel deployment migrating from Cloudflare Tunnel to OpenResty
origin routing. Ships as `DEPLOY_STATUS=pending` until the user fills:

1. `UPSTREAM_HOST` — internal IP of the dev server running mini-tunnel. **Unknown.**
2. `CF_TOKEN_REF` — 1Password vault/item path for the Cloudflare API token. **Unknown.**
3. `ALLOW_CIDRS` — optional; omit for OAuth2-only, or set office/VPN CIDRs for an IP gate.

Do not invent values for those fields. `validate_deployment` rejects
`DEPLOY_STATUS=active` with `ALLOW_CIDRS=__FILL_ME__` or empty allowlist + `AUTH_MODE=none`.

OpenResty origin: `195.85.88.187` (SSH alias `local-sbase-dev-openresty`,
internal `10.29.0.50`). Wildcard cert `*.leanflag.net` already covers the hostname.
