# Architecture

---

## Execution Flow

The full request-to-response path:

```
Discord message (manager/agent)
        |
        v
OpenClaw Gateway (port 18789, localhost only)
        |
        v
Agent LLM — gpt-4.1-mini
  1. Understands intent (NLP)
  2. Extracts parameters (username, states, campaigns, etc.)
  3. Asks for confirmation if destructive operation
  4. Identifies the correct bash script via decision table
  5. Executes: exec script.sh [params] (yieldMs: 120,000ms)
        |
        v
Bash Script (autonomous — no LLM involvement)
  - Login via Chrome headless CDP
  - Navigate via UI clicks (never direct URL)
  - Fill forms, click buttons, handle popups
  - Output: single-line JSON {"success": true/false, "message": "..."}
        |
        v
Agent LLM
  6. Parses JSON result
  7. Responds to manager in natural language (ES or EN)
        |
        v
Discord response in #readymode-soporte
```

---

## Design Decisions

### D1 — `tools.deny: ["browser"]`

**Decision:** The agent LLM is explicitly blocked from calling the browser tool directly. It can only execute bash scripts, which internally use `openclaw browser` as a subprocess.

**Reasoning:** This was a deliberate architectural decision made after the agent kept trying to manually guide users through steps in Discord instead of actually executing operations. This forces a single controlled path: the agent's only job is to understand the request, extract parameters, and fire the right script. All DOM logic, selectors, and browser interactions live exclusively inside the scripts — never in the agent's context.

---

### D2 — Dispatcher Pattern, Not Conversational Guide

**Decision:** The agent is a **pure dispatcher**: receive request → confirm if needed → execute script → report result. It never describes how operations work internally.

**Reasoning:** Early versions behaved as a conversational assistant, explaining how to do things manually in Discord. This was wrong. The agent was rewritten entirely. Without the dispatcher constraint, an agent with operational knowledge will share that knowledge conversationally rather than executing.

---

### D3 — Navigation via UI Clicks, Never Direct URLs

**Decision:** All navigation happens by clicking links within the dashboard (using `a.dash_link` selectors). Direct URL navigation is only used for a small set of known-safe routes (`/+Team/ManageLicenses`).

**Reasoning:** ReadyMode is a React SPA. Navigating directly to URLs like `/+Team/ManageUsers` returns a blank DOM because the app hasn't bootstrapped client-side state. All navigation must happen by clicking links in the dashboard, exactly as a human would (see Incident 5).

---

### D4 — Native Value Setter for React Inputs

**Decision:** All form field inputs use the native value setter pattern plus `input` event dispatch.

**Pattern:**
```javascript
const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
  HTMLInputElement.prototype, 'value'
).set;
nativeInputValueSetter.call(input, value);
input.dispatchEvent(new Event('input', { bubbles: true }));
```

**Reasoning:** ReadyMode's input fields are controlled React components. Standard `input.value = 'x'` doesn't trigger React's state management, so the field appears filled but submits empty. Used in login, password setting, and user creation (see Incidents 3 & 10).

---

### D5 — Anti-Hallucination Rules (Explicit)

**Decision:** `AGENTS.md` contains explicit prohibitions against fabricating results.

**Key rule:** "If the script output is ambiguous or still running, you must report that honestly. Never fabricate success."

**Reasoning:** A `yieldMs` of 120,000ms (2 minutes) gives scripts enough time to complete before the agent evaluates the result. Polling between script checks has a minimum of 20 seconds and a maximum of 4 polls to avoid saturating the gateway (see Incidents 7 & 9).

---

### D6 — Confirmation Before Destructive Operations

**Decision:** Before executing Clear Licenses or any operation that affects multiple agents, the bot asks the manager to confirm ("Confirmas?").

**Reasoning:** Operations like Reset Leads permanently delete queue data. A misunderstood command or a test message from a manager should never trigger irreversible actions without a clear confirmation step.

---

## Server Infrastructure

