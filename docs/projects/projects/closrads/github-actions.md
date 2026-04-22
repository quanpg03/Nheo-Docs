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
          CLOSRTECH_EMAIL: ${{ secrets.CLOSRTECH_EMAIL }}
          CLOSRTECH_PASSWORD: ${{ secrets.CLOSRTECH_PASSWORD }}
          CLOSRTECH_CAMPAIGN: ${{ secrets.CLOSRTECH_CAMPAIGN }}
          FB_ACCESS_TOKEN: ${{ secrets.FB_ACCESS_TOKEN }}
          FB_AD_ACCOUNT_ID: ${{ secrets.FB_AD_ACCOUNT_ID }}
          FB_CAMPAIGN_ID: ${{ secrets.FB_CAMPAIGN_ID }}
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          DRY_RUN: ${{ github.event.inputs.dry_run || 'false' }}
        run: python main.py
```

**Step-by-step reasoning:**
- `actions/checkout@v4` — checks out the repo so the runner has access to `src/`, `data/`, `main.py`, etc.
- `actions/setup-python@v5` with `python-version: '3.13'` — matches the version used in development
- `pip install -r requirements.txt` — installs all dependencies fresh on every run
- Secrets are injected as environment variables at runtime. GitHub Actions masks secret values automatically in logs
- `DRY_RUN: ${{ github.event.inputs.dry_run || 'false' }}` — for scheduled runs, `github.event.inputs.dry_run` is undefined, so the `||` fallback makes it `'false'` (production mode). For manual runs, the UI input takes precedence

---

## GitHub Secrets Required

All credentials are stored as GitHub repository secrets (Settings → Secrets and variables → Actions → New repository secret).

| Secret name | Value | Notes |
|-------------|-------|-------|
| `CLOSRTECH_EMAIL` | Mike's CLOSRTECH login email | Same as `.env` |
| `CLOSRTECH_PASSWORD` | Mike's CLOSRTECH password | Same as `.env` |
| `CLOSRTECH_CAMPAIGN` | `VND_VETERAN_LEADS` | Campaign identifier |
| `FB_ACCESS_TOKEN` | System User token from Meta Business | Non-expiring |
| `FB_AD_ACCOUNT_ID` | `act_XXXXXXXXXX` | Facebook ad account ID |
| `FB_CAMPAIGN_ID` | Campaign ID from Facebook | Long numeric string |
| `SLACK_WEBHOOK_URL` | Incoming webhook URL | Optional — leave empty to disable Slack |

**Status:** ⚠️ Not yet configured. Must be set before the scheduled cron can run successfully.

---

## The IP Whitelist Problem

This is the **primary blocker** for production activation.

**What the problem is:** CLOSRTECH's `demand.php` API has an IP whitelist — it only accepts requests from known, pre-approved IP addresses. GitHub Actions runs on ephemeral virtual machines with **dynamic IP addresses**. Every time the workflow runs, it gets a different IP from GitHub's pool.

**Why the dry-run was possible:** The dry-run on 2026-04-15 was executed **locally** (from a developer machine with a whitelisted IP), not from GitHub Actions.

**Known solutions and trade-offs:**

| Solution | How it works | Pros | Cons |
|----------|-------------|------|------|
| Static IP via proxy | Route GitHub Actions outbound traffic through a VPS with a fixed IP that CLOSRTECH whitelists | Clean, reliable, reusable across projects | ~$5/mo for a small VPS; adds a network hop |
| Self-hosted GitHub Actions runner | Run the GitHub Actions runner on a machine with a fixed IP (e.g., Nheo's server) | No extra cost if server already exists | Runner maintenance; server must be online 24/7 |
| Move cron to the Nheo server | Run the script directly via cron on the server instead of GitHub Actions | Eliminates the IP problem entirely | Loses GitHub Actions audit trail and secret management |
| Ask Mike to expand whitelist | Mike escalates to CLOSRTECH to whitelist GitHub's IP ranges | No infra change needed | CLOSRTECH may refuse; whitelist would need ongoing maintenance |

**Recommended path:** Static IP proxy (option 1) or self-hosted runner (option 2) depending on whether Nheo already has a server with a fixed IP. Discuss with Juanes before deciding.

**This item must be resolved before the `DRY_RUN=false` cron can work.**

---

## Failure Notifications

When the workflow exits with code 1 (i.e., `report.success == False`), GitHub Actions marks the run as failed. GitHub automatically sends a failure email to the repository's notification subscribers.

Additionally, `notifier.py` sends a Slack message (if `SLACK_WEBHOOK_URL` is configured) with the full SyncReport including any error messages. The team gets two signals on failure: a GitHub email and a Slack message.

For success runs, only the Slack notification fires (GitHub does not send emails on success by default).

---

## Branch Strategy

| Branch | Purpose | Current state |
|--------|---------|---------------|
| `devlop` | Active development branch | All current code lives here |
| `main` | Production branch — what the cron uses | Behind `devlop`; merge is pending |

The cron workflow is configured to run from `main`. Until the merge from `devlop` → `main` happens, the scheduled run would use whatever is currently on `main` (likely empty or stale). This merge is part of the Activation Plan and should happen only after the IP whitelist issue is resolved and Mike confirms the dry-run state list.
