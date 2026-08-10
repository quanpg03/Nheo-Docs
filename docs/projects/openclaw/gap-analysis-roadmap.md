# Gap Analysis & Roadmap

**Updated:** 2026-08-06

---

## Historical Gaps (G01–G13) — Status After v2 Rebuild

The original gap analysis was written on 2026-04-16 when the system was a bash + CDP prototype with a single client (Arpa Growth). The system was fully rebuilt in June 2026 as Python + Playwright + Claude Haiku (multi-tenant). Most original gaps are now closed or deprecated.

| ID | Original gap | Status |
|----|---|---|
| G01 | Create User: create playlist | ✅ Resolved — `executors/create_user.py` handles full playlist creation |
| G02 | Create User: drag-and-drop campaigns | ✅ Resolved — Python executor handles this |
| G03 | Create User: drag-and-drop states | ✅ Resolved |
| G04 | Create User: assign user to playlist + verify | ✅ Resolved |
| G05 | Reset Leads | ✅ Resolved — `executors/reset_leads.py` implemented; no longer blocked by Office Map |
| G06 | Upload Leads: non-standard CSV headers | ⬜ Deprecated — Upload Leads not in v2 scope |
| G07 | Upload Leads: create new campaign | ⬜ Deprecated |
| G08 | Upload Leads: merge duplicates | ⬜ Deprecated |
| G09 | Upload Leads: accept duplicates | ⬜ Deprecated |
| G10 | Upload Leads: search + move leads | ⬜ Deprecated |
| G11 | Call results automation | ⬜ Deprecated — not in v2 scope |
| G12 | Dedicated bot account | ✅ Resolved — each agency has its own ReadyMode service account |
| G13 | Create User: additional fields (AMD, Dialing Rate) | ⬜ Not confirmed as required for v2 |

---

## Active Gaps (as of 2026-08-06)

### G-NEW-01 — Messaging Bridge Stability

**Priority: 🔴 HIGH**

The messaging bridge has gone down 5 times in 3 weeks. Each outage requires manual intervention to restore 14 messaging sessions. One outage lasted 39 hours before it was noticed.

**Fix:** Manage the messaging bridge as a systemd service with `Restart=always` and `RestartSec=10` — the same pattern already used for the bot containers.

**Effort:** 0.5 days. No external blocker.

---

### G-NEW-02 — Login Result Not Validated

**Priority: 🟠 MEDIUM**

Executors do not explicitly verify that login succeeded. A wrong redirect or silently rejected credential causes the executor to proceed in a "logged in but not really" state, and all subsequent selectors fail.

**Root cause discovered:** During iul account setup (2026-08-03), a credential issue caused the login form to redirect without authenticating. The executor did not detect this.

**Fix:** After the login flow completes, check for a known post-login DOM element (e.g. presence of `a.dash_link`) before proceeding. Return `{ success: false }` immediately if not found.

**Effort:** 0.5 days. No external blocker.

---

### G-NEW-03 — Name Association Ceiling at 60%

**Priority: 🟠 MEDIUM**

The system that maps Discord usernames to ReadyMode agent names currently resolves approximately 60% of active messaging identities. The remaining 40% cannot be matched through name patterns alone (nicknames, abbreviations, different casing).

**Fix options:**

- Add "ask when unknown" behavior: when a username cannot be resolved, the bot asks the agent to confirm their ReadyMode name and saves the correspondence.
- Add a manual admin command to associate a Discord username with a ReadyMode name.
- Add validation on save: currently 22 rows contain order text in the name field; reject non-name values.

**Effort:** 2–3 days. No external blocker.

---

### G-NEW-04 — Instrumentation of "Not Found" Failures

**Priority: 🟡 MEDIUM**

When an operation fails because a user or list is not found, the failure is logged but there is no structured metric or alert. On 2026-08-05, 68 such failures occurred (51 user not found, 17 list not found) before anyone noticed. The failure rate dropped from 10.1% to 2.5% after a name correction was deployed.

**Fix:** Emit a structured metric (CloudWatch custom metric or Sentry event) for each `not found` failure, tagged by account and failure type. Alert when the rate exceeds a threshold over a 1-hour window.

**Effort:** 1 day. No external blocker.

---

### G-NEW-05 — 4 Accounts with No Queue Links

**Priority: 🟡 MEDIUM**

During the 2026-08-06 queue discovery sweep, 4 accounts returned zero queue links. These accounts cannot route leads through the queue system.

**Action required:** Inspect each account's ReadyMode panel to determine whether queues exist and if so why discovery fails. May require client-side queue configuration.

**Effort:** 0.5–1 day investigation per account. Requires client panel access.

---

### G-NEW-06 — 6 Unmounted Accounts

**Priority: 🟡 MEDIUM**

Six accounts are known but not yet mounted: breaddialer, pioneerunited, ssps, astro, merchantfinancial, unityfinancial.

**Blocker:** Client action required — credentials, Discord server invites, and dialer URLs.

**Effort:** ~0.5 days per account once client provides info.

---

### G-NEW-07 — Hooper and Surf: Empty Inventory

**Priority: 🟡 LOW** (pending client action)

Both accounts were mounted on 2026-08-05 but show 0 lists and 0 campaigns. Their ReadyMode dialers have not been populated by the clients.

**Action required:** Follow up with Hooper and Surf clients.

---

### G-NEW-08 — Account O: Different Codebase

**Priority: ⚪ LOW**

One account runs a different version of the codebase and does not participate in the messaging session system. It requires a separate delivery channel for messaging features.

**Effort:** TBD — assess scope after understanding divergence from `main`.

---

### G-NEW-09 — 3 Dialers Rejecting Unified Service Account

**Priority: ⚪ LOW**

Three ReadyMode dialers do not accept the unified service account credentials, requiring per-dialer individual credentials.

**Action required:** Coordinate with clients to provide correct credentials.

---

## Open Roadmap

| Priority | Gap | Effort | Blocker |
|---|---|---|---|
| 🔴 HIGH | G-NEW-01: Messaging bridge stability | 0.5 days | None |
| 🟠 MEDIUM | G-NEW-02: Login result validation | 0.5 days | None |
| 🟠 MEDIUM | G-NEW-03: Name association ceiling (60%) | 2–3 days | None |
| 🟡 MEDIUM | G-NEW-04: Not found failure instrumentation | 1 day | None |
| 🟡 MEDIUM | G-NEW-05: 4 accounts with no queue links | 0.5–1 day/acct | Client panel access |
| 🟡 MEDIUM | G-NEW-06: 6 unmounted accounts | 0.5 days/acct | Client credentials |
| 🟡 LOW | G-NEW-07: Hooper + Surf empty inventory | N/A | Client populates dialers |
| ⚪ LOW | G-NEW-08: Account O codebase divergence | TBD | Investigation |
| ⚪ LOW | G-NEW-09: 3 dialers rejecting service account | N/A | Client coordination |
