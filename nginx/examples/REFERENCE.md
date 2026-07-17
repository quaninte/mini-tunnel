# OpenResty house patterns (reference for the mini-tunnel template)

The generated vhost (`nginx/site.conf.tmpl` → `bin/render.sh`) copies proven
patterns from the live box `local-sbase-dev-openresty`. File:line citations below
are from recon on 2026-07-17 — re-check on the box if behavior drifts.

**Do not re-SSH to collect this** unless verifying drift; the handoff already
gathered it.

## Include path

| Fact | Source |
|------|--------|
| Dropping a file in `/usr/local/openresty/nginx/conf/others/` is enough | `nginx.conf:156` does `include others/*.conf;` |
| No shared file is edited by apply | same |

## Named upstream

| Pattern | Live source |
|---------|-------------|
| `upstream <name> { server host:port; keepalive N; }` | `others/bastion-dev.conf` |
| Template token | `{{UPSTREAM_NAME}}` from `DEPLOY_NAME`, `{{UPSTREAM_HOST}}:{{UPSTREAM_PORT}}` |

## oauth2-proxy `auth_request`

| Pattern | Live source |
|---------|-------------|
| oauth2-proxy listens on `127.0.0.1:4180` | recon |
| `location /oauth2/` + `location = /oauth2/auth` + `auth_request` on `/` | `others/leanflag-openwebui.conf` |
| Template field | `AUTH_MODE=oauth2` includes blocks; `AUTH_MODE=none` omits them entirely |

## WebSocket upgrade headers

| Pattern | Live source |
|---------|-------------|
| `proxy_set_header Upgrade $http_upgrade;` | `others/leanflag-openwebui.conf` (openchamber needs these) |
| `proxy_set_header Connection $connection_upgrade;` | same (`$connection_upgrade` map is already global on the box) |

## IP allowlist (`allow` / `deny`)

| Pattern | Live source |
|---------|-------------|
| Bare `allow <cidr>;` then `deny all;` at **server** level | `others/frp-server.conf:110`, `others/convert-core-image.conf:119` |
| No `geo` / `map` for allowlisting | nothing on that box uses them for this |
| Template field | `ALLOW_CIDRS` (optional, space-separated) → one `allow` line each + `deny all;` when set; omit both when empty |

## Real client IP behind Cloudflare (proxied)

| Pattern | Why |
|---------|-----|
| `set_real_ip_from <cf-cidr>;` + `real_ip_header CF-Connecting-IP;` | orange-cloud: `$remote_addr` is a CF edge IP until rewritten |
| **Inside our `server {}` only** | global/http scope would rewrite `$remote_addr` for ~200 other vhosts |
| Phase order is load-bearing | realip = POST_READ, allow/deny = ACCESS → allowlist sees true client |
| Stale CF ranges fail **closed** when allowlist set | edge IP matches no `ALLOW_CIDRS` → deny all |
| Ranges emitted by | `bin/cf-ranges.sh` (public `cloudflare.com/ips-v4` + `ips-v6`) |

## SSL

| Fact | Source |
|------|--------|
| Wildcard `*.leanflag.net` (+ apex) | `/etc/letsencrypt/live/leanflag.net` SANs verified |
| Template field | `SSL_CERT=leanflag.net` → `/etc/letsencrypt/live/{{SSL_CERT}}/` |
| No certbot in this repo | covered by existing wildcard |

## Box identity

| Item | Value |
|------|-------|
| SSH alias | `local-sbase-dev-openresty` |
| Internal IP | `10.29.0.50` |
| Public origin | `123.16.178.142` |
| OpenResty | 1.21.4.1, built `--with-http_realip_module` |

## Rendered example field map

Committed file: `nginx/examples/quinmini.leanflag.net.conf`  
Regenerate (must not drift): `./bin/render.sh example --stdout > nginx/examples/quinmini.leanflag.net.conf`

| Block in rendered conf | Record field(s) |
|------------------------|-----------------|
| `server_name` | `HOSTNAME` |
| `upstream mt_<name>` | `DEPLOY_NAME`, `UPSTREAM_HOST`, `UPSTREAM_PORT` |
| `ssl_certificate*` | `SSL_CERT` |
| `access_log` / `error_log` | `DEPLOY_NAME` |
| `set_real_ip_from` lines | live CF ranges via `bin/cf-ranges.sh` |
| `allow …;` + `deny all;` (or omitted) | `ALLOW_CIDRS` (optional) |
| `/oauth2` + `auth_request` | `AUTH_MODE=oauth2` |
| `proxy_pass http://mt_…` | named upstream from above |

The example record uses **documentation-only** `ALLOW_CIDRS` / `UPSTREAM_HOST`
(RFC 5737 / lab placeholders). Real deployments must use user-supplied values —
never invent CIDRs.
