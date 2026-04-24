# Activation Plan

This page defines the exact ordered steps required to go from **current state** (dry-run validated on `devlop`) to **production active** (cron running on `main` with `DRY_RUN=false` every day at 8 AM Colombia).

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

---

## Step 1 — Mike confirms the dry-run state list

**Owner:** Juanes | **Blocker for:** Step 4 (live run) | **Status:** ✅ Approved

Share the dry-run output with Mike and ask him to confirm that the 35 active states are correct:

> AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI, IA, IL, LA, MA, MD, ME, MN, MO, MS, MT, NC, ND, NH, NJ, NM, NV, OH, PA, RI, TN, TX, VA, WA, WI, WV

If Mike says these are wrong, there is a bug in how CLOSRTECH is being queried (wrong campaign ID, wrong credentials) and that must be fixed before any live run.

**Done when:** Mike replies confirming the list looks correct.

---

## Step 2 — Resolve the IP whitelist

**Owner:** Juanes (decision) + Nat (implementation) | **Blocker for:** Steps 3 and 5 | **Status:** ✅ Resolved

Choose one of the options documented in [`github-actions.md`](./github-actions.md):

| Option | Recommended if... |
|--------|------------------|
| Static IP proxy (VPS) | Nheo doesn't have an existing server with a fixed IP |
| Self-hosted GitHub Actions runner | Nheo already has a server that's always online |
| Move cron to Nheo server directly | Team prefers no GitHub Actions dependency |
| Ask Mike to expand CLOSRTECH whitelist | Mike has direct access to CLOSRTECH's admin and the vendor is responsive |

Once decided, implement the chosen solution and verify that a `curl` or `python` call to `demand.php` from the target execution environment succeeds.

**Done when:** A test HTTP request to `demand.php` from the chosen runner/environment returns a valid JSON response (not 403).
**Chosen solution**: We are going to use an EC2 instance but in the meantime, we are going to use Self-hosted Github Actions runner with Nheo's server

---

## Step 3 — Configure GitHub Secrets

**Owner:** Juanes or Nat | **Blocker for:** Step 5 (merge + cron) | **Status:** ✅ Configured

In the GitHub repo: Settings → Secrets and variables → Actions → New repository secret.

| Secret | Source |
|--------|--------|
| `CLOSRTECH_EMAIL` | Mike's CLOSRTECH credentials |
| `CLOSRTECH_PASSWORD` | Mike's CLOSRTECH credentials |
| `CLOSRTECH_CAMPAIGN` | `VND_VETERAN_LEADS` |
| `FB_ACCESS_TOKEN` | Meta Business Manager → System User token |
| `FB_AD_ACCOUNT_ID` | From Facebook Ads Manager (format: `act_XXXXXXXXXX`) |
| `FB_CAMPAIGN_ID` | Campaign ID for `VND_VETERAN_LEADS` campaign on Facebook |
| `SLACK_WEBHOOK_URL` | Optional. Create an incoming webhook in Slack if notifications are wanted |

**Important:** Do not commit any of these values to the repo. Verify that `.gitignore` includes `.env`.

**Done when:** All secrets appear in the GitHub repo secrets list (values are masked, names are visible).

---

## Step 4 — Manual `workflow_dispatch` dry-run from GitHub Actions

**Owner:** Nat | **Blocker for:** Step 5 (merge) | **Status:** ✅ Done 2026-04-21

Once the IP issue is resolved and secrets are configured, trigger the workflow manually from GitHub Actions UI with `dry_run: true`.

**What to verify in the run log:**
- No auth errors from CLOSRTECH (IP whitelist resolved)
- No auth errors from Facebook (token valid)
- Same 35 states returned as in the local dry-run
- Same 5 adsets found
- Log shows `[DRY RUN] Would update adset...` for each adset
- Exit code 0 (green check in GitHub Actions)

If the run fails, diagnose from the workflow log. Common failure points at this step: CLOSRTECH still rejects the IP, Facebook token permissions issue, or a secret name typo.

**Done when:** A `workflow_dispatch` dry-run from GitHub Actions completes with exit code 0 and the expected output.

---

## Step 5 — Merge `devlop` → `main`

**Owner:** Juanes | **Blocker for:** Step 6 (first live cron) | **Status:** ✅ Done

Create a PR from `devlop` to `main`. Review the diff — it should be the entire CLOSRADS codebase since `main` is currently empty or stale.

Merge only after Step 4 passes. The cron workflow is configured to run from `main`, so this merge is what arms the scheduled trigger.

**Done when:** PR merged, `main` contains all current code.

---

## Step 6 — First live cron run (DRY_RUN=false) 

**Owner:** Nat (monitor), Juanes (sign-off) | **Blocker for:** Nothing — this is the finish line | **Status:** ✅ Done 2026-04-21

The day after the merge to `main`, the cron fires at 13:00 UTC (8 AM Colombia) with `DRY_RUN=false`.

**What success looks like:**
- Exit code 0
- Log shows actual Facebook API update calls (not dry-run logs)
- Slack notification shows `Status: SUCCESS` with adsets updated count
- Mike's Facebook Ads Manager shows the geographic targeting updated on the 5 adsets

**What to do if it fails:**
- Check the GitHub Actions log for the exact error and which step failed
- If CLOSRTECH fails: check IP whitelist, credentials
- If Facebook fails: check token expiry, permissions, adset IDs
- If sync logic fails: check `report.errors` in the Slack message or log
- Do NOT attempt a manual fix in Facebook Ads Manager simultaneously — let the automation own the targeting

**Done when:** First live run completes with exit code 0 and Facebook targeting is confirmed updated.

---

## Blockers Summary

| Blocker | Severity | Owner | Next action |
|---------|----------|-------|-------------|
| IP whitelist for GitHub Actions | 🔴 Critical | Juanes | Decide on proxy vs self-hosted runner vs server cron |
| Mike confirmation of dry-run states | 🟡 High | Juanes | Share output with Mike and await reply |
| GitHub Secrets not configured | 🟡 High | Nat | Configure after IP decision is made |
| `devlop` → `main` not merged | 🟡 High | Juanes | Merge after Step 4 (GH Actions dry-run) passes |
| `orders.php` returns 404 | 🔵 Low (v2) | Mike | Mike must escalate to CLOSRTECH dev. Not blocking v1 |

---

## Post-Activation Monitoring

Once live, the automation should be monitored for the first 5 days:
- Check GitHub Actions workflow history each morning to confirm the run succeeded
- Spot-check Facebook Ads Manager on Day 1 and Day 3 to confirm targeting matches CLOSRTECH
- Confirm Slack notifications are being received (if configured)
- After 5 successful days, consider the automation stable and reduce monitoring to weekly spot-checks

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
