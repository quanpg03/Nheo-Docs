# Incidents & Lessons Learned

This document covers the technical blockers encountered and resolved during the ReadyMode Bot build. Incidents 1–10 originated in Phase 1; Incident 11 was logged during Phase 3. This is the most valuable institutional knowledge of the project — the next engineer to work on this system should read this before touching anything.

---

## Summary Table

| # | Problem | Category | Fix |
|---|---------|----------|-----|
| 1 | Agent explaining manually instead of executing | Agent behavior | `tools.deny: ["browser"]` + dispatcher rewrite |
| 2 | Wrong login selectors | DOM inspection | Found real selectors: `#login-account`, `#login-password`, `.sign-in` |
| 3 | React ignoring programmatic input | React SPA | Native value setter + `input` event dispatch |
| 4 | Overlay blocking post-login clicks | DOM/UI | `dismiss_blocking_overlays()` in `_lib.sh` |
| 5 | SPA blank DOM on direct URL | React SPA | Always navigate via `a.dash_link` clicks |
| 6 | Server RAM exhaustion | Infrastructure | 2 GB swap + `swappiness=10` + `vfs_cache_pressure=50` |
| 7 | Agent fabricating success | Agent behavior | `yieldMs: 120000` + explicit anti-hallucination rule |
| 8 | Exec timeout too short | Configuration | `tools.exec.backgroundMs: 90000` |
| 9 | Polling spam saturating gateway | Agent behavior | Min 20 s between polls, max 4 polls total |
| 10 | Dynamic `set_pass` field not saving | DOM/form | Dispatch `input` event to trigger `oninput` handler |
| 11 | Droplet rebuild after undocumented SSH port change (2026-05-13) | Operations / access | Restore from snapshot `OpenClow-1777504389728`; add SERVER_ACCESS_RUNBOOK.md; mandate remote-branch persistence before closing issues |

---

## Incident 1 — Agent Was Explaining Steps Manually Instead of Executing

**Symptom:** The agent would respond to a Discord request by writing out step-by-step instructions for the manager to follow manually, instead of running the automation script.

**Root cause:** `AGENTS.md` was written as a conversational assistant prompt. The agent interpreted its knowledge of the operation flows as instructions to share with the user, not as internal context for dispatching.

**Fix:** Added `tools.deny: ["browser"]` to prevent direct browser calls and rewrote `AGENTS.md` entirely using the dispatcher pattern. The agent's role is now defined as: understand intent → extract params → execute script → report result. No explaining, no guiding.

**Lesson:** An agent with operational knowledge will use that knowledge conversationally unless explicitly told it cannot. The constraint must be structural (`tools.deny`), not just instructional.

---

## Incident 2 — Login Selector Incorrect

**Symptom:** Login script failed immediately — could not find the username input field.

**Root cause:** The script used `name='username'` as the selector, which does not exist in ReadyMode's actual HTML.

**Fix:** Inspected the live DOM and found the real selectors: `#login-account` for username, `#login-password` for password, `.sign-in` for the submit button.

**Lesson:** Never assume field selectors from a description or similar platforms. Always inspect the actual DOM of the target environment before writing selectors.

---

## Incident 3 — React Did Not Detect Programmatic Input

**Symptom:** Password field appeared filled during automation but submitted empty. User was created without a password.

**Root cause:** ReadyMode uses React controlled components. Setting `input.value = 'x'` directly bypasses React's synthetic event system — the component's state never updates, so the form submits the original empty value.

**Fix:** Implemented the native value setter pattern:
```javascript
const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
  HTMLInputElement.prototype, 'value'
).set;
nativeInputValueSetter.call(input, value);
input.dispatchEvent(new Event('input', { bubbles: true }));
```

**Lesson:** Any React-heavy SPA will have this issue. Native value setter + `input` event dispatch is the standard fix and must be applied to all controlled input fields.

---

## Incident 4 — Overlay Blocking Clicks After Login

**Symptom:** After a successful login, subsequent clicks on dashboard elements failed silently. Operations would appear to start then stall immediately.

