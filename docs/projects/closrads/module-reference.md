# Module Reference

This section documents every module in `src/` in enough detail that any engineer can understand what it does, why it exists as a separate module, its key behaviors, and its error handling.

---

## `src/config.py` — Configuration & Validation

**What it does:** Loads all environment variables at import time, validates every required variable is present and non-empty, and constructs the `CAMPAIGNS` list that drives the entire sync. If anything is missing, the program fails immediately with a clear error before making any API call.

**Why fail-fast matters:** Without this, a missing env var causes a confusing error deep inside a CLOSRTECH or Facebook call — something like `NoneType is not iterable` with no obvious cause. With fail-fast: `ValueError: Missing required env var: VETERANS_FB_ACCESS_TOKEN` at startup, before any network call.

### `CampaignConfig` dataclass

| Field | Type | Example |
|-------|------|--------|
| `name` | `str` | `"Veterans"` |
| `closrtech_campaign` | `str` | `"VND_VETERAN_LEADS"` |
| `fb_access_token` | `str` | System User token |
| `fb_ad_account_id` | `str` | `"act_996226848340777"` |
| `fb_campaign_ids` | `list[str]` | `["120238960603460363"]` |

### `_load_campaign(prefix: str) -> CampaignConfig`

Helper that reads per-campaign env vars using the given prefix (e.g., `"VETERANS"`).

- Reads `{PREFIX}_CLOSRTECH_CAMPAIGN`, `{PREFIX}_FB_ACCESS_TOKEN`, `{PREFIX}_FB_AD_ACCOUNT_ID`
- Supports both single ID (`{PREFIX}_FB_CAMPAIGN_ID`) and comma-separated list (`{PREFIX}_FB_CAMPAIGN_IDS`) to handle Mortgage's two campaign IDs
- Returns a `CampaignConfig` instance

### `CAMPAIGNS` list

Built at import time by calling `_load_campaign()` for each of the three prefixes: `VETERANS`, `TRUCKERS`, `MORTGAGE`.

```python
CAMPAIGNS = [
    _load_campaign("VETERANS"),
    _load_campaign("TRUCKERS"),
    _load_campaign("MORTGAGE"),
]
```

`sync.py` iterates over this list — adding a fourth campaign requires only a new `.env` entry and one new line here.

**Key behaviors:**

- Calls `load_dotenv()` automatically on import — no other module needs to call it
- `_require(name)`: raises `ValueError` if the variable is absent or empty string
- `DRY_RUN` parsed as bool: accepts `"true"`, `"1"`, `"yes"` (case-insensitive). Defaults to `True` if unset — always safe by default
- Logs a prominent `WARNING: DRY RUN MODE — no changes will be made to Facebook` at startup when `True`

**Shared env vars:** `CLOSRTECH_EMAIL`, `CLOSRTECH_PASSWORD`, `DRY_RUN`, `SLACK_WEBHOOK_URL`

---

## `src/closrtech_client.py` — CLOSRTECH API Client

**What it does:** All communication with CLOSRTECH lives here. Nothing outside this module knows the URL, parameters, auth, retry logic, or error types.

### `get_demand(campaign: str) -> dict[str, int]`

The only function called by the orchestrator. Fetches active state demand for a given campaign param.

- **Parameter:** `campaign` — the CLOSRTECH campaign string (e.g., `"VND_VETERAN_LEADS"`). Previously read from `config` internally; now passed explicitly so each campaign in the loop can pass its own value.
- **Request:** `GET demand.php?campaign=<campaign>&email=...&pass=...`
- **Credentials:** `config.CLOSRTECH_EMAIL` and `config.CLOSRTECH_PASSWORD` (shared across all campaigns)
- **Timeout:** 30 seconds per attempt
- **Retry:** 3 attempts via `tenacity`, exponential backoff at 4s, 8s, 16s. Only retries `ClosrtechError`. Does NOT retry `ClosrtechDataError` — retrying bad data won't fix it.
- **Filtering:** Returns only states where `demand > 0`. Zero-demand states are excluded.
- **Fail-safe:** If after filtering the result is empty AND the original response was non-empty (all zeros), raises `ClosrtechDataError` and aborts.

