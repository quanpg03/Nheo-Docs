# GitHub Actions & CI/CD

---

## Overview

CLOSRADS runs as a GitHub Actions workflow, not as a hosted server or cron on a VPS. This was a deliberate choice: GitHub Actions is free within quota, requires zero infrastructure maintenance, provides native secret management, and gives a built-in audit log of every run in the workflow history.

The workflow file lives at `.github/workflows/daily-sync.yml`.

---

## Trigger Configuration

```yaml
on:
  schedule:
    - cron: '0 13 * * *'
  workflow_dispatch:
    inputs:
      dry_run:
        description: 'Run in dry-run mode (no writes to Facebook)'
        required: false
        default: 'true'
```

### Scheduled Trigger — `0 13 * * *`

This cron expression means **13:00 UTC every day**, which is **8:00 AM Colombia time (UTC−5)**.

**Important caveat:** GitHub Actions scheduled workflows are known to run late — sometimes 5 to 30 minutes after the scheduled time during periods of high GitHub load. For this use case (daily geo targeting sync) a 30-minute drift is acceptable.

### Manual Trigger — `workflow_dispatch`

Allows any team member with repo access to trigger the workflow manually from the GitHub Actions UI. The `dry_run` input defaults to `'true'` for manual runs — a manual trigger is safe by default. To do a real production run manually, the caller must explicitly set `dry_run: false`.

---

## Workflow Steps

```yaml
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - run: pip install -r requirements.txt
      - name: Run CLOSRADS sync
        env:
          # Shared credentials
          CLOSRTECH_EMAIL: ${{ secrets.CLOSRTECH_EMAIL }}
          CLOSRTECH_PASSWORD: ${{ secrets.CLOSRTECH_PASSWORD }}
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          DRY_RUN: ${{ github.event.inputs.dry_run || 'false' }}
          # Veterans
          VETERANS_CLOSRTECH_CAMPAIGN: ${{ secrets.VETERANS_CLOSRTECH_CAMPAIGN }}
          VETERANS_FB_ACCESS_TOKEN: ${{ secrets.VETERANS_FB_ACCESS_TOKEN }}
          VETERANS_FB_AD_ACCOUNT_ID: ${{ secrets.VETERANS_FB_AD_ACCOUNT_ID }}
          VETERANS_FB_CAMPAIGN_ID: ${{ secrets.VETERANS_FB_CAMPAIGN_ID }}
          # Truckers
          TRUCKERS_CLOSRTECH_CAMPAIGN: ${{ secrets.TRUCKERS_CLOSRTECH_CAMPAIGN }}
          TRUCKERS_FB_ACCESS_TOKEN: ${{ secrets.TRUCKERS_FB_ACCESS_TOKEN }}
          TRUCKERS_FB_AD_ACCOUNT_ID: ${{ secrets.TRUCKERS_FB_AD_ACCOUNT_ID }}
          TRUCKERS_FB_CAMPAIGN_ID: ${{ secrets.TRUCKERS_FB_CAMPAIGN_ID }}
          # Mortgage
          MORTGAGE_CLOSRTECH_CAMPAIGN: ${{ secrets.MORTGAGE_CLOSRTECH_CAMPAIGN }}
          MORTGAGE_FB_ACCESS_TOKEN: ${{ secrets.MORTGAGE_FB_ACCESS_TOKEN }}
          MORTGAGE_FB_AD_ACCOUNT_ID: ${{ secrets.MORTGAGE_FB_AD_ACCOUNT_ID }}
          MORTGAGE_FB_CAMPAIGN_IDS: ${{ secrets.MORTGAGE_FB_CAMPAIGN_IDS }}
        run: python main.py
```

**Step-by-step reasoning:**

- `actions/checkout@v4` — checks out the repo so the runner has access to `src/`, `data/`, `main.py`, etc.
- `actions/setup-python@v5` with `python-version: '3.13'` — matches the version used in development
- `pip install -r requirements.txt` — installs all dependencies fresh on every run
- Secrets are injected as environment variables at runtime. GitHub Actions masks secret values automatically in logs.
- `DRY_RUN: ${{ github.event.inputs.dry_run || 'false' }}` — for scheduled runs, `github.event.inputs.dry_run` is undefined, so the `||` fallback makes it `'false'` (production mode). For manual runs, the UI input takes precedence.

---

## GitHub Secrets Required

All credentials are stored as GitHub repository secrets (Settings → Secrets and variables → Actions → New repository secret).

The naming convention uses a per-campaign prefix (`VETERANS_`, `TRUCKERS_`, `MORTGAGE_`) for campaign-specific values, and no prefix for shared values.

