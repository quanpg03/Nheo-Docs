# Architecture & Data Flow

---

## End-to-End Data Flow

```
config.CAMPAIGNS (list of 3 CampaignConfig objects)
        |
        | loop per campaign
        v
┌─────────────────────────────────────────────────────┐
│  _sync_campaign(campaign)                           │
│                                                     │
│  CLOSRTECH API (demand.php)                         │
│          |                                          │
│          | JSON: {OH: 15, TX: 4, FL: 0, CA: 3, ...} │
│          v                                          │
│  closrtech_client.get_demand(campaign.closrtech_campaign)
│          - Filters: only states where demand > 0    │
│          - Fail-safe: aborts if ALL states = 0      │
│          - Output: {OH: 15, TX: 4, CA: 3, ...}      │
│          |                                          │
│          v                                          │
│  state_mapper.build_fb_regions()                    │
│          - Translates USPS codes → FB region keys   │
│          - Reads data/fb_region_keys.json (cached)  │
│          - Unknown states: omitted with warning     │
│          - Output: [{key: "3878", name: "Ohio"}, ...]│
│          |                                          │
│          v                                          │
│  facebook_client.init_api(access_token, ad_account) │
│          - Initializes SDK session per campaign     │
│          |                                          │
│          v                                          │
│  for fb_campaign_id in campaign.fb_campaign_ids:    │
│    get_active_adsets() → collect all adsets         │
│          |                                          │
│          v                                          │
│  for each adset:                                    │
│    update_adset_geo()                               │
│      - compares current vs desired keys             │
│      - deepcopy targeting, replace geo_locations    │
│      - skips if already matching                    │
│          |                                          │
│          v                                          │
│  SyncReport (per campaign)                          │
└─────────────────────────────────────────────────────┘
        |
        v
notifier.notify(reports: list[SyncReport])
        - One notification block per campaign
        - Sends to Slack or stdout
```

---

## Repository File Structure

```
closrads/
├── .github/
│   └── workflows/
│       └── daily-sync.yml       # Cron + manual trigger (16 env vars)
├── data/
│   └── fb_region_keys.json      # USPS -> FB region key mapping (committed, not a secret)
├── scripts/
│   └── fetch_fb_region_keys.py  # One-time script to generate the mapping
├── src/
│   ├── config.py                # CampaignConfig dataclass + CAMPAIGNS list (fail-fast)
│   ├── closrtech_client.py      # All CLOSRTECH API logic — get_demand(campaign)
│   ├── facebook_client.py       # All Facebook Graph API logic — no config import
│   ├── state_mapper.py          # Translates USPS codes to FB region keys
│   ├── sync.py                  # Orchestrator — loops over CAMPAIGNS, returns list[SyncReport]
│   └── notifier.py              # Slack or stdout reporting for list[SyncReport]
├── tests/
│   ├── conftest.py              # Injects per-campaign stub env vars (14 vars across 3 campaigns)
│   ├── fixtures/
│   │   └── demand_response.json # Real CLOSRTECH response snapshot for tests
│   ├── test_state_mapper.py
│   └── test_sync_logic.py
├── main.py                      # Entry point — exits 1 if any campaign failed
├── requirements.txt
└── .env.example                 # Per-campaign naming convention (no values)
```

**Files that are local-only and never committed:**

- `.env` — contains all credentials (per-campaign naming)
- `.claude/CLAUDE.md` — project context for Claude Code
- `workflow.md` — internal explanation of the project flow

---

## Layer Separation

| Layer | Module | Responsibility |
|-------|--------|----------------|
| Configuration | `config.py` | `CampaignConfig` dataclass + `CAMPAIGNS` list. Single source of truth for all env vars. Fail-fast on startup. |
| External API — source | `closrtech_client.py` | Everything about calling CLOSRTECH. Accepts `campaign: str` as parameter — no internal config reads for campaign. |
| Translation | `state_mapper.py` | Converts CLOSRTECH's format (USPS codes) to Facebook's format (region key objects). Campaign-agnostic. |
| External API — destination | `facebook_client.py` | Everything about calling Facebook. Accepts `access_token` and `ad_account_id` explicitly — does not import `config`. |
| Orchestration | `sync.py` | Loops over `config.CAMPAIGNS`, calls `_sync_campaign()` per campaign, collects `list[SyncReport]`. |
| Output | `notifier.py` | Formats and delivers one notification block per `SyncReport`. Decoupled from execution logic. |
| Entry point | `main.py` | Configures logging, runs sync, exits 1 if **any** campaign failed. |

