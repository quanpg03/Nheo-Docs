# Module Reference

This section documents every module in `src/` in enough detail that any engineer can understand what it does, why it exists as a separate module, its key behaviors, and its error handling.

---

## `src/config.py` — Configuration & Validation

**What it does:** Loads all environment variables at import time, validates every required variable is present and non-empty, and constructs the `CAMPAIGNS` list that drives the entire sync.

**`CampaignConfig` dataclass:**

| Field | Type | Example |
|-------|------|--------|
| `name` | `str` | `"Veterans"` |
| `closrtech_campaign` | `str` | `"VND_VETERAN_LEADS"` |
| `fb_access_token` | `str` | System User token |
| `fb_ad_account_id` | `str` | `"act_996226848340777"` |
| `fb_campaign_ids` | `list[str]` | `["120238960603460363"]` |

**`_load_campaign(prefix: str) -> CampaignConfig`** — reads per-campaign env vars using the given prefix (e.g., `"VETERANS"`). Supports both single `{PREFIX}_FB_CAMPAIGN_ID` and comma-separated `{PREFIX}_FB_CAMPAIGN_IDS` for Mortgage’s two IDs.

**`CAMPAIGNS` list** — built at import time. `sync.py` iterates over this. Adding a new campaign requires one `.env` entry and one new `_load_campaign()` call here.

**Key behaviors:**

- `_require(name)`: raises `ValueError` if absent or empty
- `DRY_RUN`: accepts `"true"`, `"1"`, `"yes"` (case-insensitive). Defaults to `True` if unset
- Logs `WARNING: DRY RUN MODE` at startup when `True`

**Required env vars:** All per-campaign vars + `CLOSRTECH_EMAIL`, `CLOSRTECH_PASSWORD`

**Optional env vars:**

| Variable | Purpose | Default |
|----------|---------|--------|
| `DRY_RUN` | Run without writing to Facebook | `true` |
| `SLACK_WEBHOOK_URL` | Slack notifications (legacy, replaced by email) | empty = disabled |
| `SENDER_EMAIL` | Gmail address used to send notifications | empty = email disabled |
| `SENDER_EMAIL_APP_PASSWORD` | Gmail App Password (not regular password) | empty = email disabled |
| `NOTIFY_EMAIL` | Destination email for sync reports | empty = email disabled |

**Important:** If any of the three email vars is missing or empty, email notifications are silently disabled — the system logs to stdout and continues normally. It does not raise an error.

---

## `src/closrtech_client.py` — CLOSRTECH API Client

**What it does:** All communication with CLOSRTECH lives here.

### `get_demand(campaign: str) -> dict[str, int]`

- **Parameter:** `campaign` — CLOSRTECH campaign string (e.g., `"VND_VETERAN_LEADS"`)
- **Request:** `GET demand.php?campaign=<campaign>&email=...&pass=...`
- **Timeout:** 30 seconds | **Retry:** 3 attempts, exponential backoff 4s/8s/16s
- **Filtering:** Returns only states where `demand > 0`
- **Fail-safe:** If response is non-empty AND all values are zero → raises `ClosrtechDataError`

### `get_orders()` — Disabled (v2)

Planned endpoint (`orders.php`) returns 404 for Veterans. Status untested for Truckers and Mortgage. Not called in v1.

**Error types:** `ClosrtechError` (retriable) | `ClosrtechDataError` (not retriable)

---

## `src/state_mapper.py` — USPS to Facebook Translation

**What it does:** Converts CLOSRTECH’s format (USPS 2-letter codes) to the Facebook format (list of region objects with numeric keys). Unchanged by all refactors.

### `usps_to_fb_region(usps_code) -> dict | None`

- Loads and caches `data/fb_region_keys.json` in `_MAPPING` on first call
- Case-insensitive lookup. Unknown code → logs warning, returns `None`
- Returns: `{"key": "3878", "name": "Ohio", "country": "US"}`

### `build_fb_regions(active_states) -> list[dict]`

