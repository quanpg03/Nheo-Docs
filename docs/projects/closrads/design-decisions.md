# Design Decisions

Every significant design decision made during the build of CLOSRADS — what was chosen, what the alternatives were, and why. Ordered from highest-stakes to lowest-stakes.

---

## D01 — DRY_RUN defaults to `true`

**Decision:** `config.py` defaults `DRY_RUN` to `True` if the variable is absent. The GitHub Actions workflow sets `DRY_RUN=false` only for the scheduled cron. Manual triggers default to `true`.

**Reasoning:** Any automation that writes to an external system should be safe to run accidentally. The alternative inverts the risk: a misconfigured run in live mode could update all adsets with wrong targeting. With real Facebook Ads budget at stake, there is no undo.

**Documented behavior:** `DRY_RUN` absent or empty → `True`. `true`/`1`/`yes` (case-insensitive) → `True`. `false`/`0`/`no` → `False`. Startup logs a prominent warning when `True`.

---

## D02 — All-zeros fail-safe in `closrtech_client.py`

**Decision:** If CLOSRTECH returns a non-empty response where every state has `demand == 0`, raise `ClosrtechDataError` and abort. Facebook is never touched.

**Reasoning:** Zero demand for all states is almost certainly a data error on CLOSRTECH’s side, not a legitimate instruction. Applying it would update every adset to have empty geographic targeting — pausing all coverage for the day due to a third-party bug.

**Boundary condition:** Non-empty response with all zeros triggers the fail-safe. Empty response (`{}`) is a separate abort path. Both paths prevent writing zero states to Facebook.

---

## D03 — `deepcopy` targeting before modifying

**Decision:** `_build_new_targeting()` makes a `copy.deepcopy()` before replacing `geo_locations.regions`.

**Reasoning:** Sending a partial targeting update to Facebook replaces the entire targeting object — wiping out interests, age ranges, genders, and other fields. The deepcopy preserves all fields except the one being changed.

**Why deepcopy not shallow:** `geo_locations` is a nested dict. Shallow copy still shares the reference, making the idempotency check unreliable.

---

## D04 — Idempotency check before every write

**Decision:** Compare current vs desired region key sets before calling the Facebook update API. If equal, skip.

**Reasoning:** On most days, demand is stable. Updating to the same value wastes API quota, adds risk of transient errors, and pollutes Facebook’s change history for the adset.

**Measurement:** Sets of region key strings, not full objects. Two objects with the same `key` but different `name` formatting compare as equal — correct, since Facebook identifies regions by key.

---

## D05 — No credentials in code or git history

**Decision:** All credentials load exclusively from environment variables. No fallbacks, no defaults, no comments containing real values.

**Reasoning:** A credential committed to a git repo is permanently compromised. A leaked System User token gives full programmatic control over Mike’s entire ad account.

**Enforcement:** `_require()` raises `ValueError` if absent or empty. `fb_region_keys.json` is an exception — it contains public API IDs, not credentials.

---

## D06 — Separate module per responsibility

**Decision:** `closrtech_client.py` and `facebook_client.py` are completely separate. Neither imports the other. `sync.py` is the only module that knows both.

**Reasoning:** A CLOSRTECH API change only touches `closrtech_client.py`. A Facebook SDK update only touches `facebook_client.py`. `state_mapper.py` isolates the format translation so neither client needs to know about the other’s format.

---

## D07 — `tenacity` for retries

**Decision:** Retry logic uses `tenacity` with `@retry` decorators, not manual loops.

**Reasoning:** Manual retry loops are verbose and easy to get wrong. `tenacity` reads as a specification. Exponential backoff (4s/8s/16s for CLOSRTECH, 5s/10s/20s for Facebook) gives overloaded APIs time to recover.

**Retry scope:** `ClosrtechError` (network failures) is retried. `ClosrtechDataError` (bad data) is not — retrying won’t fix it.

---

## D08 — `fb_region_keys.json` generated once and committed

**Decision:** The USPS-to-Facebook-region-key mapping is generated once and committed. Not regenerated on every run.

**Reasoning:** 51 API calls per run, 5–10 seconds of extra latency, and a new failure point — for data that hasn’t changed in years. The file is small, public, and auditable.

**DC edge case:** Facebook stores DC as `"Washington D. C."` (spaces around the period). Any regeneration must verify this.

---

## D09 — System User token over regular user token

**Decision:** The FB access token must be a Meta Business System User token, not a personal user token.

**Reasoning:** Personal user tokens expire after 60 days and are tied to individual login sessions. System User tokens belong to the business and never expire.

**This was validated the hard way:** The original token was a personal session token tied to Mike’s account. It expired April 21, 2026, breaking all three campaigns simultaneously. The System User CLOSRADS already existed in the Meta Business Manager with Admin access to both ad accounts — it just hadn’t been used. A new token was generated in May 2026.

