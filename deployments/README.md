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
| `ORIGIN_IP` | yes | OpenResty public IP (`123.16.178.142`) |
| `UPSTREAM_HOST` | yes | Dev server internal IP running mini-tunnel |
| `UPSTREAM_PORT` | yes | Port openchamber/OpenWebUI listens on |
| `OPENRESTY_HOST` | yes | SSH alias for the OpenResty box |
| `SSL_CERT` | yes | Cert name under `/etc/letsencrypt/live/` |
| `AUTH_MODE` | yes | `oauth2` or `none` |
| `ALLOW_CIDRS` | no | Optional space-separated CIDRs. Empty/omitted = no IP allowlist (rely on `AUTH_MODE`). Populated = `allow` each CIDR then `deny all`. |

\* `DEPLOY_STATUS=active` rejects `ALLOW_CIDRS=__FILL_ME__`. Empty allowlist with
`AUTH_MODE=none` is also rejected (would leave the host open).

Records are plain `KEY=VALUE` files sourced by bash. No YAML, no `jq` on the
OpenResty box path.

## Agent runbook

### Add a deployment

1. Copy `deployments/example.env` → `deployments/<name>.env`.
2. Fill required fields. Leave `__FILL_ME__` only for values the user must supply
   (`UPSTREAM_HOST`, `CF_TOKEN_REF`, optional `ALLOW_CIDRS`). Never invent CIDRs or IPs.
3. `ALLOW_CIDRS` is optional: omit/empty to rely on OAuth2 only; set real CIDRs for an IP gate.
   Prefer `DEPLOY_STATUS=pending` until `UPSTREAM_HOST` (and any desired allowlist) are real; then `active`.
4. Add a row + notes section in `REGISTRY.md`.
5. Render: `./bin/render.sh <name>` → writes `deployments/<name>.conf`.
6. DNS (dry-run first): `./bin/cf-dns.sh <name> --dry-run` then without `--dry-run`.
7. Apply: `./bin/expose.sh <name>` (render → scp → `nginx -t` → reload; rolls back on fail).

## Cloudflare token in 1Password

`CF_TOKEN_REF` is a secret reference, not the token itself. The token must be
stored locally in 1Password and resolved by `bin/cf-dns.sh` on the operator
workstation. Do not copy the token or 1Password credentials to the deployment
server.

For the `leanflag.net` DNS deployment, use the `DevOps` vault, item
`cloudflare-leanflag-net-dns`, and a concealed/password field named
`credential`:

```bash
CF_TOKEN_REF=op://DevOps/cloudflare-leanflag-net-dns/credential
```

If the item is in a different 1Password account, identify the account and test
the reference without printing its value:

```bash
op account list
op read --account my.1password.com \
  'op://DevOps/cloudflare-leanflag-net-dns/credential' \
  >/dev/null && echo "1Password reference works"
```

Run the DNS dry run and live upsert locally with the account selected:

```bash
OP_ACCOUNT=my.1password.com ./bin/cf-dns.sh <name> --dry-run
OP_ACCOUNT=my.1password.com ./bin/cf-dns.sh <name>
```

The CLI account selector is only needed when `DevOps` is not in the default
1Password account. Never run `op read` without redirecting output when testing
this token reference.

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
