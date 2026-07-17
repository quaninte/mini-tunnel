# mini-tunnel

A lightweight Bash orchestration tool that runs [opencode](https://opencode.ai) and/or [OpenWebUI](https://github.com/open-webui/open-webui) on a dev server, fronted by **OpenResty origin routing** (oauth2-proxy + IP allowlist) with Cloudflare DNS pointing at the OpenResty box.

The legacy **Cloudflare Tunnel** path is still in the repo but **deprecated and default-off** (`ENABLE_CF_TUNNEL=false`).

mini-tunnel manages two independent **stacks** that can be enabled separately or together:

- **Code stack** — opencode + openchamber, run as native background processes.
- **OpenWebUI** — runs as a single Docker container via `docker compose`.

## Architecture

```
Internet
    │
    ▼
Cloudflare (proxied DNS)  ──▶  123.16.178.142  (dev-openresty / OpenResty :443)
                                    │
                                    ├─ set_real_ip_from (CF ranges, server-scoped)
                                    ├─ optional allow ALLOW_CIDRS; deny all;
                                    ├─ oauth2-proxy auth_request (optional)
                                    └─ proxy_pass ──▶ {dev-internal-ip}:{port}
                                                          │
                                                          ├── openchamber (:3000, BIND_ADDR)
                                                          │       └── opencode (:4096, 127.0.0.1 only)
                                                          └── OpenWebUI (:8080, BIND_ADDR, optional)
```

Deployments are git-tracked under `deployments/<name>.env`. Render and apply with `bin/render.sh` / `bin/expose.sh`. See `deployments/README.md` for the agent runbook.

## LAN exposure — accepted risk

When `BIND_ADDR` is a non-loopback address, anything on the LAN (e.g. `10.29.0.0/16`) can reach openchamber/OpenWebUI **directly**, bypassing both the OpenResty allowlist and oauth2-proxy. Only `PASS_KEY` (openchamber) or OpenWebUI's own login stands in the way. The OpenResty allowlist protects the **public** path only.

This is an **accepted risk** (no firewall automation in this repo). Revisit if a deployment carries sensitive data. `opencode` always stays on `127.0.0.1` and is never LAN-bound.

## Prerequisites

- `bash`
- For the **code stack** (`ENABLE_CODE_STACK=true`, the default): [opencode](https://opencode.ai) CLI and [openchamber](https://github.com/nicholasgriffintn/openchamber) CLI
- For **OpenWebUI** (`ENABLE_OPENWEBUI=true`): Docker with the `compose` plugin
- For apply/DNS scripts: SSH access to `local-sbase-dev-openresty`, and (for `bin/cf-dns.sh`) [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) + a Cloudflare API token in 1Password

## Setup

1. Clone and configure:

```bash
git clone https://github.com/your-username/mini-tunnel.git
cd mini-tunnel
cp .env.example .env
# Set PASS_KEY; set BIND_ADDR to the dev server's internal IP when using OpenResty
```

2. Fill a deployment record (see `deployments/example.env` / `deployments/quinmini.env`):

```bash
# Edit deployments/<name>.env — never invent ALLOW_CIDRS / UPSTREAM_HOST / CF_TOKEN_REF
./bin/render.sh <name>
OP_ACCOUNT=my.1password.com ./bin/cf-dns.sh <name> --dry-run   # then without --dry-run when ready
./bin/expose.sh <name>             # scp + nginx -t + reload (only when user approves)
```

3. Start stacks on the dev server:

```bash
./start.sh
```

### `.env` variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PASS_KEY` | Yes (code stack) | — | Password for the openchamber UI |
| `BIND_ADDR` | No | `127.0.0.1` | Bind for openchamber/OpenWebUI; opencode always `127.0.0.1` |
| `ENABLE_CF_TUNNEL` | No | `false` | **Deprecated.** If true, start cloudflared (legacy) |
| `OPENCODE_PORT` | No | `4096` | Local port for the opencode server |
| `OPENCHAMBER_PORT` | No | `3000` | Local port for the openchamber server |
| `OPENCODE_PROFILE_DIR` | No | `<checkout>/.opencode-profile` | Private profile root for OpenCode/OpenChamber config, credentials, sessions, state, and cache |
| `ENABLE_CODE_STACK` | No | `true` | Run opencode + openchamber |
| `ENABLE_OPENWEBUI` | No | `false` | Run OpenWebUI via Docker Compose |
| `OPENWEBUI_PORT` | No | `8080` | Local port for OpenWebUI |
| `OPENWEBUI_TAG` | No | `main` | Docker image tag |
| `OPENWEBUI_HOSTNAME` | No | — | Hostname for OpenWebUI (docs / legacy tunnel) |
| `OPENWEBUI_SECRET_KEY` | No | — | OpenWebUI session signing key |
| `CF_HOSTNAME` | No | `quinmini.leanflag.net` | **Deprecated** tunnel hostname |
| `CF_TUNNEL_TOKEN` | No | — | **Deprecated** tunnel token |
| `OPENWEBUI_CF_TUNNEL_TOKEN` | No | — | **Deprecated** dedicated OpenWebUI tunnel token |

An existing `.env` without `BIND_ADDR` still binds `127.0.0.1`. An existing `.env` without `ENABLE_CF_TUNNEL` will **not** start cloudflared (default `false` — intentional breaking change for tunnel mode).

### Per-checkout OpenCode profiles

Each checkout keeps its OpenCode and OpenChamber state below
`.opencode-profile/` by default. This includes provider credentials, plugins,
chat sessions, preferences, logs, cache, and OpenChamber run metadata, so two
mini-tunnel clones under the same Unix user do not share chat sessions. The
directory is ignored by Git and is created on the first lifecycle command.

Profiles are intentionally fresh and require provider authentication again.
Set `OPENCODE_PROFILE_DIR` to a private persistent mount when a deployment
replaces its checkout; never point two deployments at the same profile root.

## Stacks

```bash
ENABLE_CODE_STACK=true
ENABLE_OPENWEBUI=false
```

Toggle independently. OpenResty vhosts point at `UPSTREAM_HOST:UPSTREAM_PORT` from the deployment record (usually openchamber's port).

## Cloudflare DNS and 1Password

Cloudflare DNS credentials are resolved locally through 1Password CLI. The
deployment server receives only the Git-tracked `CF_TOKEN_REF` pointer; it never
receives the token or 1Password credentials.

For a new Cloudflare account or zone:

1. Create a least-privilege Cloudflare API token in the account that owns the
   zone. Scope it to DNS editing for the required zone.
2. In the 1Password account, create or reuse the `DevOps` vault.
3. Create a concealed/password field named `credential` in the item
   `cloudflare-leanflag-net-dns` and paste the token there.
4. Store this reference, not the token, in `deployments/<name>.env`:

```bash
CF_TOKEN_REF=op://DevOps/cloudflare-leanflag-net-dns/credential
```

Verify the reference without printing the secret:

```bash
op account list
op read --account my.1password.com \
  'op://DevOps/cloudflare-leanflag-net-dns/credential' \
  >/dev/null && echo "1Password reference works"
```

Run DNS commands locally and select the 1Password account explicitly when
needed:

```bash
OP_ACCOUNT=my.1password.com ./bin/cf-dns.sh <name> --dry-run
OP_ACCOUNT=my.1password.com ./bin/cf-dns.sh <name>
```

Never put the plaintext token in Git, a runtime `.env`, the deployment server,
or shell command output.

## Usage

```bash
./start.sh          # start enabled stacks (tunnel only if ENABLE_CF_TUNNEL=true)
./status.sh         # service status + live route note
./stop.sh           # stop stacks (and tunnel if enabled)
./restart.sh        # stop, clean, start
./start.sh --force  # kill port occupants and start
```

### Deployment tooling

| Script | Purpose |
|--------|---------|
| `bin/render.sh <name>` | `.env` + template → `deployments/<name>.conf` |
| `bin/cf-ranges.sh` | Fetch CF IP ranges → `set_real_ip_from` lines |
| `bin/expose.sh <name>` | render → scp → `nginx -t` → reload (rollback on fail) |
| `bin/unexpose.sh <name>` | remove conf, test, reload, flip status |
| `bin/cf-dns.sh <name>` | upsert A record via CF API (`op read`); `--dry-run` |

## Deprecated: Cloudflare Tunnel

The cloudflared code paths remain for emergency rollback but are **off by default**.

- Set `ENABLE_CF_TUNNEL=true` and provide `CF_TUNNEL_TOKEN` only if you must use the tunnel.
- `start.sh` prints a deprecation warning when the tunnel is enabled.
- Prefer the OpenResty path: fill `deployments/<name>.env`, render, DNS, expose.

**Release note:** hosts that previously relied on an implicit tunnel must land DNS + OpenResty vhost **before** restarting with the new defaults, or they will lose public reachability.

## Logs

- `opencode.log`, `openchamber.log` (and `cloudflared.log` if tunnel enabled)
- OpenWebUI: `docker compose logs -f open-webui`

## License

MIT
