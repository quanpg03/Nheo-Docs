# CLOSRADS — Facebook Ads Geo Sync

**Linear Project:** CLOSRADS Project  
**Engineers:** Juanes and Nat  
**Status as of:** 2026-05-05  
**Last updated:** May 2026 — 4-layer ad protection + HTML email notifications

---

## What It Does in One Sentence

Every day at 8am, it reads which US states need leads from CLOSRTECH for each active campaign, then updates the geographic targeting of every active Facebook adset to match exactly — with a 4-layer protection system that prevents Meta from silently breaking lead form links during the update.

---

## Quick Reference

| Property | Value |
|----------|-------|
| Client | Mike / Charlie (veteran lead generation operation) |
| Active campaigns | Veterans, Mortgage Protection |
| Paused campaigns | Truckers (disabled — see May 2026 notes) |
| CLOSRTECH params | `VND_VETERAN_LEADS`, `VND_TRUCKER_LEADS`, `VND_MORTGAGE_PROTECTION_LEADS` |
| Facebook ad accounts | CLOSRTECH `act_996226848340777` (Veterans + Truckers) / Inbounds `act_1007012848173879` (Mortgage) |
| Language | Python 3.13 |
| Deployment | GitHub Actions — self-hosted runner on Nheo's server (13:00 UTC / 8:00 AM Colombia) |
| Default mode | DRY_RUN=true (safe by default) |
| Notifications | HTML email to Charlie after each sync |

---

## Campaign Configuration

| Campaign | CLOSRTECH param | FB Ad Account | FB Campaign ID(s) | Status |
|----------|----------------|---------------|-------------------|---------|
| Veterans | `VND_VETERAN_LEADS` | `act_996226848340777` | `120238960603460363` | ✅ Active |
| Truckers | `VND_TRUCKER_LEADS` | `act_996226848340777` | `120239404121750363` | ⚠️ Disabled |
| Mortgage | `VND_MORTGAGE_PROTECTION_LEADS` | `act_1007012848173879` | `120245305494410017`, `120241447971000017` | ✅ Active |

**Notes:**

- Veterans and Truckers share the same Facebook ad account and System User token.
- Mortgage lives in a separate Facebook ad account (Inbounds) — the same System User token has access to both accounts.
- Mortgage has two Facebook campaign IDs — the script pulls adsets from both, combines them, and applies the same demand.
- **Truckers is commented out in `config.py`.** It can be re-enabled once the 4-layer protection is confirmed to fully resolve the lead form link issue. See May 2026 Updates below.

---

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|--------|
| facebook-business | 25.0.1 | Official Meta SDK for Graph API |
| requests | 2.32.3 | HTTP calls to CLOSRTECH API |
| tenacity | 9.1.2 | Automatic retry with exponential backoff |
| python-dotenv | 1.1.0 | Load credentials from .env file |
| pytest | 8.3.5 | Test runner |
| pytest-mock | 3.14.0 | Mocking for offline tests |

---

## Current Status

| Item | Status | Notes |
|------|--------|-------|
| Veterans automation | ✅ LIVE | Running since 2026-04-21 |
| Mortgage automation | ✅ LIVE | Running with 4-layer protection since May 2026 |
| Truckers automation | ⚠️ Disabled | Commented in config — lead form issue pending confirmation |
| 4-layer ad protection system | ✅ Implemented | May 2026 — prevents Meta from breaking lead form links |
| HTML email notifications to Charlie | ✅ Implemented | May 2026 — replaces Slack |
| Hardcoded email credentials | ✅ Fixed | May 2026 — Charlie's email removed from source code |
| Offline test suite (18 tests) | ✅ Passing | After multi-campaign refactor |
| System User FB token | ✅ Resolved | Obtained May 2026 |
| IP whitelist for GitHub Actions | ✅ Resolved | Self-hosted runner on Nheo's server |
| GitHub Secrets (per-campaign naming) | ✅ Configured | All 15 + 3 new email secrets |
| `devlop` → `main` merge | ✅ Done | Multi-campaign code live |
| orders.php integration | ⏭️ Deferred to v2 | Endpoint returns 404 for Veterans — not tested for others |

---

## May 2026 Updates

### 1. 4-Layer Ad Protection System

**The problem:** When the automation updated geo targeting via API, Meta triggered an internal re-validation of all child ads in the adset. Ads using lead forms (instant forms) were especially vulnerable — Meta silently broke the link between the ad and the form, causing **error #3390001** and pausing the ad without warning. This was confirmed in the Truckers campaign and at least one Mortgage adset.

**The new flow protects every adset update with 4 ordered layers:**

| Layer | Name | What it does |
|-------|------|-------------|
| 1 | Pre-flight check | Before touching anything: checks if any ad in the adset already has active issues. If yes — skips that adset entirely that day and flags it for manual review. Rationale: don’t make a broken adset worse. |
| 2 | Cascade republish | Immediately after updating geo targeting: sends a `status=ACTIVE` signal to every active ad in the adset. This explicitly tells Meta’s servers that the ad is still valid with the new targeting and to confirm the lead form link. Without this, Meta leaves the link in a pending state and eventually pauses the ad. Confirmed by Meta support. Applied to all campaigns as a precaution. |
| 3 | Post-republish verification | Waits 3 seconds for Meta to process the republish, then queries all ad statuses. If all are healthy, done. If any still have issues, proceeds to Layer 4. |
| 4 | Automatic rollback | If verification finds broken ads after cascade republish: restores the geo targeting to its exact pre-update state. The adset is left as if it was never modified. Worst case is “not updated today” — never “left in a worse state than before.” |

