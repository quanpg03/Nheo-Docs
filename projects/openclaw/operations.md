# Operations

All four operations are managed by bash scripts in the workspace. The agent receives a request via Discord, extracts parameters, calls the appropriate script, and reports the result.

---

## Operation 1 — Clear Licenses

**Status: ✅ Complete**

**What it does:** Signs out all inactive users from ReadyMode to free up licenses.

**Steps:**
1. Login (`readymode_login()` from `_lib.sh`)
2. Navigate directly to `/+Team/ManageLicenses` (one of the few routes safe for direct navigation)
3. Click `#sign-out-inactive-btn`
4. Dismiss confirmation popup
5. Logout (`readymode_logout()` from `_lib.sh`)

**Script:** `clear_licenses.sh`

**Trigger phrase examples:** "limpiar licencias", "sign out inactive users", "free up licenses"

---

## Operation 2 — Reset Leads

**Status: 🔴 Blocked — Charlie must assign agents to Office Map**

**What it does:** Resets the leads queue for a specific agent.

**Steps (not yet implemented):**
1. Login
2. Click VIEW OFFICE MAP
3. Select the agent
4. Click Reset Leads
5. Logout

**Blocker:** The Office Map in Arpa Growth's ReadyMode account is empty. No agents have been assigned by the client. Until Charlie assigns agents to the Office Map, the selectors cannot be mapped and the script cannot be written.

**Script:** `reset_leads.sh` (stub)

**Action required:** Team → Charlie: assign agents to Office Map.

---

## Operation 3 — Create User

**Status: ⚠️ 44% complete — Steps 1–4 done, Steps 5–9 missing**

**What it does:** Creates a new agent account in ReadyMode with full configuration.

### Steps 1–4 (✅ Implemented)

| Step | Action | Implementation |
|------|--------|----------------|
| 1 | Click Users → click green `+` button | `click a.dash_link 'users'` → `.uMgmtCreateBut` |
| 2 | Fill name (`u_name`), account (`u_account`), folder, org unit (`ou`) | Standard fields |
| 3 | Set password (`set_pass`) | Native value setter + `input` event (see Incident 3 & 10) |
| 4 | Click SAVE | Submit form |

### Steps 5–9 (🟡 TODO)

| Step | Action | Blocker |
|------|--------|---------|
| 5 | Click Leads → Add a Playlist | Playlist UI not found in DOM — need screenshots from Charlie |
| 6 | Name the playlist | Depends on step 5 |
| 7 | Drag-and-drop campaigns to playlist | Unknown DOM selectors + CDP drag complexity |
| 8 | Drag-and-drop states to playlist | Same blocker as step 7 |
| 9 | Assign user to playlist, verify "1 member" | Depends on steps 5–8 |

**Script:** `create_user.sh`

**Parameters accepted:** `name`, `password`, `folder`, `org_unit`

**Action required:** Charlie must send screenshots showing: where "Add a Playlist" appears, where campaigns/states are dragged, where the user is assigned to the playlist.

---

## Operation 4 — Upload Leads

**Status: ⚠️ 55% complete — Basic flow done, advanced options missing**

**What it does:** Uploads a CSV file of leads to a campaign in ReadyMode.

### Implemented ✅

| Step | Action |
|------|--------|
| Accept CSV from Discord | OpenClaw downloads attachment to `media/inbound/*.csv` automatically |
| Navigate to Leads upload section | Via dashboard clicks |
| Auto-map 5 standard CSV headers | Phone, first name, last name, email, state |
| Select existing campaign | Dropdown selector |
| Click Done — Import Leads | Parses "Successful: N Uploaded" from response |
| Reject duplicates (default) | ReadyMode default behavior |

### Not Implemented 🟡

| Gap | Notes |
|-----|-------|
| Custom / non-standard CSV headers | Need sample CSV from Charlie |
| Create new campaign | No external blocker — can be built now |
| Merge duplicates | UI option before import |
| Accept duplicates | UI option before import |
| Move leads to another campaign | Requires search + move UI mapping |

**Script:** `upload_leads.sh`

**Parameters accepted:** `campaign_name`, `csv_file` (Discord attachment auto-downloaded)
