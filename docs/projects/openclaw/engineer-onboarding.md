# Engineer Onboarding

For a new engineer joining OpenClaw on day 1. Goal: ship a feature without breaking prod and without the agent hallucinating success.

Read [`overview.md`](./overview.md), [`architecture.md`](./architecture.md), and [`incidents.md`](./incidents.md) first. This doc is the engineer-facing companion — fewer "why we built it", more "how do I add a thing".

---

## 1. Mental Model in 60 Seconds

```
Discord  →  Gateway (LLM, gpt-4.1-mini)  →  bash script  →  ReadyMode (UI clicks)
                ^                                 |
                |________ JSON result ____________|
```

Three layers, with a strict separation of concerns:

| Layer | What it does | What it does NOT do |
|-------|--------------|----------------------|
| Agent LLM | Parse intent, extract params, dispatch to script, parse JSON, reply in ES/EN | Touch the browser, explain UI steps, improvise selectors |
| Bash script (`_lib.sh` + `*.sh`) | Drive Chrome via CDP: login, navigate, fill forms, submit, log out | Talk to Discord, decide intent, format user-facing prose |
| OpenClaw runtime | Run scripts (`tools.exec`), enforce `tools.deny`, enforce `yieldMs`, route Discord ↔ agent | Anything domain-specific |

If you find yourself reaching across boundaries (e.g. agent quoting selectors, or a script writing to Discord), stop — that's the wrong layer.

---

## 2. The Six Rules That Define This System

### Rule 1 — `tools.deny: ["browser"]` is non-negotiable

Configured in `openclaw.json`:

```json
{
  "tools": {
    "deny": ["browser"],
    "exec": { "backgroundMs": 90000 }
  },
  "yieldMs": 120000
}
```

Why: the agent kept opening the browser tool itself and then *narrating* manual steps to managers in Discord instead of running the script. Removing the tool from its toolbox is the only fix that holds. See [Incident 1](./incidents.md).

If you ever see a PR that loosens this, it's wrong. Browser interaction belongs in scripts only.

---

### Rule 2 — Navigate by clicking `a.dash_link`, not by URL

ReadyMode is a React SPA. Direct URL navigation (e.g. `/+Team/ManageUsers`) returns a blank DOM because the client-side state never bootstraps. You will see no error — just nothing on the page.

**Pattern (used in every operation):**

```javascript
// Inside the CDP eval — find the dashboard link by text and click it
const link = [...document.querySelectorAll('a.dash_link')]
  .find(a => a.textContent.trim().toLowerCase() === 'users');
if (!link) throw new Error('dash_link "Users" not found');
link.click();
```

**Exceptions** (the small set of routes that DO work direct):

| Route | Used by |
|-------|---------|
| `/+Team/ManageLicenses` | `clear_licenses.sh` |

Default to clicking. Add a route to the exceptions table here if you discover another that survives direct nav — and only after manual verification.

> **Common pitfall:** "It works on my machine" — you logged in manually, then ran the script which went direct-URL. The DOM was warm because of your prior session. In headless, it isn't. Always test from a cold browser.

See [Incident 5](./incidents.md).

---

### Rule 3 — Native value setter for every React `<input>`

Setting `input.value = 'foo'` on a React controlled component does **not** trigger React's synthetic event system. The field looks filled, the form submits empty, the user is created without a password. We hit this twice.

**The pattern:**

```javascript
const setNativeValue = (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype, 'value'
  ).set;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
};
```

This lives in `_lib.sh`'s `readymode_login()` and is reused by `create_user.sh` for `u_name`, `u_account`, and `set_pass`. **Always use it for inputs.** If a textarea, swap the prototype:

```javascript
Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
```

> **Common pitfall — dynamic `xname` attributes.** ReadyMode's `set_pass` field uses `xname="set_pass"` and only promotes to `name="set_pass"` after the `oninput` handler fires. If you skip the `dispatchEvent('input')`, the field literally isn't part of the form on submit. See [Incident 10](./incidents.md).

---

### Rule 4 — Anti-hallucination: never fabricate success

Two mechanical guards plus one prompt rule:

