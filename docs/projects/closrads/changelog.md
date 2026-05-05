# Changelog & Session Log

This file records what happened in each significant work session — including failures, what we learned from them, and what changed. Failures are as important as successes: they explain why the system works the way it does today.

---

## May 2026 — 4-Layer Protection, Email Notifications, Credential Security

### Context

Both Veterans and Mortgage were live and running daily. Truckers was deployed as part of the multi-campaign refactor but began showing a silent failure pattern: ads were getting paused without any error being raised by the automation itself. The script reported success, but Charlie was seeing ads go offline in Facebook Ads Manager.

### What Failed and Why

**The failure:** After the automation updated geo targeting on a Truckers adset, some ads using lead forms (instant forms) were silently paused by Meta. The error code was **#3390001** — a Meta-internal error indicating the link between an ad and its lead form was broken. Meta does not surface this error through the standard API response for the geo update call. The update returns 200 OK, the script considers it successful, and then Meta asynchronously re-validates the child ads and breaks the form link.

**Why lead form ads are vulnerable:** When an adset’s targeting changes, Meta triggers an internal re-validation of all ads in that adset to ensure they’re still compliant with the new targeting. For ads with lead forms, this re-validation includes re-verifying the form link. The re-verification sometimes fails, breaking the link and pausing the ad.

**Scope of the issue:** Confirmed in Truckers campaign. Also observed in at least one Mortgage adset. Veterans adsets appear to use different ad types that are less affected, but we can’t guarantee immunity.

**Immediate action:** Truckers was commented out in `config.py` while the fix was designed. Veterans and Mortgage continued running.

### Investigation

We contacted Meta support with the error code and the pattern we were observing. Meta confirmed:

1. The behavior is real and known for lead form ads
2. The recommended fix is to explicitly re-publish (send `status=ACTIVE`) to each ad immediately after a geo targeting update — this signals to Meta’s servers that the ad is still valid and re-confirms the lead form link
3. This is not documented in the public API docs but is a supported workaround

### Solution: 4-Layer Protection System

Instead of patching only the cascade republish, we built a full 4-layer protection around every adset update:

1. **Pre-flight check** — if the adset already has broken ads before we touch it, skip it entirely that day. No point adding risk to an already-broken adset.
2. **Cascade republish** — immediately after the geo update, send `status=ACTIVE` to every active ad. This is the core fix recommended by Meta.
3. **Post-republish verification** — wait 3 seconds, then check all ad statuses. If all healthy, done. If any still broken, trigger Layer 4.
4. **Automatic rollback** — if verification finds broken ads, restore the geo targeting to its exact pre-update state. The adset is left as if it was never modified. Worst case: “not updated today.” Never: “left worse than before.”

The 3-second wait in Layer 3 was chosen empirically — long enough for Meta to process the republish signal in observed cases, short enough not to meaningfully slow down the sync.

### Truckers Status

Truckers is currently **disabled** (commented out in `config.py`). It can be re-enabled once the team confirms that the 4-layer protection fully resolves the lead form issue in practice. The secrets and campaign configuration are all still in place — re-enabling requires only uncommenting one line in `config.py`.

### Email Notifications to Charlie

**Why the change:** Charlie is the client-side contact who needs operational visibility into the daily sync. He is not in the Nheo Slack workspace, so Slack notifications never reached him. The HTML email sends directly to Charlie after each sync.

**What the email shows:** Per-campaign summary (updated / unchanged / skipped preflight / reverted), colored alert boxes for skipped and reverted adsets, and the full list of active CLOSRTECH states. The colored boxes — orange for pre-flight skips, red for rollbacks, green for clean runs — make the operational status immediately readable without needing to read logs.

**Previous state:** The original Slack notifications went to the Nheo team internally. This was useful for dev monitoring but didn’t reach Charlie.

### Credential Security Fix

**What was wrong:** Charlie’s email address was hardcoded as the default value for `NOTIFY_EMAIL` in `config.py`. Any developer who cloned the repo and ran the script without configuring env vars would have sent emails to Charlie unknowingly.

**Fix:** Removed the hardcoded address. `NOTIFY_EMAIL` is now a standard optional env var. If absent, email is disabled. The address is stored only in `.env` locally and in GitHub Secrets for the cron.

### Files Changed

