# Server Operations Guide

How to operate the OpenClaw server — the box that hosts the ReadyMode bot, the Aurora marketplace, and the WhatsApp owner-policy daemon. The audience is "an engineer (or Juanes) who has never SSH'd in before but knows their way around Linux." If Miguel is unavailable, this doc should let you connect, diagnose, and recover the server independently.

This doc focuses on **the server**. For bot internals see [`engineer-onboarding.md`](./engineer-onboarding.md) and [`architecture.md`](./architecture.md). For the bot's user-facing operations see [`operations.md`](./operations.md). For the hardening posture and audit findings see [`security-audit.md`](./security-audit.md).

---

## 1. Server Identity

| Field | Value |
|---|---|
| Hostname | `OpenClow` |
| Public IP | `159.89.179.179` |
| Provider | DigitalOcean droplet (KVM) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-110-generic |
| Architecture | x86-64 |
| vCPU / RAM / Disk | 2 vCPU · 1.9 GiB RAM · 87 GiB root |
| Timezone | UTC |
| Public hostnames | `agent.nheo.ai`, `clow.nheo.ai`, `aurora.nheo.ai` (all via Cloudflare Tunnel) |

Single-server deployment — no staging box, no load balancer, no warm spare. Operating on this server **is** operating on production. Treat every change as a production change.

---

## 2. SSH Access

### Connection

```bash
ssh -p 22022 -i ~/.ssh/id_rsa miguel@159.89.179.179
```

| Setting | Value | Source file |
|---|---|---|
| Port | `22022` (non-standard, NHE-29) | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| Password auth | DISABLED | `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` |
| Root login | DISABLED | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| X11 forwarding | DISABLED | `99-hardening.conf` |
| TCP forwarding | DISABLED | `99-hardening.conf` |
| MaxAuthTries | 3 | `99-hardening.conf` |
| LoginGraceTime | 30s | `99-hardening.conf` |
| Banner | `/etc/issue.net` | `99-hardening.conf` |

### Adding a new operator

Password auth is disabled — the only way in is a key. To grant a teammate access:

1. Get their SSH public key (e.g. `id_ed25519.pub`) over a trusted channel.
2. As `miguel`, append it to `/home/miguel/.ssh/authorized_keys` (one key per line).
   `chmod 600 /home/miguel/.ssh/authorized_keys && chmod 700 /home/miguel/.ssh`.
3. Test from their workstation: `ssh -p 22022 -i ~/.ssh/<their_key> miguel@159.89.179.179`.
4. Do **not** create a new interactive Linux user without asking — the user table is small and audited.

> **Common pitfall — "SSH timed out, must be the firewall."** SSH is on **22022**, not 22. Before blaming firewall rules, verify the port: `nc -zv 159.89.179.179 22022`. The local hardened firewall does not block egress.

### Accounts

| User | UID | Purpose | Sudo? |
|---|---|---|---|
| `miguel` | 1002 | Operator login | Yes |
| `agent` | 1000 | Service account — owns `/home/agent/.openclaw/`, runs gateway/worker/dispatcher | No (allowlist only) |
| `do-agent` | 999 | DigitalOcean monitoring agent | No |

`miguel` is the only sudo user. `agent` does not have sudo and must not get it — the bot's blast radius is contained by that boundary. A small allowlist of bg-worker sudo commands lives at `/home/agent/.openclaw/workspace/runtime/bg_sudo_allowlist.json`.

---

## 3. Service Status

### Long-running systemd units