---

## D10 — Per-adset error isolation

**Decision:** Wrap each `update_adset_geo()` call in `try/except`. One failed adset logs an error and the loop continues.

**Reasoning:** Adsets are independent. A transient error on one should not leave the others with stale targeting. Steps 1–3 (CLOSRTECH, mapping, Facebook init) remain all-or-nothing — a failure there means no valid basis for any updates.

---

## D11 — Single System User token shared across all campaigns

**Decision:** The same Facebook System User token is used for Veterans, Truckers, and Mortgage — even though Mortgage is in a different ad account.

**Reasoning:** Charlie confirmed the CLOSRADS System User has Admin access to both the CLOSRTECH and Inbounds Facebook ad accounts. A single System User token with multi-account access is the correct Meta architecture — simpler to manage (one token to rotate if ever needed), and the System User was already set up correctly.

**How this works:** All three `*_FB_ACCESS_TOKEN` env vars hold the same value. `init_api(access_token, ad_account_id)` is called per campaign with the correct `ad_account_id` for each.

---

## D12 — Mortgage uses a list of campaign IDs

**Decision:** `CampaignConfig.fb_campaign_ids` is a `list[str]`. For Veterans and Truckers it has one entry. For Mortgage it has two: Bio MP and Bio MP2.

**Reasoning:** Both Mortgage Facebook campaigns share the same CLOSRTECH data source. Treating them as separate CLOSRADS campaigns would mean calling `get_demand()` twice with the same params and producing two identical Slack/email blocks for what is logically one campaign.

**Config:** `MORTGAGE_FB_CAMPAIGN_IDS` (plural) stores two IDs comma-separated. `_load_campaign()` detects the `_IDS` suffix and splits on comma.

---

## D13 — 4-layer ad protection system

**Decision:** Instead of a simple geo targeting update, every adset update runs through 4 ordered layers: pre-flight check → cascade republish → post-republish verification → automatic rollback.

**The problem this solves:** When the automation updated geo targeting via the Graph API, Meta triggered an internal re-validation of all child ads. Ads using lead forms (instant forms) were especially vulnerable — Meta silently broke the link between the ad and the form, causing error #3390001 and pausing the ad without warning. This was observed in the Truckers campaign and at least one Mortgage adset.

**Why each layer:**

- **Layer 1 (pre-flight):** Avoid touching an adset that’s already broken. The automation can’t fix a pre-existing issue, and modifying a broken adset’s targeting adds risk without benefit.
- **Layer 2 (cascade republish):** The root fix, confirmed by Meta support. Sending `status=ACTIVE` to each ad explicitly re-confirms the lead form link after the geo change. Without this, Meta leaves the link in a pending state.
- **Layer 3 (verification):** Trust but verify. The republish signal doesn’t guarantee instant resolution — waiting 3 seconds and checking gives Meta time to process and lets us detect if the problem persists.
- **Layer 4 (rollback):** Guarantees the worst case is “not updated today.” Without rollback, a failed update leaves the adset in an intermediate state — new geo targeting but broken lead form links. Rollback returns it to its last known good state.

**Trade-off:** This adds latency and extra API calls per adset. Acceptable because the adset count is small (5–10 per campaign) and the alternative is silent ad pausing.

**Scope:** Applied to all campaigns, not just the ones where the issue was observed. Better to over-protect.

---

## D14 — HTML email to Charlie instead of Slack

**Decision:** Replace Slack webhook notifications with an HTML email sent to Charlie after each sync.

**Reasoning:** Charlie is the client-side contact who needs to see the sync reports. He is not in the Nheo Slack workspace. An email goes directly to him without requiring any Slack access or channel setup. HTML email allows the colored alert boxes (orange for pre-flight skips, red for rollbacks, green for clean runs) that make the report immediately readable.

**Why Gmail App Password:** Gmail blocks direct SMTP access with the regular account password. An App Password is a separate credential generated in Google Account settings that’s specific to this application. It can be revoked without changing the main account password.

**Optional design:** If the email vars are not configured, the system logs to stdout and continues. This means the automation still runs correctly even if email is misconfigured — the sync is never blocked by a notification failure.

---

## D15 — Remove hardcoded email from source code

**Decision:** Charlie’s email address was removed from the source code entirely. All email credentials live exclusively in environment variables.

**The problem:** The email was previously hardcoded as the default value for `NOTIFY_EMAIL`. Anyone who cloned the repo and ran the script without setting any env vars would unknowingly send emails to Charlie. This is a security and privacy concern — a third party running the code for testing purposes could spam Charlie’s inbox.

**Fix:** `NOTIFY_EMAIL` is now a standard optional env var with no default. If absent, email notifications are disabled. The address is stored only in `.env` (local) and GitHub Secrets (production).

**Rule:** No email address, credential, token, or personally identifiable information ever appears as a default value in source code.
