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
- `bash` and `nc` (netcat)

You also need a [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) account with a tunnel created.

## Setup

1. Clone the repository:

```bash
git clone https://github.com/your-username/mini-tunnel.git
cd mini-tunnel
```

2. Install cloudflared as a system service:

```bash
brew install cloudflared
sudo cloudflared service install <your-tunnel-token>
```

This runs cloudflared in the background via launchd so it starts on boot. The scripts will detect the system service and skip manual cloudflared management.

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

Stops all services in reverse order and cleans up PID files.

## Logs

Service output is written to log files in the project root:

- `opencode.log`
- `openchamber.log`
- `cloudflared.log`

## License

MIT
