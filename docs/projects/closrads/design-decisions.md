# Design Decisions

Every significant design decision made during the build of CLOSRADS — what was chosen, what the alternatives were, and why the chosen approach was better for this specific context. Ordered from highest-stakes to lowest-stakes.

---

## D01 — DRY_RUN defaults to `true`

**Decision:** `config.py` parses `DRY_RUN` from the environment and defaults to `True` if the variable is absent or empty. The GitHub Actions workflow sets `DRY_RUN=false` only for the scheduled cron. Manual triggers default to `true`.

**Alternatives:** Default to `false` (live mode) and require explicit opt-in to dry-run.

**Reasoning:** Any automation that writes to an external system should be safe to run accidentally. If a developer clones the repo, creates a `.env`, and runs `python main.py` without setting `DRY_RUN=false`, nothing happens to Facebook. The alternative inverts the risk: a misconfigured run in live mode could update all adsets with wrong targeting before anyone notices.

**Why this matters more for this project specifically:** The script touches live Facebook Ads that are actively spending Mike's budget. There is no undo for a targeting update — any bad state persists until the next run corrects it.

**Documented behavior:**

- `DRY_RUN` absent → `True`
- `DRY_RUN=true`, `DRY_RUN=1`, `DRY_RUN=yes` (case-insensitive) → `True`
- `DRY_RUN=false`, `DRY_RUN=0`, `DRY_RUN=no` → `False`
- `config.py` logs a prominent `WARNING: DRY RUN MODE — no changes will be made to Facebook` at startup when `True`

---

## D02 — All-zeros fail-safe in `closrtech_client.py`

**Decision:** If CLOSRTECH returns a non-empty response where every state has `demand == 0`, the script raises `ClosrtechDataError` and aborts. Facebook is never touched.

**Alternatives:** Trust the data and apply it as-is.

**Reasoning:** Zero demand for all states is almost certainly a data error on CLOSRTECH's side (API bug, empty database query, malformed response), not a legitimate instruction to stop advertising everywhere. If the script honored an all-zeros response, it would update every Facebook adset to have empty geographic targeting — causing Mike to lose a full day of lead generation due to a third-party bug.

**The boundary condition:** The fail-safe triggers when the response is non-empty AND all values are zero. An empty response (`{}`) is also an abort, but via a different code path.

**What happens when it triggers:** `run_sync()` receives `ClosrtechDataError`, propagates it to `main.py`, which logs the error and exits with code 1. GitHub Actions marks the run failed, sends a failure email, and `notifier.py` sends a Slack alert.

---

## D03 — `deepcopy` targeting before modifying

**Decision:** `facebook_client._build_new_targeting()` creates a `copy.deepcopy()` of the current targeting object before replacing `geo_locations.regions`. The deep copy is what gets sent to the Facebook API, not a mutation of the original.

**Alternatives:** Construct the targeting update from scratch, only sending the geo fields.

**Reasoning:** Facebook adset targeting is a deeply nested dict with many fields: age min/max, genders, interests, behaviors, publisher platforms, location types, device platforms, and more. CLOSRADS only manages geographic targeting. A partial update would cause Facebook to interpret the missing fields as deletions — wiping out targeting configured by Mike's team in Ads Manager.

**Deep copy (not shallow copy) is required** because `geo_locations` is a nested dict. A shallow copy would still share the reference to `geo_locations`, and modifying `regions` would mutate the original object, making the idempotency check unreliable.

**This decision is tested explicitly:** `test_deepcopy_preserves_other_targeting` in `test_sync_logic.py` verifies that after a targeting update, every field other than `geo_locations.regions` is identical to the original.

---

## D04 — Idempotency check before every write

**Decision:** Before calling the Facebook update API for any adset, `update_adset_geo()` compares `current_keys` (set of region keys currently on the adset) to `desired_keys` (set of region keys derived from CLOSRTECH demand). If they are equal, no API call is made.

**Alternatives:** Always update, regardless of whether the value is different.

**Reasoning:** On most days, CLOSRTECH demand doesn't change dramatically overnight. Updating targeting to the same value it already has is wasted API quota, introduces unnecessary risk of a transient API error, and adds noise to Facebook's change history for the adset.