| Component | Detail |
|-----------|--------|
| Provider | DigitalOcean NYC3 |
| IP | 159.89.179.179 |
| OS | Ubuntu 24.04.3 LTS |
| RAM | 2 GB + 2 GB swap |
| Disk | 87 GB (15% used) |
| Swap config | `vm.swappiness=10`, `vm.vfs_cache_pressure=50` |
| Reverse proxy | Caddy (TLS, aurora.nheo.ai) |
| Tunnel | cloudflared (agent.nheo.ai) |
| Database | PostgreSQL 16 via Docker |
| DB admin | pgAdmin4 via Docker |

### Ports — Internal Only (localhost)

| Port | Service |
|------|---------|
| 18789 | OpenClaw Gateway |
| 18792 | OpenClaw Gateway WebSocket |
| 3000 | Aurora (Next.js) |
| 5432 | PostgreSQL |
| 5050 | pgAdmin4 |

### Ports — Exposed to Internet

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | HTTP (redirects to 443) |
| 443 | HTTPS (Caddy) |

### systemd Services

| Service | User | Description |
|---------|------|-------------|
| `openclaw-gateway` | agent | Core gateway — receives Discord messages, dispatches to agent |
| `openclaw-bg-dispatcher` | agent | Processes background commands |
| `openclaw-bg-worker` | agent | Background task worker |
| `openclaw-owner-policy` | agent | WhatsApp message parser |
| `aurora` | agent | Next.js web application |
| `caddy` | caddy | Reverse proxy + TLS |
| `cloudflared` | root | Cloudflare tunnel (currently runs as root — flagged in security audit F-10) |

---

## Workspace File Structure

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent behavior rules: dispatcher pattern, confirmation logic, anti-hallucination, polling limits, bilingual response |
| `SKILL.md` | Decision table (which script maps to which intent) + full KB for conversational support |
| `SOUL.md` | Tone and personality definition |
| `IDENTITY.md` | Who the agent is (role, name, context) |
| `_lib.sh` | Shared bash functions used by all scripts |
| `clear_licenses.sh` | Automates the Clear Licenses flow |
| `reset_leads.sh` | Automates Reset Leads (currently blocked) |
| `create_user.sh` | Automates Create User steps 1–4 (playlist steps pending) |
| `upload_leads.sh` | Automates CSV upload and campaign assignment |

### `_lib.sh` — Shared Functions

| Function | Purpose |
|----------|---------|
| `readymode_login()` | Navigates to the login page, fills credentials using the native value setter pattern, dismisses overlays post-login. Selectors: `#login-account`, `#login-password`, `.sign-in` |
| `readymode_logout()` | Appends `?logout=1` to the URL to force logout |
| `dismiss_blocking_overlays()` | Detects and closes modal overlays (e.g., `#phone_test_ui` with z-index 600) that block post-login clicks. These overlays appear inconsistently and were a significant source of early failures |

---

## OpenClaw Configuration (`openclaw.json`)

| Setting | Value | Reason |
|---------|-------|--------|
| `tools.deny` | `["browser"]` | Force all browser interaction through bash scripts |
| `tools.exec.backgroundMs` | `90000` | Scripts can take 15–45 seconds; 90s gives 2x buffer |
| `yieldMs` | `120000` | Wait up to 2 minutes for script completion before evaluating |

---

## Architecture Improvement Proposal — 3-Layer Memory

**Proposed by:** Miguel Legarda — 2026-04-16  
**Status:** Not yet implemented — pending team decision  
**Estimated effort:** ~2 days, low risk

### The Problem

The current agent LLM receives the entire workspace context on every turn: `AGENTS.md` (164 lines), `SKILL.md` (175 lines), `SOUL.md`, `IDENTITY.md`, and more. This includes information the agent never directly uses — DOM selectors, React gotchas, historical incident notes, full operation flows step-by-step. The scripts handle all of that, not the agent.