**Root cause:** A modal overlay with `id="phone_test_ui"` and `z-index: 600` was rendering on top of the dashboard after login, intercepting all click events. This overlay is intermittent, making it hard to reproduce.

**Fix:** Created `dismiss_blocking_overlays()` in `_lib.sh`. This function scans for known overlay selectors after login and dismisses them before proceeding. It runs silently if no overlay is present.

**Lesson:** Post-login states in SPAs often include onboarding modals, trial banners, or notification overlays that block interaction. Always build overlay dismissal into the login flow, not as an afterthought.

---

## Incident 5 — SPA Returns Blank DOM on Direct URL Navigation

**Symptom:** Navigating directly to `/+Team/ManageUsers` returned a page with no content — empty DOM, no elements to interact with.

**Root cause:** ReadyMode is a React SPA that bootstraps client-side state from the dashboard. Direct URL navigation skips this bootstrap, leaving the app in an uninitialized state that renders nothing.

**Fix:** All navigation must happen by clicking links within the dashboard (using `a.dash_link` selectors with matching text), exactly as a human user would navigate. Direct URL navigation is only safe for a small number of routes that ReadyMode explicitly supports (e.g., `/+Team/ManageLicenses`).

**Lesson:** For any React/Angular/Vue SPA, assume direct URL navigation will not work. Build navigation flows around UI interactions, not URL manipulation. Document the exceptions where direct navigation does work.

---

## Incident 6 — Server RAM Exhaustion

**Symptom:** `kswapd0` consuming 71% CPU, only 53 MB free RAM, SSH connections timing out, server intermittently unreachable.

**Root cause:** Chrome headless processes for ReadyMode automation are memory-intensive. The server's 2 GB RAM was insufficient without swap configured. Under load, the kernel began thrashing.

**Fix:** Added 2 GB swap file, set `vm.swappiness=10` (prefer RAM, use swap only under pressure), set `vm.vfs_cache_pressure=50` (retain filesystem cache longer). Server has been stable since.

**Lesson:** Budget at least 2x RAM in swap for automation servers running headless Chrome. Tune swappiness aggressively — the default of 60 is too aggressive for a server workload.

---

## Incident 7 — Agent Fabricating Success

**Symptom:** Agent reported "Done! Licenses cleared" to the manager in Discord, but the operation had not actually completed. The script was still running.

**Root cause:** When a script takes longer than the agent's implicit timeout, the agent would see "Command still running" in its context and, lacking explicit instructions, would sometimes fabricate a successful completion to avoid appearing stuck.

**Fix:** Two changes: (1) Set `yieldMs: 120000` to give the agent up to 2 minutes to wait for script completion before evaluating. (2) Added an explicit prohibition in `AGENTS.md`: "If the script output is ambiguous or still running, you must report that honestly. Never fabricate success."

**Lesson:** LLMs will fill silence with plausible-sounding answers. Explicit anti-hallucination rules in the agent prompt are not optional — they are critical for any automation agent where false positives cause real harm.

---

## Incident 8 — Script Execution Timeout Too Short

**Symptom:** Scripts were being terminated after ~10 seconds, mid-execution. Operations would fail partway through — user created but no password set, or login completed but navigation never happened.

**Root cause:** The default `exec` tool timeout in OpenClaw was 10 seconds, which is insufficient for ReadyMode automation. A single login + navigation + form fill can take 15–40 seconds depending on page load times.

**Fix:** Set `tools.exec.backgroundMs: 90000` in `openclaw.json`, giving scripts up to 90 seconds to complete before the exec tool reports timeout.

**Lesson:** Always profile the actual runtime of automation scripts under real network conditions before setting timeouts. Add 2x buffer for production. A script that takes 20 seconds in testing might take 45 under load.

---

## Incident 9 — Agent Polling Spam Saturating the Gateway

**Symptom:** After executing a script, the agent would poll for results every 2–3 seconds, flooding the OpenClaw gateway with requests and causing it to become unresponsive.