| Unit | What it does | Owner | Safe to restart? |
|---|---|---|---|
| `openclaw-gateway.service` | Discord ↔ agent LLM bridge — the live bot serving Arpa Growth | agent | **No — explicit signal from Miguel required** |
| `openclaw-bg-worker.service` | Executes background `/bg run` jobs | agent | Yes — see RUNBOOK_BG_WORKER |
| `openclaw-bg-dispatcher.service` | Routes `/bg` chat commands to the worker | agent | Yes — see RUNBOOK_BG_WORKER |
| `openclaw-owner-policy.service` | WhatsApp command parser (owner policy daemon) | agent | Ask first |
| `aurora.service` | Aurora Next.js app (serves `aurora.nheo.ai` on `127.0.0.1:3000`) | aurora user | Ask first |
| `caddy.service` | Reverse proxy (HTTP → upstream) | root | Yes — `caddy reload` is graceful |
| `cloudflared.service` | Cloudflare Tunnel (public hostnames → loopback ports) | root | Yes (stateless) |
| `docker.service` | Container runtime (Aurora DB + pgAdmin) | root | Yes — `live-restore: true` keeps containers up |
| `fail2ban.service` | SSH brute-force jail | root | Yes (stateless) |
| `auditd.service` | Kernel audit subsystem | root | Yes |
| `unattended-upgrades.service` | Auto security patches | root | Yes |

### Quick status snapshot

```bash
# All openclaw + supporting services up?
systemctl --no-pager --type=service --state=running \
  | grep -E 'openclaw|aurora|caddy|cloudflared|docker|fail2ban'

# One unit at a time
systemctl status openclaw-gateway --no-pager
systemctl status caddy --no-pager
systemctl status cloudflared --no-pager

# Anything failed?
systemctl --no-pager --failed
```

### Docker containers

| Container | Image purpose | Bound port |
|---|---|---|
| `aurora-postgres` | Aurora marketplace Postgres | `127.0.0.1:5432` (loopback only) |
| `aurora-pgadmin` | Web admin for the DB | `127.0.0.1:5050` (loopback only) |

Both ports are deliberately loopback-only. Reach them from a workstation with an SSH tunnel — see § 6.

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo docker stats --no-stream                             # CPU/RAM per container
sudo docker compose -f /opt/aurora-infra/docker-compose.yml ps
```

### Bg worker heartbeat

```bash
sudo cat /home/agent/.openclaw/workspace/runtime/worker-heartbeat.json     # < 60s old
sudo /home/agent/.openclaw/workspace/bin/bgctl.py queue                    # active jobs
```

> **`ps` truncates usernames > 8 chars.** `cloudflared` shows up as `cloudfl+`. In any verify script use `ps -eo user:32,cmd` to widen the column, or you'll think a service is missing when it's only truncated.

---

## 4. Logs

`journalctl` is the source of truth for every service on this box. The patterns below are the ones you'll use in 90% of incidents.

| Service | Live tail | Last 200 lines |
|---|---|---|
| openclaw-gateway | `sudo journalctl -u openclaw-gateway -f` | `sudo journalctl -u openclaw-gateway -n 200 --no-pager` |
| openclaw-bg-worker | `sudo journalctl -u openclaw-bg-worker -f` | `sudo journalctl -u openclaw-bg-worker -n 200 --no-pager` |
| openclaw-bg-dispatcher | `sudo journalctl -u openclaw-bg-dispatcher -f` | `sudo journalctl -u openclaw-bg-dispatcher -n 200 --no-pager` |
| openclaw-owner-policy | `sudo journalctl -u openclaw-owner-policy -f` | `sudo journalctl -u openclaw-owner-policy -n 200 --no-pager` |
| aurora | `sudo journalctl -u aurora -f` | `sudo journalctl -u aurora -n 200 --no-pager` |
| caddy | `sudo journalctl -u caddy -f` | `sudo journalctl -u caddy -n 200 --no-pager` |
| cloudflared | `sudo journalctl -u cloudflared -f` | `sudo journalctl -u cloudflared -n 200 --no-pager` |
| fail2ban | `sudo journalctl -u fail2ban -f` | `sudo fail2ban-client status sshd` |
| Audit (kernel) | `sudo tail -f /var/log/audit/audit.log` | `sudo ausearch -ts today \| tail` |

### Per-job bg logs

```bash
sudo /home/agent/.openclaw/workspace/bin/bgctl.py logs <job_id> --tail 120
sudo ls /home/agent/.openclaw/workspace/runtime/jobs/                # raw job log dir
```

### Bot conversation history

```bash
# All sessions for a given agent (JSONL, one event per line — pipe through jq)
sudo ls /home/agent/.openclaw/agents/main/sessions/
sudo tail -n 200 /home/agent/.openclaw/agents/main/sessions/<file>.jsonl | jq
```

### Time-bounded queries

```bash
# Last 10 minutes across the whole system
sudo journalctl --since '10 minutes ago' --no-pager