Approximately **40% of the agent's context window is consumed by irrelevant technical detail.** Consequences: less space for actual conversation, higher latency per turn, the agent occasionally tries to "help" with DOM details it has no business mentioning, and adding a new operation means editing a large tangled `AGENTS.md` file.

### The Proposal — 3-Layer Memory Separation

| Layer | Contents | Used by | Lives in |
|-------|----------|---------|----------|
| Global Memory (persistent) | Available operations, required parameters, decision table, KB troubleshooting, support phone number | Agent LLM | `OPERATIONS.md` + `KNOWLEDGE.md` |
| Local Memory (per session) | Behavioral rules: language, Discord format, when to confirm, anti-hallucination rules, polling limits | Agent LLM | `BEHAVIOR.md` |
| Script Logic (autonomous) | DOM selectors, React gotchas, SPA navigation rules, overlay handling, incident workarounds, step-by-step flows | Only the bash scripts | `_lib.sh` + inline script comments |

### Proposed Execution Flow (Post-Refactor)

```
Discord message
    |
    v
Agent LLM (lightweight context: BEHAVIOR + OPERATIONS + KNOWLEDGE ~140 lines)
    1. Understands user intent
    2. Extracts required parameters
    3. Looks up decision table → identifies script
    4. exec script.sh with params (yieldMs: 120,000ms)
    |
    v
Bash Script (fully autonomous — all DOM logic internal)
    - Login, navigation, form fills, drag-and-drop
    - All gotchas and workarounds live here
    - Output: JSON {"success": true/false, "message": "..."}
    |
    v
Agent LLM
    5. Parses JSON
    6. Responds in natural language
    |
    v
Discord response
```

### File Restructuring Plan

| Current file | Proposed destination | What changes |
|-------------|---------------------|---------------|
| `AGENTS.md` (164 lines) | `BEHAVIOR.md` (~50 lines) | Only behavioral rules remain: language, format, confirmation logic, anti-hallucination, polling limits |
| `SKILL.md` (175 lines) | `OPERATIONS.md` (~40 lines) + `KNOWLEDGE.md` (~50 lines) | Decision table + params go to OPERATIONS. KB troubleshooting goes to KNOWLEDGE. DOM flows and few-shot examples removed |
| DOM flows, selectors, gotchas, incidents (currently in AGENTS.md) | Deleted from agent context | Moved to inline comments inside each bash script |
| `SOUL.md` + `IDENTITY.md` | No change | Already lightweight (<40 lines total) |

**Net result:** Agent context shrinks from ~340 lines to ~140 lines — a ~60% reduction.

### Benefits

1. **Less hallucination risk.** Without DOM selectors and technical flows in its context, the agent physically cannot improvise with selectors or explain manual steps.
2. **Faster responses.** Fewer tokens in context = lower latency per LLM call.
3. **Easier maintenance.** Adding a new operation = create a bash script + add one row to the decision table in `OPERATIONS.md`.
4. **Clean debugging separation.** Agent problems live in `BEHAVIOR.md`. Automation problems live in the scripts.
5. **Scripts become self-documented.** Moving gotchas into script comments means the next engineer opening `create_user.sh` will find everything they need.

### Implementation Plan

| Phase | Task | Effort |
|-------|------|--------|
| A | Create `BEHAVIOR.md`, `OPERATIONS.md`, `KNOWLEDGE.md` by splitting and trimming existing files | 1 day |
| B | Move DOM details, selectors, and gotchas into inline comments in each bash script | 0.5 days |
| C | Test that agent still handles all operations and KB scenarios correctly with reduced context | 0.5 days |
| **Total** | **Low risk — scripts do not change, only context files** | **~2 days** |

> **Decision needed:** The team should decide whether to implement this before or after closing the remaining feature gaps (G01–G10). Since it's independent and low-risk, it can run in parallel. If G01–G04 (Create User playlist) are about to be implemented, it may be cleaner to do the refactor first so the new script is written into the already-clean architecture.
