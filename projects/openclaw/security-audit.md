# Security Audit — Server 159.89.179.179

**Auditor:** Miguel Legarda | **Date:** 2026-04-16 | **Classification:** CONFIDENTIAL

**Overall score: 48/110 — MEDIUM-LOW**

---

## Score by Area

| Area | Score | Level |
|------|-------|-------|
| SSH Authentication | 7/10 | Good |
| Users & Privileges | 4/10 | Poor |
| Firewall & Network | 2/10 | **Critical** |
| Kernel Hardening | 5/10 | Medium |
| Services & Attack Surface | 6/10 | Acceptable |
| Docker | 6/10 | Acceptable |
| TLS & Encryption | 5/10 | Medium |
| Logging & Audit | 3/10 | Poor |
| Updates & Patches | 4/10 | Poor |
| File Permissions | 7/10 | Good |
| systemd Hardening | 4/10 | Poor |
| **TOTAL** | **48/110** | **MEDIUM-LOW** |

The server is actively receiving ~2,500 brute-force SSH attempts per day with no rate-limiting or blocking in place. SSH key-only auth is a strong baseline but is not sufficient on its own.

---

## Critical Findings (4)

**F-01 — PermitRootLogin enabled.**
Root can SSH directly. Fix: `PermitRootLogin no` in `/etc/ssh/sshd_config`.

**F-02 — No fail2ban.**
17,797 brute-force attempts in 7 days. Fix: `apt install fail2ban`, maxretry=5, bantime=3600.

**F-07 — UFW completely disabled.**
All inbound traffic accepted. Fix: `ufw default deny incoming`, allow 22/80/443, `ufw enable`.

**F-16 — auditd not installed.**
No audit trail. Forensics impossible after an incident. Fix: `apt install auditd` with rules for passwd, shadow, sudoers, `openclaw.env`, execve.

---

## High Findings (7)

**F-05 — All users have `sudo ALL NOPASSWD`.**
Root, agent, juanesteban, miguel — any compromised account = instant root. Agent has an allowlist completely overridden by the ALL grant. Fix: restrict agent to its allowlist only; remove ALL grant from non-root users.

**F-08 — sysctl not hardened.**
`net.ipv4.conf.default` and all IPv6 params insecure. ICMP redirect injection possible. Fix: create `/etc/sysctl.d/99-hardening.conf`.

**F-17 — No logrotate for OpenClaw.**
Session JSONL and debug logs grow without limit. Fix: weekly rotation, keep 12 cycles, compress.

**F-18 — Kernel outdated, reboot required.**
Running 6.8.0-107, available 6.8.0-110. Security patches inactive until reboot.

**F-19 — 28+ packages pending update.**
Includes docker-ce, apparmor, chrome-stable (v145 vs v147). Chrome runs all ReadyMode automation.

**F-23 — systemd units inconsistently hardened.**
`openclaw-gateway` has zero security directives. Fix: `NoNewPrivileges=true`, `PrivateTmp=true`, `ProtectSystem=strict` on all OpenClaw + Aurora units.

**F-24 — No AppArmor profiles for OpenClaw.**
Fix: create profiles for `openclaw-gateway`, `aurora`, `openclaw-bg-dispatcher`.

---

## Medium Findings (9)

| ID | Finding | Fix |
|----|---------|-----|
| F-03 | X11Forwarding enabled on headless server | `X11Forwarding no` |
| F-06 | No SSH key rotation policy | 6-month rotation; use `chage` |
| F-09 | Unnecessary services: ModemManager, multipathd, udisks2 | `systemctl disable --now` + mask |
| F-10 | cloudflared runs as root | Create dedicated `cloudflared` user |
| F-11 | bg-dispatcher used 5+ days CPU in 6 days uptime | Investigate; add `CPUQuota` |
| F-12 | No Docker daemon.json | Add `no-new-privileges`, log limits, `live-restore`, `userns-remap` |
| F-14 | DNS unencrypted — no DoT or DNSSEC | systemd-resolved with Cloudflare/Quad9 DoT |
| F-15 | No disk encryption | Evaluate SOPS/age or DigitalOcean encrypted volumes |
| F-22 | 14 secrets in plaintext in `/etc/openclaw.env` | Evaluate Vault, Doppler, or SOPS/age |

---

## Low / Informational Findings

| ID | Finding |
|----|---------|
| F-04 | SSH on default port 22 |
| F-13 | Docker in rootful mode |
| F-25 | `kptr_restrict=1` (should be 2) |
| F-26 | Unprivileged user namespaces enabled |
| F-27 | Journal size uncapped (511 MB) |

---

## Remediation Plan

### Phase 1 — Do Today (under 30 minutes)

| # | Action | Mitigates |
|---|--------|-----------|
| 1 | Enable UFW — deny incoming, allow 22/80/443 | F-07 |
| 2 | Install and configure fail2ban (maxretry=5, bantime=3600) | F-02 |
| 3 | Set `PermitRootLogin no` in sshd_config | F-01 |
| 4 | `apt upgrade -y` + reboot | F-18, F-19 |

### Phase 2 — This Week

| # | Action |
|---|--------|
| 5 | Install auditd with hardening rules (passwd, shadow, sudoers, openclaw.env, execve) |
| 6 | Create `/etc/sysctl.d/99-hardening.conf` |
| 7 | Add systemd sandboxing directives to all OpenClaw + Aurora units |
| 8 | Create Docker `daemon.json` (no-new-privileges, log limits, live-restore, userns-remap) |
| 9 | Disable and mask unnecessary services (ModemManager, multipathd, udisks2) |
| 10 | Configure logrotate for OpenClaw logs |

### Phase 3 — Within 2 Weeks

| # | Action |
|---|--------|
| 11 | Restrict sudo per user (agent to its allowlist only) |
| 12 | DNS-over-TLS via systemd-resolved (Cloudflare or Quad9) |
| 13 | Move cloudflared to a non-root dedicated user |
| 14 | Write AppArmor profiles for openclaw-gateway, aurora, openclaw-bg-dispatcher |
| 15 | Evaluate secrets manager (Vault, Doppler, or SOPS/age) |
| 16 | Disable X11Forwarding |
| 17 | Set `SystemMaxUse=500M` in journald.conf |

---

> **Bottom line:** Phase 1 takes under 30 minutes and is non-negotiable. The server holds 14 API secrets in plaintext, receives 2,500 daily brute-force attempts, and has no firewall or fail2ban active. This must be fixed before any new feature work continues.