# Errors only, last hour, multiple units
sudo journalctl -p err --since '1 hour ago' \
  -u openclaw-gateway -u aurora -u caddy -u cloudflared --no-pager
```

---

## 5. Manually Triggering Scripts

When the bot is broken, paused, or you need to sanity-check a single operation, you can run the bash scripts directly. The scripts live under the `agent` account.

### Where the scripts are

```
/home/agent/.openclaw/workspace/skills/readymode-support/scripts/
├── _lib.sh                 # shared helpers (login, dash_link click, native value setter)
├── clear_licenses.sh       # Operation 1
├── create_user.sh          # Operation 3 (steps 1–4 only)
├── reset_leads.sh          # Operation 2 (returns unavailable until G05)
└── upload_leads.sh         # Operation 4
```

### Running a script as `agent`

```bash
# Switch to the service account (agent has no login shell by default; use sudo)
sudo -iu agent

# Inside agent's shell:
cd /home/agent/.openclaw/workspace
bash skills/readymode-support/scripts/clear_licenses.sh
```

### Dry-run mode (no production hits)

Always start here when you're unsure:

```bash
sudo -iu agent
cd /home/agent/.openclaw/workspace
OPENCLAW_DRY_RUN=true OPENCLAW_LOG_LEVEL=debug \
  bash skills/readymode-support/scripts/clear_licenses.sh
```

`OPENCLAW_DRY_RUN=true` skips CDP / browser actions and prints what the script *would* do. Pair with `OPENCLAW_LOG_LEVEL=debug` for verbose output.

### Running the gateway manually

If the systemd unit is stopped and you want to bring the bot up under your terminal (e.g. to see live logs while you reproduce a bug):

```bash
sudo systemctl stop openclaw-gateway
sudo -iu agent
/home/agent/.npm-global/bin/openclaw gateway \
  --port 18789 --bind loopback --ws-log compact
```

Ctrl-C to stop. `systemctl start openclaw-gateway` puts it back under systemd.

> **Don't run the bot in foreground while the systemd unit is also active** — both will try to bind the same port (`18789`) and the second instance will exit immediately, or worse, the running instance will keep stale state while you think you're testing fresh.

### Submitting a one-off background job

The `/bg` chat command is also available as a CLI:

```bash
sudo /home/agent/.openclaw/workspace/bin/bgctl.py queue
sudo /home/agent/.openclaw/workspace/bin/bgctl.py status <job_id>
sudo /home/agent/.openclaw/workspace/bin/bgctl.py logs <job_id> --tail 120
sudo /home/agent/.openclaw/workspace/bin/bgctl.py cancel <job_id>
```

Job states: `QUEUED | RUNNING | DONE | FAILED | CANCELED | TIMEOUT`. Full contract in `RUNBOOK_BG_WORKER.md` on the server.

---

## 6. Database Access

The Aurora Postgres instance and the pgAdmin web UI run as Docker containers under `/opt/aurora-infra/`. Both are bound to **localhost only** — there is no public DB endpoint.

### Where the credentials live

```bash
sudo cat /opt/aurora-infra/.env        # mode 0600, owner agent:agent
```

The `.env` defines:

| Variable | Used for |
|---|---|
| `POSTGRES_DB` | Database name |
| `POSTGRES_USER` | Postgres superuser |
| `POSTGRES_PASSWORD` | Postgres superuser password |
| `PGADMIN_DEFAULT_EMAIL` | pgAdmin login email |
| `PGADMIN_DEFAULT_PASSWORD` | pgAdmin login password |

> **Never commit, paste, or transcribe `.env` over an untrusted channel.** If you need a teammate to have credentials, share via SOPS (NHE-66) or a 1-time-secret link, not Slack/email.

### Option A — psql inside the container (fastest)

```bash
# Open a shell in the postgres container as the configured user
sudo docker exec -it aurora-postgres bash -lc \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# Or one-shot a query
sudo docker exec -i aurora-postgres psql -U postgres -d postgres \
  -tAc 'SELECT COUNT(*) FROM "User";'
