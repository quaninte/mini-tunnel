# Deployments registry

Git-tracked registry of mini-tunnel deployments fronted by OpenResty.

## Schema (`deployments/<name>.env`)

| Key | Required | Description |
|-----|----------|-------------|
| `DEPLOY_NAME` | yes | Short name; must match the filename stem |
| `DEPLOY_STATUS` | yes | `active` \| `pending` \| `decommissioned` |
| `HOSTNAME` | yes | Public hostname, e.g. `quinmini.leanflag.net` |
| `CF_ZONE` | yes | Cloudflare zone name |
| `CF_TOKEN_REF` | yes | `op://vault/item/field` for the CF API token |
| `CF_PROXIED` | yes | `true` / `false` (orange cloud) |
| `ORIGIN_IP` | yes | OpenResty public IP (`195.85.88.187`) |
| `UPSTREAM_HOST` | yes | Dev server internal IP running mini-tunnel |
| `UPSTREAM_PORT` | yes | Port openchamber/OpenWebUI listens on |
| `OPENRESTY_HOST` | yes | SSH alias for the OpenResty box |
| `SSL_CERT` | yes | Cert name under `/etc/letsencrypt/live/` |
| `AUTH_MODE` | yes | `oauth2` or `none` |
| `ALLOW_CIDRS` | yes* | Space-separated CIDRs; **required non-empty for `active`** |

\* `validate_deployment` fails closed: `DEPLOY_STATUS=active` with empty or
`__FILL_ME__` `ALLOW_CIDRS` is rejected.

Records are plain `KEY=VALUE` files sourced by bash. No YAML, no `jq` on the
OpenResty box path.

## Agent runbook

### Add a deployment

1. Copy `deployments/example.env` → `deployments/<name>.env`.
2. Fill every field. Leave `__FILL_ME__` only for values the user must supply
   (`ALLOW_CIDRS`, `UPSTREAM_HOST`, `CF_TOKEN_REF`). Never invent CIDRs or IPs.
3. Set `DEPLOY_STATUS=pending` until `ALLOW_CIDRS` is real; then `active`.
4. Add a row + notes section in `REGISTRY.md`.
5. Render: `./bin/render.sh <name>` → writes `deployments/<name>.conf`.
6. DNS (dry-run first): `./bin/cf-dns.sh <name> --dry-run` then without `--dry-run`.
7. Apply: `./bin/expose.sh <name>` (render → scp → `nginx -t` → reload; rolls back on fail).

### Change a deployment

1. Edit `deployments/<name>.env`.
2. Re-render: `./bin/render.sh <name>`.
3. Re-apply: `./bin/expose.sh <name>`.
4. If hostname/origin/proxied changed: `./bin/cf-dns.sh <name>`.
5. Update notes in `REGISTRY.md`.

### Remove a deployment

1. `./bin/unexpose.sh <name>` (removes conf, `nginx -t`, reload, flips status).
2. Optionally delete DNS via Cloudflare dashboard (no automated delete in `cf-dns.sh`).
3. Mark decommissioned notes in `REGISTRY.md`. Leave the `.env` for history or delete it.

## Hard constraints for agents

- Never invent `ALLOW_CIDRS`, `UPSTREAM_HOST`, `CF_TOKEN_REF`, vault paths, or account names.
- Never `ssh`/`scp`/`nginx -t`/`reload` the live OpenResty box except via the
  written apply scripts when the user explicitly asks to run them.
- Never call the Cloudflare API except via `bin/cf-dns.sh` when the user asks.
- `op` may not be installed; write the code path, do not require a live test.
