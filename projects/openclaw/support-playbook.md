# Conversational Support Playbook

These are the 13 scenarios where the agent provides support guidance to managers rather than executing automation. The agent answers in the same language as the incoming message (ES/EN).

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
4. If still single-state: escalate to manager — the playlist may need reconfiguration.

---

## S03 — No Pickups at All

**Trigger:** Agent is logged in and ready but receiving zero calls.

**Response flow:**
1. Confirm the agent is assigned to a playlist and the playlist has active members.
2. Verify at least one state on the playlist is within calling hours.
3. Check that at least one campaign on the playlist has leads remaining.
4. Check the agent's internet connection — ReadyMode requires a stable connection.
5. If all checks pass and still no pickups: escalate to manager.

---

## S04 — License Error

**Trigger:** Agent cannot log in — "license in use" or "no available license" error.

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

## S09 — Call Results: Type A

**Trigger:** Manager asks about call result type A.

**Response:** Explain what Type A call results represent and when to use them. (Content to be confirmed with client — see R32 in compliance matrix.)

---

## S10 — Call Results: Type B

**Trigger:** Manager asks about call result type B.

**Response:** Explain what Type B call results represent and when to use them. (Content to be confirmed with client.)

---

## S11 — Call Results: Normal

**Trigger:** Manager asks about normal call results.

**Response:** Explain the normal call result category and when to use it. (Content to be confirmed with client.)

---

## S12 — Agent Showing as Available But Not Taking Calls

**Trigger:** Manager sees agent as "available" in ReadyMode but the agent is not receiving calls.

**Response flow:**
1. Verify the agent's playlist is active and has states within calling hours.
2. Ask the agent to log out and log back in to refresh their session state.
3. If still not working: check whether the agent was recently added to the playlist — there may be a sync delay.

---

## S13 — General Escalation

**Trigger:** Any issue that the bot cannot resolve through the above scenarios.

**Response:** Acknowledge the issue, provide any relevant diagnostic information already gathered, and instruct the manager to contact ReadyMode support at **1-800-694-1049 ext. 4**.