This separation matters because when something breaks, you know exactly which module owns the problem. A CLOSRTECH API change only touches `closrtech_client.py`. A Facebook SDK update only touches `facebook_client.py`. Adding a fourth campaign only touches `config.py` and `.env`.

---

## Secrets Architecture

| Location | Contents | Why |
|----------|----------|-----|
| `.env` (local only) | All 16 credentials and config | Never committed. Only exists on the developer's machine. |
| GitHub Secrets | Same 16 credentials | GitHub Actions cannot read a local `.env`. Secrets are injected as env vars at runtime. |
| `.env.example` (committed) | Variable names with no values | Documents what needs to be configured without exposing actual credentials. |
| `data/fb_region_keys.json` (committed) | Facebook region IDs | Not a secret — these are public API IDs. Committed so the script doesn't need to fetch them on every run. |

**Per-campaign env var structure (16 total):**

| Variable | Veterans | Truckers | Mortgage | Notes |
|----------|----------|----------|---------|-------|
| `{P}_CLOSRTECH_CAMPAIGN` | `VETERANS_...` | `TRUCKERS_...` | `MORTGAGE_...` | Campaign param |
| `{P}_FB_ACCESS_TOKEN` | same token for all | same token for all | same token | System User token |
| `{P}_FB_AD_ACCOUNT_ID` | `act_996226848340777` | `act_996226848340777` | `act_1007012848173879` | |
| `{P}_FB_CAMPAIGN_ID(S)` | single ID | single ID | `CAMPAIGN_IDS` (comma) | Mortgage uses plural |
| `CLOSRTECH_EMAIL` | shared | shared | shared | |
| `CLOSRTECH_PASSWORD` | shared | shared | shared | |
| `SLACK_WEBHOOK_URL` | shared | shared | shared | Optional |
| `DRY_RUN` | set in workflow YAML | | | Not a GitHub Secret |

**Rule:** no credential or token ever appears in the source code or git history. `.env` is in `.gitignore`.

---

## Execution Sequence in `sync.py`

`run_sync()` iterates over `config.CAMPAIGNS` and calls `_sync_campaign()` per campaign. A failure in one campaign does not abort the others — all campaigns run and all reports are collected.

Within `_sync_campaign(campaign)`, the following steps run in order:

| Step | Call | Failure behavior |
|------|------|------------------|
| 1 | `get_demand(campaign.closrtech_campaign)` | Abort this campaign. Facebook untouched. |
| 2 | `build_fb_regions()` — translate states to FB format | Abort if mapping file missing or all states unmapped. |
| 3 | `init_api(campaign.fb_access_token, campaign.fb_ad_account_id)` | Abort if token invalid. |
| 4 | `get_active_adsets()` for each `fb_campaign_id` | Abort if Graph API fails. |
| 5 | `update_adset_geo()` per adset | Per-adset: log error and continue. Does not abort the whole campaign. |
| 6 | `notify()` — report results | Always runs after all campaigns complete, one block per campaign. |

The asymmetry in step 5 is intentional: if one adset fails (e.g., a transient API error), the others should still be updated.

---

## The `fb_region_keys.json` Mapping File

Facebook does not accept USPS state codes (`OH`, `TX`) directly in targeting. It requires internal numeric region IDs (`3878`, `3890`). This mapping was generated once using `scripts/fetch_fb_region_keys.py`, which called the Facebook Graph API search endpoint for each of the 51 states (50 + DC).

Key facts:

- 51/51 states mapped successfully
- DC is stored as `"Washington D. C."` (Facebook's own name, with spaces around the period)
- Region keys run from 3843 (Alabama) to 3893 (Wyoming)
- Committed to the repo because it's not a secret and avoids 51 API calls on every execution
- Should be regenerated only if Meta changes their region ID system (historically very rare)
- The same mapping file is used for all three campaigns — US states are the same regardless of campaign