```

### Option B — psql from the host

```bash
# Read creds from the env file (don't echo to a shared terminal)
set -a; source /opt/aurora-infra/.env; set +a
psql "host=127.0.0.1 port=5432 dbname=$POSTGRES_DB user=$POSTGRES_USER"
unset POSTGRES_PASSWORD
```

### Option C — psql / pgAdmin from your workstation (SSH tunnel)

```bash
# Tunnel both DB (5432) and pgAdmin (5050) over SSH
ssh -p 22022 \
    -L 5432:127.0.0.1:5432 \
    -L 5050:127.0.0.1:5050 \
    miguel@159.89.179.179
```

While the tunnel is open:

- **psql:** `psql "host=127.0.0.1 port=5432 dbname=<db> user=<user>"` — password from `/opt/aurora-infra/.env`.
- **pgAdmin:** open `http://127.0.0.1:5050` in your browser. Login with `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`. Add a server pointing at `host=postgres` (the container name) `port=5432`.

### Useful one-liners

```bash
# Health
sudo docker ps --filter name=aurora-postgres --format '{{.Status}}'

# Live size of the DB
sudo docker exec aurora-postgres psql -U postgres -d postgres \
  -tAc "SELECT pg_size_pretty(pg_database_size(current_database()));"

# Top 10 tables by row count
sudo docker exec aurora-postgres psql -U postgres -d postgres -c \
  "SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;"

# Migrations applied
sudo docker exec aurora-postgres psql -U postgres -d postgres -c \
  "SELECT migration_name, finished_at FROM _prisma_migrations ORDER BY finished_at DESC LIMIT 10;"
```

For backup/restore, see § 9 and `RUNBOOK_BACKUP_RESTORE.md` on the server.

---

## 7. Reverse Proxy & Public DNS

Public traffic reaches this server in two ways: **Cloudflare Tunnel** (`cloudflared`) and **Caddy** (local reverse proxy). Inbound port 80/443 on the public IP is firewalled — there is no direct ingress. Everything public goes through the tunnel.

### Cloudflare Tunnel (`cloudflared`)

| Field | Value |
|---|---|
| Tunnel ID | `44d9537e-3633-4103-a970-1ab7737115d2` |
| Credentials | `/etc/cloudflared/44d9537e-3633-4103-a970-1ab7737115d2.json` |
| Config | `/etc/cloudflared/config.yml` |
| systemd unit | `cloudflared.service` |

Current ingress rules:

| Public hostname | Forwards to | Served by |
|---|---|---|
| `agent.nheo.ai` | `http://127.0.0.1:18789` | `openclaw-gateway` |
| `clow.nheo.ai` | `http://127.0.0.1:18789` | `openclaw-gateway` (alias) |
| `aurora.nheo.ai` | `http://127.0.0.1:3000` | `aurora.service` (Next.js) |
| (anything else) | `http_status:404` | — |