| Guard | Where | Why |
|-------|-------|-----|
| `yieldMs: 120000` | `openclaw.json` | Give the script 2 minutes to actually finish before the LLM evaluates output |
| `tools.exec.backgroundMs: 90000` | `openclaw.json` | Don't kill the script at 10 s (the default) |
| Polling: min 20 s, max 4 polls | `AGENTS.md` | Stop the LLM from spamming the gateway |
| Explicit prompt rule | `AGENTS.md` | "If the script output is ambiguous or still running, you must report that honestly. Never fabricate success." |

**Script contract (every script must honor):**

```bash
# stdout: ONE single-line JSON, nothing else
echo '{"success": true,  "message": "Licenses cleared. 7 users signed out."}'
echo '{"success": false, "message": "Login failed: bad credentials."}'
echo '{"success": false, "unavailable": true, "message": "Office Map empty."}'  # exit 2
```

If the script can't determine success, return `success: false` with a precise message. Do not guess. The LLM is instructed to surface that verbatim.

See [Incident 7](./incidents.md) and [Incident 9](./incidents.md).

---

### Rule 5 — Confirm before destructive ops

Clear Licenses, Reset Leads, and anything that touches multiple agents must prompt the manager with **"Confirmas?"** before firing. This rule lives in `AGENTS.md` and the agent enforces it from context — but if you're adding a destructive operation, mirror the existing confirmation flow rather than skipping it. A single accidental Reset Leads is irreversible queue loss.

---

### Rule 6 — The agent does not know DOM. The scripts do not know Discord.

Concrete check before merging:
- Does your change put a CSS selector or a "click X then Y" instruction inside `AGENTS.md`, `SKILL.md`, `OPERATIONS.md`, or `KNOWLEDGE.md`? → Move it to the script.
- Does your change put a Discord message string inside a `.sh` file? → Move it to the agent prompt.

The 3-layer memory proposal in [`architecture.md`](./architecture.md) makes this physical, but the principle holds today.

---

## 3. Adding a New Command — End to End

Suppose you're adding `pause_campaign` (a new operation triggered by `"Pausa la campaña X"`). Six steps:

### Step 1 — Inspect the real DOM first

