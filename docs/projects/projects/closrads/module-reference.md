# Module Reference

This section documents every module in `src/` in enough detail that any engineer can understand what it does, why it exists as a separate module, its key behaviors, and its error handling.

---

## `src/config.py` — Configuration & Validation

**What it does:** Loads all environment variables at import time and validates every required variable is present and non-empty. If anything is missing, the program fails immediately with a clear error before making any API call.

**Why fail-fast matters:** Without this, a missing env var causes a confusing error deep inside a CLOSRTECH or Facebook call — something like `NoneType is not iterable` with no obvious cause. With fail-fast: `ValueError: Missing required env var: FB_ACCESS_TOKEN` at startup, before any network call.

**Key behaviors:**
- Calls `load_dotenv()` automatically on import — no other module needs to call it
- `_require(name)`: raises `ValueError` if the variable is absent or empty string
- `DRY_RUN` parsed as bool: accepts `"true"`, `"1"`, `"yes"` (case-insensitive). Defaults to `True` if unset — always safe by default
- Logs a prominent warning at startup when `DRY_RUN=True` so it's always visible in the logs

**Required vars:** `CLOSRTECH_EMAIL`, `CLOSRTECH_PASSWORD`, `CLOSRTECH_CAMPAIGN`, `FB_ACCESS_TOKEN`, `FB_AD_ACCOUNT_ID`, `FB_CAMPAIGN_ID`

**Optional vars:** `DRY_RUN` (defaults `true`), `SLACK_WEBHOOK_URL` (defaults empty, disables Slack)

---

## `src/closrtech_client.py` — CLOSRTECH API Client

**What it does:** All communication with CLOSRTECH lives here. Nothing outside this module knows the URL, parameters, auth, retry logic, or error types.

### `get_demand() -> dict[str, int]`

The only function called by the orchestrator. Fetches active state demand.

- **Request:** `GET demand.php?campaign=VND_VETERAN_LEADS&email=...&pass=...`
- **Timeout:** 30 seconds per attempt
- **Retry:** 3 attempts via `tenacity`, exponential backoff at 4s, 8s, 16s. Only retries `ClosrtechError` (network/HTTP failures). Does NOT retry `ClosrtechDataError` (bad response data) — retrying a bad response won't fix it
- **Filtering:** Returns only states where `demand > 0`. Zero-demand states are excluded from the output
- **Fail-safe:** If after filtering the result is empty AND the original response was non-empty (meaning every state had `demand == 0`), raises `ClosrtechDataError` and aborts

### `get_orders()` — Disabled (v2)

Planned endpoint (`orders.php`) returns 404. Exists as a placeholder. Mike must escalate to the CLOSRTECH developer. Not called anywhere in v1.

**Error types:**
- `ClosrtechError` — network failure, timeout, HTTP error (retriable)
- `ClosrtechDataError` — invalid response or all-zeros fail-safe triggered (not retriable)

---

## `src/state_mapper.py` — USPS to Facebook Translation

**What it does:** Converts CLOSRTECH's format (USPS 2-letter codes) to the exact format Facebook expects for geographic targeting (list of region objects with numeric keys).

**Why its own module:** CLOSRTECH client knows how to talk to CLOSRTECH. Facebook client knows how to talk to Facebook. The translation between their formats is a third responsibility that belongs to neither.

### `usps_to_fb_region(usps_code) -> dict | None`

- Loads `data/fb_region_keys.json` on first call and caches it in `_MAPPING` (module-level). Subsequent calls read from memory, never from disk again
- Normalizes input to uppercase: `"oh"`, `"OH"`, `" OH "` all resolve correctly
- Unknown code: logs a warning, returns `None`. Does not raise — one unmapped state should not abort the entire sync
- Returns: `{"key": "3878", "name": "Ohio", "country": "US"}`

### `build_fb_regions(active_states) -> list[dict]`

- Takes the filtered CLOSRTECH dict (`{"OH": 15, "TX": 4, ...}`) and converts it to the list Facebook expects
- States that return `None` from `usps_to_fb_region()` are omitted (warning already logged)
- Returns the full list ready to be passed directly into the targeting update
- **Edge case:** if every state fails to map (corrupted or missing `fb_region_keys.json`), returns empty list. `sync.py` detects this and aborts before touching Facebook

---

## `src/facebook_client.py` — Facebook Graph API Wrapper

**What it does:** All communication with Facebook lives here. No other module imports the `facebook-business` SDK or calls the Graph API directly.

### `init_api(access_token, ad_account_id) -> AdAccount`