### `get_orders()` — Disabled (v2)

Planned endpoint (`orders.php`) returns 404 for Veterans. Status untested for Truckers and Mortgage. Exists as a placeholder. Mike must escalate to the CLOSRTECH developer. Not called anywhere in v1.

**Error types:**

- `ClosrtechError` — network failure, timeout, HTTP error (retriable)
- `ClosrtechDataError` — invalid response or all-zeros fail-safe triggered (not retriable)

---

## `src/state_mapper.py` — USPS to Facebook Translation

**What it does:** Converts CLOSRTECH's format (USPS 2-letter codes) to the exact format Facebook expects for geographic targeting (list of region objects with numeric keys).

This module is unchanged by the multi-campaign refactor — it has no concept of campaigns and works identically for Veterans, Truckers, and Mortgage.

**Why its own module:** CLOSRTECH client knows how to talk to CLOSRTECH. Facebook client knows how to talk to Facebook. The translation between their formats is a third responsibility that belongs to neither.

### `usps_to_fb_region(usps_code) -> dict | None`

- Loads `data/fb_region_keys.json` on first call and caches it in `_MAPPING` (module-level). Subsequent calls read from memory, never from disk again.
- Normalizes input to uppercase: `"oh"`, `"OH"`, `" OH "` all resolve correctly.
- Unknown code: logs a warning, returns `None`. Does not raise — one unmapped state should not abort the entire sync.
- Returns: `{"key": "3878", "name": "Ohio", "country": "US"}`

### `build_fb_regions(active_states) -> list[dict]`

- Takes the filtered CLOSRTECH dict (`{"OH": 15, "TX": 4, ...}`) and converts it to the list Facebook expects.
- States that return `None` from `usps_to_fb_region()` are omitted (warning already logged).
- **Edge case:** if every state fails to map (corrupted or missing `fb_region_keys.json`), returns empty list. `sync.py` detects this and aborts before touching Facebook.

---

## `src/facebook_client.py` — Facebook Graph API Wrapper

**What it does:** All communication with Facebook lives here. No other module imports the `facebook-business` SDK or calls the Graph API directly. This module **does not import `config`** — all parameters are passed explicitly, which allows different campaigns to use different tokens and ad accounts.

### `init_api(access_token: str, ad_account_id: str) -> AdAccount`

- **Parameters:** `access_token` and `ad_account_id` passed explicitly (previously read from `config` internally — removed in the multi-campaign refactor).
- Initializes the Facebook SDK session with the provided System User token.
- Configures the `FacebookAdsApi` singleton (SDK requirement before any API call).
- Returns an `AdAccount` object bound to the specified account for subsequent calls.
- **Failure:** If the token is invalid, the SDK raises on the first actual API call (`get_active_adsets`), not here.

### `get_active_adsets(ad_account, campaign_id) -> list[AdSet]`

- Queries the Graph API for all adsets in the specified campaign.
- Filters client-side for `effective_status == "ACTIVE"` — paused and archived adsets are excluded.
- Requests only the fields needed: `id`, `name`, `targeting`, `effective_status`.
- **Why `effective_status` not `status`:** `effective_status` reflects the combined state including whether the parent campaign is active.

### `update_adset_geo(adset, fb_regions, dry_run) -> bool`

- **Idempotency check:** Compares `current_keys` vs `desired_keys` as sets. If equal, skips the write and returns `False`.
- **deepcopy pattern:** Reads the full current targeting object, makes a `copy.deepcopy()` of it, replaces only `geo_locations.regions` in the copy, then sends the copy as the update payload. Every other targeting field is preserved exactly as-is.
- **DRY_RUN guard:** If `dry_run=True`, logs what would be done but makes no API call. Returns `True` (would have updated) so SyncReport shows correct count.
- **Retry:** 3 attempts, exponential backoff at 5s, 10s, 20s via `tenacity`.
- Returns `True` if an update was made (or would have been made in dry-run), `False` if skipped.

