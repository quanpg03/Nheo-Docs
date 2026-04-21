# Architecture

---

## Execution Flow

```
Discord message
  → OpenClaw Gateway (port 18789)
    → Agent: LLM (gpt-4.1-mini)
      → Bash script (headless Chrome CDP)
        → ReadyMode UI at arpagrowth.readymode.com
          → Result reported back to Discord
```

---

## Design Decisions

### D1 — tools.deny: ["browser"]

**Decision:** The agent is explicitly prohibited from calling the browser directly.

**Reasoning:** Without this constraint, the agent would attempt to navigate and fill forms itself, leading to brittle, non-reproducible behavior. All browser interaction is encapsulated in bash scripts that are testable, auditable, and consistent. The agent's only job is to understand intent, extract parameters, and dispatch the correct script.

---

### D2 — Dispatcher Pattern (not conversational guide)

**Decision:** The agent's role is: understand intent → extract params → execute script → report result. It does not guide the user through manual steps.

**Reasoning:** The agent has operational knowledge of every ReadyMode workflow. Without explicit constraints, it will share that knowledge conversationally — telling the manager what to click rather than doing it. The dispatcher rewrite (see Incident 1) eliminated this behavior entirely.

---

### D3 — UI Clicks, Not Direct URLs

**Decision:** All navigation happens by clicking links within the dashboard (using `a.dash_link` selectors). Direct URL navigation is only used for a small set of known-safe routes (`/+Team/ManageLicenses`).

**Reasoning:** ReadyMode is a React SPA that bootstraps client-side state from the dashboard. Direct URL navigation skips this bootstrap, leaving the app in an uninitialized state that renders an empty DOM (see Incident 5).

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

**Reasoning:** ReadyMode uses React controlled components. Setting `input.value` directly bypasses React's synthetic event system — the component's state never updates, so the form submits the original empty value (see Incidents 3 & 10).

---

### D5 — Anti-Hallucination Rules (Explicit)

**Decision:** `AGENTS.md` contains explicit prohibitions against fabricating results.

**Key rule:** "If the script output is ambiguous or still running, you must report that honestly. Never fabricate success."

**Reasoning:** LLMs fill silence with plausible-sounding answers. When a script takes longer than expected and the agent sees "Command still running", it will sometimes report success to avoid appearing stuck (see Incident 7). Explicit rules + `yieldMs: 120000` prevent this.

---

### D6 — Confirmation Before Destructive Operations

**Decision:** Any operation that cannot be undone requires an explicit confirmation from the Discord user before executing.

**Reasoning:** Operations like Reset Leads permanently delete queue data. A misunderstood command or a test message from a manager should never trigger irreversible actions without a clear confirmation step.

---

## Server Infrastructure

| Field | Value |
|-------|-------|
| Provider | DigitalOcean |
| IP | 159.89.179.179 |
| OS | Ubuntu 24.04 |
| RAM | 2 GB + 2 GB swap |
| Swap config | `vm.swappiness=10`, `vm.vfs_cache_pressure=50` |

### Ports

| Port | Service | Exposure |
|------|---------|----------|
| 18789 | OpenClaw Gateway | Internal |
| 18792 | OpenClaw secondary | Internal |
| 3000 | Aurora (dashboard) | Internal |
| 5432 | PostgreSQL | Internal |
| 5050 | pgAdmin | Internal |
| 22 | SSH | External |
| 80 | HTTP (Caddy) | External |
| 443 | HTTPS (Caddy) | External |

### systemd Services

| Service | Role |
|---------|------|
| `openclaw-gateway` | Main OpenClaw gateway — receives Discord messages, dispatches to LLM |
| `openclaw-bg-dispatcher` | Background task dispatcher |
| `openclaw-bg-worker` | Background task worker |
| `openclaw-owner-policy` | Owner policy enforcement |
| `aurora` | OpenClaw web dashboard |
| `caddy` | Reverse proxy + automatic TLS |
| `cloudflared` | Cloudflare tunnel (currently runs as root — see Security Audit F-10) |

---

## Workspace File Structure

```
/workspace/
├── AGENTS.md          # Agent behavior: dispatcher pattern, anti-hallucination rules, polling limits
├── SKILL.md           # Operation knowledge: what each script does, params, expected output
├── SOUL.md            # Agent personality and tone guidelines
├── IDENTITY.md        # Agent identity definition
├── _lib.sh            # Shared library: readymode_login(), readymode_logout(), dismiss_blocking_overlays()
├── clear_licenses.sh  # Operation 1: sign out inactive users
├── reset_leads.sh     # Operation 2: reset agent leads queue (blocked)
├── create_user.sh     # Operation 3: create ReadyMode agent account
└── upload_leads.sh    # Operation 4: upload leads CSV to campaign
```

### `_lib.sh` — Shared Functions

| Function | Purpose |
|----------|---------|
| `readymode_login()` | Login via CDP — uses `#login-account`, `#login-password`, `.sign-in` selectors. Applies native value setter for password field. |
| `readymode_logout()` | Logout by appending `?logout=1` to current URL |
| `dismiss_blocking_overlays()` | Scans for known overlay selectors (e.g., `#phone_test_ui` z-index 600) after login and dismisses them. Runs silently if no overlay present. |

---

## OpenClaw Configuration (`openclaw.json`)

| Setting | Value | Reason |
|---------|-------|--------|
| `tools.deny` | `["browser"]` | Force all browser interaction through bash scripts |
| `tools.exec.backgroundMs` | `90000` | Scripts can take 15–45 seconds; 90s gives 2x buffer |
| `yieldMs` | `120000` | Wait up to 2 minutes for script completion before evaluating |

---

## Architecture Improvement Proposal — 3-Layer Memory

**Problem:** All context (global rules, local operation knowledge, script details) is loaded into every agent interaction, inflating context size unnecessarily.

**Proposed solution:** Split into 3 layers:

| Layer | Contents | Loaded when |
|-------|----------|-------------|
| Global | Dispatcher rules, anti-hallucination rules, polling limits, confirmation policy | Always |
| Local | Knowledge for the specific operation being executed | After intent identified |
| Script | Technical details (selectors, CDP patterns) | Only inside the script itself |

**Expected benefit:** ~60% context reduction per interaction. Faster inference, lower cost, more focused agent behavior.

**Status:** Proposal — not yet implemented.
