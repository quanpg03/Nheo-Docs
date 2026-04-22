# Conversational Support Playbook

These are the 13 scenarios where the agent provides support guidance to managers rather than executing automation. The agent answers in the same language as the incoming message (ES/EN).

> **Key rule on "log out and back in":** This is the most common fix, but it should only be suggested *after* making a change or verifying the agent's configuration — never as a reflexive first response. Overusing it without checking first loses credibility with managers.

---

## S01 — No Assignments / Agents Not Receiving Calls

**Trigger:** Manager reports agents are not getting calls assigned.

**Response flow:**
1. Check the time — is it within calling hours? ReadyMode uses PST. If before 8:00 AM or after 9:00 PM PST, no calls will be assigned regardless of setup.
2. Check the states on the playlist — are the states currently in legal calling hours for their timezone?
3. If timing is correct: ask the agent to log out of ReadyMode and log back in to refresh the session.

---

## S02 — Single State Pickups

**Trigger:** Agent is only receiving calls from one state.

**Response flow:**
1. Verify the playlist contains multiple states.
2. Check that all target states are within their calling hour windows.
3. Ask the agent to log out and log back in.
4. If still single-state: temporarily remove the highest-pickup state from the playlist and re-add it — this forces a reset. Escalate to manager if persists.

---

## S03 — No Pickups at All

**Trigger:** Agent is logged in and ready but receiving zero calls.

**Response flow:**
1. Confirm the agent is assigned to a playlist and the playlist has active members.
2. Verify at least one state on the playlist is within calling hours.
3. Check that at least one campaign on the playlist has leads remaining.
4. Check the agent's internet connection — ReadyMode requires a stable connection.
5. If all checks pass and still no pickups: escalate to ReadyMode support at **1-800-694-1049**.

---

## S04 — License Error ("We're Sorry")

**Trigger:** Agent cannot log in — "We're sorry..." license error.

**Response:** Automatically trigger `clear_licenses.sh` to sign out inactive users and free the license. Confirm completion in Discord.

---

## S05 — Only Receiving Inbound Calls

**Trigger:** Agent is only receiving inbound calls, not outbound.

**Response flow:**
1. Ask the agent to log out of ReadyMode and log back in.
2. If the problem persists: check whether the agent is assigned to an inbound queue in addition to their outbound playlist. Ask the manager to remove the agent from inbound queues if not needed.

---

## S06 — 3+ Minutes Between Each Pickup

**Trigger:** Agent reports very long wait times between calls.

**Response flow:**
1. Check how many states are on the playlist — a playlist with only 1–2 states will have very limited lead availability at any given moment.
2. Check the time — near the boundaries of calling hours, the system dials fewer numbers.
3. If wait times are consistently long: recommend the manager adds more states to the playlist or purchases additional states. The phrase used is "compra más estados" (buy more states).

---

## S07 — Wrong Credentials

**Trigger:** Agent cannot log in due to incorrect username or password.

**Response:** Send the manager a screenshot of the correct credentials format. Do not share the actual credentials in the Discord channel.

---

## S08 — Connection Problems

**Trigger:** Agent reports calls dropping, poor audio quality, or frequent disconnections.

**Response flow:**
1. Try a different browser (Chrome recommended).
2. Ensure the agent is NOT using a public or shared Wi-Fi network.
3. Ensure the agent is NOT using a VPN — ReadyMode is incompatible with VPNs.
4. If the problem persists: contact ReadyMode support at **1-800-694-1049 ext. 4**.

---

## S09 — Duplicate Leads — Correction Upload

**Trigger:** Manager uploaded leads with a mistake (wrong column mapping, missing field) and needs to correct them.

**Response:** Advise using **Merge duplicates** mode when re-uploading. This updates existing records without creating duplicate entries. The corrected fields overwrite the previous values.

---

## S10 — Duplicate Leads — Survey Uploads

**Trigger:** Manager is uploading survey leads that already exist in the system as paid leads.

**Response:** Advise using **Accept duplicates** mode. This allows the same phone number to be re-uploaded and treated as a new lead entry, regardless of whether it already exists in the campaign.

---

## S11 — Duplicate Leads — High Duplicate Volume

**Trigger:** Manager has a file with many leads that already exist in the system and re-uploading would create unmanageable duplicates.

**Response:** Advise using the **Move leads** approach instead of re-uploading. Find the lead in ReadyMode's search bar and use the move function to transfer it to the requested campaign. This is cleaner than a bulk upload when duplicates are the majority.

---

## S12 — Call Results — Standard Campaigns

**Trigger:** Manager or agent asks which call results to use for a standard campaign.

**Response:** Use **Normal call results** for standard campaigns. This is the default result type for regular outbound dialing campaigns.

---

## S13 — Call Results — Personal or Team Campaigns

**Trigger:** Manager or agent asks which call results to use for a personal or team-based campaign.

**Response:** Use **Type “A” call results** for personal and team campaigns. Type A is designed for campaigns that track individual agent performance or team-level outcomes rather than standard outbound metrics.

> **Note on Type “B” call results:** Used for new agencies onboarded to the platform. If a manager asks about call results for a newly onboarded agency, advise Type "B" call results.