**How idempotency is measured:** The comparison uses Python sets of region key strings (`{"3878", "3890", ...}`), not the full region objects. Two objects with the same `key` but different `name` formatting compare as equal by key — which is the correct behavior since Facebook identifies regions by key, not by name.

**SyncReport reflects this:** `adsets_skipped` counts adsets that passed the idempotency check. On a typical day with stable demand, expect `adsets_skipped` to be high and `adsets_updated` to be low.

---

## D05 — No credentials in code or git history

**Decision:** All credentials are loaded exclusively from environment variables. No credential appears as a default value, a fallback string, or a comment in any source file. The `.env` file is in `.gitignore`.

**Alternatives:** `.env` file committed to repo, hardcoded for testing.

**Reasoning:** A credential committed to a git repo is permanently compromised — even if removed in a later commit, it remains in the git history. For Facebook tokens, a leaked System User token gives full programmatic control over Mike's entire ad account.

**How this is enforced:** `config.py`'s `_require()` function raises `ValueError` if a variable is absent or empty. There is no fallback value for any required credential.

**The `fb_region_keys.json` exception:** This file is committed to the repo and contains Facebook region IDs. These are not credentials — they are public API identifiers that anyone can look up via the Graph API. Committing them is correct.

---

## D06 — Separate module per responsibility, no shared client

**Decision:** `closrtech_client.py` and `facebook_client.py` are completely separate modules. Neither imports from the other. `sync.py` is the only module that knows about both.

**Alternatives:** Single `api_client.py`, or two modules where one calls the other.

**Reasoning:** The two APIs have nothing in common except that they are both called in sequence during a sync. Separating them means a CLOSRTECH API contract change only touches `closrtech_client.py`, and a Facebook SDK version update only touches `facebook_client.py`.

**The translation layer:** `state_mapper.py` exists specifically because neither client should know about the other's format. Putting the translation in either client would create an implicit coupling.

---

## D07 — `tenacity` for retries, not manual retry loops

**Decision:** Retry logic for both CLOSRTECH and Facebook API calls uses the `tenacity` library with `@retry` decorators.

**Alternatives:** Manual `for` loops with `time.sleep()`.

**Reasoning:** Manual retry loops are verbose, easy to get wrong (off-by-one on attempts, forgetting to re-raise after max retries), and hard to test. `tenacity` provides a declarative interface.

**Exponential backoff rationale:** Flat retries hammer an API that may be temporarily overloaded. Exponential backoff (4s, 8s, 16s for CLOSRTECH; 5s, 10s, 20s for Facebook) gives the API time to recover. Facebook's Graph API has stricter rate limiting and recovers more slowly, hence the slightly longer waits.

**What is retried vs not:** `ClosrtechError` (network/HTTP failures) is retried. `ClosrtechDataError` (bad data — all zeros, invalid JSON) is not retried. Retrying bad data is pointless and wastes time.

---

## D08 — `fb_region_keys.json` generated once and committed

**Decision:** The USPS-to-Facebook-region-key mapping was generated once via `scripts/fetch_fb_region_keys.py` and committed to the repo as `data/fb_region_keys.json`. It is not regenerated on every run.

**Alternatives:** Regenerate on every run via API call, or hardcode in Python.

**Reasoning:** Facebook's internal region IDs for US states are stable. Regenerating on every run would cost 51 API calls per execution, add 5–10 seconds of latency, and introduce a failure point. The same mapping file is used unchanged for all three campaigns.

**When to regenerate:** Only if Meta announces a change to their region ID system (historically very rare).

**The DC edge case:** Facebook stores Washington D.C. as `"Washington D. C."` (with spaces around the period). Any future regeneration should verify this name is still correct.

---

## D09 — System User token over regular user token

**Decision:** The `FB_ACCESS_TOKEN` used by the script must be a Meta Business System User token, not a personal user access token.

**Alternatives:** A long-lived user token (60-day expiry) with a renewal workflow.

**Reasoning:** Regular user access tokens expire after 60 days. A cron job that runs every day would need token rotation logic — if the rotation fails or is forgotten, the automation breaks silently. System User tokens are non-expiring.