```bash
# View / edit the tunnel config
sudo cat /etc/cloudflared/config.yml
sudo $EDITOR /etc/cloudflared/config.yml

# Reload after editing
sudo systemctl reload cloudflared        # or: restart, if reload not supported
sudo systemctl status cloudflared --no-pager

# Live ingress test
curl -fsS -H "Host: agent.nheo.ai" http://127.0.0.1:18789/healthz
curl -fsS -H "Host: aurora.nheo.ai" http://127.0.0.1:3000/
```

DNS for `*.nheo.ai` is managed in Cloudflare. The tunnel handles TLS termination at the edge — there is no certificate on this server.

### Caddy

Caddy is the local reverse proxy. It currently only fronts `aurora.nheo.ai` for direct (non-tunnel) HTTP access.

| Field | Value |
|---|---|
| Binary | `/usr/bin/caddy` |
| Config | `/etc/caddy/Caddyfile` |
| systemd unit | `caddy.service` |

Current `Caddyfile`:

```caddy
aurora.nheo.ai {
    encode gzip zstd
    reverse_proxy 127.0.0.1:3000
}
```

Editing and reloading:

```bash
# Validate before reloading
sudo caddy validate --config /etc/caddy/Caddyfile

# Graceful reload (no dropped connections)
sudo systemctl reload caddy
# or, if you want Caddy itself to do the reload via its admin API:
sudo caddy reload --config /etc/caddy/Caddyfile

# Inspect what Caddy is actually serving
sudo systemctl status caddy --no-pager
sudo journalctl -u caddy -n 100 --no-pager
```

### Adding a new public hostname

1. Decide where it terminates: **Cloudflare Tunnel** (preferred — zero firewall changes) or **Caddy** (only if you need on-box TLS or special headers).
2. **Tunnel route:** add an `ingress` block in `/etc/cloudflared/config.yml` above the catch-all `http_status:404` line, then `systemctl reload cloudflared`. Add the DNS CNAME in Cloudflare to the tunnel.
3. **Caddy route:** add a site block in `/etc/caddy/Caddyfile`, `caddy validate`, `systemctl reload caddy`.
4. Test with `curl -fsS -H "Host: <name>" http://127.0.0.1:<port>/`.

---

## 8. Common Troubleshooting

### Triage flow (when "something is wrong")

1. `systemctl --no-pager --failed` — anything red?
2. `df -h /` — disk full?
3. `free -h` — out of memory?
4. `sudo docker ps` — both Aurora containers up?
5. `sudo journalctl --since '10 minutes ago' -p err --no-pager` — recent errors?
6. Drill into the specific unit: `journalctl -u <unit> -n 200 --no-pager`.

### Symptom → first check

| Symptom | First check | Likely cause |
|---|---|---|
| SSH "Connection timed out" | `nc -zv 159.89.179.179 22022` | Wrong port (22 vs 22022) |
| SSH "Connection refused" | `sudo fail2ban-client status sshd` | Banned IP after MaxAuth 3 |
| Bot stops responding in Discord | `systemctl status openclaw-gateway` + `journalctl -u openclaw-gateway -n 200` | Gateway crashed; or ReadyMode session collision (NHE-56) |
| `agent.nheo.ai` returns 502 | `curl -I http://127.0.0.1:18789/healthz`; `journalctl -u cloudflared -n 100` | Gateway down or tunnel disconnected |
| `aurora.nheo.ai` returns 502 | `curl -I http://127.0.0.1:3000/`; `systemctl status aurora caddy` | Aurora app or Caddy down |
| `/bg` commands hang | `bgctl.py queue`, `journalctl -u openclaw-bg-worker -n 200` | Worker stuck or dispatcher down |
| Bot reports "license error" loop | Charlie hasn't assigned agents to Office Map | NHE-G05 — external blocker |
| ReadyMode "logged out" mid-operation | Bot and Miguel share `manager` account | NHE-56 (G22) — don't log into ReadyMode while the bot is running |
| Aurora DB unreachable from app | `docker ps`; `docker logs aurora-postgres --tail 50` | Container restart loop or healthcheck failure |
| Disk filling up | `du -xhd 1 /var/log /home/agent/.openclaw/agents /opt/aurora-infra/backups` | Docker JSON logs (capped 10m × 3), session JSONL growth, or stale dumps |
| RAM/CPU spike | `top`, `sudo docker stats --no-stream`, `journalctl --since '10 minutes ago'` | Bot retry loop, runaway bash subshell, or container OOM |
| `sudo` from `agent` denied | `cat /home/agent/.openclaw/workspace/runtime/bg_sudo_allowlist.json` | Command not in allowlist (by design) |

