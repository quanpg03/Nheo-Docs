# Operations

All four operations are managed by bash scripts in the workspace. The agent receives a request via Discord, extracts parameters, calls the appropriate script, and reports the result.

---

## Operation 1 — Clear Licenses

**Status: ✅ 100% Complete** | Verified: 2026-04-09

**What it does:** Signs out all inactive users from ReadyMode to free up licenses. Triggered when agents receive the "We're sorry..." license error.

| Step | Status | Implementation detail |
|------|--------|----------------------|
| Login to ReadyMode | ✅ Done | `readymode_login()` in `_lib.sh` using native value setter |
| Navigate to License Usage | ✅ Done | Direct navigation to `/+Team/ManageLicenses` (one of the few routes that works directly) |
| Click Sign Out Inactive Users | ✅ Done | Click `#sign-out-inactive-btn` |
| OK popup + Logout | ✅ Done | `dismiss_blocking_overlays()` + `readymode_logout()` |
| Confirmation before executing | ✅ Done | Bot asks "Confirmas?" before triggering |

**Script:** `clear_licenses.sh`

**No outstanding gaps for this operation.**

---

## Operation 2 — Reset Leads

**Status: 🔴 0% — Blocked (External)** | Blocker owner: Charlie

**What it does:** Resets the leads queue for a specific agent.

The script `reset_leads.sh` exists but returns `{"success": false, "unavailable": true}` with exit code 2. When triggered, the agent responds that the operation is unavailable and suggests the manager handle it manually or call ReadyMode support.

| Step | Status | Detail |
|------|--------|--------|
| Login to ReadyMode | ✅ Done | Shared `readymode_login()` |
| Click VIEW OFFICE MAP | 🔴 Blocked | Office Map is empty — only "St. 43 - Manager" visible, no agents |
| Select agent + click Reset Leads | 🔴 Blocked | Cannot map DOM selectors without agents visible in the map |
| Logout | ✅ Done | Shared `readymode_logout()` |

**Root cause:** The ReadyMode Office Map for Arpa Growth has no agents assigned to it. Without agents visible in the map, the team cannot inspect the DOM to find the correct selectors for agent names and the Reset Leads button.

**Action required:** Charlie must assign at least 2–3 agents to the Office Map in ReadyMode. Once agents are visible, the team can inspect selectors and complete the script.

**Estimated effort post-unblock:** 1–2 days

---

## Operation 3 — Create User

**Status: ⚠️ 44% — 4 of 9 steps complete** | Critical gap

**What it does:** Creates a new agent account in ReadyMode with full configuration. A user created by the bot currently **cannot receive leads** because no playlist is assigned — forcing the manager to manually complete setup.

### Steps 1–4 (✅ Done) — Verified 2026-04-11

| Step | Status | Implementation detail |
|------|--------|----------------------|
| Login | ✅ Done | `readymode_login()` |
| Click Users | ✅ Done | `click a.dash_link` with text "users" |
| Click green + button | ✅ Done | `.uMgmtCreateBut > tr.uMgmtBulkUser` |
| Name + password + SAVE | ✅ Done | Fills `u_name`, `u_account`, `folder=Openers`, `ou=Users-Openers` using native value setter. `set_pass` field required `input` event dispatch to activate `oninput` handler and promote `xname` to `name` |

### Steps 5–9 (🔴 Not implemented)

| Step | Status | Blocker |
|------|--------|---------|
| Click Leads → Add a Playlist | 🔴 Not implemented | Playlist UI not found in DOM |
| Name the playlist | 🔴 Not implemented | Depends on step above |
| Drag-and-drop campaigns to playlist | 🔴 Not implemented | UI unknown + drag-and-drop complexity in headless |
| Drag-and-drop states to playlist | 🔴 Not implemented | Same blocker |
| Assign user to playlist + verify "1 member" | 🔴 Not implemented | Depends on all above |

### Blocker Analysis

**Blocker 1 — Playlist UI not found in DOM**

The team searched the following URL patterns: `/+Team/Playlist`, `/+AI Leads/Playlist`, `/+Communication/Playlist`, `/+CCS Profile/Playlist`. None exist. An HTML search for the word "playlist" in the DOM returned 0 matches. The playlist section exists somewhere in the ReadyMode UI but its location in Arpa Growth's specific instance is unknown.

Charlie must send screenshots showing: where "Add a Playlist" appears, where campaigns and states are dragged into groups, and where the user is assigned to the playlist.

**Blocker 2 — Drag-and-drop in headless Chrome**

Step 8 requires dragging campaigns and states into playlist groups. Drag-and-drop in Chrome headless via CDP requires simulating `mousedown → mousemove → mouseup` events using `Input.dispatchMouseEvent`. This is technically feasible but requires knowing the exact source and destination selectors, which depend on resolving Blocker 1 first.

**Script:** `create_user.sh`

**Estimated effort post-unblock:** 3–5 days (includes drag-and-drop implementation, edge cases, and end-to-end testing)

---

## Operation 4 — Upload Leads

**Status: ⚠️ ~55% — 6 of 11 sub-tasks complete** | Verified: 2026-04-10 (basic flow only)

**What it does:** Uploads a CSV file of leads to a campaign in ReadyMode. The basic upload flow works end-to-end for CSVs with standard headers and an existing campaign.

### Implemented ✅

| Sub-task | Status | Detail |
|----------|--------|--------|
| Receive CSV from Discord | ✅ Done | OpenClaw downloads to `/home/agent/.openclaw/media/inbound/` |
| POST CSV to ReadyMode | ✅ Done | `fetch + FormData` to `/AI Leads/upload/index.php` (bypasses file chooser in headless) |
| Auto-map standard headers | ✅ Done | `first_name`, `last_name`, `phone`, `email`, `state` map automatically |
| Select existing campaign | ✅ Done | `select[name='set[campaignId]']` by campaign name |
| Click Done — Import Leads | ✅ Done | Click + parse "Successful: N Uploaded" from response |
| Reject duplicates (default) | ✅ Done | ReadyMode default behavior |

### Not Implemented 🔴

| Sub-task | Status | Notes |
|----------|--------|-------|
| Custom/non-standard CSV headers | 🔴 Not implemented | When headers don't match standard fields, ReadyMode shows a manual mapping modal — not handled |
| Create new campaign | 🔴 Not implemented | Only selects existing campaigns; no external blocker, ~0.5–1 day effort |
| Merge duplicates | 🔴 Not implemented | Requires selecting the merge option in the UI before importing; no blocker |
| Accept duplicates | 🔴 Not implemented | Same as merge — different UI option; no blocker |
| Move leads to campaign | 🔴 Not implemented | Requires searching the lead in ReadyMode and using the move function; ~1–2 day effort |

**Script:** `upload_leads.sh`
