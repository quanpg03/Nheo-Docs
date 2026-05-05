# CLOSRADS — Facebook Ads Geo Sync

**Linear Project:** CLOSRADS Project  
**Engineers:** Juanes and Nat  
**Status as of:** 2026-04-26  
**Last dry-run:** 2026-04-25 (multi-campaign — CLOSRTECH ✅, Facebook ❌ expired token)

---

## What It Does in One Sentence

Every day at 8am, it reads which US states need leads from CLOSRTECH for each of three campaigns (Veterans, Truckers, and Mortgage Protection), then updates the geographic targeting of every active Facebook adset in each campaign to match exactly.

---

## Quick Reference

| Property | Value |
|----------|-------|
| Client | Mike (veteran lead generation operation) |
| Campaigns | Veterans, Truckers, Mortgage Protection |
| CLOSRTECH params | `VND_VETERAN_LEADS`, `VND_TRUCKER_LEADS`, `VND_MORTGAGE_PROTECTION_LEADS` |
| Facebook ad accounts | CLOSRTECH `act_996226848340777` (Veterans + Truckers) / Inbounds `act_1007012848173879` (Mortgage) |
| Language | Python 3.13 |
| Deployment | GitHub Actions — cron 8:00 AM Colombia (13:00 UTC) |
| Trigger | Automatic daily + manual via workflow_dispatch |
| Default mode | DRY_RUN=true (safe by default, no writes) |
| Branch structure | `devlop` (development) → `main` (production) |
| Current state | Multi-campaign code done. Pending: new System User FB token + IP whitelist |

---

## Campaign Configuration

| Campaign | CLOSRTECH param | FB Ad Account | FB Campaign ID(s) |
|----------|----------------|---------------|-------------------|
| Veterans | `VND_VETERAN_LEADS` | `act_996226848340777` (CLOSRTECH) | `120238960603460363` |
| Truckers | `VND_TRUCKER_LEADS` | `act_996226848340777` (CLOSRTECH) | `120239404121750363` |
| Mortgage | `VND_MORTGAGE_PROTECTION_LEADS` | `act_1007012848173879` (Inbounds) | `120245305494410017`, `120241447971000017` |

**Notes:**

- Veterans and Truckers share the same Facebook ad account and the same System User access token.
- Mortgage lives in a separate Facebook ad account (Inbounds) — the same System User token has access to both accounts (confirmed by Charlie).
- Mortgage has two Facebook campaign IDs — the script pulls adsets from both, builds one combined list, and applies the same CLOSRTECH demand to all.

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
| Core automation (single campaign) | ✅ Done | Original Veterans automation |
| Multi-campaign refactor | ✅ Done | 2026-04-25 — supports Veterans, Truckers, Mortgage |
| Offline test suite | ✅ Done | 18 tests, 100% passing after refactor |
| Dry-run — CLOSRTECH (all 3 campaigns) | ✅ Done | 2026-04-25 — all 3 read successfully |
| Dry-run — Facebook (all 3 campaigns) | ❌ Failed | Token expired 2026-04-21 (was personal session token, not System User) |
| New System User FB token | ⚠️ Pending Mike | Token generation initiated — waiting for Mike to approve permission request |
| IP whitelist for GitHub Actions | ⚠️ Pending | Blocking for cron — CLOSRTECH only accepts known IPs |
| GitHub Secrets (new per-campaign names) | ⚠️ Pending | Must update before cron fires (new 16-var naming convention) |
| Visual verification (Facebook Ads Manager) | ⚠️ Pending | Saved adset URL; run after new token is available |
| `devlop` → `main` merge | ⚠️ Pending | All work is on devlop, not yet in production branch |
| orders.php integration | ⏭️ Deferred to v2 | Endpoint returns 404 for Veterans — not tested for Truckers/Mortgage |

---

## Dry-Run Results

### April 25-26, 2026 — Multi-campaign dry-run

**CLOSRTECH side — fully working for all 3 campaigns:**

| Campaign | Active states | Demand total |
|----------|--------------|-------------|
| Veterans | 34 states | 122 |
| Truckers | 9 states | 12 |
| Mortgage | 30 states | 23,960 |

**Notable:** Mortgage demand numbers are in the hundreds to thousands per state (e.g. FL: 1,988, TX: 1,990), much higher volume than Veterans or Truckers.

**Facebook side — failed for all 3** with the same error:

```
Session has expired on Tuesday, 21-Apr-26 09:00:00 PDT
```

**Root cause:** The access token was a personal Facebook login session token tied to Mike's account, not a System User token. When the session expired on April 21 (likely due to a password change or forced re-login), the token died for all campaigns simultaneously.

**Resolution in progress:** Navigated to Meta Business Manager → SP Insurance Group → Ajustes → Usuarios del sistema. Found an existing System User called CLOSRADS (Admin access) already assigned to both ad accounts (CLOSRTECH and Inbounds). Clicked "Generar identificador," selected the Manus app (already assigned to the System User), and initiated token generation. A permission approval was sent to Mike and is pending.

**Why System User tokens don't expire:** They belong to the business, not to any individual login session. They remain valid until explicitly revoked or the System User is deleted.

