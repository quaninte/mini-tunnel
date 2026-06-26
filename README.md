# mini-tunnel

A lightweight Bash orchestration tool that runs [opencode](https://opencode.ai) behind a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), making your local AI coding environment publicly accessible and password-protected.

## Architecture

```
Internet
    │
    ▼
Cloudflare Tunnel  (cloudflared)
    │
    ▼
openchamber        (port 3000, password-protected UI)
    │
    ▼
opencode serve     (port 4096, localhost only)
```

## Prerequisites

Install the following before getting started:

- [opencode](https://opencode.ai) CLI
- [openchamber](https://github.com/nicholasgriffintn/openchamber) CLI
- [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
- `bash` (required by the `#!/usr/bin/env bash` scripts)

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
| `PASS_KEY` | Yes | — | Password for the openchamber UI |
| `CF_TUNNEL_TOKEN` | No | — | Only needed if not using the system service |
| `OPENCODE_PORT` | No | `4096` | Local port for the opencode server |
| `OPENCHAMBER_PORT` | No | `3000` | Local port for the openchamber server |
| `CF_HOSTNAME` | No | `quinmini.leanflag.net` | Public hostname mapped to your tunnel |

## Usage

### Start all services

```bash
./start.sh
```

This launches opencode and openchamber. If cloudflared is running as a system service, it's skipped; otherwise it's started manually. On success it prints the local and public URLs.

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

Service output is written to log files in the project root:

- `opencode.log`
- `openchamber.log`
- `cloudflared.log`

## License

MIT
