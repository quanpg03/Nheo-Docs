# Architecture & Data Flow

---

## End-to-End Data Flow

```
CLOSRTECH API (demand.php)
        |
        | JSON: {OH: 15, TX: 4, FL: 0, CA: 3, ...}
        |
        v
closrtech_client.py
        - Filters: only states where demand > 0
        - Fail-safe: aborts if ALL states have demand = 0
        - Output: {OH: 15, TX: 4, CA: 3, ...}
        |
        v
state_mapper.py
        - Translates USPS codes to Facebook region keys
        - Reads data/fb_region_keys.json (in-memory cache)
        - Unknown states: omitted with warning, does not abort
        - Output: [{key: "3878", name: "Ohio", country: "US"}, ...]
        |
        v
facebook_client.py
        - Lists all adsets in the campaign via Graph API
        - Filters: only effective_status == ACTIVE
        - For each adset:
            reads current targeting
            compares current_keys vs desired_keys
            if equal   -> skip (no API write call)
            if different -> deepcopy targeting, replace geo_locations.regions, update
        |
        v
notifier.py
        - Builds SyncReport: adsets_processed, updated, skipped, states, errors
        - Sends to Slack (if SLACK_WEBHOOK_URL configured) or stdout
        - GitHub Actions captures stdout in workflow logs
```

---

## Repository File Structure

```
closrads/
├── .github/
│   └── workflows/
│       └── daily-sync.yml       # Cron + manual trigger
├── data/
│   └── fb_region_keys.json      # USPS -> FB region key mapping (committed, not a secret)
├── scripts/
│   └── fetch_fb_region_keys.py  # One-time script to generate the mapping
├── src/
│   ├── config.py                # Loads and validates all env vars (fail-fast)
│   ├── closrtech_client.py      # All CLOSRTECH API logic
│   ├── facebook_client.py       # All Facebook Graph API logic
│   ├── state_mapper.py          # Translates USPS codes to FB region keys
│   ├── sync.py                  # Orchestrator - calls all modules in order
│   └── notifier.py              # Slack or stdout reporting
├── tests/
│   ├── conftest.py              # Injects stub env vars before any module imports
│   ├── fixtures/
│   │   └── demand_response.json # Real CLOSRTECH response snapshot for tests
│   ├── test_state_mapper.py
│   └── test_sync_logic.py
├── main.py                      # Entry point
├── requirements.txt
└── .env.example                 # Documents required variables (no values)
```

**Files that are local-only and never committed:**
- `.env` — contains all credentials
- `.claude/CLAUDE.md` — project context for Claude Code
- `workflow.md` — internal explanation of the project flow

---

## Layer Separation

| Layer | Module | Responsibility |
|-------|--------|----------------|
| Configuration | `config.py` | Single source of truth for env vars. Fail-fast on startup if anything is missing |
| External API — source | `closrtech_client.py` | Everything about calling CLOSRTECH. The rest of the code never knows the URL, params, or retry logic |
| Translation | `state_mapper.py` | Converts CLOSRTECH's format (USPS codes) to Facebook's format (region key objects). Neither client knows about the other |
| External API — destination | `facebook_client.py` | Everything about calling Facebook. No other module touches the SDK or Graph API |
| Orchestration | `sync.py` | Calls modules in order, handles errors at each step, accumulates the SyncReport |
| Output | `notifier.py` | Formats and delivers the report. Decoupled from execution logic |
| Entry point | `main.py` | Configures logging, runs sync, exits with correct code |

This separation matters because when something breaks, you know exactly which module owns the problem. A CLOSRTECH API change only touches `closrtech_client.py`. A Facebook SDK update only touches `facebook_client.py`. The orchestrator never has to change.

---

## Secrets Architecture

| Location | Contents | Why |
|----------|----------|-----|
| `.env` (local only) | All credentials and config | Never committed. Only exists on the developer's machine or Mike's machine |
| GitHub Secrets | Same credentials | GitHub Actions cannot read a local `.env`. Secrets are injected as env vars at runtime |
| `.env.example` (committed) | Variable names with no values | Documents what needs to be configured without exposing actual credentials |
| `data/fb_region_keys.json` (committed) | Facebook region IDs | Not a secret — these are public API IDs. Committed so the script doesn't need to fetch them on every run |

**Rule:** no credential or token ever appears in the source code or git history. `.env` is in `.gitignore`.

---

## Execution Sequence in `sync.py`

`sync.py` is the orchestrator. It runs the following steps in order, and stops at the first critical failure:

| Step | Call | Failure behavior |
|------|------|------------------|
| 1 | `get_demand()` — fetch CLOSRTECH demand | Abort entire sync. Facebook untouched. |
| 2 | `build_fb_regions()` — translate states to FB format | Abort if mapping file missing. |
| 3 | `init_api()` — initialize Facebook SDK | Abort if token invalid. |
| 4 | `get_active_adsets()` — list active adsets | Abort if Graph API fails. |
| 5 | `update_adset_geo()` — update each adset | Per-adset: log error and continue. Does not abort the whole sync. |
| 6 | `notify()` — report results | Always runs, even if some adsets failed. |

The asymmetry in step 5 is intentional: if one adset fails (e.g., a transient API error), the others should still be updated. The failure is logged and included in the SyncReport, but it doesn't block the rest. Steps 1–4 are all-or-nothing because without valid demand data or a working Facebook connection, there is nothing safe to do.

---

## The `fb_region_keys.json` Mapping File

Facebook does not accept USPS state codes (`OH`, `TX`) directly in targeting. It requires internal numeric region IDs (`3878`, `3890`). This mapping was generated once using `scripts/fetch_fb_region_keys.py`, which called the Facebook Graph API search endpoint for each of the 51 states (50 + DC).

Key facts:
- 51/51 states mapped successfully
- DC is stored as `"Washington D. C."` (Facebook's own name, not an exact match to "District of Columbia")
- Region keys run from 3843 (Alabama) to 3893 (Wyoming)
- Committed to the repo because it's not a secret and avoids 51 API calls on every execution
- Should be regenerated only if Meta changes their region ID system (historically very rare)
