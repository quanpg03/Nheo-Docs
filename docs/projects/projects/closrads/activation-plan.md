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
| GitHub Secrets | ⚠️ Not configured |
| IP whitelist for GitHub Actions | ⚠️ Unresolved — main blocker |
| Mike confirmation of dry-run output | ⚠️ Pending |
| `devlop` → `main` merge | ⚠️ Pending |
| First live cron run | ⚠️ Pending |

---

## Step 1 — Mike confirms the dry-run state list

**Owner:** Juanes | **Blocker for:** Step 4 (live run) | **Status:** ⚠️ Pending

Share the dry-run output with Mike and ask him to confirm that the 35 active states are correct:

> AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI, IA, IL, LA, MA, MD, ME, MN, MO, MS, MT, NC, ND, NH, NJ, NM, NV, OH, PA, RI, TN, TX, VA, WA, WI, WV

If Mike says these are wrong, there is a bug in how CLOSRTECH is being queried (wrong campaign ID, wrong credentials) and that must be fixed before any live run.

**Done when:** Mike replies confirming the list looks correct.

---

## Step 2 — Resolve the IP whitelist

**Owner:** Juanes (decision) + Nat (implementation) | **Blocker for:** Steps 3 and 5 | **Status:** ⚠️ Unresolved

Choose one of the options documented in [`github-actions.md`](./github-actions.md):

| Option | Recommended if... |
|--------|------------------|
| Static IP proxy (VPS) | Nheo doesn't have an existing server with a fixed IP |
| Self-hosted GitHub Actions runner | Nheo already has a server that's always online |
| Move cron to Nheo server directly | Team prefers no GitHub Actions dependency |
| Ask Mike to expand CLOSRTECH whitelist | Mike has direct access to CLOSRTECH's admin and the vendor is responsive |

Once decided, implement the chosen solution and verify that a `curl` or `python` call to `demand.php` from the target execution environment succeeds.

**Done when:** A test HTTP request to `demand.php` from the chosen runner/environment returns a valid JSON response (not 403).

---

## Step 3 — Configure GitHub Secrets

**Owner:** Juanes or Nat | **Blocker for:** Step 5 (merge + cron) | **Status:** ⚠️ Not configured

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

**Owner:** Nat | **Blocker for:** Step 5 (merge) | **Status:** ⚠️ Pending Steps 2 and 3

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

**Owner:** Juanes | **Blocker for:** Step 6 (first live cron) | **Status:** ⚠️ Pending Step 4

Create a PR from `devlop` to `main`. Review the diff — it should be the entire CLOSRADS codebase since `main` is currently empty or stale.

Merge only after Step 4 passes. The cron workflow is configured to run from `main`, so this merge is what arms the scheduled trigger.

**Done when:** PR merged, `main` contains all current code.

---

## Step 6 — First live cron run (DRY_RUN=false)

**Owner:** Nat (monitor), Juanes (sign-off) | **Blocker for:** Nothing — this is the finish line | **Status:** ⚠️ Pending Step 5

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