### Disk & memory checks

```bash
df -h /                                         # root usage
du -xhd 1 / 2>/dev/null | sort -h | tail -20    # biggest top-level dirs
sudo journalctl --disk-usage                    # journal size
sudo docker system df                           # docker disk usage
free -h                                         # RAM + swap
sudo dmesg -T | tail -50                        # kernel-level errors (OOM kills, etc.)
```

### Restart what is safe to restart

```bash
# SSHD config change — graceful, keeps your session alive
sudo systemctl reload sshd

# UFW / fail2ban — stateless
sudo systemctl restart fail2ban
sudo ufw reload

# Caddy / cloudflared — graceful reload
sudo systemctl reload caddy
sudo systemctl reload cloudflared

# Docker — live-restore keeps containers running
sudo systemctl restart docker

# Bg worker / dispatcher — RUNNING jobs auto-mark FAILED on next start
sudo systemctl restart openclaw-bg-worker
sudo systemctl restart openclaw-bg-dispatcher
```

### Things that need explicit approval from Miguel

```bash
sudo systemctl restart openclaw-gateway       # ❌ ask first — live customer service
sudo systemctl restart aurora                 # ❌ ask first
sudo systemctl restart openclaw-owner-policy  # ❌ ask first
sudo reboot                                   # ❌ ask first
```

### When the bot misbehaves but the box looks fine

The bot is built to fail loud, not to recover silently. If `openclaw-gateway` is running, journal is clean, but Discord users say "it's broken":

1. Open the relevant agent's session JSONL: `sudo tail -n 200 /home/agent/.openclaw/agents/main/sessions/*.jsonl | jq`
2. Look for the last `tool_use` and its result — the failure is almost always at the script ↔ LLM boundary, not the kernel.
3. Cross-reference `RUNBOOK_READYMODE_DEDUP.md` and the dedup timer pattern (NHE-64) before assuming a real outage.

### AppArmor edits

The bot's profile (`openclaw-bg-dispatcher`) is inherited by anything `agent` launches under sudo, including `sudo python3`. To edit `/etc/apparmor.d/` files without the profile getting in the way:

```bash
sudo aa-exec -p unconfined -- python3   # or your editor of choice
```

Plain `sudo python3` will inherit the profile and silently fail at the policy boundary.

---

## 9. Hardening Profile (Summary)

The full posture lives in `SECURITY-RUNBOOK.md` on the server (and the audit baseline lives in [`security-audit.md`](./security-audit.md)). Quick reference of what is enforced in production today:

| Layer | Control |
|---|---|
| Network (inbound) | UFW default-deny; allow `22022/tcp`, `80/tcp`, `443/tcp+udp` only |
| Brute-force | `fail2ban` SSH jail (maxretry 3, bantime 1h) |
| SSH | Key-only, port 22022, no root, no X11/TCP fwd, MaxAuth 3, LoginGrace 30s |
| Kernel | `dmesg_restrict=1`, `randomize_va_space=2`, `rp_filter=2`, syncookies, no redirects |
| Filesystem | `/dev/shm` mounted `noexec,nosuid,nodev` (persisted in `/etc/fstab`) |
| Docker | `no-new-privileges`, `icc=false`, `userland-proxy=false`, log size cap, live-restore |
| Audit | `auditd` running; logs in `/var/log/audit/` |
| Patches | `unattended-upgrades` (security only) |
| Secrets | SOPS + age (NHE-66); master key at `/root/.config/sops/age/keys.txt`, paper-backed |

