# Activation Plan

This page covers two phases: (1) the original single-campaign Veterans automation — **already live since April 21**, and (2) the multi-campaign expansion (Veterans + Truckers + Mortgage) — **in progress as of April 26**.

Every step includes who owns it, what done looks like, and whether it is a blocker for the next step.

---

## Current State Summary

| Item | Status |
|------|--------|
| Core automation code | ✅ Complete, on `devlop` branch |
| Offline tests (18/18) | ✅ Passing |
| Dry-run against real APIs (local) | ✅ Done 2026-04-15 — 35 states, 5 adsets |
| GitHub Secrets | ✅ Configured 2026-04-20 |
| IP whitelist for GitHub Actions | ✅ Resolved — main blocker |
| Mike confirmation of dry-run output | ✅ Cofirmed |
| `devlop` → `main` merge | ✅ Done 2026-04-19 |
| First live cron run | ✅ Done 2026-04-21 |
| Core automation code (Veterans, single-campaign) | ✅ Complete |
| Veterans automation — live in production | ✅ LIVE since 2026-04-21 |
| Offline tests (18/18) | ✅ Passing — including after multi-campaign refactor |
| IP whitelist for GitHub Actions | ✅ Resolved — self-hosted runner on Nheo's server (moving to EC2 long-term) |
| GitHub Secrets (original single-campaign) | ✅ Configured 2026-04-20 |
| Mike confirmation of dry-run output | ✅ Confirmed |
| `devlop` → `main` merge (Veterans) | ✅ Done 2026-04-19 |
| First live cron run (Veterans) | ✅ Done 2026-04-21 |
| Multi-campaign refactor (Veterans + Truckers + Mortgage) | ✅ Complete, on `devlop` (April 25-26 session) |
| Dry-run — CLOSRTECH all 3 campaigns | ✅ Done 2026-04-25 — all 3 read successfully |
| Dry-run — Facebook all 3 campaigns | ❌ Failed — token expired 2026-04-21 (was personal session token) |
| New System User FB token | ⚠️ Pending Mike approval of permission request |
| GitHub Secrets (new per-campaign naming) | ⚠️ Not configured with new naming convention |
| Visual verification (Facebook Ads Manager, multi-campaign) | ⚠️ Pending new token |
| `devlop` → `main` merge (multi-campaign) | ⚠️ Pending |
| First live cron run (all 3 campaigns) | ⚠️ Pending |

---

## Phase 1 — Original Veterans Automation (COMPLETE)

**Owner:** Juanes | **Blocker for:** Step 4 (live run) | **Status:** ✅ Approved
The following steps document how the original single-campaign Veterans automation went live. All steps are done.

### Step 1 — Mike confirms the dry-run state list ✅ Approved

Mike confirmed the 35 active states returned by the local dry-run on 2026-04-15 were correct.

> AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI, IA, IL, LA, MA, MD, ME, MN, MO, MS, MT, NC, ND, NH, NJ, NM, NV, OH, PA, RI, TN, TX, VA, WA, WI, WV

### Step 2 — Resolve the IP whitelist ✅ Resolved

**Owner:** Juanes (decision) + Nat (implementation)

**Chosen solution:** Self-hosted GitHub Actions runner using Nheo's server. The runner is registered with the repo and the server's IP was added to CLOSRTECH's whitelist. This is a temporary setup — the long-term plan is to move to a dedicated EC2 instance for better isolation and reliability.

A test HTTP request to `demand.php` from the self-hosted runner returned a valid JSON response.

### Step 3 — Configure GitHub Secrets ✅ Configured 2026-04-20

**Owner:** Nat

Original single-campaign secrets configured in the GitHub repo. At this stage the naming was not yet per-campaign (that change came with the multi-campaign refactor).

### Step 4 — Manual `workflow_dispatch` dry-run from GitHub Actions ✅ Done 2026-04-21

**Owner:** Nat