**Root cause:** No polling limits were defined. The agent's default behavior was to check for results as frequently as possible.

**Fix:** Added explicit polling rules to `AGENTS.md`: minimum 20 seconds between polls, maximum 4 polls total before reporting timeout to the user.

**Lesson:** Any agentic loop that waits for an async result needs explicit rate-limiting defined upfront. "Poll as fast as possible" is never the right default for production systems.

---

## Incident 10 — Dynamic `set_pass` Field Not Accepting Input

**Symptom:** Password was being set correctly visually during automation (field appeared filled) but was not saving. User was created with no password.

**Root cause:** The password field uses `xname='set_pass'` instead of a standard `name` attribute. This is a dynamic attribute that only gets promoted to `name` when an `oninput` event fires. Without the `oninput` event, the field is never registered by the form and its value is ignored on submit.

**Fix:** After setting the field value using the native value setter, explicitly dispatch an `input` event (not just `change`) to trigger the `oninput` handler that promotes `xname` to `name`:
```javascript
input.dispatchEvent(new Event('input', { bubbles: true }));
```

**Lesson:** Non-standard attribute patterns (`xname`, `data-name`, dynamic `name` promotion) exist in older or custom web apps. When a field value disappears on submit, inspect the form submission payload directly (via CDP Network events) to verify what's actually being sent, rather than relying on visual inspection.

---

## Incident 11 — Droplet Rebuild After Undocumented SSH Port Change (2026-05-13)

**Symptom:** Simultaneous loss of SSH access to the production droplet (`159.89.179.179`) for multiple team members on 2026-05-13. Reconnections to port 22 timed out without any actionable error. The persistent 14-day SSH session that operations had been relying on had expired, masking the underlying configuration drift.

**Root cause:** On 2026-04-29 the SSH daemon was migrated from port 22 to port 22022 as part of NHE-29 hardening, via `/etc/ssh/sshd_config.d/99-hardening.conf`. The change was applied directly to production without a corresponding entry in a shared access runbook and without notifying the operations team. As long as existing SSH sessions stayed alive the change was invisible; once the 14-day persistent session expired, every client still pointing at port 22 was locked out.

**Fix:** Operations performed a destructive droplet rebuild from the most recent DigitalOcean snapshot (`OpenClow-1777504389728`, taken 2026-04-29, 17.09 GB, NYC3) to recover SSH access. The rebuild restored the system to its 2026-04-29 state. Hardening layers (AppArmor profiles, SOPS+age binaries, DNS-over-TLS, sudo allowlist, cloudflared non-root) were re-applied and verified in the post-rebuild audit (2026-05-14). The self-hosted GitHub Actions runner under `/home/agent/actions-runner/` survived on disk but lost its systemd unit and was unregistered from GitHub — it requires re-registration via a fresh registration token.

Side effect: any work persisted only on the droplet filesystem between 2026-04-29 and 2026-05-13 was lost, including artifacts associated with twelve Linear issues that had been marked Done during that window. Those issues are being reopened and the work redone.

**Lesson:** Three independent failures had to align for this incident to occur, and any one of them being addressed in advance would have prevented it:

1. **Access-plane changes must be documented before they ship.** Any change that affects how operators reach production — SSH port, firewall, sudo, AppArmor, key rotation, MFA — must be written into a `SERVER_ACCESS_RUNBOOK.md` checked into Nheo-Docs and announced in the operations channel before the change is applied. Long-lived SSH sessions hide configuration drift; the next disconnect is the deadline.
2. **Closing an issue requires remote persistence.** Code, configuration, or scripts that exist only on a production filesystem are one snapshot rollback away from disappearing. Before marking a Linear issue Done, the corresponding work must be committed and pushed to a remote branch of the project's repository.
3. **Snapshot cadence must be automatic.** Relying on manual, on-demand snapshots makes the recovery window equal to the elapsed time since the last person remembered to take one. A daily automated snapshot policy bounds the worst-case data loss to 24 hours.
