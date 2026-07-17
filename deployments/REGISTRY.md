# Deployment registry

Index of mini-tunnel deployments fronted by OpenResty on `local-sbase-dev-openresty`.
Each row has a matching `deployments/<name>.env` record. Free-form notes live below.

## Index

| Name | Hostname | Status | Upstream | Auth | Notes |
|------|----------|--------|----------|------|-------|
| example | quinmini.leanflag.net | pending | 10.29.0.99 (docs only) | oauth2 | Reference record + source of nginx/examples/quinmini.leanflag.net.conf; do not apply |
| quinmini | quinmini.leanflag.net | pending | `__FILL_ME__` | oauth2 | Blocked on ALLOW_CIDRS, UPSTREAM_HOST, CF_TOKEN_REF |

## Notes

### example

Reference schema for agents and humans. Not a live deployment. Copy to a new
`<name>.env` and fill real values before `bin/render.sh` / `bin/expose.sh`.

### quinmini

Existing mini-tunnel deployment migrating from Cloudflare Tunnel to OpenResty
origin routing. Ships as `DEPLOY_STATUS=pending` until the user fills:

1. `ALLOW_CIDRS` — office range? VPN pool? both? **Unknown.**
2. `UPSTREAM_HOST` — internal IP of the dev server running mini-tunnel. **Unknown.**
3. `CF_TOKEN_REF` — 1Password vault/item path for the Cloudflare API token. **Unknown.**

Do not invent values for those fields. `validate_deployment` will reject
`DEPLOY_STATUS=active` while `ALLOW_CIDRS` is empty or `__FILL_ME__`.

OpenResty origin: `195.85.88.187` (SSH alias `local-sbase-dev-openresty`,
internal `10.29.0.50`). Wildcard cert `*.leanflag.net` already covers the hostname.
