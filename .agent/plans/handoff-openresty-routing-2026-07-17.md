# Handoff: OpenResty Origin Routing — Implementation Snapshot

**Date:** 2026-07-17
**Repo:** `/Users/quin/code/labs/mini-tunnel` (branch `main`)
**Architecture & rationale:** read `.agent/plans/light-plan-openresty-routing-2026-07-17.md` in this repo **first**. It is the source of truth for *why*. This file is the source of truth for *what you may do*.

---

## HARD CONSTRAINTS — violating any of these is a BLOCKED, not a judgement call

1. **Never invent an `ALLOW_CIDRS` value.** It is an IP allowlist — a security control. A guessed CIDR either locks out real users or grants access to strangers. Use the literal placeholder `__FILL_ME__` and document it. Do not substitute `0.0.0.0/0`, `10.0.0.0/8`, or any "sensible default". There is no sensible default.
2. **Never invent `UPSTREAM_HOST`, `CF_TOKEN_REF`, vault paths, or account names.** Same rule: placeholder + comment.
3. **Do not touch the live OpenResty box.** No `ssh`, `scp`, `nginx -t`, or `reload` against `local-sbase-dev-openresty`. That box fronts ~200 production vhosts. You are *writing* the apply scripts, not *running* them. Ship them unexecuted.
4. **Do not make live Cloudflare API calls.** No DNS reads or writes. `bin/cf-dns.sh` gets written and syntax-checked, never invoked against the API.
5. **Do not run `op`.** It is not installed. Write the code path; do not test it live.
6. **Do not modify `.env`** (gitignored, holds real secrets). Only `.env.example`.
7. **Preserve backwards compatibility:** `BIND_ADDR` defaults to `127.0.0.1`, so an existing `.env` lacking the key behaves exactly as today.
8. `bin/cf-ranges.sh` may fetch `https://www.cloudflare.com/ips-v4` and `ips-v6` — these are public, unauthenticated, read-only. This is the one network call you may make.

---

## In scope

Tasks 1, 2, 3, 6, 7 from the light plan, plus **writing** (not running) the scripts in tasks 4 and 5.

**File targets:**

| File | Action |
|---|---|
| `deployments/REGISTRY.md` | CREATE — index table + per-deployment notes sections |
| `deployments/example.env` | CREATE — fully commented reference record |
| `deployments/quinmini.env` | CREATE — real record, unknown fields as `__FILL_ME__` |
| `deployments/README.md` | CREATE — schema + agent runbook (add/change/remove) |
| `lib_deploy.sh` | CREATE — `load_deployment`, `list_deployments`, `validate_deployment` |
| `nginx/site.conf.tmpl` | CREATE — the vhost template |
| `nginx/examples/quinmini.leanflag.net.conf` | CREATE — annotated rendered example |
| `nginx/examples/REFERENCE.md` | CREATE — house patterns w/ file:line citations |
| `bin/render.sh` | CREATE — record + template → conf |
| `bin/cf-ranges.sh` | CREATE — CF ranges → `set_real_ip_from` lines |
| `bin/expose.sh` | CREATE — render→scp→install→`nginx -t`→reload, rollback on fail |
| `bin/unexpose.sh` | CREATE — remove, test, reload, flip status |
| `bin/cf-dns.sh` | CREATE — `op read` → zone_id → upsert A record; `--dry-run` |
| `.env.example` | MODIFY — add `BIND_ADDR`, `ENABLE_CF_TUNNEL`; mark tunnel vars deprecated |
| `code_stack.sh` | MODIFY — openchamber `--host "$BIND_ADDR"`; opencode stays `127.0.0.1` |
| `compose.yml` | MODIFY — bind `"${BIND_ADDR:-127.0.0.1}:${OPENWEBUI_PORT:-8080}:8080"` |
| `start.sh` | MODIFY — gate cloudflared on `ENABLE_CF_TUNNEL`; deprecation warning; LAN warn |
| `stop.sh` / `status.sh` | MODIFY — gate cloudflared paths on `ENABLE_CF_TUNNEL` |
| `README.md` | MODIFY — new diagram, walkthrough, Deprecated section, LAN risk note |

## Out of scope — do not attempt

