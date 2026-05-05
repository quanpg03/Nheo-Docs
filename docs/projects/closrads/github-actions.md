# GitHub Actions & CI/CD

---

## Overview

CLOSRADS runs as a GitHub Actions workflow on a **self-hosted runner** registered on Nheo’s server. The self-hosted runner solved the IP whitelist problem — CLOSRTECH only accepts requests from known IPs, and Nheo’s server has a fixed IP that was whitelisted. The long-term plan is to move to a dedicated EC2 instance.

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

**13:00 UTC every day** = **8:00 AM Colombia time (UTC−5)**.

GitHub Actions scheduled workflows can run 5–30 minutes late during high load. Acceptable for this use case.

### Manual Trigger — `workflow_dispatch`

Any team member with repo access can trigger manually. `dry_run` defaults to `'true'` for manual runs — safe by default. To do a real production run manually, set `dry_run: false`.

---

## Workflow Steps

```yaml
jobs:
  sync:
    runs-on: self-hosted
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
          # Email notifications
          SENDER_EMAIL: ${{ secrets.SENDER_EMAIL }}
          SENDER_EMAIL_APP_PASSWORD: ${{ secrets.SENDER_EMAIL_APP_PASSWORD }}
          NOTIFY_EMAIL: ${{ secrets.NOTIFY_EMAIL }}
        run: python main.py
```

**Key notes:**

- `runs-on: self-hosted` — uses Nheo’s server runner instead of GitHub-hosted. This is what solves the IP whitelist problem.
- `DRY_RUN: ${{ github.event.inputs.dry_run || 'false' }}` — for scheduled runs (no input), falls back to `'false'` (production mode).
- Email secrets are optional — if absent, `notifier.py` logs to stdout without failing.

---

## GitHub Secrets Required

Settings → Secrets and variables → Actions → New repository secret.

| Secret | Value | Notes |
|--------|-------|-------|
| `CLOSRTECH_EMAIL` | Mike’s CLOSRTECH login email | Shared across all campaigns |
| `CLOSRTECH_PASSWORD` | Mike’s CLOSRTECH password | Shared |
| `VETERANS_CLOSRTECH_CAMPAIGN` | `VND_VETERAN_LEADS` | |
| `VETERANS_FB_ACCESS_TOKEN` | System User token | Same token for all campaigns |
| `VETERANS_FB_AD_ACCOUNT_ID` | `act_996226848340777` | CLOSRTECH account |
| `VETERANS_FB_CAMPAIGN_ID` | `120238960603460363` | |
| `TRUCKERS_CLOSRTECH_CAMPAIGN` | `VND_TRUCKER_LEADS` | Campaign disabled but secret kept |
| `TRUCKERS_FB_ACCESS_TOKEN` | System User token | |
| `TRUCKERS_FB_AD_ACCOUNT_ID` | `act_996226848340777` | |
| `TRUCKERS_FB_CAMPAIGN_ID` | `120239404121750363` | |
| `MORTGAGE_CLOSRTECH_CAMPAIGN` | `VND_MORTGAGE_PROTECTION_LEADS` | |
| `MORTGAGE_FB_ACCESS_TOKEN` | System User token | |
| `MORTGAGE_FB_AD_ACCOUNT_ID` | `act_1007012848173879` | Inbounds account |
| `MORTGAGE_FB_CAMPAIGN_IDS` | `120245305494410017,120241447971000017` | Two IDs comma-separated |
| `SENDER_EMAIL` | Gmail address to send from | Optional — email disabled if absent |
| `SENDER_EMAIL_APP_PASSWORD` | Gmail App Password | Not the regular Gmail password |
| `NOTIFY_EMAIL` | Charlie’s email | Destination for sync reports |

**Total: 17 secrets** (14 per-campaign + 3 email). `SLACK_WEBHOOK_URL` removed — email replaces Slack.

**Note on Truckers secrets:** Truckers is currently disabled in `config.py`, but the secrets are kept in case the campaign is re-enabled. They don’t cause any harm when the campaign is commented out.

---

## The IP Whitelist — Resolved

CLOSRTECH’s `demand.php` API has an IP whitelist. GitHub-hosted runners have dynamic IPs that change on every run — they cannot be whitelisted.

**Chosen solution:** Self-hosted GitHub Actions runner on Nheo’s server. The server has a fixed IP that was added to CLOSRTECH’s whitelist. The runner is registered in the repo (Settings → Actions → Runners) and the workflow uses `runs-on: self-hosted`.

**Long-term plan:** Move to a dedicated EC2 instance for better isolation, reliability, and separation from Nheo’s main server workload.

**Historical context:** The April 15-21 dry-runs were run locally from a developer machine with a whitelisted IP. The self-hosted runner was set up in late April 2026 as part of the activation plan.

---

## Failure Notifications

When the workflow exits with code 1, GitHub Actions marks the run failed and sends a failure email to repo notification subscribers.

Additionally, `notifier.py` sends an HTML email to Charlie with the full report — one block per campaign, with colored boxes for skipped and reverted adsets. Charlie is the primary recipient of these operational reports.

For success runs, only the HTML email to Charlie fires.

---

## Branch Strategy

| Branch | Purpose | Status |
|--------|---------|--------|
| `devlop` | Active development | All new code goes here first |
| `main` | Production — what the cron uses | Multi-campaign code live |
