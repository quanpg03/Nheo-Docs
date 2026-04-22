# CLOSRADS — Facebook Ads Geo Sync

**Linear Project:** CLOSRADS Project  
**Engineers:** Juanes and Nat  
**Status as of:** 2026-04-16  
**Dry-run verified:** 2026-04-15

---

## What It Does in One Sentence

Every day at 8am, it reads which US states need leads from CLOSRTECH, then updates the geographic targeting of every active Facebook adset in the `VND_VETERAN_LEADS` campaign to match exactly.

---

## Quick Reference

| Property | Value |
|----------|-------|
| Client | Mike (veteran lead generation operation) |
| CLOSRTECH campaign | VND_VETERAN_LEADS |
| Facebook ad account | act_XXXXXXXXXX (configured via env var) |
| Language | Python 3.13 |
| Deployment | GitHub Actions — cron 8:00 AM Colombia (13:00 UTC) |
| Trigger | Automatic daily + manual via workflow_dispatch |
| Default mode | DRY_RUN=true (safe by default, no writes) |
| Branch structure | `devlop` (development) → `main` (production) |
| Current state | Dry-run validated. Pending: IP whitelist + merge to main |

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
| Core automation script | ✅ Done | All modules implemented and tested |
| Offline test suite | ✅ Done | 18 tests, 100% passing |
| Dry-run against production APIs | ✅ Done | Verified 2026-04-15 |
| CLOSRTECH credentials in .env | ⚠️ Pending | Must be added before production run |
| IP whitelist for GitHub Actions | ⚠️ Pending | Blocking for cron — CLOSRTECH only accepts known IPs |
| Mike confirmation of dry-run states | ⚠️ Pending | 35 states shown — Mike must verify |
| GitHub Secrets configured | ⚠️ Pending | Required for GitHub Actions to work |
| devlop → main merge | ⚠️ Pending | All work is on devlop, not yet in production branch |
| orders.php integration | ⏭️ Deferred to v2 | Endpoint returns 404 — Mike must escalate to CLOSRTECH dev |

---

## Dry-Run Results (2026-04-15)

First real execution against production APIs with DRY_RUN=true. No changes were made to Facebook — only logged what would have happened.

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

## Background & Problem

### The Manual Process Before CLOSRADS

Mike runs a veteran lead generation operation in the USA. His business depends on buying leads through Facebook Ads, but not all US states need leads every day — demand shifts based on orders placed through CLOSRTECH, a platform his clients use to signal which states they need covered.

The daily routine before this automation existed:
1. Someone opens CLOSRTECH and reads which states have active demand
2. They open Facebook Ads Manager
3. They navigate to each active adset in the `VND_VETERAN_LEADS` campaign
4. They manually edit the geographic targeting of each adset to match the states from CLOSRTECH
5. They repeat for every active adset

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
  ?campaign=VND_VETERAN_LEADS
  &email=<email>
  &pass=<password>
```

Response format: a JSON object where keys are USPS state codes and values are the quantity demanded. States with zero demand are included in the response but filtered out by the script.

**Important constraint:** CLOSRTECH has an IP whitelist. Only known IPs can call the API. This is the main blocker for running the automation from GitHub Actions, since GitHub uses dynamic IPs that change on every run.

A second endpoint (`orders.php`) exists but returns 404 — it was planned for v2 but is currently broken on CLOSRTECH's side. Mike needs to escalate this to the CLOSRTECH developer.

**Facebook Graph API** — The script uses the `facebook-business` Python SDK (v25.0.1) to list active adsets, read their current targeting, compare against CLOSRTECH demand, and update only if there's a difference. The access token used is a System User token from Mike's Meta Business account — non-expiring, unlike regular user tokens.

### The Critical Fail-Safe

The most important design decision: if CLOSRTECH returns a non-empty response where every state has `demand == 0`, the script treats this as an error (not valid data). It raises `ClosrtechDataError` and aborts immediately — Facebook is never touched. This prevents a CLOSRTECH bug from zeroing out all of Mike's advertising.

### What the Automation Changed

| Before | After |
|--------|-------|
| 20–40 min manual work daily | ~30 seconds automated |
| Human must be available every morning | Runs at 8am regardless |
| Errors from copy-paste or forgetting a state | Exact sync from CLOSRTECH data |
| No audit trail of what changed | Full log in GitHub Actions + optional Slack notification |
| If person is sick or unavailable, nothing runs | Automatic with failure alerts |

### Scope of v1

This automation handles one campaign (`VND_VETERAN_LEADS`) and one type of change (geographic targeting). Everything else in the adset targeting — age ranges, genders, interests, behaviors, location types — is explicitly left untouched. The script reads the full current targeting, makes a deep copy, replaces only `geo_locations.regions`, and writes it back.

Expanding to other campaigns or other targeting dimensions would require explicit new scope.

---

## Documentation

| File | Contents |
|------|----------|
| [`architecture.md`](./architecture.md) | Data flow, file structure, layer separation, secrets architecture, execution sequence, fb_region_keys.json |
| [`module-reference.md`](./module-reference.md) | Detailed docs for all 7 modules in src/ |
| [`github-actions.md`](./github-actions.md) | Workflow YAML, trigger config, secrets, IP whitelist problem, branch strategy |
| [`tests.md`](./tests.md) | 18 tests, offline strategy, conftest, fixtures, coverage gaps |
| [`activation-plan.md`](./activation-plan.md) | 6 ordered steps to go live, blockers, post-activation monitoring |
| [`design-decisions.md`](./design-decisions.md) | D01–D10: every significant architectural decision with full reasoning |
