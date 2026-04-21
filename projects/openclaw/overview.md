# OpenClaw — ReadyMode Bot (Arpa Growth)

## Project Summary

| Field | Value |
|-------|-------|
| Client | Arpa Growth (insurance industry) |
| Client contact | Charlie |
| Platform | ReadyMode CRM/dialer — `arpagrowth.readymode.com` |
| Channel | Discord — guild `1476748033134956756`, channel `#readymode-soporte` |
| Bot name | @ReadyMode |
| LLM | `gpt-4.1-mini` |
| Server | DigitalOcean — `159.89.179.179`, Ubuntu 24.04, 2 GB RAM + 2 GB swap |
| Agent gateway | OpenClaw (self-hosted, multi-channel) |
| Phase | Phase 1 complete — Phase 2 pending |

---

## Background

Arpa Growth managers needed to perform repetitive administrative tasks in ReadyMode (a CRM/dialer with no open API) several times per day. The only interface is a React SPA accessible via browser. The solution: a Discord bot backed by an LLM agent that receives plain-language commands and executes Chrome CDP automation scripts on the server.

ReadyMode has no API. All automation is done via headless Chrome (CDP) acting as a human user.

---

## Operations — Status Overview

| Operation | Status | Notes |
|-----------|--------|-------|
| Clear Licenses | ✅ Complete | Fully automated |
| Reset Leads | 🔴 Blocked | Charlie must assign agents to Office Map |
| Create User | ⚠️ 44% | Steps 1–4 done; playlist UI (steps 5–9) missing |
| Upload Leads | ⚠️ 55% | Basic flow done; custom headers, new campaign, merge/accept/move not implemented |

See [`operations.md`](./operations.md) for full details on each operation.

---

## Subpages

| File | Contents |
|------|----------|
| [`operations.md`](./operations.md) | All 4 operations — background, steps, current status, blockers |
| [`architecture.md`](./architecture.md) | Design decisions, server infrastructure, workspace files, systemd services |
| [`support-playbook.md`](./support-playbook.md) | 13 conversational support scenarios |
| [`incidents.md`](./incidents.md) | 10 incidents & lessons learned from Phase 1 |
| [`security-audit.md`](./security-audit.md) | Full security audit — 27 findings, 3-phase remediation plan |
| [`compliance-matrix.md`](./compliance-matrix.md) | R01–R33 compliance matrix (57% done, 30% TODO, 6% blocked) |
| [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) | G01–G13 gap inventory, prioritized roadmap, ~10–16 dev days to full closure |

---

## Key Constraints

- **No API.** ReadyMode has no open API. All automation uses headless Chrome via Chrome DevTools Protocol (CDP).
- **React SPA.** Setting `input.value` directly does not work — must use the native value setter pattern.
- **No direct URL navigation.** Pages must be reached by clicking links within the dashboard, exactly as a human would.
- **Dispatcher only.** The agent does not guide users. It extracts parameters and executes scripts. No conversational step-by-step instructions.
- **tools.deny: ["browser"].** The agent cannot call the browser directly. All browser interaction is done via bash scripts.