| File | Change |
|------|--------|
| `src/config.py` | Added `SENDER_EMAIL`, `SENDER_EMAIL_APP_PASSWORD`, `NOTIFY_EMAIL` as optional vars. Removed hardcoded default. |
| `src/facebook_client.py` | Added `check_ad_health()`, `republish_ads()`, `verify_ads_after_republish()`, `rollback_geo()` |
| `src/sync.py` | Updated `_sync_campaign()` to run 4-layer protection per adset. Added `adsets_skipped_preflight` and `adsets_reverted` to `SyncReport`. |
| `src/notifier.py` | Replaced Slack webhook with HTML email via Gmail SMTP. Updated `notify()` to handle colored alert boxes. |
| `.github/workflows/daily-sync.yml` | Added `SENDER_EMAIL`, `SENDER_EMAIL_APP_PASSWORD`, `NOTIFY_EMAIL` env vars. |

### Current Campaign Status After This Session

| Campaign | Status | Notes |
|----------|--------|-------|
| Veterans | ✅ Active | Running normally |
| Mortgage | ✅ Active | Running with 4-layer protection |
| Truckers | ⚠️ Disabled | Commented in config — re-enable after 4-layer confirmation |

---

## April 25-26, 2026 — Multi-Campaign Refactor + Token Crisis

### Context

The goal was to expand from Veterans-only to all three campaigns (Veterans, Truckers, Mortgage). Charlie sent a Loom video showing the requirement. We extracted the campaign params and Facebook IDs from the transcript.

### What Failed

**Facebook token expired.** The dry-run on April 25 successfully read all three campaigns from CLOSRTECH but failed to reach Facebook with:

```
Session has expired on Tuesday, 21-Apr-26 09:00:00 PDT
```

Root cause: the token was a personal session token tied to Mike’s Facebook account, not a System User token. When Mike’s session expired April 21 (likely a password change or forced re-login), the token became invalid for all three campaigns simultaneously.

**Why this wasn’t caught earlier:** The April 15 dry-run (Veterans only, single campaign) had worked because the token was still valid at that time.

### Resolution

Navigated to Meta Business Manager → SP Insurance Group → Usuarios del sistema. Found an existing System User called CLOSRADS with Admin access to both ad accounts. Generated a new token using the Manus app. Mike’s approval was needed and obtained.

System User tokens do not expire — they belong to the business, not to any individual login session.

### Code Changes

Refactored the codebase from single-campaign to N-campaigns via `CampaignConfig` dataclass and `CAMPAIGNS` list. All function signatures updated to accept explicit parameters instead of reading from `config` internally. See [`module-reference.md`](./module-reference.md) for details.

### Nat’s Initial Implementation (April 24)

Nat started the multi-campaign refactor before the April 25-26 session, using a `campaign_mapping` dict approach in `sync.py`. Her implementation identified two issues:

1. CLOSRTECH returned HTTP 403 for `VND_MORTGAGE_PROTECTION_LEADS` — credentials may not have had access yet, or the param string was not yet confirmed. Resolved in May 2026 after the new token and correct credentials were in place.
2. `main.py` and `notifier.py` were not yet updated to handle `list[SyncReport]` and crashed with `AttributeError: 'list' object has no attribute 'dry_run'`. Fixed in the April 25-26 session.

---

## April 19-21, 2026 — Original Veterans Automation Goes Live

### What Happened

- **April 19:** `devlop` → `main` merge completed. Nat set up the self-hosted GitHub Actions runner on Nheo’s server, solving the CLOSRTECH IP whitelist problem.
- **April 20:** GitHub Secrets configured for the single-campaign Veterans setup.
- **April 21:** Manual `workflow_dispatch` dry-run from GitHub Actions passed. First live cron run (DRY_RUN=false) fired at 13:00 UTC. All 5 Veterans adsets updated. Slack notification received.

### IP Whitelist Solution

The self-hosted runner runs on Nheo’s server, which has a fixed IP that was whitelisted in CLOSRTECH. Nheo’s server runs the GitHub Actions runner process and the workflow executes on it as if it were a GitHub-hosted runner, but from a fixed IP. Long-term plan: move to a dedicated EC2 instance.

---

## April 15, 2026 — First Dry-Run (Veterans, Local)

### What Happened

First execution against production APIs. Run locally from a developer machine (whitelisted IP). `DRY_RUN=true` — no changes made to Facebook.

Results: 35 active states from CLOSRTECH, 5 active adsets found, all 5 would have been updated. Zero errors.

Verified in Facebook Ads Manager: one Veterans adset showed 38 states currently targeted. The dry-run showed 34 states with demand — the automation would have made precise additions and removals.

### What This Confirmed

- The automation was reading the `demand` field correctly (not `stock` — the UI shows “Stock” but the API field that matters is `demand`)
- The state mapper was translating USPS codes to Facebook region keys correctly
- The idempotency check was working — some adsets already had correct targeting and would be skipped
