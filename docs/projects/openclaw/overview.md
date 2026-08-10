# OpenClaw ReadyMode Bot — Fleet Overview

**Status as of:** 2026-08-06  
**Lead engineer:** Miguel Legarda and Juan Esteban Paez

**Version:** 2.0 — Python + Playwright + Claude Haiku (replaces original OpenClaw gateway, June 2026)

---

## Quick Reference

| Property | Value |
|---|---|
| Interaction channel | Discord (per-agency channel IDs or ticket-channel regex) |
| Infrastructure | AWS EC2 + Docker — one container per agency |
| LLM | Claude Haiku (intent parsing + response phrasing) |
| Browser automation | Playwright (Chromium, headless) |
| Bot framework | Python + nextcord |
| Fleet | 15 containers in operation as of 2026-08-06 |
| Total known accounts | 21 |
| Automated operations | 7 intents + KB fallback |
| Code repository | GitHub — branch-per-agency (`agency/<name>`) |

---

## What This Is

A self-hosted, multi-tenant Discord bot fleet that allows call-center managers to control ReadyMode CRM using natural-language commands in Discord. Each client agency gets its own isolated Docker container with its own bot token, ReadyMode credentials, and Anthropic API key. No operation in one container can affect any other.

**This system fully replaced the original OpenClaw Node.js gateway in June 2026.** The original system ran a single client (Arpa Growth / arpagrowth.readymode.com) on a DigitalOcean droplet using bash scripts driven by Chrome DevTools Protocol (CDP) and gpt-4.1-mini for intent parsing. The current system is Python + Playwright + Claude Haiku, multi-tenant from the ground up, running on AWS EC2.

### Why ReadyMode has no API

ReadyMode exposes no public API and actively blocks AI-agent traffic at the API layer. All automation drives the live UI via Playwright (headless Chromium), exactly as a human operator would.

---

## Current Fleet Status

| Containers running | Messaging sessions active | Accounts with ticket-channel access |
|---|---|---|
| 15 / 15 | 14 / 14 | 5 verified |

Six additional accounts are known but not yet mounted. Two accounts (Hooper, Surf) had zero inventory as of 2026-08-05 — their ReadyMode dialers had not been populated by the clients yet.

See [`fleet-status.md`](./fleet-status.md) for the full per-account table.

---

## 7 Automated Operations + KB

| Operation | Intent key | Notes |
|---|---|---|
| Create User | `create_user` | Account + playlist + state/campaign filters + member assignment |
| Create Playlist | `create_playlist` | Standalone playlist without account creation |
| Reset Leads | `reset_leads` | Resets leads queue for a specified agent |
| Clear Licenses | `clear_licenses` | Signs out inactive users to free ReadyMode licenses |
| User Exists | `user_exists` | Confirms whether an agent account exists |
| User Playlist | `user_playlist` | Finds which playlist a specific agent belongs to |
| Playlist Members | `playlist_members` | Lists all agents assigned to a specific playlist |
| KB Support | `kb_support` | Hardcoded Q&A for common ReadyMode questions (bilingual ES/EN, no Playwright) |

`kb_support` does not open a browser session — it is a direct dictionary lookup via `kb.py`.

---

## Architecture at a Glance

```
Discord message
  → Bot (nextcord)
  → Validation
  → Intent Parser (Claude Haiku)
  → Dispatcher
  → Executor (Playwright + Chromium)
  → Responder (Claude Haiku)
  → Discord reply
```

Six layers, strict separation of concerns. See [`architecture.md`](./architecture.md) for full detail.

---

## Key Constraints

- **No API.** Everything goes through Playwright clicking the ReadyMode UI.
- **React SPA.** All inputs require the native value setter + `input` event dispatch pattern.
- **Global job lock per container.** One Playwright session at a time — concurrent ReadyMode logins on the same account kick each other out.
- **One container = one agency.** A crash in one container does not affect any other.
- **`READYMODE_HEADLESS=false` is production-banned.** EC2 has no display; setting it crashes the browser silently.
- **Queue discovery needs retries.** ReadyMode's queue list renders asynchronously; the bot retries up to 6 times before aborting.

---

## Documentation Index

| File | Contents |
|---|---|
| [`architecture.md`](./architecture.md) | 6-layer architecture, file structure, branch strategy, deployment |
| [`fleet-status.md`](./fleet-status.md) | All 21 accounts — status, inventory, pending items |
| [`operations.md`](./operations.md) | Per-operation detail, executor patterns |
| [`engineer-onboarding.md`](./engineer-onboarding.md) | Day-1 guide for new engineers |
| [`server-guide.md`](./server-guide.md) | EC2 + Docker + systemd setup and maintenance |
| [`incidents.md`](./incidents.md) | All incidents and lessons learned |
| [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) | Open gaps and prioritized roadmap |
| [`security-audit.md`](./security-audit.md) | Server hardening and audit findings |
