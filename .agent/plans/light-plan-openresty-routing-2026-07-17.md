# Light Plan: Replace Cloudflare Tunnel with OpenResty Origin Routing

**Date:** 2026-07-17
**Scope:** Deprecate the Cloudflare Tunnel path (disabled by default), expose each mini-tunnel deployment on its dev server's internal IP, front it with a generated OpenResty vhost on `dev-openresty` (oauth2-proxy + IP allowlist), point Cloudflare DNS at `195.85.88.187`, and add a git-tracked deployment registry with reference templates that an AI agent can drive.

**Revision note (rev 2):** `ALLOW_CIDRS` is now an enforced gate using the box's existing `allow/deny` convention; the LAN-exposure firewall rule is an accepted, documented risk rather than a task; reference templates are a first-class deliverable.

---

## Architecture Overview

Today mini-tunnel is a **push** topology: `cloudflared` dials out from the dev server to Cloudflare's edge, and every service binds `127.0.0.1`. Nothing but the tunnel can reach them, which is exactly why the security team can't inspect the traffic — it bypasses the OpenResty layer entirely and arrives at the app with no reviewable ingress point.

The new topology is **pull**: Cloudflare (proxied) → `195.85.88.187` (dev-openresty) → OpenResty `:443` → IP allowlist → `oauth2-proxy` auth_request → `proxy_pass` to `{dev-internal-ip}:{port}`. This puts every request through the existing house security layer. The change has three moving parts that must land together, because each is useless without the others: mini-tunnel must **bind to its LAN IP** instead of loopback; OpenResty needs a **vhost** pointing at that IP:port; and **DNS** must resolve the hostname to the OpenResty origin rather than to the tunnel's CNAME.

The OpenResty side is genuinely low-risk to automate, and the recon confirmed why. `nginx.conf:156` already does `include others/*.conf;`, so a generated file dropped in that directory is picked up with no edit to any shared file. A wildcard cert (`*.leanflag.net`, `DNS:leanflag.net`) already exists at `/etc/letsencrypt/live/leanflag.net`, so `quinmini.leanflag.net` needs **no certbot run at all**. Passwordless sudo works over the SSH alias, so render → validate → reload is a single scripted round-trip. The generated vhost copies proven patterns already on the box: the oauth2-proxy `auth_request` block and WebSocket upgrade headers from `leanflag-openwebui.conf` (openchamber needs those), the named `upstream` block from `bastion-dev.conf`, and the `allow <cidr>; deny all;` form from `frp-server.conf:110` / `convert-core-image.conf:119`.

Two security layers stack in the generated vhost, and **their ordering is a correctness property, not a preference**. Because you chose **proxied (orange cloud)**, `$remote_addr` arrives as a Cloudflare edge IP, so `set_real_ip_from` (each CF range) + `real_ip_header CF-Connecting-IP` must rewrite it to the true client. The realip module runs at nginx's POST_READ phase and `allow`/`deny` at the later ACCESS phase, so **the allowlist evaluates against the real client IP** — the layering works as intended. Usefully, this **fails closed**: if the CF ranges are stale or missing, `$remote_addr` stays an edge IP, matches no entry in `ALLOW_CIDRS`, and everything is denied. A visible outage, never a silent bypass. These `real_ip` directives go inside our generated `server {}` block, **not at http level** — the box fronts ~200 vhosts, and a global `set_real_ip_from` would silently rewrite `$remote_addr` for every one of them.

The repo grows a **registry** rather than a database. Each deployment is a `KEY=VALUE` file that bash `source`s directly (no `yq`/`jq` dependency, and the OpenResty box has no `jq` anyway), plus a markdown index carrying the free-form context — why a deployment exists, what broke, what's decommissioned. Alongside it ships a **template plus worked reference configs**, so adding a deployment is copy-a-record-and-render rather than reverse-engineering nginx from scratch. Scripts read the `.env`; the agent reads and writes the markdown. That split is what makes it hybrid: the mechanical parts are automated, the judgment parts stay in prose.

---

## Data Model Changes

