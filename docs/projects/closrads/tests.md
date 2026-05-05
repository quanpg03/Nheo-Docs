# Tests & Coverage

---

## Overview

CLOSRADS has 18 unit tests across two test files. All 18 pass — including after the multi-campaign refactor (no test logic changes required). The test suite is entirely **offline** — it never calls CLOSRTECH, Facebook, or Slack.

**Run command:**
```bash
pytest tests/ -v
```

---

## Offline Testing Strategy

**Why no real API calls in tests:** External API tests require valid credentials (can't be in the repo), network access (fails in CI without IP whitelist), stable API responses (a state being added/removed by CLOSRTECH would break a test), and time (real HTTP calls are slow). Instead, every external dependency is **mocked** using `pytest-mock`. Tests run in under 2 seconds on any machine, with no credentials, no network, and no flakiness.

### The `conftest.py` approach

The most important testing infrastructure decision is `tests/conftest.py`. It runs before any test module is imported and **injects stub environment variables** into `os.environ`.

This is necessary because `src/config.py` calls `_require()` at import time. If you import any `src/` module in a test without the env vars present, Python raises `ValueError: Missing required env var` before the test even runs.

After the multi-campaign refactor, `conftest.py` uses the per-campaign naming convention:

```python
import os

# Shared credentials
os.environ.setdefault('CLOSRTECH_EMAIL', 'test@example.com')
os.environ.setdefault('CLOSRTECH_PASSWORD', 'test_password')

# Veterans
os.environ.setdefault('VETERANS_CLOSRTECH_CAMPAIGN', 'VND_VETERAN_LEADS')
os.environ.setdefault('VETERANS_FB_ACCESS_TOKEN', 'fake_token_veterans')
os.environ.setdefault('VETERANS_FB_AD_ACCOUNT_ID', 'act_996226848340777')
os.environ.setdefault('VETERANS_FB_CAMPAIGN_ID', '120238960603460363')

# Truckers
os.environ.setdefault('TRUCKERS_CLOSRTECH_CAMPAIGN', 'VND_TRUCKER_LEADS')
os.environ.setdefault('TRUCKERS_FB_ACCESS_TOKEN', 'fake_token_truckers')
os.environ.setdefault('TRUCKERS_FB_AD_ACCOUNT_ID', 'act_996226848340777')
os.environ.setdefault('TRUCKERS_FB_CAMPAIGN_ID', '120239404121750363')

# Mortgage (two campaign IDs, comma-separated)
os.environ.setdefault('MORTGAGE_CLOSRTECH_CAMPAIGN', 'VND_MORTGAGE_PROTECTION_LEADS')
os.environ.setdefault('MORTGAGE_FB_ACCESS_TOKEN', 'fake_token_mortgage')
os.environ.setdefault('MORTGAGE_FB_AD_ACCOUNT_ID', 'act_1007012848173879')
os.environ.setdefault('MORTGAGE_FB_CAMPAIGN_IDS', '120245305494410017,120241447971000017')
```

Using `setdefault` (not `os.environ[key] = ...`) means that if a real `.env` file is loaded first, the real values take precedence.

### The `demand_response.json` fixture

`tests/fixtures/demand_response.json` is a snapshot of a real CLOSRTECH API response (reflecting what was seen during the dry-run on 2026-04-15). Tests use this fixture to have a realistic, stable input without calling the API.

---

## Test Files

### `tests/test_state_mapper.py` — 8 tests

Tests the USPS → Facebook region key translation logic in `state_mapper.py`.

| Test | What it verifies |
|------|------------------|
| `test_known_state_returns_correct_key` | `usps_to_fb_region('OH')` returns `{key: '3878', name: 'Ohio', country: 'US'}` |
| `test_case_insensitive_lookup` | `'oh'`, `'OH'`, `' OH '` all return the same result |
| `test_unknown_state_returns_none` | `usps_to_fb_region('XX')` returns `None`, does not raise |
| `test_dc_maps_correctly` | DC maps to `'Washington D. C.'` (Facebook's non-standard name) |
| `test_build_fb_regions_filters_none` | States that don't map are omitted from the output list |
| `test_build_fb_regions_empty_input` | Empty demand dict returns empty list |
| `test_build_fb_regions_all_unknown` | All-unknown states returns empty list (sync.py catches this) |
| `test_mapping_cache_used` | After the first call, subsequent calls read from memory, not disk (verifies `_MAPPING` cache) |

**Why these tests matter:** The mapping file is static but it's the only source of truth for state-to-key translation. A silent bug here (wrong key for a state) would mean Facebook gets incorrect region IDs and targets the wrong state — across all three campaigns.

### `tests/test_sync_logic.py` — 10 tests

Tests the orchestration logic in `sync.py` and the Facebook targeting logic in `facebook_client.py`, using mocked versions of all external dependencies.

| Test | What it verifies |
|------|------------------|
| `test_full_sync_dry_run` | Full run with `DRY_RUN=True`: correct modules called in order, no Facebook write, report shows `dry_run=True` |
| `test_full_sync_live` | Full run with `DRY_RUN=False`: update API called for each adset with different targeting |
| `test_idempotency_skip` | If current targeting already matches desired, `update_adset_geo` is not called (zero API writes) |
| `test_all_zeros_failsafe` | If CLOSRTECH returns all demand=0, sync raises `ClosrtechDataError` and Facebook is never touched |
| `test_empty_regions_abort` | If `build_fb_regions` returns empty list, sync aborts before calling Facebook |
| `test_per_adset_error_isolation` | If one adset fails, the others are still updated; error appears in `report.errors` |
| `test_sync_report_fields` | `SyncReport` fields (`campaign_name`, `adsets_processed`, `adsets_updated`, `adsets_skipped`, `errors`, `success`) are correctly populated |
| `test_deepcopy_preserves_other_targeting` | After update, only `geo_locations.regions` changed; all other targeting fields identical to original |
| `test_dry_run_does_not_call_update_api` | With `DRY_RUN=True`, the Facebook update API is never called even when targeting differs |
| `test_closrtech_retry_on_network_error` | Network error triggers retry up to 3 times before raising `ClosrtechError` |

**Why these tests matter:** These cover the two highest-risk behaviors in the system — the fail-safe (all-zeros abort) and the deepcopy (don't touch non-geo targeting). A regression in either would be silent and potentially catastrophic.

---

## What Is NOT Tested

| Gap | Reason | Risk level |
|-----|--------|------------|
| Real CLOSRTECH API call | Requires credentials + IP whitelist; tested manually during dry-run | Low (tested manually) |
| Real Facebook Graph API call | Requires credentials; tested manually during dry-run | Low (tested manually) |
| Multi-campaign loop in `run_sync()` | Current tests mock at the `_sync_campaign` level; loop behavior is simple iteration | Low |
| `notifier.py` Slack delivery | Would require a real or mock HTTP server; stdout path is implicitly exercised | Low (Slack failure is non-blocking) |
| `main.py` exit codes | Not unit tested; covered by integration test if/when added | Low (2-line function) |
| GitHub Actions workflow YAML syntax | Not validated by pytest; caught by GitHub on push | Low (syntax errors are obvious) |
| Token expiration handling | System User tokens don't expire; not a realistic scenario | Low |

The most meaningful untested path is the full end-to-end run from GitHub Actions against both real APIs for all three campaigns. That requires the IP whitelist issue and the new System User token to be resolved first. Once both are ready, a manual `workflow_dispatch` run with `DRY_RUN=true` should be the integration test.

---

## Running Tests Locally

```bash
# Install dependencies (if not already done)
pip install -r requirements.txt

# Run all tests with verbose output
pytest tests/ -v

# Run a single test file
pytest tests/test_state_mapper.py -v

# Run a specific test by name
pytest tests/test_sync_logic.py::test_all_zeros_failsafe -v
```

No `.env` file is required to run tests — `conftest.py` injects stubs automatically. Tests run offline with zero credentials.