- Converts filtered CLOSRTECH dict to list Facebook expects
- Omits unmapped states. Empty result → `sync.py` aborts before touching Facebook

---

## `src/facebook_client.py` — Facebook Graph API Wrapper

**What it does:** All communication with Facebook lives here. Does not import `config` — all parameters are passed explicitly. Contains the full 4-layer protection logic.

### `init_api(access_token: str, ad_account_id: str) -> AdAccount`

- Initializes Facebook SDK with the provided System User token
- Returns an `AdAccount` object bound to the specified account

### `get_active_adsets(ad_account, campaign_id) -> list[AdSet]`

- Lists all adsets in a campaign filtered to `effective_status == "ACTIVE"`
- Requests: `id`, `name`, `targeting`, `effective_status`

### `update_adset_geo(adset, fb_regions, dry_run) -> bool`

- **Idempotency check:** Compares current vs desired region key sets. If equal, skips.
- **deepcopy pattern:** Makes `copy.deepcopy()` of full targeting, replaces only `geo_locations.regions`, sends copy as update
- **DRY_RUN guard:** Logs but makes no API call when `dry_run=True`
- **Retry:** 3 attempts, exponential backoff 5s/10s/20s
- Returns `True` if updated (or would have in dry-run), `False` if skipped

### Layer 1 — `check_ad_health(adset) -> bool`

**Pre-flight check.** Queries all ads in the adset and checks for active issues.

- Returns `True` if any ad has existing problems (errors, disapprovals, or paused status from a prior issue)
- Returns `False` if all ads are healthy
- If `True`: `_sync_campaign()` skips this adset entirely that day and adds it to `report.adsets_skipped_preflight`
- Rationale: if an ad is already broken, modifying the adset’s geo targeting would only add risk. Skip it and flag for manual review.

### Layer 2 — `republish_ads(adset) -> list[str]`

**Cascade republish.** Immediately after a geo targeting update, sends `status=ACTIVE` to every active ad in the adset.