No database. Three new file-shaped "models":

- **`deployments/<name>.env`** 🆕 — one record per deployment, sourced directly by bash:
  - `DEPLOY_NAME`, `DEPLOY_STATUS` (`active` | `decommissioned`)
  - `HOSTNAME` (`quinmini.leanflag.net`), `CF_ZONE` (`leanflag.net`)
  - `CF_TOKEN_REF` (`op://DevOps/cloudflare-leanflag/credential`) ← multi-account resolution lives here
  - `CF_PROXIED=true`, `ORIGIN_IP=195.85.88.187`
  - `UPSTREAM_HOST` (dev server internal IP), `UPSTREAM_PORT`
  - `OPENRESTY_HOST=local-sbase-dev-openresty`, `SSL_CERT=leanflag.net`
  - `AUTH_MODE=oauth2`, `ALLOW_CIDRS` (space-separated; **required and non-empty for active deployments**)
- **`deployments/REGISTRY.md`** 🆕 — human/agent index: table of deployments + a notes section per entry.
- **`.env`** ✏️ — add `BIND_ADDR` (default `127.0.0.1`) and `ENABLE_CF_TUNNEL` (default `false`); `CF_TUNNEL_TOKEN` / `OPENWEBUI_CF_TUNNEL_TOKEN` / `CF_HOSTNAME` marked deprecated but still honored.

Putting `CF_TOKEN_REF` on the record (instead of a separate zone→token map) is what makes multi-account fall out for free — the credential is a property of the deployment, resolved at runtime via `op read`.

---

## High-Level Task List

```
1. Repo scaffolding + deployment registry
   - Create deployments/ with REGISTRY.md and a fully-commented example record
   - Write deployments/quinmini.env for the existing deployment
   - Add lib_deploy.sh: load_deployment(), list_deployments(), validate_deployment()
     (validate rejects an active record with empty ALLOW_CIDRS — fail closed by construction)

2. Bind services to the LAN instead of loopback
   - Add BIND_ADDR to .env.example (default 127.0.0.1, backwards-compatible)
   - code_stack.sh: openchamber --host "$BIND_ADDR"; leave opencode on 127.0.0.1
     (it's a backend openchamber fronts — it must never reach the LAN)
   - compose.yml: bind "${BIND_ADDR:-127.0.0.1}:${OPENWEBUI_PORT}:8080"
   - start.sh: warn when BIND_ADDR is not loopback, pointing at the documented LAN risk

3. OpenResty template + reference configs   ← "easy to add a new deployment"
   - nginx/site.conf.tmpl — the single source of truth. Layered in order:
     80→443 redirect; named upstream (bastion-dev.conf pattern); server-scoped
     set_real_ip_from CF ranges + real_ip_header CF-Connecting-IP; allow/deny gate
     from ALLOW_CIDRS; /oauth2 + auth_request block; WebSocket upgrade headers;
     per-host access/error logs. Conditional blocks omitted when a field is empty.
   - nginx/examples/quinmini.leanflag.net.conf — a real rendered output, committed,
     annotated with what each block does and which record field produced it
   - nginx/examples/REFERENCE.md — the upstream house patterns this template copies,
     with file:line citations back to the live box, so a future agent can verify drift
   - bin/render.sh: deployment .env + template -> deployments/<name>.conf (git-tracked)
   - bin/cf-ranges.sh: fetch cloudflare.com/ips-v4 + ips-v6, emit set_real_ip_from lines

4. Apply pipeline (laptop -> OpenResty over SSH)
   - bin/expose.sh <name>: render -> scp to /tmp -> sudo install into others/
     -> `nginx -t` -> reload on pass, restore previous conf and abort on fail
   - bin/unexpose.sh <name>: remove conf, test, reload, flip DEPLOY_STATUS
   - Never reload without a passing `nginx -t` — this box fronts ~200 vhosts

5. Cloudflare DNS automation
   - bin/cf-dns.sh <name>: op read CF_TOKEN_REF -> resolve zone_id -> upsert A record
     (ORIGIN_IP, proxied per CF_PROXIED); idempotent, no-op when already correct
   - Add --dry-run printing the intended change

6. Deprecate the tunnel
   - ENABLE_CF_TUNNEL (default false) gates all cloudflared start/stop/status paths
   - start.sh prints a deprecation warning when it's true; code path left intact
   - status.sh reports the OpenResty route as the live path

7. Docs
   - README: new architecture diagram, per-deployment walkthrough, Deprecated section,
     and an explicit "LAN exposure — accepted risk" note (see Risks)
   - deployments/README.md: registry schema + the agent-facing add/change/remove runbook
```

