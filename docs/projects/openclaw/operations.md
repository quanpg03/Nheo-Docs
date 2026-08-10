# Operations

All seven operations are implemented as Python executors in `executors/`. When a Discord message arrives, Claude Haiku extracts the intent and parameters, the dispatcher routes to the correct executor, and Claude Haiku phrases the result as a natural-language reply.

Operations execute serially per container — a global job lock prevents concurrent Playwright sessions on the same ReadyMode account.

**All 7 operations are fully implemented as of June 2026.** See [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) for known edge cases and open gaps.

---

## Operation 1 — Create User

**File:** `executors/create_user.py`

Creates a full agent account in ReadyMode: credentials, playlist, state/campaign filters, and member assignment. The user is immediately active and can receive leads after this operation completes.

**Parameters extracted by intent parser:**

- Agent name (first + last)
- Password
- State(s) to assign
- Campaign(s) to assign
- Playlist name (derived from agent name if not explicit)

**Flow:**

1. Login → dismiss post-login overlay
2. Navigate to Users via `a.dash_link`
3. Click the green + button → bulk user form
4. Fill name, password (native value setter + `input` event for React), folder, OU
5. Save → navigate to Leads → Add a Playlist
6. Name playlist, configure campaigns and states
7. Assign user to playlist → verify "1 member"
8. Logout

**Historical note:** The original OpenClaw bash script (`create_user.sh`) completed only steps 1–4 (44%). The user was created with no playlist and could not receive leads. This is fully resolved in the Python executor.

---

## Operation 2 — Create Playlist

**File:** `executors/create_playlist.py`

Creates a standalone playlist with specified states and campaigns, without creating a user account.

**Parameters:** Playlist name, states, campaigns.

---

## Operation 3 — Reset Leads

**File:** `executors/reset_leads.py`

Resets the leads queue for a specific agent.

**Parameters:** Agent name.

**Historical note:** The original bash script (`reset_leads.sh`) was blocked — the ReadyMode Office Map had no agents assigned, making it impossible to locate selectors. This is resolved in the Python executor, which navigates through a different path not dependent on the Office Map.

---

## Operation 4 — Clear Licenses

**File:** `executors/clear_licenses.py`

Signs out all inactive ReadyMode users to free licenses. Triggered by managers when agents receive the "We're sorry…" license error.

**Flow:**

1. Login → dismiss overlay
2. Navigate directly to `/+Team/ManageLicenses` (one of the few routes that supports direct navigation)
3. Click Sign Out Inactive Users (`#sign-out-inactive-btn`)
4. Dismiss confirmation popup
5. Logout

Confirmation is required from the manager before this operation executes.

---

## Operation 5 — User Exists

**File:** `executors/user_exists.py`

Checks whether a ReadyMode user account with the given name exists.

**Parameters:** Agent name.

**Returns:** Boolean + user details if found.

---

## Operation 6 — User Playlist

**File:** `executors/user_playlist.py`

Finds which playlist a specific agent is assigned to.

**Parameters:** Agent name.

**Returns:** Playlist name, or a "not assigned" response if the agent has no playlist.

---

## Operation 7 — Playlist Members

**File:** `executors/playlist_members.py`

Lists all agents assigned to a specific playlist.

**Parameters:** Playlist name.

**Returns:** List of agent names.

---

## KB Support

**File:** `kb.py` — called directly from the dispatcher; no executor or Playwright session involved.

Answers common ReadyMode support questions from a hardcoded bilingual (ES/EN) dictionary. The responder (Claude Haiku) detects the message language and replies in kind. No browser session is opened.

Coverage includes: common errors, license management, lead upload questions, and general CRM guidance.
