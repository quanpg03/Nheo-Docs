# Incidents & Lessons Learned

This document covers the technical blockers encountered and resolved during the ReadyMode Bot build. Incidents 1–10 originated in Phase 1 (bash + CDP prototype); Incident 11 was logged during Phase 3 (server recovery); Incidents 12–17 were logged during the August 2026 multi-tenant operational sessions. This is the most valuable institutional knowledge of the project — the next engineer to work on this system should read this before touching anything.

---

## Summary Table

| # | Problem | Category | Fix |
|---|---------|----------|-----|
| 1 | Agent explaining manually instead of executing | Agent behavior | `tools.deny: ["browser"]` + dispatcher rewrite |
| 2 | Wrong login selectors | DOM inspection | Found real selectors: `#login-account`, `#login-password`, `.sign-in` |
| 3 | React ignoring programmatic input | React SPA | Native value setter + `input` event dispatch |
| 4 | Overlay blocking post-login clicks | DOM/UI | `dismiss_blocking_overlays()` |
| 5 | SPA blank DOM on direct URL | React SPA | Always navigate via `a.dash_link` clicks |
| 6 | Server RAM exhaustion | Infrastructure | 2 GB swap + `swappiness=10` + `vfs_cache_pressure=50` |
| 7 | Agent fabricating success | Agent behavior | `yieldMs: 120000` + explicit anti-hallucination rule |
| 8 | Exec timeout too short | Configuration | `tools.exec.backgroundMs: 90000` |
| 9 | Polling spam saturating gateway | Agent behavior | Min 20 s between polls, max 4 polls total |
| 10 | Dynamic `set_pass` field not saving | DOM/form | Dispatch `input` event to trigger `oninput` handler |
| 11 | Droplet rebuild after undocumented SSH port change | Operations / access | Restore from snapshot; add SERVER_ACCESS_RUNBOOK.md |
| 12 | Login form does not validate result | Executor logic | Explicit post-login DOM check before proceeding |
| 13 | Ticket channels returning 403 | Discord permissions | Add bot as Support role in ticket panel, not server-wide |
| 14 | Messaging bridge down 39 hours (5th outage in 3 weeks) | Infrastructure | Manage bridge as systemd service with Restart=always |
| 15 | `sandbox not found` when renaming running container | Docker | Stop container before renaming |
| 16 | Queue list empty due to async render (race condition) | Playwright / DOM | 6-retry loop with 500 ms waits |
| 17 | Queue traversal stops at first populated queue + veto logic gap | Playwright / logic | Traverse all queues; veto catalog write on incomplete sweep |

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

**Fix:** Created `dismiss_blocking_overlays()`. This function scans for known overlay selectors after login and dismisses them before proceeding. It runs silently if no overlay is present.

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

---

## Incident 12 — Login Form Does Not Validate Result (2026-08-03)

**Symptom:** During the setup of the `iul` account, the bot reported the container as connected and operational when it was not. The login flow completed without error, but the agent was not actually authenticated in ReadyMode.

**Root cause:** The login executor submitted credentials and waited for the page transition to complete, but did not check whether the post-login page was the authenticated dashboard or a redirect back to the login form (which ReadyMode returns on bad credentials). Because both pages load successfully from a Playwright perspective, there was no exception to catch.

**The specific trigger:** The `iul` account was initially configured with unified service account credentials that ReadyMode rejected silently — it redirected to the login page without displaying an error message.

**Fix:** After the login flow completes, all executors must check for a known post-login DOM indicator (e.g. the presence of `a.dash_link` navigation elements) before proceeding. If the indicator is absent, the executor returns `{ success: false, error: "Login failed or credentials rejected" }` immediately.

**Lesson:** Never assume a page transition equals a successful authentication. Verify the post-login state explicitly. ReadyMode does not always display an error on bad credentials — it may simply redirect.

---

## Incident 13 — Ticket Channels Returning 403 (2026-08-05)

**Symptom:** Three bots (ascenti, missedinbound, iul) configured to respond in Discord ticket channels were returning 403 errors when attempting to read or post in those channels. The bots were operating correctly in non-ticket channels.

**Root cause:** The Discord ticket system (likely Ticket Tool or similar) isolates ticket channels at the category level and manages access through a Support role that is granted within the ticket panel itself, not through a server-wide role. The bots had been added with a server-wide role, which the ticket system did not recognize as having access to ticket channels.

**Fix:** For each brand's Discord server, the bot application was added as a Support role within the ticket panel's role configuration — not as a server-wide permission. After this change, all three bots could read and post in ticket channels correctly.