- Initializes the Facebook SDK session with the System User token
- Configures the `FacebookAdsApi` singleton (SDK requirement before any API call)
- Returns an `AdAccount` object bound to `act_XXXXXXXXXX` for subsequent calls
- **Failure:** If the token is invalid, the SDK raises on the first actual API call (`get_active_adsets`), not here

### `get_active_adsets(ad_account, campaign_id) -> list[AdSet]`

- Queries the Graph API for all adsets in the specified campaign
- Filters client-side for `effective_status == "ACTIVE"` — paused and archived adsets are excluded
- Requests only the fields needed: `id`, `name`, `targeting`, `effective_status`
- **Why `effective_status` not `status`:** `effective_status` reflects the combined state including whether the parent campaign is active

### `update_adset_geo(adset, fb_regions, dry_run) -> bool`

- **Idempotency check:** Compares `current_keys` vs `desired_keys` as sets. If equal, skips the write and returns `False`
- **deepcopy pattern:** Reads the full current targeting object, makes a `copy.deepcopy()` of it, replaces only `geo_locations.regions` in the copy, then sends the copy as the update payload. Every other targeting field is preserved exactly as-is
- **DRY_RUN guard:** If `dry_run=True`, logs what would be done but makes no API call. Returns `True` (would have updated) so SyncReport shows correct count
- **Retry:** 3 attempts, exponential backoff at 5s, 10s, 20s via `tenacity`
- Returns `True` if an update was made (or would have been made in dry-run), `False` if skipped

### `_build_new_targeting(current_targeting, fb_regions) -> dict`

- Internal helper (underscore prefix — not called outside this module)
- Encapsulates the deepcopy + replace pattern so it can be unit-tested in isolation

---

## `src/sync.py` — Orchestrator

**What it does:** The single function `run_sync()` calls every other module in the correct order, handles errors at each step, accumulates a `SyncReport`, and returns it.

### `run_sync() -> SyncReport`

- **Early abort:** Steps 1–4 raise on failure and propagate to `main.py`, which logs and exits with code 1
- **Per-adset error isolation:** Step 5 wraps each `update_adset_geo()` call in try/except. One failed adset is logged in `report.errors` and the loop continues
- **Empty fb_regions abort:** If `build_fb_regions()` returns an empty list, `run_sync()` raises immediately — writing no states to Facebook would disable all geographic targeting

### `SyncReport` (dataclass)

| Field | Type | Meaning |
|-------|------|---------|
| `adsets_processed` | `int` | Total active adsets found |
| `adsets_updated` | `int` | Adsets where targeting was changed |
| `adsets_skipped` | `int` | Adsets where targeting was already correct |
| `active_states` | `list[str]` | USPS codes of states with demand > 0 |
| `errors` | `list[str]` | Per-adset error messages (empty if all succeeded) |
| `dry_run` | `bool` | Whether this was a dry run |
| `success` | `bool` | `True` if no errors in `errors` list |

The `success` field determines exit code: `sys.exit(0)` if `True`, `sys.exit(1)` if `False`.

---

## `src/notifier.py` — Slack or stdout Reporting

**What it does:** Takes a completed `SyncReport` and delivers it. If `SLACK_WEBHOOK_URL` is configured, sends a structured message to Slack. If not, prints to stdout.

**Report format:**
```
CLOSRADS Sync — [DRY RUN] | 2026-04-15 13:01:22 UTC
Status: SUCCESS
Active states (35): AK, AR, AZ, CA, CO, CT, DE, FL, GA, HI...
Adsets processed: 5 | Updated: 5 | Skipped: 0
Errors: none
```

- If Slack fails (timeout, bad status code), logs a warning but does NOT raise — a notification failure should never mask the actual sync result
- Always called after sync completes, regardless of success/failure

---

## `main.py` — Entry Point

**What it does:** Minimal entry point. Configures logging, runs the sync, handles the exit code.

**Why the UTF-8 fix:** Python 3 on Windows defaults stdout to the system code page (often cp1252), which crashes when printing characters outside that range. The fix `sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")` forces UTF-8 regardless of OS. GitHub Actions runs on Linux (UTF-8 by default) so this is a no-op there.

**Logging config:**
- Level: `INFO`
- Format: `%(asctime)s [%(levelname)s] %(name)s: %(message)s`

**Execution flow:**
```python
if __name__ == "__main__":
    # 1. UTF-8 fix
    # 2. logging.basicConfig
    # 3. report = run_sync()
    # 4. sys.exit(0 if report.success else 1)
```

The exit code is the contract with GitHub Actions. Exit 0 = success (green check). Exit 1 = failure (red X, notification sent to team if configured).