- Filling real values for `ALLOW_CIDRS`, `UPSTREAM_HOST`, `CF_TOKEN_REF` (blocked on the user).
- Applying any config to OpenResty; changing any DNS record; installing `op`.
- Firewall rules / `ufw` (explicitly deferred by the user — accepted risk).
- Deleting the cloudflared code paths. They are **deprecated and default-off**, not removed.
- `git commit` / `git push`. Leave changes in the working tree.

---

## Decisions already made — do not redesign

- **Registry is `KEY=VALUE` sourced by bash.** No YAML, no `yq`, no `jq` in anything that could run on the OpenResty box.
- **`allow <cidr>; deny all;`** — bare directives at server level. This is the box's existing convention (`frp-server.conf:110`, `convert-core-image.conf:119`). No `geo`/`map` blocks; nothing on that box uses them.
- **`set_real_ip_from` + `real_ip_header CF-Connecting-IP` go INSIDE our `server {}` block, never at http level.** Global scope would rewrite `$remote_addr` for ~200 other vhosts.
- **Ordering is load-bearing and already correct:** realip runs at POST_READ, `allow`/`deny` at ACCESS, so the allowlist sees the true client IP. Stale CF ranges fail *closed*. Do not "fix" this by reordering.
- **`validate_deployment` must reject `DEPLOY_STATUS=active` with an empty/`__FILL_ME__` `ALLOW_CIDRS`.** Fail closed by construction. `quinmini.env` therefore ships as `DEPLOY_STATUS=pending`.
- **`opencode` stays bound to `127.0.0.1`.** Only openchamber/OpenWebUI honor `BIND_ADDR`. The opencode backend must never be LAN-reachable.
- **`nginx -t` gates every reload in `expose.sh`,** with restore-previous-conf on failure.
- **SSL:** reuse the existing `*.leanflag.net` wildcard at `/etc/letsencrypt/live/leanflag.net`. No certbot logic.
- Template layers, in order: `80→443` redirect → named `upstream` block → server-scoped realip → allow/deny → `/oauth2` + `auth_request` → WebSocket upgrade headers → per-host logs. Blocks whose source field is empty are omitted.

## Reference material (already gathered — do not re-SSH to collect it)

- `nginx.conf:156` does `include others/*.conf;` → dropping a file in `/usr/local/openresty/nginx/conf/others/` is sufficient; no shared file is edited.
- oauth2-proxy listens on `127.0.0.1:4180`; the `auth_request` pattern to copy is in `others/leanflag-openwebui.conf`.
- Named `upstream` pattern to copy: `others/bastion-dev.conf`.
- Wildcard cert SANs verified: `DNS:*.leanflag.net, DNS:leanflag.net`.
- OpenResty 1.21.4.1, built `--with-http_realip_module` (confirmed).
- OpenResty box internal IP `10.29.0.50`; public origin `195.85.88.187`; SSH alias `local-sbase-dev-openresty`.

---

## Verification (all offline — run these yourself)

- `bash -n` passes on every `.sh` file you create or modify.
- `shellcheck` on new scripts if available; otherwise skip silently.
- `./bin/render.sh example` output is byte-identical to the committed `nginx/examples/quinmini.leanflag.net.conf` (or the example is regenerated from it — they must not drift).
- Rendering a record with empty `ALLOW_CIDRS` + `DEPLOY_STATUS=active` exits non-zero with a clear error.
- Rendering with `AUTH_MODE=none` omits the `/oauth2` block entirely; with `oauth2` it includes it.
- `grep -c set_real_ip_from` in rendered output is > 0 and every occurrence sits inside the `server {}` block, not at file top level.
- `./status.sh` and `./stop.sh` still run clean with no `.env` present (defaults path).
- Existing `.env` without `BIND_ADDR`/`ENABLE_CF_TUNNEL` → services still bind `127.0.0.1` and cloudflared does not start.

## Unresolved blockers (user-owned — leave as placeholders, do not resolve)

1. `ALLOW_CIDRS` values — office range? VPN pool? both? **Unknown.**
2. Dev server internal IPs running mini-tunnel → `UPSTREAM_HOST`. **Unknown.**
3. 1Password vault/item path → `CF_TOKEN_REF`. **Unknown.**
4. `op` CLI not installed locally.

If a step cannot proceed without one of these, that is expected: leave the placeholder, note it in `deployments/REGISTRY.md`, and continue with the rest. Do not stop the whole run for these four.