**Owner:** Juanes (decision) + Nat (implementation) | **Blocker for:** Steps 3 and 5 | **Status:** ✅ Resolved
Triggered from GitHub Actions UI with `dry_run: true`. Run completed successfully via the self-hosted runner. CLOSRTECH and Facebook both responded without errors.

### Step 5 — Merge `devlop` → `main` ✅ Done 2026-04-19

**Owner:** Juanes

PR merged. `main` contained the full Veterans single-campaign codebase.

**Done when:** A test HTTP request to `demand.php` from the chosen runner/environment returns a valid JSON response (not 403).
**Chosen solution**: We are going to use an EC2 instance but in the meantime, we are going to use Self-hosted Github Actions runner with Nheo's server
### Step 6 — First live cron run (Veterans, DRY_RUN=false) ✅ Done 2026-04-21

**Owner:** Nat (monitor), Juanes (sign-off)

The cron fired at 13:00 UTC on April 21. Exit code 0. Facebook Ads Manager confirmed the targeting updated on all 5 active adsets. Slack notification received.

---

## Phase 2 — Multi-Campaign Expansion (IN PROGRESS)

Expanding from Veterans-only to Veterans + Truckers + Mortgage Protection. The campaign params and Facebook IDs were confirmed with Charlie.

**Owner:** Juanes or Nat | **Blocker for:** Step 5 (merge + cron) | **Status:** ✅ Configured
### Step 1 — Get the new System User FB token

**Owner:** Mike (approve) → Juanes (generate + distribute) | **Blocker for:** Steps 2 and 3 | **Status:** ⚠️ Pending Mike approval

The personal session token expired April 21. A System User token was identified as the correct replacement — it belongs to the business and does not expire.

Navigation: Meta Business Manager → SP Insurance Group → Ajustes → Usuarios del sistema → CLOSRADS System User (Admin, already has access to both ad accounts).

Once Mike approves the permission request:
1. Click "Generar identificador" → select Manus app → generate token
2. Drop the token into `.env` replacing all three `*_FB_ACCESS_TOKEN` values (same token for all campaigns)

**Done when:** `python main.py` with `DRY_RUN=true` completes without Facebook token errors for all 3 campaigns.

---

### Step 2 — Second dry-run (all 3 campaigns, CLOSRTECH + Facebook)

**Owner:** Nat | **Blocker for:** Step 5 (merge) | **Status:** ✅ Done 2026-04-21
**Owner:** Juanes or Nat | **Blocker for:** Step 3 | **Status:** ⚠️ Pending Step 1

Run `python main.py` locally with the new token and `DRY_RUN=true`.

**What to verify:**
- All 3 campaigns read CLOSRTECH without auth errors
- All 3 campaigns reach Facebook without token errors
- Mortgage specifically: confirm no HTTP 403 from CLOSRTECH (see Known Issues below)
- State counts roughly match April 25-26 results: Veterans ~34, Truckers ~9, Mortgage ~30

**Done when:** Local dry-run exits code 0 with demand data + Facebook adset counts for all 3 campaigns.

---

### Step 3 — Visual verification (Facebook Ads Manager)

**Owner:** Juanes or Nat | **Blocker for:** Step 4 | **Status:** ⚠️ Pending Step 2

Open the saved Veterans adset URL (`adsmanager.facebook.com/adsmanager/manage/adsets/edit/standalone?act=996226848340777...`), note the current states, run `DRY_RUN=false` locally, reload and confirm states changed.

**Done when:** Adset targeting in Facebook Ads Manager matches what the dry-run log said it would set.

---

### Step 4 — Configure GitHub Secrets (new per-campaign naming)

**Owner:** Juanes or Nat | **Blocker for:** Step 5 | **Status:** ⚠️ Not configured

The naming convention changed from the original single-campaign secrets to per-campaign prefixes. Delete the old single-campaign secrets and replace with:

| Secret | Value |
|--------|-------|
| `CLOSRTECH_EMAIL` | Mike's CLOSRTECH email |
| `CLOSRTECH_PASSWORD` | Mike's CLOSRTECH password |
| `VETERANS_CLOSRTECH_CAMPAIGN` | `VND_VETERAN_LEADS` |
| `VETERANS_FB_ACCESS_TOKEN` | New System User token |
| `VETERANS_FB_AD_ACCOUNT_ID` | `act_996226848340777` |
| `VETERANS_FB_CAMPAIGN_ID` | `120238960603460363` |
| `TRUCKERS_CLOSRTECH_CAMPAIGN` | `VND_TRUCKER_LEADS` |
| `TRUCKERS_FB_ACCESS_TOKEN` | Same System User token |
| `TRUCKERS_FB_AD_ACCOUNT_ID` | `act_996226848340777` |
| `TRUCKERS_FB_CAMPAIGN_ID` | `120239404121750363` |
| `MORTGAGE_CLOSRTECH_CAMPAIGN` | `VND_MORTGAGE_PROTECTION_LEADS` |
| `MORTGAGE_FB_ACCESS_TOKEN` | Same System User token |
| `MORTGAGE_FB_AD_ACCOUNT_ID` | `act_1007012848173879` |
| `MORTGAGE_FB_CAMPAIGN_IDS` | `120245305494410017,120241447971000017` |
| `SLACK_WEBHOOK_URL` | Optional. Incoming webhook URL. |

**Done when:** All 15 secrets appear in the GitHub repo secrets list under the new names.

---

### Step 5 — Manual `workflow_dispatch` dry-run from GitHub Actions (multi-campaign)

**Owner:** Nat | **Blocker for:** Step 6 | **Status:** ⚠️ Pending Steps 1 and 4

Trigger from GitHub Actions UI with `dry_run: true`. The self-hosted runner from Phase 1 is already registered — no new runner setup needed.

**Owner:** Juanes | **Blocker for:** Step 6 (first live cron) | **Status:** ✅ Done
**What to verify:**
- No auth errors from CLOSRTECH or Facebook for any campaign
- Demand data and adset counts logged for all 3 campaigns
- Log shows `[DRY RUN] Would update adset...` for each adset
- Exit code 0

**Done when:** `workflow_dispatch` dry-run completes with exit code 0 for all 3 campaigns.

---

### Step 6 — Merge `devlop` → `main` (multi-campaign)

**Owner:** Juanes | **Blocker for:** Step 7 | **Status:** ⚠️ Pending Step 5

Create a PR from `devlop` to `main`. The diff should include the multi-campaign refactor: `CampaignConfig` dataclass, `CAMPAIGNS` list, updated function signatures across all modules.

**Done when:** PR merged, `main` contains all current multi-campaign code.

---

## Step 6 — First live cron run (DRY_RUN=false) 

**Owner:** Nat (monitor), Juanes (sign-off) | **Blocker for:** Nothing — this is the finish line | **Status:** ✅ Done 2026-04-21
### Step 7 — First live cron run (all 3 campaigns, DRY_RUN=false)

**Owner:** Nat (monitor), Juanes (sign-off) | **Blocker for:** Nothing — this is the finish line | **Status:** ⚠️ Pending Step 6

The day after the merge, the cron fires at 13:00 UTC (8 AM Colombia) with `DRY_RUN=false`.

**What success looks like:**
- Exit code 0
- Slack shows one `Status: SUCCESS` block per campaign (Veterans, Truckers, Mortgage)
- Facebook Ads Manager shows updated targeting for adsets across all 3 campaigns

**What to do if it fails:**
- Check the GitHub Actions log for which campaign/step failed
- If one campaign fails but others succeed: check that campaign's specific config (campaign ID, ad account ID, CLOSRTECH param)
- Do NOT manually fix in Facebook Ads Manager simultaneously — let the automation own the targeting

**Done when:** First live run exits 0 and Facebook targeting is confirmed updated for all 3 campaigns.

---

## Blockers Summary

