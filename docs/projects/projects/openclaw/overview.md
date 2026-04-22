# OpenClaw — ReadyMode Bot (Arpa Growth)

**Linear Project:** OpenClaw Project  
**Engineer:** Miguel Legarda  
**Status as of:** 2026-04-16  
**Last verified end-to-end:** 2026-04-11

---

## Quick Reference

| Property | Value |
|----------|-------|
| Client | Arpa Growth (insurance agency) |
| Client contact | Charlie |
| Platform (CRM) | ReadyMode — arpagrowth.readymode.com |
| Interaction channel | Discord — #readymode-soporte |
| Server | DigitalOcean — 159.89.179.179 (Ubuntu 24.04, 2 GB RAM + 2 GB swap) |
| LLM engine | gpt-4.1-mini (OpenAI) |
| Operations required | 4 (Clear Licenses, Reset Leads, Create User, Upload Leads) |
| Operations in production | 3 of 4 (75%) |
| Conversational support scenarios | 13 implemented |
| Overall functional completeness | ~60% |

---

## Current Status at a Glance

| Operation | Status | Notes |
|-----------|--------|-------|
| Clear Licenses | ✅ Done | 100% — verified 2026-04-09 |
| Reset Leads | 🔴 Blocked | Office Map empty — Charlie must assign agents |
| Create User (steps 1–4) | ✅ Done | Account creation + password — verified 2026-04-11 |
| Create User playlist (steps 5–9) | 🔴 Not started | Critical gap — needs screenshots from Charlie |
| Upload Leads (basic flow) | ✅ Done | Standard headers + existing campaign — verified 2026-04-10 |
| Conversational KB / Support | ✅ Done | 13 troubleshooting scenarios |
| Discord integration | ✅ Done | Bot active, bilingual ES/EN |

---

## Background & Why This Was Built

Arpa Growth is an insurance agency that relies on **ReadyMode** as their primary dialer/CRM. The platform manages agent licenses, lead distribution, user accounts, and call routing.

Managers were spending significant time on repetitive CRM tasks — clearing inactive licenses when agents got locked out, resetting leads for individual agents, creating new user accounts from scratch, and uploading lead files. These tasks required manual login, multiple UI clicks, and careful configuration each time.

A critical constraint defined the entire technical approach: **ReadyMode has no open API and actively rejects AI agent integration at the API level.** The only viable path was direct UI automation — the bot had to operate ReadyMode exactly as a human would, by clicking through the browser.

Built on **OpenClaw** (the team's self-hosted AI agent gateway), using Chrome headless (CDP) for browser automation and Discord as the communication layer.

### Platform Constraints That Shaped the Architecture

- No open API — all automation must go through the ReadyMode web UI
- ReadyMode explicitly rejects AI agent API access
- Heavy use of React/SPA rendering — direct URL navigation often returns blank DOM; navigation must go through UI clicks
- Several UI elements use non-standard event handling (native value setters required for React input fields)
- Some operations involve drag-and-drop (playlist configuration), which is technically complex in headless Chrome via CDP

---

## Original Requirements — 4 Primary Operations

The client specified 4 operations the bot must perform, each triggered by a manager message in Discord.

**Clear Licenses (4 steps):** Triggered when agents get a "We're sorry..." license error. Login → Click "License Usage" → Click "Sign Out Inactive Users" → OK popup + logout.

**Reset Leads (4 steps):** Triggered when an agent needs their leads reset. Login → Click "VIEW OFFICE MAP" → Find agent + click "Reset Leads" → Logout.

**Create User (9 steps — most complex):** Requires agent name, states, and campaigns before proceeding. Login → Click Users → Click green + button → Enter name + password + SAVE → Click Leads → Add a Playlist → Enter playlist name → Drag-and-drop campaigns and states → Assign user to playlist + verify "1 member".

**Upload Leads (variable steps):** Triggered when a manager sends a CSV. Accept CSV → Match headers → Select/create campaign → Import → Handle duplicates:

| Duplicate mode | When to use |
|----------------|-------------|
| Reject (default) | Standard uploads — new leads |
| Merge | Correcting a previous upload error (wrong column mapping, missing field) |
| Accept | Uploading surveys that already exist in the system as paid leads |
| Move | When a file has many duplicates — find the lead in search bar and move it to the requested campaign |

---

## Conversational Support — 13 Scenarios

Beyond the 4 automated operations, the bot handles common support questions conversationally as first-line support.

| Scenario | Bot response logic |
|----------|-------------------|
| No assignments | Timing issue (late EST/PST) — check PST states, advise log out/in |
| Single state pickups | Verify all states in playlist — suggest log out/in — temporarily remove highest-pickup state if persists |
| No pickups | Check playlist members, states, campaigns, agent connection status — escalate to ReadyMode support (1-800-694-1049) if unresolved |
| License error ("We're Sorry") | Trigger Clear Licenses automation |
| Only receiving inbounds | Log out/in first — remove agent from inbound queues if problem persists |
| 3+ min per pickup | Check state count and campaign size — advise timing or "buy more states" |
| Wrong credentials | Send manager a screenshot of correct credentials |
| Connection problems | Advise: change browser, use private/stable network, disable VPN — escalate to 1-800-694-1049 ext. 4 |
| Duplicate leads — correction | Advise Merge duplicates |
| Duplicate leads — surveys | Advise Accept duplicates |
| Duplicate leads — other | Advise moving leads to the requested campaign |
| Call results — standard campaigns | Normal call results |
| Call results — personal/team campaigns | Type "A" call results |

> **Key rule on "log out and back in":** This is the most common fix, but it should only be suggested *after* making a change or verifying the agent's configuration — never as a reflexive first response. Overusing it without checking first loses credibility with managers.

---

## Key Constraints

- **No API.** ReadyMode has no open API. All automation uses headless Chrome via Chrome DevTools Protocol (CDP).
- **React SPA.** Setting `input.value` directly does not work — must use the native value setter pattern.
- **No direct URL navigation.** Pages must be reached by clicking links within the dashboard, exactly as a human would.
- **Dispatcher only.** The agent does not guide users. It extracts parameters and executes scripts. No conversational step-by-step instructions.
- **tools.deny: ["browser"].** The agent cannot call the browser directly. All browser interaction is done via bash scripts.

---

## Documentation

| File | Contents |
|------|----------|
| [`operations.md`](./operations.md) | All 4 operations — detailed status, selectors, blockers, implementation notes |
| [`architecture.md`](./architecture.md) | Execution flow, design decisions, server infra, workspace files, 3-layer memory proposal |
| [`support-playbook.md`](./support-playbook.md) | 13 conversational support scenarios with full response flows |
| [`incidents.md`](./incidents.md) | 10 incidents & lessons learned from Phase 1 |
| [`security-audit.md`](./security-audit.md) | Full security audit — 27 findings, 3-phase remediation plan |
| [`compliance-matrix.md`](./compliance-matrix.md) | R01–R33 compliance matrix (57% done, 30% TODO, 6% blocked) |
| [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) | G01–G13 gap inventory, prioritized roadmap, ~10–16 dev days to full closure |