### April 15, 2026 — Original Veterans dry-run (local)

| Metric | Result |
|--------|--------|
| Active states from CLOSRTECH | 35 |
| Active adsets found | 5 |
| Adsets that would have been updated | 5/5 |
| Errors | 0 |

**Active states detected:** AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI, IA, IL, LA, MA, MD, ME, MN, MO, MS, MT, NC, ND, NH, NJ, NM, NV, OH, PA, RI, TN, TX, VA, WA, WI, WV

**Active adsets:**

- `120243386906050363` — BROAD - Copy 2
- `120243287242520363` — BROAD - Copy 2
- `120243238391470363` — BROAD - Copy 2
- `120243079782840363` — BROAD - OLDER ORDERS URGENT
- `120240834861880363` — BROAD - Copy

---

## Visual Verification — April 25-26, 2026

Accessed Facebook Ads Manager and navigated to the Veterans campaign (VOV-VET). One active adset showed **38 US states** currently targeted in the Lugares (geographic locations) section.

The dry-run reported **34 states** with active demand that day. This means when we run with `DRY_RUN=false`, the automation would:

- Remove states that have zero demand but are currently still targeted
- Add states that have demand but are not yet targeted

This confirmed the automation is reading the correct field and would make precise changes. The direct adset URL was saved for the post-token verification step.

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

This took **20 to 40 minutes every day**. It was error-prone: a state left in when it shouldn't be means budget burned on leads nobody ordered. A state missed means a client with demand gets nothing. It also required someone to be available every morning to do it, with no fallback if they weren't.

### Why Automation Was Straightforward Here

Unlike the ReadyMode bot (which required UI automation because ReadyMode has no API), both systems here have proper APIs:

- **CLOSRTECH** exposes a `demand.php` endpoint that returns a JSON dict of states and quantities
- **Facebook** has the Graph API with full support for reading and updating adset targeting

This meant the automation could be a clean script: read from one API, write to the other. No browser, no DOM, no headless Chrome. Just HTTP calls and the official Meta SDK.

### The Two Systems

**CLOSRTECH** is a platform Mike uses to manage lead orders. His clients place orders specifying which states they need leads from and how many. CLOSRTECH aggregates this into a demand view per campaign.

The API endpoint used:

```
GET https://closrtech.com/mergers/api/demand.php
  ?campaign=<CAMPAIGN_PARAM>
  &email=<email>
  &pass=<password>
```

Response format: a JSON object where keys are USPS state codes and values are the quantity demanded. States with zero demand are included in the response but filtered out by the script.

**Important constraint:** CLOSRTECH has an IP whitelist. Only known IPs can call the API. This is the main blocker for running the automation from GitHub Actions, since GitHub uses dynamic IPs that change on every run.

A second endpoint (`orders.php`) exists but returns 404 for Veterans — it was planned for v2 but is currently broken on CLOSRTECH's side. Status for Truckers and Mortgage is untested. Mike needs to escalate this to the CLOSRTECH developer.

**Facebook Graph API** — The script uses the `facebook-business` Python SDK (v25.0.1) to list active adsets, read their current targeting, compare against CLOSRTECH demand, and update only if there's a difference. The access token used must be a System User token from Mike's Meta Business account — non-expiring, unlike regular user tokens.

### The Critical Fail-Safe

The most important design decision: if CLOSRTECH returns a non-empty response where every state has `demand == 0`, the script treats this as an error (not valid data). It raises `ClosrtechDataError` and aborts immediately — Facebook is never touched. This prevents a CLOSRTECH bug from zeroing out all of Mike's advertising.

### What the Automation Changed

| Before | After |
|--------|-------|
| 20–40 min manual work daily per campaign | ~30 seconds automated for all 3 |
| Human must be available every morning | Runs at 8am regardless |
| Errors from copy-paste or forgetting a state | Exact sync from CLOSRTECH data |
| No audit trail of what changed | Full log in GitHub Actions + optional Slack notification |
| If person is sick or unavailable, nothing runs | Automatic with failure alerts |

### Scope of v1

This automation handles three campaigns (Veterans, Truckers, Mortgage Protection) and one type of change (geographic targeting). Everything else in the adset targeting — age ranges, genders, interests, behaviors, location types — is explicitly left untouched. The script reads the full current targeting, makes a deep copy, replaces only `geo_locations.regions`, and writes it back.

Expanding to other campaigns or other targeting dimensions would require explicit new scope.

---

## Documentation

| File | Contents |
|------|----------|
| [`architecture.md`](./architecture.md) | Data flow, file structure, layer separation, secrets architecture, execution sequence, fb_region_keys.json |
| [`module-reference.md`](./module-reference.md) | Detailed docs for all 7 modules in src/ |
| [`github-actions.md`](./github-actions.md) | Workflow YAML, trigger config, 16 secrets with per-campaign naming, IP whitelist problem |
| [`tests.md`](./tests.md) | 18 tests, offline strategy, conftest, fixtures, coverage gaps |
| [`activation-plan.md`](./activation-plan.md) | Ordered steps to go live, current blockers, post-activation monitoring |
| [`design-decisions.md`](./design-decisions.md) | D01–D12: every significant architectural decision with full reasoning |