Before writing any script:
1. Open ReadyMode in a normal browser, manually perform the operation, and watch DevTools.
2. Note the **exact** dashboard link text (`a.dash_link` content) for the entry navigation.
3. Identify selectors for every input, button, and confirmation dialog.
4. Check the network tab — is there a direct `POST` you could call instead of clicking? (Sometimes yes, see `upload_leads.sh`'s `fetch + FormData` to `/AI Leads/upload/index.php`.)

Do not start coding selectors from documentation or screenshots alone. ReadyMode's per-tenant DOM differs.

### Step 2 — Write the script

Create `pause_campaign.sh` next to the others. Skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

CAMPAIGN_NAME="${1:-}"
[[ -z "$CAMPAIGN_NAME" ]] && {
  echo '{"success": false, "message": "Missing campaign name."}'
  exit 1
}

readymode_login || { echo '{"success": false, "message": "Login failed."}'; exit 1; }
dismiss_blocking_overlays

# Click into Campaigns via dash_link — never direct URL
cdp_eval "
  const link = [...document.querySelectorAll('a.dash_link')]
    .find(a => a.textContent.trim().toLowerCase() === 'campaigns');
  if (!link) throw new Error('campaigns dash_link not found');
  link.click();
"

# ... operation-specific clicks, with native value setter for any inputs ...

readymode_logout
echo '{"success": true, "message": "Campaign paused: '"$CAMPAIGN_NAME"'."}'
```

Rules to follow:
- Single-line JSON to stdout. No prose, no progress logs to stdout (use stderr if needed).
- Always `dismiss_blocking_overlays` after login.
- Always `readymode_logout` at the end (even on failure paths where you've reached the dashboard).
- `set -euo pipefail`. Every script. Always.

### Step 3 — Register the command

Add a row to the decision table in `SKILL.md` (or `OPERATIONS.md` if the 3-layer refactor has landed). Include:
- Trigger phrases in ES and EN.
- Required parameters.
- Whether confirmation is required.
- The exact `exec` command the agent should run.

Example row:

```
| Pause Campaign | "pausa la campaña X" / "pause campaign X" | campaign_name | yes | exec pause_campaign.sh "$campaign_name" |
```

### Step 4 — Update behavioral rules if needed

If the operation introduces a new pattern (e.g. multi-step confirmation, special error handling), add the minimum rule to `AGENTS.md`. Keep it under 5 lines. Do not paste DOM details there.

### Step 5 — Test against a non-prod tenant

See section 4 below. **Do not test against `arpagrowth.readymode.com` directly.** A misfire pauses real campaigns for a paying client.

### Step 6 — Ship behind manual confirmation on first deploy

For the first week of a new operation, hard-require `"Confirmas?"` even if the operation isn't destructive. It catches false-positive intent matches before they cost anything.

---

## 4. Local Dev — Testing Without Hitting Production

The bot runs against `arpagrowth.readymode.com`. **Do not test new scripts against that URL.** Options, in order of preference:

### Option A — Dedicated ReadyMode sandbox tenant (preferred)

If/when [G12](./gap-analysis-roadmap.md) (dedicated bot account) lands and a sandbox tenant exists, point `READYMODE_URL` at it via env var. The credentials live in SOPS (see `docs/projects/openclaw/secrets/`).

### Option B — Mock the CDP layer

For pure logic changes (parameter parsing, JSON shape, confirmation flow), the script's CDP calls can be stubbed:

```bash
# In a test script
export OPENCLAW_DRY_RUN=1
./pause_campaign.sh "TestCampaign"
# The _lib.sh wrappers should short-circuit when this is set, returning canned DOM responses.
```

If `_lib.sh` doesn't yet honor `OPENCLAW_DRY_RUN`, add the support — it's a small, low-risk change and pays back the first time you need to debug locally without a tenant.

### Option C — Run against a captured ReadyMode HTML snapshot

For DOM-only experiments (selector hunting, native value setter behavior), save the post-login dashboard HTML, serve it locally with `python -m http.server`, and point Chrome at `http://localhost:8000`. Form submits won't work but selectors and React patterns will.

### Hard rules — never do these in dev

| Don't | Why |
|-------|-----|
| Run new scripts against `arpagrowth.readymode.com` | Real campaigns, real agents, real consequences |
| Reuse the production manager Discord account for testing | Bot/human session collision; logging in kicks the bot offline |
| `ssh miguel@159.89.179.179` and edit scripts in place | Production. Edit in the repo, deploy via the normal flow |
| Reboot or restart `openclaw-*.service` without explicit user approval | The bot is live for Arpa Growth |

The ReadyMode session collision (bot and manager share the `manager` account) is a known problem — see [G22 / NHE-56](./gap-analysis-roadmap.md). Until a dedicated bot account exists, any human login kicks the bot. Plan around it.

---

## 5. Common Pitfalls

A grab-bag of things that have actually happened.

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Direct URL nav for "just this one route" | Blank DOM, script hangs at next selector | Click `a.dash_link` instead; document the exception if it really does work |
| `input.value = 'x'` | Field looks filled, form submits empty, no error | Native value setter + `dispatchEvent('input')` |
| Returning `{"success": true}` because you "saw the click happen" | Agent reports done, but ReadyMode rejected the submit | Verify final state (e.g. row count, member count) and report that |
| Forgetting `dismiss_blocking_overlays` after login | Subsequent clicks silently swallowed by `#phone_test_ui` modal (z-index 600) | Always call it post-login, even if you didn't see the overlay locally |
| Multi-line script output | LLM can't parse JSON, fabricates a guess | Single-line JSON to stdout, everything else to stderr |
| Polling the gateway in tight loop | Gateway becomes unresponsive | 20 s min between polls, 4 polls max |
| Writing tests against prod | One typo, real damage | See section 4 |

---

## 6. What to Read Next

In order:

1. [`overview.md`](./overview.md) — Client context and the 4 operations.
2. [`architecture.md`](./architecture.md) — The decisions D1–D6 and why.
3. [`incidents.md`](./incidents.md) — All 10 lessons learned. Read every one before touching anything.
4. [`operations.md`](./operations.md) — Per-operation status and selector specifics.
5. [`support-playbook.md`](./support-playbook.md) — Conversational scenarios.
6. [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) — What's still TODO and why.
7. [`security-audit.md`](./security-audit.md) — Server posture and what NOT to touch.

If you read those and still have questions, the answer probably belongs in this doc — open a PR.