| Blocker | Severity | Owner | Next action |
|---------|----------|-------|-------------|
| New FB System User token | 🔴 Critical | Mike → Juanes | Mike approves permission request; Juanes generates token |
| GitHub Secrets (new per-campaign naming) | 🟡 High | Nat | Configure after new token is available |
| `devlop` → `main` not merged (multi-campaign) | 🟡 High | Juanes | Merge after Step 5 (GH Actions dry-run) passes |
| Mortgage HTTP 403 from CLOSRTECH | 🟡 High | Juanes | Verify with new System User token — may resolve automatically |
| `orders.php` returns 404 | 🔵 Low (v2) | Mike | Mike must escalate to CLOSRTECH dev. Not blocking v1. |

**IP whitelist:** ✅ No longer a blocker — resolved in Phase 1 using self-hosted runner on Nheo's server.

---

## Known Issues (from multi-campaign implementation — Nat, April 24)

These issues were found during Nat's initial multi-campaign implementation and remain open going into the April 25-26 refactor:

**1. CLOSRTECH HTTP 403 for Mortgage campaigns**
`VND_MORTGAGE_PROTECTION_LEADS` returns `403 — No access to this campaign` when called with the current CLOSRTECH credentials. This may mean Mike's CLOSRTECH account does not yet have access to the Mortgage campaign identifiers, or the campaign param string differs. This should be retested after the new System User FB token is in place (the CLOSRTECH credentials themselves are unchanged, but the full dry-run with a working Facebook token will give a cleaner picture).

**2. `main.py` and `notifier.py` not yet updated for `list[SyncReport]`**
Nat's initial refactor changed `sync.py` to return `list[SyncReport]` but left `main.py` and `notifier.py` expecting a single `SyncReport`. This causes `AttributeError: 'list' object has no attribute 'dry_run'` at runtime. This was resolved in the April 25-26 code review session — both files now handle `list[SyncReport]` correctly.

---

## Nat's Multi-Campaign Implementation Notes (April 24, 2026)

_These notes document Nat's initial implementation approach before the April 25-26 code review session refactored it into the `CampaignConfig` dataclass pattern. Kept here as a record of the design evolution._

**Scope:** Expanded from 1 campaign (Veterans) to 4 Facebook campaign IDs across 2 ad accounts: Veterans, Truckers, Mortgage MP, Mortgage MP2.

**Changes by file:**

`closrtech_client.py` — `get_demand()` now accepts a `campaign: str` parameter instead of reading `config.CLOSRTECH_CAMPAIGN` directly. This allows each campaign to query its own CLOSRTECH demand independently.

`facebook_client.py` — No changes required in this version. The existing FB token has access to both ad accounts, so `get_active_adsets(campaign_id)` works across accounts without modification.

`sync.py` — Added a `campaign_mapping` dict pairing each `FB_CAMPAIGN_ID` with its corresponding `CLOSRTECH_CAMPAIGN` identifier. `init_api()` moved outside the loop — called once since the token is shared. The main loop iterates over `campaign_mapping.items()`. A fresh `SyncReport` is instantiated per campaign iteration. All error handlers use `continue` instead of `return` so a failure in one campaign does not abort the others. Return type changed from `SyncReport` to `list[SyncReport]`.

`main.py` and `notifier.py` — Not yet updated in this version (see Known Issues above). Fixed in the April 25-26 session.

**GitHub Actions secrets used in this version:**
`FB_CAMPAIGN_ID_V`, `FB_CAMPAIGN_ID_T`, `FB_CAMPAIGN_ID_MP`, `FB_CAMPAIGN_ID_MP2` for the four campaign IDs; `CLOSRTECH_CAMPAIGN_VETERAN`, `CLOSRTECH_CAMPAIGN_TRUCKER`, `CLOSRTECH_CAMPAIGN_MORGAGE` for the CLOSRTECH params. Both Facebook account IDs added but not actively used since the token covers both. Shared secrets (`CLOSRTECH_EMAIL`, `CLOSRTECH_PASSWORD`, `FB_ACCESS_TOKEN`) kept the same.