**This was validated the hard way:** The token originally used was a personal session token tied to Mike's account. When that session expired on April 21, 2026, the automation failed for all three campaigns simultaneously. The correct System User (CLOSRADS) already existed in the Meta Business Manager and had access to both ad accounts — it just had not been used. Going forward, only System User tokens should be used.

---

## D10 — Per-adset error isolation in the update loop

**Decision:** In `_sync_campaign()`, the loop that calls `update_adset_geo()` for each adset wraps each call in a `try/except`. If one adset fails, the error is appended to `report.errors` and the loop continues to the next adset.

**Alternatives:** Abort the entire campaign sync on the first adset failure.

**Reasoning:** The adsets are independent — a transient Facebook API error on one adset has no bearing on others. Aborting the entire sync on the first failure would leave all remaining adsets with stale targeting for the rest of the day.

**The contrast with steps 1–3:** CLOSRTECH fetch, state mapping, and Facebook init use all-or-nothing failure. A failure at any of those steps means there is no valid basis for any updates. The asymmetry is intentional.

---

## D11 — Single System User token shared across all three campaigns

**Decision:** The same Facebook System User token is used for Veterans, Truckers, and Mortgage — even though Mortgage is in a different ad account (Inbounds `act_1007012848173879` vs CLOSRTECH `act_996226848340777`).

**Alternatives:** Separate System User token per campaign or per ad account.

**Reasoning:** Charlie confirmed that the CLOSRADS System User (which already existed) has Admin access to both the CLOSRTECH and Inbounds Facebook ad accounts. A single System User token with multi-account access is the correct Meta architecture for this situation — it is simpler to manage (one token to rotate if ever needed) and the System User was already set up with the right permissions.

**How this is implemented:** All three `*_FB_ACCESS_TOKEN` environment variables hold the same token value. The `facebook_client.init_api(access_token, ad_account_id)` function is called per campaign, so while the token is the same, the `ad_account_id` differs for Mortgage — which is the correct account binding.

---

## D12 — Mortgage uses a list of campaign IDs (`fb_campaign_ids`)

**Decision:** `CampaignConfig.fb_campaign_ids` is a `list[str]`. For Veterans and Truckers this list has one entry. For Mortgage it has two: `Bio MP` (`120245305494410017`) and `Bio MP2` (`120241447971000017`).

**Alternatives:** Treat each Facebook campaign as a separate CLOSRADS campaign entry (two Mortgage entries in `CAMPAIGNS`).

**Reasoning:** Both Mortgage Facebook campaigns share the same CLOSRTECH data source (`VND_MORTGAGE_PROTECTION_LEADS`). Treating them as separate CLOSRADS campaigns would mean calling `get_demand()` twice with the same parameters and applying the same demand data twice — redundant API calls, two Slack blocks for what is logically one campaign, and double the error surface.

**How it works:** `_sync_campaign()` iterates over `campaign.fb_campaign_ids`, calls `get_active_adsets()` for each, and combines all adsets into one list before applying the demand. The result is one `SyncReport` for Mortgage with the combined adset count from both Facebook campaigns.

**Config:** `MORTGAGE_FB_CAMPAIGN_IDS` (plural) stores the two IDs as a comma-separated string. The `_load_campaign()` helper detects whether to read `{PREFIX}_FB_CAMPAIGN_ID` (singular) or `{PREFIX}_FB_CAMPAIGN_IDS` (plural, split on comma).

---

## D13 — Sync frequency: hourly cron instead of event-driven execution

**Decision**: The workflow runs on a fixed hourly cron schedule rather than being triggered by demand-change events.

**Alternatives**: Switch to an event-driven model that fires the sync only when a change in demand is detected (as requested by the client).

**Reasoning**: Event-driven execution would require a separate layer to detect demand changes, adding significant complexity for little practical gain. An hourly cron is simple, cheap to run, and already gives near-real-time responsiveness — demand changes are picked up within 60 minutes at most, which covers the client's concern.

**Config**: The cron expression moves from 0 8 * * * (once daily) to 0 * * * * (at the start of every hour). No other scheduling logic changes.