- Explicitly signals Meta’s servers: “this ad is still valid with the new targeting — confirm the lead form link”
- Without this step, Meta leaves the link in a pending state and eventually pauses the ad (error #3390001)
- This behavior was confirmed by Meta support and applies to any adset using lead forms (instant forms)
- Applied to all campaigns as a precaution, not just the campaigns where the issue was observed
- Returns list of ad IDs that were republished

### Layer 3 — `verify_ads_after_republish(adset, wait_seconds: int = 3) -> list[dict]`

**Post-republish verification.** Waits for Meta to process the republish signal, then queries ad statuses.

- Waits `wait_seconds` (default: 3) to give Meta time to process
- Queries all ad statuses in the adset
- Returns a list of ads that still have issues after the republish
- Empty list = all healthy, done
- Non-empty list = some ads still broken → triggers Layer 4

### Layer 4 — `rollback_geo(adset, original_targeting: dict) -> bool`

**Automatic rollback.** If post-republish verification finds broken ads, restores the geo targeting to its exact pre-update state.

- Takes the `original_targeting` dict captured before the update was made
- Sends it back to Facebook as the adset’s current targeting
- The adset is left as if it was never modified
- Guarantees the worst possible outcome is “not updated today” — never “left in a worse state than before”
- Returns `True` if rollback succeeded, `False` if the rollback API call itself failed (logged as a critical error)

### `_build_new_targeting(current_targeting, fb_regions) -> dict`

Internal helper. Encapsulates the deepcopy + replace pattern.

---

## `src/sync.py` — Orchestrator

**What it does:** `run_sync()` iterates over all configured campaigns, runs each through `_sync_campaign()`, and returns a list of reports.

### `run_sync() -> list[SyncReport]`

- Iterates over `config.CAMPAIGNS`
- Calls `_sync_campaign(campaign)` for each
- A failure in one campaign does not abort the others

### `_sync_campaign(campaign: CampaignConfig) -> SyncReport`

Full pipeline for one campaign, including the 4-layer protection per adset:

1. `get_demand(campaign.closrtech_campaign)` — fetch CLOSRTECH demand
2. `build_fb_regions()` — translate states (abort if empty)
3. `init_api(campaign.fb_access_token, campaign.fb_ad_account_id)`
4. For each `fb_campaign_id`: `get_active_adsets()` — collect all adsets
5. For each adset:
   - **Layer 1:** `check_ad_health(adset)` — if True, skip and log to `adsets_skipped_preflight`
   - Capture `original_targeting` before any change
   - `update_adset_geo(adset, fb_regions, dry_run)` — update geo
   - If updated and not dry-run:
     - **Layer 2:** `republish_ads(adset)`
     - **Layer 3:** `verify_ads_after_republish(adset)` — wait 3s, check statuses
     - If broken ads found → **Layer 4:** `rollback_geo(adset, original_targeting)`, log to `adsets_reverted`
6. Return `SyncReport`

Steps 1–3 are all-or-nothing. Step 5 is per-adset isolated (one failure doesn’t stop the rest).

### `SyncReport` (dataclass)

| Field | Type | Meaning |
|-------|------|----------|
| `campaign_name` | `str` | Human-readable name (e.g., `"Veterans"`) |
| `adsets_processed` | `int` | Total active adsets found |
| `adsets_updated` | `int` | Adsets where targeting was changed (and held after verification) |
| `adsets_skipped` | `int` | Adsets skipped because targeting was already correct (idempotency) |
| `adsets_skipped_preflight` | `int` | Adsets skipped because they had pre-existing broken ads (Layer 1) |
| `adsets_reverted` | `int` | Adsets updated then rolled back because verification found broken ads (Layer 4) |
| `active_states` | `list[str]` | USPS codes of states with demand > 0 |
| `errors` | `list[str]` | Per-adset error messages |
| `dry_run` | `bool` | Whether this was a dry run |
| `success` | `bool` | `True` if no errors in `errors` list |

---

## `src/notifier.py` — HTML Email Reporting

**What it does:** Takes a list of completed `SyncReport` objects and sends an HTML email to Charlie. Replaced the previous Slack integration.

### `notify(reports: list[SyncReport])`

- Checks if `SENDER_EMAIL`, `SENDER_EMAIL_APP_PASSWORD`, and `NOTIFY_EMAIL` are all configured
- If any is missing: logs report to stdout and returns without error
- If configured: sends one HTML email summarizing all campaigns

**Email format:**

- Header: date, DRY RUN indicator if applicable
- Per-campaign section with counts: updated / unchanged / skipped (pre-flight) / reverted
- **Orange box** (if any `adsets_skipped_preflight > 0`): lists each skipped adset with the ad name and error description. Signals: “these adsets had broken ads before we ran — we left them alone, manual review needed.”
- **Red box** (if any `adsets_reverted > 0`): explains which adsets were updated, then rolled back after verification found broken ads. Confirms targeting was restored to its previous state.
- **Green box** (if all campaigns clean): “all campaigns ran without issues.”
- Full list of active CLOSRTECH states for each campaign

**Authentication:** Uses Gmail SMTP with an App Password (`SENDER_EMAIL_APP_PASSWORD`). This is a specific application password generated in Google Account settings — not the regular Gmail password. Required because Gmail blocks less-secure app access by default.

**Failure handling:** If the email send fails (SMTP error, timeout, bad credentials), logs a warning but does NOT raise. A notification failure should never mask the actual sync result.

---

## `main.py` — Entry Point

**What it does:** Configures logging, runs the sync, handles the exit code.

**Exit code logic:** Exits 1 if any campaign had `report.success == False`. Exits 0 if all campaigns succeeded.

```python
if __name__ == "__main__":
    # 1. UTF-8 fix
    # 2. logging.basicConfig
    # 3. reports = run_sync()
    # 4. notify(reports)
    # 5. sys.exit(0 if all(r.success for r in reports) else 1)
```

**Logging config:** Level `INFO`, format `%(asctime)s [%(levelname)s] %(name)s: %(message)s`