_Note: The April 25-26 refactor consolidated this into the `CampaignConfig` dataclass + `CAMPAIGNS` list pattern with per-campaign prefix naming (`VETERANS_`, `TRUCKERS_`, `MORTGAGE_`). See [`module-reference.md`](./module-reference.md) and [`github-actions.md`](./github-actions.md) for the final implementation._

---

## Post-Activation Monitoring

Once all 3 campaigns are live, monitor for the first 5 days:

- Check GitHub Actions workflow history each morning — confirm all 3 campaigns ran successfully
- Spot-check Facebook Ads Manager on Day 1 and Day 3 for at least one adset per campaign
- Confirm Slack notifications are received — verify one block per campaign per day
- After 5 successful days, reduce monitoring to weekly spot-checks

**Long-term:** The System User token does not expire, so no credential rotation is expected. The only maintenance scenario is if Meta changes the `facebook-business` SDK (update `requirements.txt`) or if CLOSRTECH changes their API contract (update `closrtech_client.py`).

# Multi-Campaign Support Adaptation
_Context_
The original implementation was designed to sync a single campaign (Veteran) between CLOSRTECH and Facebook Ads. The scope was expanded to support 4 campaigns across 2 Facebook Ad Accounts:

Veteran (original)
Trucker (new)
Morgage MP (new)
Morgage MP2 (new)

### Changes by file:
- **closrtech_client.py**:
  get_demand() now accepts a campaign: str parameter instead of reading config.CLOSRTECH_CAMPAIGN directly. This allows each campaign to query its own CLOSRTECH demand independently.

- **facebook_client.py**:
  No changes required. The existing FB token has access to both ad accounts, so get_active_adsets(campaign_id) works across accounts without         modification.

- **sync.py**:
  - Added campaign_mapping dict that pairs each FB_CAMPAIGN_ID with its corresponding CLOSRTECH_CAMPAIGN identifier.
  - init_api() moved outside the loop — called once since the token is shared.
  - The main loop now iterates over campaign_mapping.items(), unpacking both IDs per iteration.
  - A fresh SyncReport is instantiated at the start of each campaign iteration, giving an independent report per campaign.
  - All error handlers use continue instead of return so a failure in one campaign does not abort the others. The failed report is still appended to preserve the record.
  - run_sync() return type changed from SyncReport to list[SyncReport].

- **main.py and notifier.py**: Pending update, is currently expecting a SyncReport but with the changes made, we are returning a list of SyncReports.

### GitHub Actions workflow
- Added secrets for all 4 campaign IDs: FB_CAMPAIGN_ID_V, FB_CAMPAIGN_ID_T, FB_CAMPAIGN_ID_MP, FB_CAMPAIGN_ID_MP2.
- Added CLOSRTECH campaign secrets: CLOSRTECH_CAMPAIGN_VETERAN, CLOSRTECH_CAMPAIGN_TRUCKER, CLOSRTECH_CAMPAIGN_MORGAGE.
- Added both facebook account IDs but are nor currently being used because the token is said to be enough.
- The rest of secrets were kept the same (CLOSRTECH_EMAIL, CLOSRTECH_PASSWORD, FB_ACCESS_TOKEN)


### Known current issues
1. CLOSRTECH_CAMPAIGN_MORGAGE (MP and MP2) returns HTTP 403 "No access to this campaign" — the credentials provided may not have access to these campaign IDs yet.
2. main.py and notifier.py crash with AttributeError: 'list' object has no attribute 'dry_run' because they have not yet been updated to handle list[SyncReport].  
**Long-term:** The System User token does not expire. The only maintenance scenarios are: Meta changes the `facebook-business` SDK (update `requirements.txt`), CLOSRTECH changes their API contract (update `closrtech_client.py`), a new campaign needs to be added (one `.env` entry + one line in `config.py`), or the self-hosted runner needs maintenance (move to EC2 as planned).