**Lesson:** Discord ticket bots manage permissions outside the standard server role hierarchy. When a bot needs ticket channel access, add it within the ticket panel's own role settings, not through server-level role assignment. Verify with a test ticket after configuration.

---

## Incident 14 — Messaging Bridge Down 39 Hours — 5th Outage in 3 Weeks (2026-08-05)

**Symptom:** The messaging bridge (which maintains the 14 active messaging sessions across the fleet) went offline and was not detected for 39 hours. This was the 5th such outage in a 3-week period.

**Root cause:** The messaging bridge was running as a standalone process with no watchdog or automatic restart mechanism. When the process crashed, it stayed down until someone manually noticed the messaging sessions were missing and restarted it.

**Impact:** 39 hours of messaging downtime affected all 14 accounts using the messaging system.

**Fix required (not yet implemented):** Manage the messaging bridge as a systemd service with `Restart=always` and `RestartSec=10`, matching the pattern already used for the bot containers. This would limit each outage to the restart delay (10 seconds) rather than the time until someone notices.

**Lesson:** Any process that needs to stay up must be managed by a process supervisor. Running it manually or with a startup script is not sufficient for production. If the bot containers can restart automatically, the messaging bridge should too.

See [Gap G-NEW-01](./gap-analysis-roadmap.md) for the open item.

---

## Incident 15 — `sandbox not found` When Renaming a Running Container (2026-08-05)

**Symptom:** When attempting to rename a Docker container while it was running (to correct a naming inconsistency), the container threw a `sandbox not found` error and became unresponsive.

**Root cause:** Docker's internal networking sandbox is identified by the container name at creation time. Renaming a running container does not update the sandbox reference, leaving the container in a state where its network sandbox cannot be found.

**Fix:** Stop the container before renaming it, then restart it under the new name. The sequence is: `docker stop <name>` → `docker rename <name> <new-name>` → `systemctl start readymode-<new-name>`.

**Lesson:** Never rename a running Docker container. The operation appears to succeed at the Docker level but breaks the container's network stack. Always stop first.

---

## Incident 16 — Queue List Empty Due to Async Rendering (Race Condition) (2026-08-06)

**Symptom:** The queue discovery routine was returning empty results for accounts that visibly had queues in ReadyMode. Affected accounts showed zero queue links in the catalog even though queues existed.

**Root cause:** ReadyMode renders queue list items asynchronously after the page navigation completes. The executor was reading queue elements immediately after `wait_for_load_state("networkidle")`, at which point the queue DOM had not yet been injected. The read returned an empty list, which was treated as "no queues found."

**Fix:** Replaced the single read with a 6-attempt retry loop with 500 ms waits between attempts:

```python
queues = []
for _ in range(6):
    queues = await page.query_selector_all(".queue-item")
    if queues:
        break
    await asyncio.sleep(0.5)
```

If all 6 attempts return empty, the executor logs a warning and aborts the sweep for that account (rather than writing an empty catalog).

**Lesson:** `wait_for_load_state("networkidle")` does not guarantee that all asynchronously rendered content is present. For dynamically injected lists, always add a retry loop with a reasonable wait. Do not treat "element not found" as "element does not exist" without retrying.

---

## Incident 17 — Queue Traversal Stops at First Populated Queue + Veto Logic Gap (2026-08-06)

**Symptom:** Two related bugs discovered during the Aug 6 queue discovery session:

1. The queue traversal loop stopped processing as soon as it found the first queue that contained at least one list. Subsequent queues were never read, producing an incomplete catalog.
2. The veto check (which was supposed to prevent writing a catalog if the sweep was incomplete) only evaluated queues that had returned at least one name. Queues that failed silently during the sweep (returned no name) were not counted as failures, so the veto was never triggered even when the sweep was incomplete.

**Root cause:** The traversal loop had an early-exit condition (`break` on first hit) that was intended to short-circuit when the target was found for a lookup operation, but was incorrectly applied to the catalog-building sweep. The veto logic had a related assumption: it iterated over queues that had names, rather than over all queues that were attempted.

**Fix:**

1. Removed the early-exit from the catalog sweep. The loop now runs through all discovered queues regardless of whether earlier ones had content.
2. Rewrote the veto check to count all attempted queues, not just those that returned names. If any attempted queue fails to return a result (empty or error), the catalog write is vetoed.

**Test coverage:** 357 tests before → 382 tests after, all green.

**Lesson:** Sweep and lookup are different operations. A loop built for lookup (exit when found) is wrong for a sweep (must visit everything). Review loop termination conditions carefully when repurposing existing traversal code. Veto logic must be based on what was attempted, not what was found.