Verify the live config with the commands in `SECURITY-RUNBOOK.md` § *Verify Commands*. **Don't trust this table over the server itself** — re-run the verifies before relying on a property.

### Not yet enforced (deferred)

- Docker `userns-remap` — needs container recreation; planned maintenance window
- AIDE file-integrity monitoring — Phase 4
- Fail2ban recidive jail — optional

---

## 10. Backups & Recovery

Source of truth: `RUNBOOK_BACKUP_RESTORE.md` on the server. Quick reference:

| Component | What | Where | Cadence | RPO |
|---|---|---|---|---|
| Aurora Postgres | `pg_dump --format=custom` + sha256 sidecar | `/opt/aurora-infra/backups/` | Daily ~03:18 UTC | 24h |
| Aurora offsite | restic snapshots to Cloudflare R2 (NHE-66) | bucket `claw-aurora/postgres` | Daily | 24h |
| Agent sessions | per-agent JSONL conversation logs | `/home/agent/.openclaw/agents/<agent>/sessions/` | None today | n/a |
| SOPS age key | master decryption key | `/root/.config/sops/age/keys.txt`, paper + USB offsite | One-time backup | n/a |

Run the restore drill quarterly — a backup that has never been restored is not a backup. Drill commands and expected timing live in `RUNBOOK_BACKUP_RESTORE.md`. Append a row to its drill log every time.

### Bare-metal recovery sketch

1. Provision a fresh DigitalOcean droplet, install Docker + docker-compose.
2. Restore `/opt/aurora-infra/` from the most recent restic snapshot.
3. Pull the latest `aurora_*.dump` from R2 if local disk is gone.
4. `docker compose up -d aurora-postgres`, then `pg_restore` per the runbook.
5. Restore SOPS age key to `/root/.config/sops/age/keys.txt` from paper/USB.
6. Decrypt `openclaw.env.enc` and place it at `/etc/openclaw.env`.
7. Re-create the cloudflared tunnel config (or restore `/etc/cloudflared/`) and start `cloudflared.service`.
8. Bring the bot up and run a no-op operation to confirm DB connectivity.

---

## 11. Maintenance & Change Control

- **Production reboot policy:** never reboot, never restart prod services, without an explicit signal from Miguel. The bot is a live customer-facing service.
- **Change approval pattern:** prepare the artifact (don't activate), present a short table — *time to apply / downtime / rollback* — and wait for the green light. This is how every hardening phase has shipped on this box.
- **Audit before exec:** plans more than a few weeks old need a fresh server-side audit (services, paths, perms) before applying. Report any drift before changing anything.
- **Rotation deferral:** when secret rotation needs an external console Miguel doesn't have access to, deliver the at-rest component (encrypted, deployed, decryptable) and defer the rotation step to a natural trigger.
- **No autonomous LLM in prod:** we do not give the agent a self-modifying loop on this server. Any "self-improving" feature lands as a *scan + ask* flow with a human in the loop.

---

## 12. Where to Look Next

| You want to | Read |
|---|---|
| Understand the bot's architecture | [`architecture.md`](./architecture.md), [`engineer-onboarding.md`](./engineer-onboarding.md) |
| Trace a specific bot operation | [`operations.md`](./operations.md) |
| See past incidents and lessons | [`incidents.md`](./incidents.md) |
| Audit the security posture | [`security-audit.md`](./security-audit.md) + `SECURITY-RUNBOOK.md` (server-side) |
| Run a backup/restore drill | `RUNBOOK_BACKUP_RESTORE.md` (server-side) |
| Operate `/bg` jobs in detail | `RUNBOOK_BG_WORKER.md` (server-side) |
| Track open requirements | [`compliance-matrix.md`](./compliance-matrix.md), [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) |
