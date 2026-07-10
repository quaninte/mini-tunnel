# mini-tunnel

A lightweight Bash orchestration tool that runs [opencode](https://opencode.ai) and/or [OpenWebUI](https://github.com/open-webui/open-webui) behind a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), making them publicly accessible and password-protected.

mini-tunnel manages two independent **stacks** that can be enabled separately or together:

- **Code stack** — opencode + openchamber, run as native background processes (the original mini-tunnel behavior).
- **OpenWebUI** — runs as a single Docker container via `docker compose`.

## Architecture

```
Internet
    │
    ▼
Cloudflare Tunnel  (cloudflared, one tunnel — two possible public hostnames)
    │
    ├──▶ CF_HOSTNAME ────────▶ openchamber   (port 3000, password-protected UI)
    │                              │
    │                              ▼
    │                         opencode serve (port 4096, localhost only)
    │
    └──▶ OPENWEBUI_HOSTNAME ─▶ OpenWebUI     (port 8080, Docker container, own login)
```

Either branch can be enabled on its own, or both at once — see [Stacks](#stacks) below.

## Prerequisites

Install the following before getting started:

- [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
- `bash` (required by the `#!/usr/bin/env bash` scripts)
- For the **code stack** (`ENABLE_CODE_STACK=true`, the default): [opencode](https://opencode.ai) CLI and [openchamber](https://github.com/nicholasgriffintn/openchamber) CLI
- For **OpenWebUI** (`ENABLE_OPENWEBUI=true`): Docker with the `compose` plugin (Docker Desktop on macOS, or Docker Engine + `docker-compose-plugin` on Linux)

You also need a [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) account with a tunnel created.

## Setup

1. Clone the repository:

```bash
git clone https://github.com/your-username/mini-tunnel.git
cd mini-tunnel
```

2. Install cloudflared and register it as a system service:

```bash
# macOS
brew install cloudflared

# Ubuntu / Debian
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared

# Both platforms
sudo cloudflared service install <your-tunnel-token>
```

This runs cloudflared in the background via launchd on macOS or systemd on Linux so it starts on boot. The scripts detect the active system service and skip manual cloudflared management on both platforms.

3. Create your `.env` file from the example:

```bash
cp .env.example .env
```

4. Fill in the required variables in `.env`:

| Variable | Required | Default | Description |
|---|---|---|---|
| `PASS_KEY` | Yes (code stack) | — | Password for the openchamber UI |
| `CF_TUNNEL_TOKEN` | No | — | Only needed if not using the system service |
| `OPENCODE_PORT` | No | `4096` | Local port for the opencode server |
| `OPENCHAMBER_PORT` | No | `3000` | Local port for the openchamber server |
| `CF_HOSTNAME` | No | `quinmini.leanflag.net` | Public hostname mapped to the code stack |
| `ENABLE_CODE_STACK` | No | `true` | Run opencode + openchamber |
| `ENABLE_OPENWEBUI` | No | `false` | Run OpenWebUI via Docker Compose |
| `OPENWEBUI_PORT` | No | `8080` | Local port for OpenWebUI |
| `OPENWEBUI_TAG` | No | `main` | Docker image tag for `ghcr.io/open-webui/open-webui` |
| `OPENWEBUI_HOSTNAME` | No | — | Public hostname mapped to OpenWebUI |
| `OPENWEBUI_SECRET_KEY` | No | — | Signing key for OpenWebUI sessions; set it to keep sessions valid across restarts |

An existing `.env` from before this feature (missing the `ENABLE_*`/`OPENWEBUI_*` keys entirely) still works unchanged — it defaults to the code stack only, exactly like before.

## Stacks

Toggle stacks independently in `.env`:

```bash
# Code stack only (default, original behavior)
ENABLE_CODE_STACK=true
ENABLE_OPENWEBUI=false

# OpenWebUI only
ENABLE_CODE_STACK=false
ENABLE_OPENWEBUI=true

# Both at once
ENABLE_CODE_STACK=true
ENABLE_OPENWEBUI=true
```

### Routing both stacks through the tunnel

There is one Cloudflare Tunnel, but it can carry multiple public hostnames — each mapped to a different local port via a **Public Hostname** rule in the [Zero Trust dashboard](https://one.dash.cloudflare.com/) (Networks → Tunnels → your tunnel → Public Hostname tab). If you enable both stacks, add one rule per stack:

| Hostname (`.env` var) | Service | Local URL |
|---|---|---|
| `CF_HOSTNAME` | Code stack | `http://127.0.0.1:$OPENCHAMBER_PORT` |
| `OPENWEBUI_HOSTNAME` | OpenWebUI | `http://127.0.0.1:$OPENWEBUI_PORT` |

If `ENABLE_OPENWEBUI=true` but `OPENWEBUI_HOSTNAME` is unset, `start.sh` still brings OpenWebUI up locally but prints a warning — it won't be reachable through the tunnel until you add its Public Hostname rule.

## Usage

### Start enabled stacks

```bash
./start.sh
```

This launches whichever stacks are enabled in `.env`. If cloudflared is running as a system service, it's skipped; otherwise it's started manually. On success it prints the local and public URLs for each enabled stack.

### Check status

```bash
./status.sh
```

Reports whether each service is running.

### Stop all services

```bash
./stop.sh
```

Stops all services in reverse order and cleans up PID files. Waits for each process to exit and ensures ports are released before returning.

### Restart all services

```bash
./restart.sh
```

Stops all running services, waits for all ports to be released, cleans up stale state, then starts everything fresh. This is the safest way to restart after updates or crashes.

### Force restart

```bash
./start.sh --force
```

Kills any process occupying the configured ports and starts fresh. Useful when `stop.sh` can't clean up a hung process.

## Logs

Native code-stack processes write log files in the project root:

- `opencode.log`
- `openchamber.log`
- `cloudflared.log`

OpenWebUI runs as a Docker container, so its logs are available via Docker instead:

```bash
docker compose logs -f open-webui
```

## License

MIT