### `_build_new_targeting(current_targeting, fb_regions) -> dict`

Internal helper (underscore prefix — not called outside this module). Encapsulates the deepcopy + replace pattern so it can be unit-tested in isolation.

---

## `src/sync.py` — Orchestrator

**What it does:** `run_sync()` iterates over all configured campaigns, runs each through `_sync_campaign()`, collects all reports, and returns them as a list. A failure in one campaign does not abort the others.

### `run_sync() -> list[SyncReport]`

- Iterates over `config.CAMPAIGNS`
- Calls `_sync_campaign(campaign)` for each
- Returns `list[SyncReport]` — one report per campaign
- A failure in one campaign does not abort the others — all campaigns run regardless

### `_sync_campaign(campaign: CampaignConfig) -> SyncReport`

Runs the full pipeline for one campaign:

1. `get_demand(campaign.closrtech_campaign)` — fetch CLOSRTECH demand for this campaign's param
2. `build_fb_regions()` — translate states to FB format (abort if empty)
3. `init_api(campaign.fb_access_token, campaign.fb_ad_account_id)` — initialize Facebook SDK
4. For each `fb_campaign_id` in `campaign.fb_campaign_ids`: `get_active_adsets()` — collect all adsets
5. Combine all adsets from all campaign IDs into one list (Mortgage has two IDs)
6. `update_adset_geo()` per adset — isolated: one failure doesn't stop the rest
7. Return `SyncReport` with `campaign_name` populated

Steps 1–3 are all-or-nothing. Step 6 is per-adset isolated.

### `SyncReport` (dataclass)

| Field | Type | Meaning |
|-------|------|---------|
| `campaign_name` | `str` | Human-readable name (e.g., `"Veterans"`) |
| `adsets_processed` | `int` | Total active adsets found across all campaign IDs |
| `adsets_updated` | `int` | Adsets where targeting was changed |
| `adsets_skipped` | `int` | Adsets where targeting was already correct |
| `active_states` | `list[str]` | USPS codes of states with demand > 0 |
| `errors` | `list[str]` | Per-adset error messages (empty if all succeeded) |
| `dry_run` | `bool` | Whether this was a dry run |
| `success` | `bool` | `True` if no errors in `errors` list |

---

## `src/notifier.py` — Slack or stdout Reporting

**What it does:** Takes a list of completed `SyncReport` objects and delivers them. Sends one notification block per campaign. If `SLACK_WEBHOOK_URL` is configured, sends a structured message to Slack. If not, prints to stdout.

### `notify(reports: list[SyncReport])`

- Iterates over reports and formats one block per campaign
- Report format per campaign:

```
CLOSRADS Sync — Veterans | [DRY RUN] | 2026-04-25 13:01:22 UTC
Status: SUCCESS
Active states (34): AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI...
Adsets processed: 5 | Updated: 5 | Skipped: 0
Errors: none
```

- If Slack fails (timeout, bad status code), logs a warning but does NOT raise — a notification failure should never mask the actual sync result.
- Always called after all campaigns complete, regardless of success/failure.

---

## `main.py` — Entry Point

**What it does:** Minimal entry point. Configures logging, runs the sync, handles the exit code.

**Exit code logic:** Exits with code 1 if **any** campaign in the list had `report.success == False`. Exits 0 only if all campaigns succeeded.

**Execution flow:**

```python
if __name__ == "__main__":
    # 1. UTF-8 fix
    # 2. logging.basicConfig
    # 3. reports = run_sync()
    # 4. sys.exit(0 if all(r.success for r in reports) else 1)
```

**Why UTF-8 fix:** Python 3 on Windows defaults stdout to the system code page (often cp1252), which crashes when printing characters outside that range. `sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")` forces UTF-8 regardless of OS. GitHub Actions runs on Linux (UTF-8 by default) so this is a no-op there.

**Logging config:**

- Level: `INFO`
- Format: `%(asctime)s [%(levelname)s] %(name)s: %(message)s`