### 2. HTML Email Notifications to Charlie

Replaced Slack notifications with an HTML email sent to Charlie automatically after each sync.

**Email contents:**

- Per-campaign summary: adsets updated / unchanged / with issues / reverted
- **Orange box:** adsets skipped by the pre-flight check (pre-existing broken ads) — includes ad name and error description
- **Red box:** adsets that were reverted after the update triggered broken ads — explains what happened and confirms targeting was restored
- **Green box:** all campaigns ran cleanly
- Full list of active CLOSRTECH states for that day

If email credentials are not configured, the system logs to stdout and continues normally without failing.

### 3. Credential Security Fix

Charlie’s email address was previously hardcoded in the source code as a default value. Anyone who cloned the repo and ran the script could inadvertently send emails to Charlie. The hardcoded value was removed — all email credentials now live exclusively in environment variables.

**Three new required env vars (when using email notifications):**

| Variable | Purpose |
|----------|--------|
| `SENDER_EMAIL` | Gmail address used to send notifications |
| `SENDER_EMAIL_APP_PASSWORD` | Gmail App Password (not the regular account password) |
| `NOTIFY_EMAIL` | Destination email address |

---

## Dry-Run Results

### April 25-26, 2026 — Multi-campaign dry-run

**CLOSRTECH side — fully working for all 3 campaigns:**

| Campaign | Active states | Demand total |
|----------|--------------|-------------|
| Veterans | 34 states | 122 |
| Truckers | 9 states | 12 |
| Mortgage | 30 states | 23,960 |

**Facebook side — failed for all 3** with the same error:

```
Session has expired on Tuesday, 21-Apr-26 09:00:00 PDT
```

**Root cause:** The token was a personal session token tied to Mike’s account. When the session expired April 21, the token died for all campaigns simultaneously. A System User token was obtained in May 2026 and this is no longer an issue.

### April 15, 2026 — Original Veterans dry-run (local)

| Metric | Result |
|--------|--------|
| Active states from CLOSRTECH | 35 |
| Active adsets found | 5 |
| Adsets that would have been updated | 5/5 |
| Errors | 0 |

**Active adsets:**

- `120243386906050363` — BROAD - Copy 2
- `120243287242520363` — BROAD - Copy 2
- `120243238391470363` — BROAD - Copy 2
- `120243079782840363` — BROAD - OLDER ORDERS URGENT
- `120240834861880363` — BROAD - Copy

---

## Background & Problem

### The Manual Process Before CLOSRADS

Mike runs a veteran lead generation operation in the USA. His business depends on buying leads through Facebook Ads, but not all US states need leads every day — demand shifts based on orders placed through CLOSRTECH, a platform his clients use to signal which states they need covered.

The daily routine before this automation existed:

1. Someone opens CLOSRTECH and reads which states have active demand
2. They open Facebook Ads Manager
3. They navigate to each active adset in the campaign
4. They manually edit the geographic targeting of each adset to match the states from CLOSRTECH
5. They repeat for every active adset across all campaigns

This took **20 to 40 minutes every day**. It was error-prone, required someone available every morning, and had no fallback.

### The Two Systems

**CLOSRTECH** exposes a `demand.php` endpoint that returns a JSON dict of states and quantities. Only known IPs can call the API (IP whitelist) — resolved using Nheo’s self-hosted GitHub Actions runner.

**Facebook Graph API** — The script uses the `facebook-business` Python SDK (v25.0.1) to list active adsets, read their current targeting, compare against CLOSRTECH demand, and update only if there’s a difference. Geo targeting updates can trigger Meta’s re-validation of child ads — this is what the 4-layer protection was built to handle.

### The Critical Fail-Safe

If CLOSRTECH returns a non-empty response where every state has `demand == 0`, the script treats this as an error. It raises `ClosrtechDataError` and aborts immediately — Facebook is never touched. This prevents a CLOSRTECH bug from zeroing out all of Mike’s advertising.

### What the Automation Changed

| Before | After |
|--------|-------|
| 20–40 min manual work daily per campaign | ~30 seconds automated for all active campaigns |
| Human must be available every morning | Runs at 8am regardless |
| Errors from copy-paste or forgetting a state | Exact sync from CLOSRTECH data |
| No audit trail | Full log in GitHub Actions + HTML email to Charlie |
| If person unavailable, nothing runs | Automatic with failure alerts |

---

## Documentation

| File | Contents |
|------|----------|
| [`architecture.md`](./architecture.md) | Data flow, file structure, layer separation, secrets architecture, execution sequence |
| [`module-reference.md`](./module-reference.md) | Detailed docs for all modules including 4-layer protection functions |
| [`github-actions.md`](./github-actions.md) | Workflow YAML, trigger config, all 18 secrets, IP whitelist solution |
| [`tests.md`](./tests.md) | 18 tests, offline strategy, conftest, fixtures |
| [`activation-plan.md`](./activation-plan.md) | Phase 1 (complete) and Phase 2 multi-campaign steps |
| [`design-decisions.md`](./design-decisions.md) | D01–D15: every significant architectural decision |
| [`changelog.md`](./changelog.md) | Session logs with full context including failures |