---

## Key Decisions Made

- **`ALLOW_CIDRS` is an enforced gate**, rendered as the box's existing `allow <cidr>; deny all;` form — bare directives at server level, matching `frp-server.conf:110`. No `geo`/`map` indirection; nothing on this box uses it.
- **Layering order is load-bearing.** `real_ip` (POST_READ) rewrites `$remote_addr` before `allow`/`deny` (ACCESS) reads it, so the allowlist sees true client IPs and stale CF ranges fail closed.
- **`real_ip` is scoped to our server block, never http level.** Global scope would rewrite `$remote_addr` for every vhost on a box serving ~200 sites.
- **An active record with empty `ALLOW_CIDRS` is a validation error**, so the gate can't be skipped by omission.
- **Registry is `KEY=VALUE`, not YAML.** Pure-bash repo; `source` beats adding a `yq` dependency, and the OpenResty box has no `jq`.
- **`CF_TOKEN_REF` lives on the deployment record** as an `op://` reference — multi-account resolution with no separate map file and no plaintext token on disk.
- **`opencode` stays on `127.0.0.1`.** Only openchamber/OpenWebUI move to `BIND_ADDR`; the backend must not be LAN-reachable.
- **Rendered confs are git-tracked** under `deployments/<name>.conf`, so every applied config is reviewable and diffable even though apply runs over SSH.
- **No certbot work.** The existing `*.leanflag.net` wildcard already covers the hostname — verified.
- **`nginx -t` gates every reload**, with rollback to the previous conf on failure.
- **No firewall automation** (your call) — LAN exposure is an accepted risk, documented in the README rather than mitigated in code.

---

## Open Questions / Risks

- ⚠️ **`op` is not installed on your laptop** (`command -v op` → not found). Task 5 is blocked until `brew install 1password-cli` + enabling CLI integration in the 1Password app. `jq`, `curl`, `envsubst` are all present.
- ⚠️ **LAN exposure is an accepted risk** (your call: keep as-is). Anything on `10.29.0.0/16` can reach openchamber on `:3000` directly, bypassing both the allowlist and oauth2-proxy, with only `PASS_KEY` in the way; OpenWebUI would have just its own login. Note the OpenResty allowlist protects the *public* path only — it does nothing for LAN-origin traffic. Documented in the README; revisit if a deployment ever carries anything sensitive.
- ⚠️ **`ENABLE_CF_TUNNEL=false` by default is a breaking change** for any existing `.env` lacking the key — those deployments stop tunneling on next restart. Intended per "disabled by default," but it needs a release note, and existing hosts need DNS + vhost in place *before* they restart.
- ⚠️ **Proxied mode leaves the origin reachable directly** at `195.85.88.187` — anyone who learns the IP can skip Cloudflare's WAF *and* the `real_ip`-dependent allowlist would then see the true `$remote_addr` anyway, so the allowlist still holds. The residual gap is WAF/DDoS coverage, not access control. Flagging as deliberate.
- **Cloudflare IP ranges drift**, and because the allowlist fails closed, stale ranges mean an outage rather than a leak. `bin/cf-ranges.sh` makes refreshing cheap, but nothing reminds you — a quarterly re-run or cron is worth considering.
- **Unknown:** which dev server(s) run mini-tunnel today, their internal IPs, and **which CIDRs belong in `ALLOW_CIDRS`** (office range? VPN pool? both?). `quinmini.env` can't be completed without these — this is the first thing the deep plan will need.
