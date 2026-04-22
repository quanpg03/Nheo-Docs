# Compliance Matrix — R01 to R33

This matrix maps every explicit requirement from the client's original spec to its current implementation status. It is the authoritative record of what was asked for vs. what was built.

**Legend:** ✅ DONE = fully implemented and verified | ⚠️ PARTIAL = partially implemented | 🟡 TODO = not yet implemented | 🔴 BLOCKED = cannot proceed without external input

**Overall: 19 done (57%), 2 partial (6%), 10 TODO (30%), 2 blocked (6%)**

---

## Login & Logout

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R01 | Login to ReadyMode via browser | ✅ DONE | `readymode_login()` in `_lib.sh` — native value setter + overlay dismissal |
| R02 | Logout at end of each operation | ✅ DONE | `readymode_logout()` in `_lib.sh` — appends `?logout=1` |

---

## Clear Licenses

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R03 | Click License Usage | ✅ DONE | Direct navigation to `/+Team/ManageLicenses` |
| R04 | Click Sign Out Inactive Users + OK popup | ✅ DONE | Click `#sign-out-inactive-btn` + `dismiss_blocking_overlays()` |

---

## Reset Leads

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R05 | Click VIEW OFFICE MAP | 🔴 BLOCKED | Office Map empty — no agents assigned by client |
| R06 | Select agent + click Reset Leads | 🔴 BLOCKED | Depends on R05 — Charlie must configure Office Map |

---

## Create User

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R07 | Click Users + green `+` button | ✅ DONE | `click a.dash_link 'users'` + `.uMgmtCreateBut` |
| R08 | Enter name + password + SAVE | ✅ DONE | Fills `u_name`, `u_account`, `folder`, `ou`; `set_pass` with native value setter. Verified 2026-04-11 |
| R09 | Click Leads → Add a Playlist | 🟡 TODO | Not implemented — playlist UI not found in DOM |
| R10 | Name the playlist | 🟡 TODO | Depends on R09 |
| R11 | Drag-and-drop campaigns to playlist | 🟡 TODO | Not implemented — drag-and-drop in headless CDP |
| R12 | Drag-and-drop states to playlist | 🟡 TODO | Same blocker as R11 |
| R13 | Assign user to playlist + verify "1 member" | 🟡 TODO | Depends on R09–R12 |

---

## Upload Leads

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R14 | Accept CSV attachment from Discord | ✅ DONE | OpenClaw downloads to `media/inbound/*.csv` automatically |
| R15 | Match CSV headers to ReadyMode fields | ⚠️ PARTIAL | Auto-maps 5 standard fields. Custom/non-standard headers: NOT handled |
| R16 | Select or create campaign | ⚠️ PARTIAL | Selects existing campaign. Creating a new campaign: NOT implemented |
| R17 | Click Done — Import Leads | ✅ DONE | Click + parse "Successful: N Uploaded" from response |
| R18 | Reject duplicates (default) | ✅ DONE | ReadyMode default behavior |
| R19 | Merge duplicates | 🟡 TODO | Requires selecting merge option in UI before importing |
| R20 | Accept duplicates | 🟡 TODO | Requires selecting accept option in UI |
| R21 | Move leads to campaign | 🟡 TODO | Requires searching lead + using move function in ReadyMode |

---

## Conversational Support (Knowledge Base)

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R22 | Support: No assignments | ✅ DONE | KB: timing context + PST states check + log out/in |
| R23 | Support: Single state pickups | ✅ DONE | KB: verify playlist states + log out/in + manager awareness |
| R24 | Support: No pickups | ✅ DONE | KB: playlist members + states + campaigns + connection + escalation |
| R25 | Support: License error | ✅ DONE | Automated via `clear_licenses.sh` |
| R26 | Support: Only receiving inbounds | ✅ DONE | KB: log out/in + remove from inbound queues |
| R27 | Support: 3+ min per pickup | ✅ DONE | KB: states count + timing + "buy more states" |
| R28 | Support: Wrong credentials | ✅ DONE | KB: send screenshot of correct credentials to manager |
| R29 | Support: Connection problems | ✅ DONE | KB: browser change, private network, no VPN, support 1-800-694-1049 ext. 4 |

---

## Discord Integration

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R30 | Receive messages from Discord | ✅ DONE | Bot @ReadyMode in guild `1476748033134956756`, channel #readymode-soporte |
| R31 | Respond in Discord channel | ✅ DONE | Automatic bilingual response (ES/EN based on incoming message language) |

---

## Campaign & Call Results

| ID | Requirement | Status | Implementation detail |
|----|-------------|--------|-----------------------|
| R32 | Call results: type A / B / normal | 🟡 TODO | Documented as KB (conversational). Automated assignment in UI: not implemented. Requires client confirmation on whether automation is needed |
| R33 | Campaign creation | 🟡 TODO | Only existing campaigns selectable. New campaign creation not implemented |

---

## Summary

| Status | Count | % |
|--------|-------|---|
| ✅ DONE | 19 | 57% |
| ⚠️ PARTIAL | 2 | 6% |
| 🟡 TODO | 10 | 30% |
| 🔴 BLOCKED | 2 | 6% |
| **TOTAL** | **33** | **100%** |

> **Note on R32 (Call results):** The client's spec describes call results assignment conversationally (which type to use and when). Whether the bot should also *execute* the assignment in the ReadyMode UI is ambiguous. This needs explicit confirmation from the client before implementation.