| Secret name | Value | Notes |
|-------------|-------|-------|
| `CLOSRTECH_EMAIL` | Mike's CLOSRTECH login email | Shared across all campaigns |
| `CLOSRTECH_PASSWORD` | Mike's CLOSRTECH password | Shared across all campaigns |
| `VETERANS_CLOSRTECH_CAMPAIGN` | `VND_VETERAN_LEADS` | CLOSRTECH campaign param |
| `VETERANS_FB_ACCESS_TOKEN` | System User token | Same token works for all campaigns |
| `VETERANS_FB_AD_ACCOUNT_ID` | `act_996226848340777` | CLOSRTECH Facebook ad account |
| `VETERANS_FB_CAMPAIGN_ID` | `120238960603460363` | Veterans Facebook campaign ID |
| `TRUCKERS_CLOSRTECH_CAMPAIGN` | `VND_TRUCKER_LEADS` | CLOSRTECH campaign param |
| `TRUCKERS_FB_ACCESS_TOKEN` | System User token | Same as Veterans |
| `TRUCKERS_FB_AD_ACCOUNT_ID` | `act_996226848340777` | Same account as Veterans |
| `TRUCKERS_FB_CAMPAIGN_ID` | `120239404121750363` | Truckers Facebook campaign ID |
| `MORTGAGE_CLOSRTECH_CAMPAIGN` | `VND_MORTGAGE_PROTECTION_LEADS` | CLOSRTECH campaign param |
| `MORTGAGE_FB_ACCESS_TOKEN` | System User token | Same as others |
| `MORTGAGE_FB_AD_ACCOUNT_ID` | `act_1007012848173879` | Inbounds Facebook ad account |
| `MORTGAGE_FB_CAMPAIGN_IDS` | `120245305494410017,120241447971000017` | Two IDs — comma-separated |
| `SLACK_WEBHOOK_URL` | Incoming webhook URL | Optional — leave empty to disable Slack |

**Status:** ⚠️ Not yet configured with new per-campaign names. Must be updated before the scheduled cron can run successfully.

**Important:** All three `*_FB_ACCESS_TOKEN` secrets will hold the same System User token value — Charlie confirmed the CLOSRADS System User has Admin access to both the CLOSRTECH and Inbounds ad accounts.

---

## The Facebook Token Situation

### What happened (April 21, 2026)

The token used previously was a personal Facebook login session token tied to Mike's account, not a System User token. When the session expired on April 21 (likely due to a password change or forced re-login), the token died for all three campaigns simultaneously. This was discovered during the April 25-26 dry-run when all Facebook calls returned:

```
Session has expired on Tuesday, 21-Apr-26 09:00:00 PDT
```

### Resolution

Navigated to Meta Business Manager → SP Insurance Group → Ajustes → Usuarios del sistema. Found an existing System User called **CLOSRADS** (Admin access) already assigned to both ad accounts (CLOSRTECH `act_996226848340777` and Inbounds `act_1007012848173879`). Clicked "Generar identificador," selected the Manus app (already assigned to the System User), and initiated token generation. A permission approval was sent to Mike and is pending.

### Why System User tokens don't expire

System User tokens belong to the business (SP Insurance Group), not to any individual login session. They remain valid until explicitly revoked or the System User is deleted. This is the correct token type for any automated system — personal session tokens are not suitable for production automation.

### After Mike approves

Once the permission is approved and the token is generated:

1. Drop the new token into `.env` replacing all three `*_FB_ACCESS_TOKEN` values (same token for all)
2. Run dry-run again: `python main.py` with `DRY_RUN=true` — confirm all 3 campaigns reach CLOSRTECH and Facebook without errors
3. Visual check: open the saved Veterans adset URL, note current states, run `DRY_RUN=false`, reload and confirm states changed
4. Update GitHub Secrets with the new token and new per-campaign naming convention

---

## The IP Whitelist Problem

This remains the **primary blocker** for the scheduled cron to reach CLOSRTECH.

**What the problem is:** CLOSRTECH's `demand.php` API has an IP whitelist — it only accepts requests from known, pre-approved IP addresses. GitHub Actions runs on ephemeral virtual machines with **dynamic IP addresses**. Every time the workflow runs, it gets a different IP from GitHub's pool.

**Known solutions and trade-offs:**

| Solution | How it works | Pros | Cons |
|----------|-------------|------|------|
| Static IP via proxy | Route GitHub Actions outbound traffic through a VPS with a fixed IP that CLOSRTECH whitelists | Clean, reliable, reusable across projects | ~$5/mo for a small VPS; adds a network hop |
| Self-hosted GitHub Actions runner | Run the GitHub Actions runner on a machine with a fixed IP (e.g., Nheo's server) | No extra cost if server already exists | Runner maintenance; server must be online 24/7 |
| Move cron to the Nheo server | Run the script directly via cron on the server instead of GitHub Actions | Eliminates the IP problem entirely | Loses GitHub Actions audit trail and secret management |
| Ask Mike to expand whitelist | Mike escalates to CLOSRTECH to whitelist GitHub's IP ranges | No infra change needed | CLOSRTECH may refuse; whitelist would need ongoing maintenance |

**Recommended path:** Static IP proxy (option 1) or self-hosted runner (option 2) depending on whether Nheo already has a server with a fixed IP. Discuss with Juanes before deciding.

**This item must be resolved before the `DRY_RUN=false` cron can work from GitHub Actions.**

---

## Failure Notifications

When the workflow exits with code 1 (i.e., any `SyncReport.success == False`), GitHub Actions marks the run as failed. GitHub automatically sends a failure email to the repository's notification subscribers.

Additionally, `notifier.py` sends a Slack message (if `SLACK_WEBHOOK_URL` is configured) with one block per campaign including any error messages. The team gets two signals on failure: a GitHub email and a Slack message.

For success runs, only the Slack notification fires (GitHub does not send emails on success by default).

---

## Branch Strategy

| Branch | Purpose | Current state |
|--------|---------|---------------|
| `devlop` | Active development branch | All current code lives here — includes multi-campaign refactor |
| `main` | Production branch — what the cron uses | Behind `devlop`; merge is pending |

The cron workflow is configured to run from `main`. Until the merge from `devlop` → `main` happens, the scheduled run would use whatever is currently on `main`. This merge is part of the Activation Plan and should happen only after the IP whitelist issue is resolved and the new System User token is working.
